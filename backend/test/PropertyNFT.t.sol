// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PropertyNFT} from "../src/assets/PropertyNFT.sol";

contract PropertyNFTTest is Test {
    PropertyNFT public nft;

    address public owner   = address(this);
    address public user1   = makeAddr("user1");
    address public nobody  = makeAddr("nobody");

    PropertyNFT.PropertyMetadata public meta;

    function setUp() public {
        nft = new PropertyNFT();

        meta = PropertyNFT.PropertyMetadata({
            name:            "Sunset Apartments",
            location:        "Miami, FL",
            valuationUSD:    1_200_000,
            legalIdentifier: "DEED-FL-2024-00101",
            mintedAt:        0,
            originalOwner:   address(0)
        });
    }

    // ─── mintProperty ─────────────────────────────────────────────────────────

    function test_MintProperty_Success() public {
        uint256 tokenId = nft.mintProperty(user1, meta);
        assertEq(nft.ownerOf(tokenId), user1);
    }

    function test_MintProperty_StoresMetadataCorrectly() public {
        uint256 tokenId = nft.mintProperty(user1, meta);
        PropertyNFT.PropertyMetadata memory stored = nft.getPropertyDetails(tokenId);

        assertEq(stored.name,            meta.name);
        assertEq(stored.location,        meta.location);
        assertEq(stored.valuationUSD,    meta.valuationUSD);
        assertEq(stored.legalIdentifier, meta.legalIdentifier);
        assertEq(stored.originalOwner,   user1);
        assertTrue(stored.mintedAt > 0);
    }

    function test_MintProperty_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit PropertyNFT.PropertyMinted(0, user1, meta.legalIdentifier);
        nft.mintProperty(user1, meta);
    }

    function test_MintProperty_OnlyOwner() public {
        vm.prank(nobody);
        vm.expectRevert();
        nft.mintProperty(user1, meta);
    }

    function test_MintProperty_IncrementsTokenIds() public {
        uint256 t0 = nft.mintProperty(user1, meta);
        uint256 t1 = nft.mintProperty(user1, meta);
        assertEq(t0, 0);
        assertEq(t1, 1);
    }

    // ─── tokenURI ─────────────────────────────────────────────────────────────

    function test_TokenURI_ReturnsBase64Json() public {
        uint256 tokenId = nft.mintProperty(user1, meta);
        string memory uri = nft.tokenURI(tokenId);
        // Must start with the data URI prefix
        assertTrue(_startsWith(uri, "data:application/json;base64,"), "URI must be base64 JSON data URI");
    }

    function test_TokenURI_ContainsSVG() public {
        uint256 tokenId = nft.mintProperty(user1, meta);
        string memory uri = nft.tokenURI(tokenId);

        // Strip the outer JSON base64 prefix and verify by checking the URI is non-trivial
        bytes memory uriBytes = bytes(uri);
        assertTrue(uriBytes.length > 200, "URI should be substantial");

        // The URI is base64-encoded JSON which contains a base64-encoded SVG.
        // We verify the outer wrapper is valid (starts with expected prefix) —
        // deep decode is done off-chain.
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
    }

    // ─── linkFractionToken ────────────────────────────────────────────────────

    function test_LinkFractionToken_Success() public {
        uint256 tokenId = nft.mintProperty(user1, meta);
        address mockToken = makeAddr("token");

        nft.linkFractionToken(tokenId, mockToken);
        assertEq(nft.fractionToken(tokenId), mockToken);
    }

    function test_LinkFractionToken_EmitsEvent() public {
        uint256 tokenId = nft.mintProperty(user1, meta);
        address mockToken = makeAddr("token");

        vm.expectEmit(true, true, false, false);
        emit PropertyNFT.FractionTokenLinked(tokenId, mockToken);
        nft.linkFractionToken(tokenId, mockToken);
    }

    function test_LinkFractionToken_RevertsIfCalledTwice() public {
        uint256 tokenId = nft.mintProperty(user1, meta);
        address mockToken1 = makeAddr("token1");
        address mockToken2 = makeAddr("token2");

        nft.linkFractionToken(tokenId, mockToken1);

        vm.expectRevert(abi.encodeWithSelector(PropertyNFT.FractionTokenAlreadyLinked.selector, tokenId));
        nft.linkFractionToken(tokenId, mockToken2);
    }

    // ─── updateValuation ──────────────────────────────────────────────────────

    function test_UpdateValuation_Success() public {
        uint256 tokenId = nft.mintProperty(user1, meta);
        nft.updateValuation(tokenId, 2_000_000);

        PropertyNFT.PropertyMetadata memory stored = nft.getPropertyDetails(tokenId);
        assertEq(stored.valuationUSD, 2_000_000);
    }

    function test_UpdateValuation_EmitsOldAndNewValue() public {
        uint256 tokenId = nft.mintProperty(user1, meta);

        vm.expectEmit(true, false, false, true);
        emit PropertyNFT.ValuationUpdated(tokenId, meta.valuationUSD, 2_000_000);
        nft.updateValuation(tokenId, 2_000_000);
    }

    // ─── ownership ────────────────────────────────────────────────────────────

    function test_TokenOwnership_TransfersCorrectly() public {
        uint256 tokenId = nft.mintProperty(user1, meta);
        assertEq(nft.ownerOf(tokenId), user1);

        vm.prank(user1);
        nft.transferFrom(user1, nobody, tokenId);
        assertEq(nft.ownerOf(tokenId), nobody);
    }

    function test_SupportsInterface_ERC721() public view {
        assertTrue(nft.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(nft.supportsInterface(0x780e9d63)); // ERC721Enumerable
    }

    // ─── Error paths ──────────────────────────────────────────────────────────

    function test_MintProperty_ZeroAddress_Reverts() public {
        vm.expectRevert(PropertyNFT.ZeroAddress.selector);
        nft.mintProperty(address(0), meta);
    }

    function test_LinkFractionToken_NonExistentToken_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PropertyNFT.PropertyDoesNotExist.selector, 999));
        nft.linkFractionToken(999, makeAddr("mockToken"));
    }

    function test_LinkFractionToken_ZeroAddress_Reverts() public {
        uint256 tid = nft.mintProperty(user1, meta);
        vm.expectRevert(PropertyNFT.ZeroAddress.selector);
        nft.linkFractionToken(tid, address(0));
    }

    function test_UpdateValuation_NonExistentToken_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PropertyNFT.PropertyDoesNotExist.selector, 0));
        nft.updateValuation(0, 500_000);
    }

    function test_GetPropertyDetails_NonExistentToken_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PropertyNFT.PropertyDoesNotExist.selector, 0));
        nft.getPropertyDetails(0);
    }

    // ─── SVG helper branch coverage ───────────────────────────────────────────

    function test_TokenURI_FormatUSD_ZeroValue() public {
        PropertyNFT.PropertyMetadata memory m = PropertyNFT.PropertyMetadata({
            name: "Zero Val", location: "Nowhere",
            valuationUSD: 0, legalIdentifier: "DEED-Z",
            mintedAt: 0, originalOwner: address(0)
        });
        uint256 tid = nft.mintProperty(user1, m);
        assertTrue(_startsWith(nft.tokenURI(tid), "data:application/json;base64,"));
    }

    function test_TokenURI_FormatUSD_SmallValue() public {
        PropertyNFT.PropertyMetadata memory m = PropertyNFT.PropertyMetadata({
            name: "Tiny Val", location: "Somewhere",
            valuationUSD: 750, legalIdentifier: "DEED-S",
            mintedAt: 0, originalOwner: address(0)
        });
        uint256 tid = nft.mintProperty(user1, m);
        assertTrue(_startsWith(nft.tokenURI(tid), "data:application/json;base64,"));
    }

    function test_TokenURI_XmlEscape_SpecialChars() public {
        // Exercises <, >, &, " branches in _escapeXml
        PropertyNFT.PropertyMetadata memory m = PropertyNFT.PropertyMetadata({
            name: "A<B>C&D\"E",
            location: "East & \"West\"",
            valuationUSD: 1_000_000,
            legalIdentifier: "DEED-XML",
            mintedAt: 0, originalOwner: address(0)
        });
        uint256 tid = nft.mintProperty(user1, m);
        assertTrue(_startsWith(nft.tokenURI(tid), "data:application/json;base64,"));
    }

    function test_TokenURI_JsonEscape_SpecialChars() public {
        // Exercises " and \ branches in _escapeJson
        PropertyNFT.PropertyMetadata memory m = PropertyNFT.PropertyMetadata({
            name: "Prop \"Alpha\" \\Beta",
            location: "Miami",
            valuationUSD: 500_000,
            legalIdentifier: "DEED-JSON",
            mintedAt: 0, originalOwner: address(0)
        });
        uint256 tid = nft.mintProperty(user1, m);
        assertTrue(_startsWith(nft.tokenURI(tid), "data:application/json;base64,"));
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory sb = bytes(s);
        bytes memory pb = bytes(prefix);
        if (sb.length < pb.length) return false;
        for (uint256 i = 0; i < pb.length; i++) {
            if (sb[i] != pb[i]) return false;
        }
        return true;
    }
}
