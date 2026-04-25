// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {PropertyNFT} from "../src/assets/PropertyNFT.sol";
import {FractionalToken} from "../src/tokens/FractionalToken.sol";
import {RWAFactory} from "../src/factory/RWAFactory.sol";

contract RWAFactoryTest is Test {
    IdentityRegistry public registry;
    PropertyNFT      public nft;
    RWAFactory       public factory;

    address public deployer = address(this);
    address public user     = makeAddr("user");

    uint256 public constant SUPPLY = 1_000 * 1e18;

    PropertyNFT.PropertyMetadata public meta;

    function setUp() public {
        registry = new IdentityRegistry();
        nft      = new PropertyNFT();
        factory  = new RWAFactory(address(registry));

        // Transfer PropertyNFT ownership to factory so it can mint
        nft.transferOwnership(address(factory));

        meta = PropertyNFT.PropertyMetadata({
            name:            "Sunset Apartments",
            location:        "Miami, FL",
            valuationUSD:    1_200_000,
            legalIdentifier: "DEED-FL-2024-00101",
            mintedAt:        0,
            originalOwner:   address(0)
        });
    }

    // ─── createAsset ──────────────────────────────────────────────────────────

    function test_CreateAsset_DeploysAllContracts() public {
        (uint256 tokenId, address token) = factory.createAsset(
            meta, "Sunset Token", "SSET", SUPPLY, address(nft)
        );

        assertTrue(token != address(0));
        assertEq(FractionalToken(payable(token)).maxSupply(), SUPPLY);
        assertEq(FractionalToken(payable(token)).linkedNFTId(), tokenId);
    }

    function test_CreateAsset_NFTTransferredToSender() public {
        (uint256 tokenId,) = factory.createAsset(
            meta, "Sunset Token", "SSET", SUPPLY, address(nft)
        );

        assertEq(nft.ownerOf(tokenId), deployer);
    }

    function test_CreateAsset_FractionTokenLinkedToNFT() public {
        (uint256 tokenId, address token) = factory.createAsset(
            meta, "Sunset Token", "SSET", SUPPLY, address(nft)
        );

        assertEq(nft.fractionToken(tokenId), token);
    }

    function test_CreateAsset_InitialSupplyMintedToSender() public {
        (, address token) = factory.createAsset(
            meta, "Sunset Token", "SSET", SUPPLY, address(nft)
        );

        assertEq(FractionalToken(payable(token)).balanceOf(deployer), SUPPLY);
    }

    function test_CreateAsset_RecordedInMapping() public {
        (uint256 tokenId, address token) = factory.createAsset(
            meta, "Sunset Token", "SSET", SUPPLY, address(nft)
        );

        RWAFactory.AssetRecord memory record = factory.getAsset(0);
        assertEq(record.tokenId,       tokenId);
        assertEq(record.fractionToken, token);
        assertEq(record.assetName,     meta.name);
        assertTrue(record.createdAt > 0);
    }

    function test_CreateAsset_EmitsEvent() public {
        vm.expectEmit(false, false, false, false); // just check it emits
        emit RWAFactory.AssetCreated(0, 0, address(0), meta.name);
        factory.createAsset(meta, "Sunset Token", "SSET", SUPPLY, address(nft));
    }

    // ─── getAllAssets ─────────────────────────────────────────────────────────

    function test_GetAllAssets_ReturnsCorrectCount() public {
        factory.createAsset(meta, "Token A", "TKA", SUPPLY, address(nft));

        RWAFactory.AssetRecord[] memory all = factory.getAllAssets();
        assertEq(all.length, 1);
    }

    function test_CreateMultipleAssets_AllTracked() public {
        factory.createAsset(meta, "Token A", "TKA", SUPPLY, address(nft));

        PropertyNFT.PropertyMetadata memory meta2 = meta;
        meta2.name = "Harbor View";
        meta2.legalIdentifier = "DEED-CA-2024-00202";
        factory.createAsset(meta2, "Token B", "TKB", SUPPLY, address(nft));

        RWAFactory.AssetRecord[] memory all = factory.getAllAssets();
        assertEq(all.length, 2);
        assertEq(all[0].assetName, "Sunset Apartments");
        assertEq(all[1].assetName, "Harbor View");
    }

    function test_GetAsset_OutOfBounds_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(RWAFactory.AssetIndexOutOfBounds.selector, 0));
        factory.getAsset(0);
    }

    // ─── CalledByUser ─────────────────────────────────────────────────────────

    function test_CreateAsset_CalledByUser_NFTGoesToUser() public {
        vm.prank(user);
        (uint256 tokenId, address token) = factory.createAsset(
            meta, "Sunset Token", "SSET", SUPPLY, address(nft)
        );

        assertEq(nft.ownerOf(tokenId), user);
        assertEq(FractionalToken(payable(token)).balanceOf(user), SUPPLY);
    }

    // ─── Zero address guard ───────────────────────────────────────────────────

    function test_Constructor_ZeroRegistry_Reverts() public {
        vm.expectRevert(RWAFactory.ZeroAddress.selector);
        new RWAFactory(address(0));
    }

    function test_CreateAsset_ZeroNFTContract_Reverts() public {
        vm.expectRevert(RWAFactory.ZeroAddress.selector);
        factory.createAsset(meta, "Token", "TKN", SUPPLY, address(0));
    }
}
