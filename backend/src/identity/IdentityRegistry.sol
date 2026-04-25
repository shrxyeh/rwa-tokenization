// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title IdentityRegistry
/// @notice ERC-3643-inspired on-chain KYC/AML compliance registry. Governs which addresses
///         may send and receive fractional property tokens. All transfer validation is
///         read-only (view), so no reentrancy risk exists in the compliance hook.
/// @dev Roles:
///        ADMIN_ROLE  — pause/unpause, block/unblock jurisdictions
///        AGENT_ROLE  — add/revoke individual investors
contract IdentityRegistry is AccessControl, Pausable {
    // ─── Roles ────────────────────────────────────────────────────────────────

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    // ─── Storage ──────────────────────────────────────────────────────────────

    /// @notice Per-investor compliance data.
    /// @dev Packed into two 32-byte slots:
    ///      slot0: kycExpiry (128 bits) + investorTier (8 bits) — packed
    ///      slot1: jurisdiction (256 bits)
    ///      slot2: active (8 bits)
    struct InvestorData {
        uint128 kycExpiry;      // unix timestamp; uint128 saves a slot vs uint256
        uint8   investorTier;   // 1=retail (10k cap), 2=accredited, 3=institutional
        bytes32 jurisdiction;   // e.g. bytes32("US"), bytes32("OFAC") — cheaper than string
        bool    active;
    }

    mapping(address => InvestorData) private _investors;
    mapping(bytes32 => bool)         public  blockedJurisdictions;

    // ─── Custom Errors ────────────────────────────────────────────────────────

    error NotVerified(address investor);
    error KYCExpired(address investor, uint128 expiry);
    error JurisdictionBlocked(address investor, bytes32 jurisdiction);
    error TransfersPaused();
    error AlreadyVerified(address investor);
    error InvalidTier(uint8 tier);
    error ArrayLengthMismatch();
    error Unauthorized(address caller);

    // ─── Events ───────────────────────────────────────────────────────────────

    event InvestorAdded(address indexed investor, uint8 tier, bytes32 jurisdiction, uint128 kycExpiry);
    event InvestorRevoked(address indexed investor);
    event JurisdictionBlockedEvent(bytes32 indexed jurisdiction);
    event JurisdictionUnblockedEvent(bytes32 indexed jurisdiction);
    event TransferValidationFailed(address indexed from, address indexed to, string reason);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @notice Grants DEFAULT_ADMIN_ROLE, ADMIN_ROLE, and AGENT_ROLE to the deployer.
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, msg.sender);
    }

    // ─── Agent Functions ──────────────────────────────────────────────────────

    /// @notice Registers an investor after off-chain KYC verification.
    /// @param kycExpiry    Unix timestamp when this approval expires.
    /// @param jurisdiction bytes32-encoded country/region code, e.g. bytes32("US").
    /// @param tier         1=retail (10k cap), 2=accredited, 3=institutional.
    function addInvestor(
        address investor,
        uint128 kycExpiry,
        bytes32 jurisdiction,
        uint8   tier
    ) external onlyRole(AGENT_ROLE) {
        if (tier < 1 || tier > 3) revert InvalidTier(tier);
        _investors[investor] = InvestorData({
            kycExpiry:    kycExpiry,
            investorTier: tier,
            jurisdiction: jurisdiction,
            active:       true
        });
        emit InvestorAdded(investor, tier, jurisdiction, kycExpiry);
    }

    /// @notice Batch-registers multiple investors in a single transaction.
    function batchAddInvestors(
        address[]      calldata investors,
        InvestorData[] calldata data
    ) external onlyRole(AGENT_ROLE) {
        if (investors.length != data.length) revert ArrayLengthMismatch();
        uint256 len = investors.length;
        for (uint256 i = 0; i < len; ) {
            if (data[i].investorTier < 1 || data[i].investorTier > 3) revert InvalidTier(data[i].investorTier);
            _investors[investors[i]] = data[i];
            emit InvestorAdded(investors[i], data[i].investorTier, data[i].jurisdiction, data[i].kycExpiry);
            unchecked { ++i; }
        }
    }

    /// @notice Revokes an investor's verified status immediately.
    function revokeInvestor(address investor) external onlyRole(AGENT_ROLE) {
        _investors[investor].active = false;
        emit InvestorRevoked(investor);
    }

    // ─── Admin Functions ──────────────────────────────────────────────────────

    /// @notice Blocks all transfers involving a specific jurisdiction.
    function blockJurisdiction(bytes32 jurisdiction) external onlyRole(ADMIN_ROLE) {
        blockedJurisdictions[jurisdiction] = true;
        emit JurisdictionBlockedEvent(jurisdiction);
    }

    /// @notice Unblocks a previously blocked jurisdiction.
    function unblockJurisdiction(bytes32 jurisdiction) external onlyRole(ADMIN_ROLE) {
        blockedJurisdictions[jurisdiction] = false;
        emit JurisdictionUnblockedEvent(jurisdiction);
    }

    /// @notice Pauses all token transfers system-wide. Emergency circuit-breaker.
    function pauseAllTransfers() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Restores token transfers after a pause.
    function unpauseAllTransfers() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    /// @notice Returns true if the investor is active, KYC-valid, and in an unblocked jurisdiction.
    function isVerified(address investor) public view returns (bool) {
        InvestorData storage d = _investors[investor];
        if (!d.active)                              return false;
        if (d.kycExpiry <= block.timestamp)         return false;
        if (blockedJurisdictions[d.jurisdiction])   return false;
        return true;
    }

    /// @notice Returns the full compliance record for an investor.
    function getInvestor(address investor) external view returns (InvestorData memory) {
        return _investors[investor];
    }

    /// @notice Called by FractionalToken._update on every non-mint, non-burn transfer.
    ///         View-only — no state changes, so reentrancy is impossible.
    ///         Checks are ordered cheapest-first.
    /// @param amount Reserved for future per-amount tier enforcement; unused today.
    /// @return valid  True if the transfer may proceed.
    /// @return reason Failure code on rejection, e.g. "SENDER_KYC_EXPIRED".
    function validateTransfer(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool valid, string memory reason) {
        // amount intentionally unused; reserved for future per-amount tier enforcement
        amount;
        // 1. Global pause check
        if (paused()) return (false, "TRANSFERS_PAUSED");

        // Cache storage reads to avoid double SLOAD
        InvestorData storage fromData = _investors[from];
        InvestorData storage toData   = _investors[to];

        // 2. Sender active check
        if (!fromData.active) return (false, "SENDER_NOT_VERIFIED");

        // 3. Receiver active check
        if (!toData.active) return (false, "RECEIVER_NOT_VERIFIED");

        // 4. Sender KYC expiry
        if (fromData.kycExpiry <= block.timestamp) return (false, "SENDER_KYC_EXPIRED");

        // 5. Receiver KYC expiry
        if (toData.kycExpiry <= block.timestamp) return (false, "RECEIVER_KYC_EXPIRED");

        // 6. Sender jurisdiction
        if (blockedJurisdictions[fromData.jurisdiction]) return (false, "SENDER_JURISDICTION_BLOCKED");

        // 7. Receiver jurisdiction
        if (blockedJurisdictions[toData.jurisdiction]) return (false, "RECEIVER_JURISDICTION_BLOCKED");

        return (true, "");
    }
}
