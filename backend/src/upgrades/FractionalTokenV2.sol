// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";

/// @title FractionalTokenV2
/// @notice UUPS-upgradeable FractionalToken. Adds cliff-vesting locks on top of
///         the V1 compliance and dividend logic.
/// @dev Storage layout preserves V1 slots. `lockUntil` is appended at the end.
contract FractionalTokenV2 is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ─── Storage ──────────────────────────────────────────────────────────────
    // Mirrors V1 immutables as storage (proxy pattern)

    uint256 public linkedNFTId;
    address public propertyNFT;
    address public identityRegistry;
    uint256 public maxSupply;
    uint256 public constant TIER1_MAX_BALANCE = 10_000 * 1e18;

    bool private _initialMintDone;

    struct DividendRound {
        uint256 totalETH;
        uint256 snapshotBlock;
        uint256 claimedCount;
        uint256 totalSupplyAtSnapshot;
    }

    uint256 public roundCount;
    mapping(uint256 => DividendRound)            public dividendRounds;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // V2: lockUntil[investor] = timestamp after which outbound transfers are allowed.
    mapping(address => uint256) public lockUntil;

    // ─── Errors / Events ──────────────────────────────────────────────────────

    error InitialMintAlreadyDone();
    error ComplianceTransferBlocked(string reason);
    error TierLimitExceeded(address investor, uint256 currentBalance, uint256 wouldBe, uint256 limit);
    error NoDividendToClaim(address investor, uint256 roundId);
    error AlreadyClaimed(address investor, uint256 roundId);
    error InvalidRound(uint256 roundId);
    error ZeroETH();
    error InsufficientContractBalance();
    error ETHTransferFailed();
    error TokensLocked(address investor, uint256 unlocksAt);

    event InitialSupplyMinted(address indexed to, uint256 amount);
    event DividendDeposited(uint256 indexed roundId, uint256 totalETH, uint256 snapshotBlock);
    event DividendClaimed(uint256 indexed roundId, address indexed investor, uint256 amount);
    event ComplianceCheckFailed(address indexed from, address indexed to, string reason);
    event TokenLocked(address indexed investor, uint256 unlocksAt);
    event TokenUnlocked(address indexed investor);

    // ─── Init ─────────────────────────────────────────────────────────────────

    function initialize(
        string memory name,
        string memory symbol,
        uint256 _linkedNFTId,
        address _propertyNFT,
        address _identityRegistry,
        uint256 _maxSupply,
        address initialOwner
    ) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __ERC20Votes_init();
        __Pausable_init();
        __Ownable_init(initialOwner);

        linkedNFTId      = _linkedNFTId;
        propertyNFT      = _propertyNFT;
        identityRegistry = _identityRegistry;
        maxSupply        = _maxSupply;
    }

    // ─── Pause ────────────────────────────────────────────────────────────────

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ─── V2: Token Locking ────────────────────────────────────────────────────

    /// @notice Prevents outbound transfers from `investor` until `until` (unix timestamp).
    function lockTokens(address investor, uint256 until) external onlyOwner {
        lockUntil[investor] = until;
        emit TokenLocked(investor, until);
    }

    function unlockTokens(address investor) external onlyOwner {
        lockUntil[investor] = 0;
        emit TokenUnlocked(investor);
    }

    // ─── Core ─────────────────────────────────────────────────────────────────

    function mintInitialSupply(address to) external onlyOwner {
        if (_initialMintDone) revert InitialMintAlreadyDone();
        _initialMintDone = true;
        _mint(to, maxSupply);
        emit InitialSupplyMinted(to, maxSupply);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function depositDividend() external payable onlyOwner {
        if (msg.value == 0) revert ZeroETH();
        // snapshot is the previous block so current-block transfers don't affect the round
        uint256 snap    = block.number - 1;
        uint256 supply  = getPastTotalSupply(snap);
        uint256 roundId = roundCount;
        dividendRounds[roundId] = DividendRound({
            totalETH:              msg.value,
            snapshotBlock:         snap,
            claimedCount:          0,
            totalSupplyAtSnapshot: supply
        });
        unchecked { ++roundCount; }
        emit DividendDeposited(roundId, msg.value, snap);
    }

    function claimDividend(uint256 roundId) external {
        if (roundId >= roundCount) revert InvalidRound(roundId);
        DividendRound storage round = dividendRounds[roundId];
        if (hasClaimed[roundId][msg.sender]) revert AlreadyClaimed(msg.sender, roundId);
        uint256 bal = getPastVotes(msg.sender, round.snapshotBlock);
        if (bal == 0) revert NoDividendToClaim(msg.sender, roundId);
        hasClaimed[roundId][msg.sender] = true;
        unchecked { ++round.claimedCount; }
        uint256 payout = (bal * round.totalETH) / round.totalSupplyAtSnapshot;
        if (address(this).balance < payout) revert InsufficientContractBalance();
        (bool ok,) = msg.sender.call{value: payout}("");
        if (!ok) revert ETHTransferFailed();
        emit DividendClaimed(roundId, msg.sender, payout);
    }

    // ─── Compliance + Lock Hook ───────────────────────────────────────────────

    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        if (from == address(0)) { super._update(from, to, amount); return; }
        if (to   == address(0)) { super._update(from, to, amount); return; }

        _requireNotPaused();

        uint256 unlockTime = lockUntil[from];
        if (unlockTime != 0 && block.timestamp < unlockTime) {
            revert TokensLocked(from, unlockTime);
        }

        (bool valid, string memory reason) = IIdentityRegistry(identityRegistry)
            .validateTransfer(from, to, amount);
        if (!valid) {
            emit ComplianceCheckFailed(from, to, reason);
            revert ComplianceTransferBlocked(reason);
        }

        (,uint8 toTier,,) = IIdentityRegistry(identityRegistry).getInvestor(to);
        if (toTier == 1) {
            uint256 current = balanceOf(to);
            uint256 wouldBe = current + amount;
            if (wouldBe > TIER1_MAX_BALANCE) {
                revert TierLimitExceeded(to, current, wouldBe, TIER1_MAX_BALANCE);
            }
        }

        super._update(from, to, amount);
    }

    receive() external payable {}

    // ─── UUPS ─────────────────────────────────────────────────────────────────

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ─── Clock ────────────────────────────────────────────────────────────────

    function clock() public view override returns (uint48) {
        return uint48(block.number);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    function nonces(address owner)
        public
        view
        override(ERC20PermitUpgradeable, NoncesUpgradeable)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
