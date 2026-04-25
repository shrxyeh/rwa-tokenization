// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PropertyNFT} from "../assets/PropertyNFT.sol";

/// @title IPropertyNFT
/// @notice Interface consumed by RWAFactory to mint and link properties.
interface IPropertyNFT {
    /// @notice Mints a new property NFT. Returns the new token ID.
    function mintProperty(address to, PropertyNFT.PropertyMetadata calldata meta)
        external returns (uint256 tokenId);

    /// @notice Links a FractionalToken contract to a token. One-time per tokenId.
    function linkFractionToken(uint256 tokenId, address token) external;

    /// @notice ERC-721 transfer used by the factory to hand the NFT to the caller.
    function transferFrom(address from, address to, uint256 tokenId) external;

    /// @notice Returns the FractionalToken address linked to a tokenId (0 if unlinked).
    function fractionToken(uint256 tokenId) external view returns (address);
}
