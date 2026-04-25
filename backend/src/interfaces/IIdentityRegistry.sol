// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IIdentityRegistry
/// @notice Minimal interface consumed by FractionalToken and RWAFactory.
interface IIdentityRegistry {
    /// @notice Returns true if the investor is active, KYC-valid, and in an unblocked jurisdiction.
    function isVerified(address investor) external view returns (bool);

    /// @notice Validates a pending transfer against all compliance rules.
    /// @return valid  True if the transfer is permitted.
    /// @return reason Short failure code if rejected, e.g. "SENDER_KYC_EXPIRED".
    function validateTransfer(address from, address to, uint256 amount)
        external view returns (bool valid, string memory reason);

    /// @notice Returns the raw compliance record for an investor.
    /// @return kycExpiry     Unix timestamp of KYC expiration.
    /// @return investorTier  1=retail, 2=accredited, 3=institutional.
    /// @return jurisdiction  bytes32-encoded country code.
    /// @return active        Whether the investor is currently active.
    function getInvestor(address investor) external view returns (
        uint128 kycExpiry,
        uint8   investorTier,
        bytes32 jurisdiction,
        bool    active
    );
}
