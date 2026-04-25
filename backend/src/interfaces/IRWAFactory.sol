// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PropertyNFT} from "../assets/PropertyNFT.sol";

/// @title IRWAFactory
/// @notice External interface for the RWAFactory contract.
interface IRWAFactory {
    struct AssetRecord {
        uint256 tokenId;
        address fractionToken;
        string  assetName;
        uint256 createdAt;
    }

    /// @notice Deploys a FractionalToken and mints a PropertyNFT in one transaction.
    function createAsset(
        PropertyNFT.PropertyMetadata calldata meta,
        string calldata tokenName,
        string calldata tokenSymbol,
        uint256 fractionSupply,
        address propertyNFTContract
    ) external returns (uint256 tokenId, address token);

    /// @notice Returns all ever-created asset records.
    function getAllAssets() external view returns (AssetRecord[] memory arr);

    /// @notice Returns a single asset record by index.
    function getAsset(uint256 index) external view returns (AssetRecord memory);

    /// @notice Total number of assets created.
    function assetCount() external view returns (uint256);

    /// @notice The compliance registry used for every asset.
    function identityRegistry() external view returns (address);
}
