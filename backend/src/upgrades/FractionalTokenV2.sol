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
/// @notice UUPS-upgradeable version of FractionalToken.
///         Adds token locking for vesting simulation: admin locks an investor's
///         outbound transfers until a specified timestamp, simulating cliff vesting.
/// @dev    Storage layout must preserve V1 slots. New V2 storage is appended at the end.
contract FractionalTokenV2 is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ─── V1 Immutable-equivalent Storage ─────────────────────────────────────
    // In upgradeable contracts, "immutables" become storage slots in the proxy.

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

    // ─── V2 Storage ───────────────────────────────────────────────────────────

    /// @notice lockUntil[investor] = timestamp after which transfers are allowed again.
    ///         If 0 or in the past, the investor is not locked.
    mapping(address => uint256) public lockUntil;

    // ─── Custom Errors ────────────────────────────────────────────────────────

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

    // ─── Events ───────────────────────────────────────────────────────────────

    event InitialSupplyMinted(address indexed to, uint256 amount);
    event DividendDeposited(uint256 indexed roundId, uint256 totalETH, uint256 snapshotBlock);
    event DividendClaimed(uint256 indexed roundId, address indexed investor, uint256 amount);
    event ComplianceCheckFailed(address indexed from, address indexed to, string reason);
    event TokensLockedEvent(address indexed investor, uint256 unlocksAt);
    event TokensUnlocked(address indexed investor);

    // ─── Initializer ──────────────────────────────────────────────────────────

    /// @param name               ERC-20 name.
    /// @param symbol             ERC-20 symbol.
    /// @param _linkedNFTId       NFT token ID this fractionalizes.
    /// @param _propertyNFT       PropertyNFT contract address.
    /// @param _identityRegistry  IdentityRegistry contract address.
    /// @param _maxSupply         Total supply to mint.
    /// @param initialOwner       Owner of this proxy.
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

    // ─── V2 Feature: Token Locking ────────────────────────────────────────────

    /// @notice Locks an investor's outbound transfers until a future timestamp.
    ///         Simulates a cliff-vesting schedule managed by the asset admin.
    /// @param investor  The address to lock.
    /// @param until     Unix timestamp after which transfers are permitted again.
    function lockTokens(address investor, uint256 until) external onlyOwner {
        lockUntil[investor] = until;
        emit TokensLockedEvent(investor, until);
    }

    /// @notice Releases a lock before its natural expiry.
    /// @param investor  The address to unlock.
    function unlockTokens(address investor) external onlyOwner {
        lockUntil[investor] = 0;
        emit TokensUnlocked(investor);
    }

    // ─── V1 Functions ─────────────────────────────────────────────────────────

    /// @notice Mints the full initial supply. Callable once.
    function mintInitialSupply(address to) external onlyOwner {
        if (_initialMintDone) revert InitialMintAlreadyDone();
        _initialMintDone = true;
        _mint(to, maxSupply);
        emit InitialSupplyMinted(to, maxSupply);
    }

    /// @notice Burns caller's tokens.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Deposits ETH for a new dividend round.
    function depositDividend() external payable onlyOwner {
        if (msg.value == 0) revert ZeroETH();
        uint256 snap   = block.number - 1;
        uint256 supply = totalSupply();
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

    /// @notice Claims pro-rata ETH dividend for a given round.
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

        // V2: Check vesting lock before compliance
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
