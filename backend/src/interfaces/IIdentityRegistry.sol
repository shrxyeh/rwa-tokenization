// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface consumed by FractionalToken and RWAFactory.
interface IIdentityRegistry {
    /// @notice Returns true if the investor is active, KYC-valid, and not in a blocked jurisdiction.
    function isVerified(address investor) external view returns (bool);

    /// @notice Validates a transfer against all compliance rules.
    /// @return valid   True if permitted.
    /// @return reason  Short failure code if rejected (e.g. "SENDER_KYC_EXPIRED").
    function validateTransfer(address from, address to, uint256 amount)
        external view returns (bool valid, string memory reason);

    /// @notice Returns the raw compliance record for an investor.
    function getInvestor(address investor) external view returns (
        uint128 kycExpiry,
        uint8   investorTier,
        bytes32 jurisdiction,
        bool    active
    );
}
