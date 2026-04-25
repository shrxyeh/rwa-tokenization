// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFractionalToken
/// @notice Minimal interface consumed by RWAFactory.
interface IFractionalToken {
    /// @notice Mints the full initial supply to `to`. Callable once only by the owner.
    function mintInitialSupply(address to) external;

    /// @notice Deposits ETH to be distributed to token holders as a new dividend round.
    function depositDividend() external payable;

    /// @notice Claims the caller's share of a given dividend round.
    function claimDividend(uint256 roundId) external;

    /// @notice PropertyNFT token ID this contract fractionalizes.
    function linkedNFTId() external view returns (uint256);
}
