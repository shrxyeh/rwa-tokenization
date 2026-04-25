// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PropertyNFT} from "../assets/PropertyNFT.sol";
import {FractionalToken} from "../tokens/FractionalToken.sol";

/// @title RWAFactory
/// @notice One-transaction orchestrator that:
///         1. Mints a PropertyNFT to itself
///         2. Deploys a FractionalToken linked to that NFT
///         3. Links the FractionalToken back to the NFT
///         4. Mints the initial supply to the caller
///         5. Transfers the NFT to the caller
///         All in a single atomic call — either everything succeeds or nothing does.
contract RWAFactory {
    // ─── Immutables ───────────────────────────────────────────────────────────

    address public immutable identityRegistry;

    // ─── Storage ──────────────────────────────────────────────────────────────

    struct AssetRecord {
        uint256 tokenId;
        address fractionToken;
        string  assetName;
        uint256 createdAt;
    }

    uint256 public assetCount;
    mapping(uint256 => AssetRecord) public assets;

    // ─── Custom Errors ────────────────────────────────────────────────────────

    error ZeroAddress();
    error AssetIndexOutOfBounds(uint256 index);

    // ─── Events ───────────────────────────────────────────────────────────────

    event AssetCreated(
        uint256 indexed assetIndex,
        uint256 indexed tokenId,
        address indexed fractionToken,
        string  assetName
    );

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param _identityRegistry  Address of the deployed IdentityRegistry contract.
    constructor(address _identityRegistry) {
        if (_identityRegistry == address(0)) revert ZeroAddress();
        identityRegistry = _identityRegistry;
    }

    // ─── Core ─────────────────────────────────────────────────────────────────

    /// @notice Creates a fully-linked RWA asset in one atomic transaction.
    ///         PropertyNFT must have this factory set as owner before calling.
    /// @return tokenId The minted NFT id.
    /// @return token   The deployed FractionalToken address.
    function createAsset(
        PropertyNFT.PropertyMetadata calldata meta,
        string  calldata tokenName,
        string  calldata tokenSymbol,
        uint256          fractionSupply,
        address          propertyNFTContract
    ) external returns (uint256 tokenId, address token) {
        if (propertyNFTContract == address(0)) revert ZeroAddress();

        PropertyNFT nft = PropertyNFT(propertyNFTContract);

        // 1. Mint the NFT to this factory (so we can link before handing off)
        tokenId = nft.mintProperty(address(this), meta);

        // 2. Deploy the FractionalToken; factory is the initial owner
        FractionalToken ft = new FractionalToken(
            tokenName,
            tokenSymbol,
            tokenId,
            propertyNFTContract,
            identityRegistry,
            fractionSupply
        );
        token = address(ft);

        // 3. Record the link in the NFT contract (one-time, immutable after this)
        nft.linkFractionToken(tokenId, token);

        // 4. Mint all fractional tokens to the caller
        ft.mintInitialSupply(msg.sender);

        // 5. Transfer FractionalToken ownership to the caller so they can deposit dividends
        ft.transferOwnership(msg.sender);

        // 6. Transfer NFT to the caller
        nft.transferFrom(address(this), msg.sender, tokenId);

        // 7. Record asset
        uint256 index = assetCount;
        assets[index] = AssetRecord({
            tokenId:       tokenId,
            fractionToken: token,
            assetName:     meta.name,
            createdAt:     block.timestamp
        });
        unchecked { ++assetCount; }

        emit AssetCreated(index, tokenId, token, meta.name);
    }

    // ─── Views ────────────────────────────────────────────────────────────────

    /// @notice Returns the AssetRecord at a given index.
    function getAsset(uint256 index) external view returns (AssetRecord memory) {
        if (index >= assetCount) revert AssetIndexOutOfBounds(index);
        return assets[index];
    }

    /// @notice Returns all AssetRecords in creation order.
    function getAllAssets() external view returns (AssetRecord[] memory arr) {
        uint256 count = assetCount;
        arr = new AssetRecord[](count);
        for (uint256 i = 0; i < count; ) {
            arr[i] = assets[i];
            unchecked { ++i; }
        }
    }
}
