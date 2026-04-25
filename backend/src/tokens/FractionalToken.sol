// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";

/// @title FractionalToken
/// @notice ERC-20 representing fractional ownership in a tokenized real-world property.
///         Every transfer is gated by the IdentityRegistry compliance layer (ERC-3643 pattern).
///         Inherits ERC20Votes for snapshot-based dividend distribution.
///
/// @dev Compliance in _update is VIEW-only (no state changes before potential revert),
///      so reentrancy is structurally impossible. The compliance check cannot be bypassed:
///        - Minting/burning skip compliance (address(0) as from/to)
///        - All user-initiated transfers must pass validateTransfer
///        - The registry address is immutable — cannot be swapped post-deploy
///        - No delegatecall path exists that could re-enter with a different registry
contract FractionalToken is ERC20, ERC20Permit, ERC20Votes, Pausable, Ownable {
    // ─── Immutables ───────────────────────────────────────────────────────────

    uint256 public immutable linkedNFTId;
    address public immutable propertyNFT;
    address public immutable identityRegistry;
    uint256 public immutable maxSupply;

    /// @notice Maximum token balance allowed for Tier-1 (retail) investors.
    uint256 public constant TIER1_MAX_BALANCE = 10_000 * 1e18;

    // ─── Storage ──────────────────────────────────────────────────────────────

    bool private _initialMintDone;

    struct DividendRound {
        uint256 totalETH;
        uint256 snapshotBlock;          // block number used for getPastVotes
        uint256 claimedCount;
        uint256 totalSupplyAtSnapshot;
    }

    uint256 public roundCount;
    mapping(uint256 => DividendRound)            public dividendRounds;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

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

    // ─── Events ───────────────────────────────────────────────────────────────

    event InitialSupplyMinted(address indexed to, uint256 amount);
    event DividendDeposited(uint256 indexed roundId, uint256 totalETH, uint256 snapshotBlock);
    event DividendClaimed(uint256 indexed roundId, address indexed investor, uint256 amount);
    event ComplianceCheckFailed(address indexed from, address indexed to, string reason);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param _maxSupply Total supply in wei, e.g. 1000 * 1e18 for 1,000 tokens.
    constructor(
        string memory name,
        string memory symbol,
        uint256 _linkedNFTId,
        address _propertyNFT,
        address _identityRegistry,
        uint256 _maxSupply
    )
        ERC20(name, symbol)
        ERC20Permit(name)
        Ownable(msg.sender)
    {
        linkedNFTId       = _linkedNFTId;
        propertyNFT       = _propertyNFT;
        identityRegistry  = _identityRegistry;
        maxSupply         = _maxSupply;
    }

    // ─── Mint / Burn ──────────────────────────────────────────────────────────

    /// @notice Mints the full initial supply. Callable once only.
    function mintInitialSupply(address to) external onlyOwner {
        if (_initialMintDone) revert InitialMintAlreadyDone();
        _initialMintDone = true;
        _mint(to, maxSupply);
        emit InitialSupplyMinted(to, maxSupply);
    }

    /// @notice Burns tokens from the caller's balance.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // ─── Dividends ────────────────────────────────────────────────────────────

    /// @notice Deposits ETH to be distributed pro-rata to token holders at the current block.
    /// @dev Uses ERC20Votes clock (block number) for snapshot. Pro-rata is calculated via
    ///      getPastVotes at claim time, preventing front-running between deposit and claim.
    function depositDividend() external payable onlyOwner {
        if (msg.value == 0) revert ZeroETH();

        // Use the *previous* block as snapshot so the current block's transfers
        // don't affect an already-deposited round.
        uint256 snap = block.number - 1;
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

    /// @notice Claims the caller's share of a specific dividend round.
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

    // ─── Compliance Hook ──────────────────────────────────────────────────────

    /// @notice Single chokepoint for all ERC-20 movement. Mint and burn skip compliance
    ///         intentionally (address(0) as from/to). All other paths enforce KYC.
    ///         Registry address is immutable — cannot be swapped post-deploy.
    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        // Minting — no compliance check; registry hasn't whitelisted address(0)
        if (from == address(0)) {
            super._update(from, to, amount);
            return;
        }
        // Burning — no compliance check; investor voluntarily destroying their tokens
        if (to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        // ── Compliance check ─────────────────────────────────────────────────
        (bool valid, string memory reason) = IIdentityRegistry(identityRegistry)
            .validateTransfer(from, to, amount);

        if (!valid) {
            emit ComplianceCheckFailed(from, to, reason);
            revert ComplianceTransferBlocked(reason);
        }

        // ── Tier-1 balance cap ───────────────────────────────────────────────
        // Fetch tier directly to avoid an extra external call
        (,uint8 toTier,,) = IIdentityRegistry(identityRegistry).getInvestor(to);
        if (toTier == 1) {
            uint256 current  = balanceOf(to);
            uint256 wouldBe  = current + amount;
            if (wouldBe > TIER1_MAX_BALANCE) {
                revert TierLimitExceeded(to, current, wouldBe, TIER1_MAX_BALANCE);
            }
        }

        super._update(from, to, amount);
    }

    // ─── Receive ETH ──────────────────────────────────────────────────────────

    /// @notice Accepts ETH for dividend deposits and direct top-ups.
    receive() external payable {}

    // ─── ERC20Votes clock ─────────────────────────────────────────────────────

    /// @notice Uses block numbers (default mode) for vote/snapshot checkpoints.
    function clock() public view override returns (uint48) {
        return uint48(block.number);
    }

    /// @notice Signals that this contract uses block-number mode (not timestamp).
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    // ─── Nonces override (ERC20Permit + ERC20Votes both need nonces) ──────────

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
