// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

/// @title PropertyNFT
/// @notice ERC-721 representing a unique real-world property asset.
///         Each token carries fully on-chain metadata and a rendered SVG deed —
///         no IPFS dependency, no external calls, fully self-contained.
/// @dev Inherits ERC721Enumerable and ERC721URIStorage. The _update and
///      supportsInterface overrides are required by OZ v5 multiple inheritance.
contract PropertyNFT is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable {
    // ─── Storage ──────────────────────────────────────────────────────────────

    /// @notice Full metadata for a tokenized property.
    struct PropertyMetadata {
        string  name;
        string  location;
        uint256 valuationUSD;   // whole USD, e.g. 1200000 = $1,200,000
        string  legalIdentifier; // e.g. "DEED-CA-2024-00101"
        uint64  mintedAt;       // block.timestamp at mint
        address originalOwner;  // first owner recorded for audit
    }

    uint256 private _nextTokenId;

    mapping(uint256 => PropertyMetadata) public properties;

    /// @notice Maps tokenId → linked FractionalToken contract address.
    ///         Set once via linkFractionToken; immutable after that.
    mapping(uint256 => address) public fractionToken;

    // ─── Custom Errors ────────────────────────────────────────────────────────

    error FractionTokenAlreadyLinked(uint256 tokenId);
    error PropertyDoesNotExist(uint256 tokenId);
    error ZeroAddress();
    error Unauthorized(address caller);

    // ─── Events ───────────────────────────────────────────────────────────────

    event PropertyMinted(uint256 indexed tokenId, address indexed owner, string legalIdentifier);
    event FractionTokenLinked(uint256 indexed tokenId, address indexed tokenContract);
    event ValuationUpdated(uint256 indexed tokenId, uint256 oldValuation, uint256 newValuation);

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor() ERC721("RWA Property Deed", "DEED") Ownable(msg.sender) {}

    // ─── Minting ──────────────────────────────────────────────────────────────

    /// @notice Mints a property NFT with fully on-chain SVG metadata.
    /// @return tokenId The newly minted token ID.
    function mintProperty(address to, PropertyMetadata calldata meta)
        external
        onlyOwner
        returns (uint256 tokenId)
    {
        if (to == address(0)) revert ZeroAddress();
        tokenId = _nextTokenId;
        unchecked { ++_nextTokenId; }

        PropertyMetadata storage stored = properties[tokenId];
        stored.name            = meta.name;
        stored.location        = meta.location;
        stored.valuationUSD    = meta.valuationUSD;
        stored.legalIdentifier = meta.legalIdentifier;
        stored.mintedAt        = uint64(block.timestamp);
        stored.originalOwner   = to;

        // Use _mint (not _safeMint) because minting to the RWAFactory — a controlled contract
        // that immediately transfers the NFT — does not require ERC721Receiver compliance.
        _mint(to, tokenId);
        _setTokenURI(tokenId, _generateTokenURI(tokenId, meta));

        emit PropertyMinted(tokenId, to, meta.legalIdentifier);
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Links a FractionalToken contract to this NFT. One-time per tokenId.
    function linkFractionToken(uint256 tokenId, address token) external onlyOwner {
        if (!_exists(tokenId)) revert PropertyDoesNotExist(tokenId);
        if (fractionToken[tokenId] != address(0)) revert FractionTokenAlreadyLinked(tokenId);
        if (token == address(0)) revert ZeroAddress();
        fractionToken[tokenId] = token;
        emit FractionTokenLinked(tokenId, token);
    }

    /// @notice Updates the USD valuation stored in on-chain metadata.
    function updateValuation(uint256 tokenId, uint256 newValuation) external onlyOwner {
        if (!_exists(tokenId)) revert PropertyDoesNotExist(tokenId);
        uint256 old = properties[tokenId].valuationUSD;
        properties[tokenId].valuationUSD = newValuation;
        emit ValuationUpdated(tokenId, old, newValuation);
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice Returns all metadata for a given property token.
    function getPropertyDetails(uint256 tokenId) external view returns (PropertyMetadata memory) {
        if (!_exists(tokenId)) revert PropertyDoesNotExist(tokenId);
        return properties[tokenId];
    }

    // ─── On-chain SVG + Metadata URI ──────────────────────────────────────────

    /// @notice Generates a fully on-chain data URI: base64 JSON wrapping a base64 SVG.
    function _generateTokenURI(uint256 tokenId, PropertyMetadata memory meta)
        internal
        pure
        returns (string memory)
    {
        string memory svg = _buildSVG(tokenId, meta);
        string memory svgEncoded = Base64.encode(bytes(svg));

        string memory json = string(abi.encodePacked(
            '{"name":"',   _escapeJson(meta.name), '"',
            ',"description":"Tokenized real estate property deed minted on-chain via RWA Tokenization System."',
            ',"image":"data:image/svg+xml;base64,', svgEncoded, '"',
            ',"attributes":[',
                '{"trait_type":"Location","value":"',         _escapeJson(meta.location), '"},',
                '{"trait_type":"Valuation USD","value":"',    LibString.toString(meta.valuationUSD), '"},',
                '{"trait_type":"Legal Identifier","value":"', _escapeJson(meta.legalIdentifier), '"},',
                '{"trait_type":"Token ID","value":"',         LibString.toString(tokenId), '"}',
            ']}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        ));
    }

    /// @notice Renders a property deed SVG — dark background, gold border.
    function _buildSVG(uint256 tokenId, PropertyMetadata memory meta)
        internal
        pure
        returns (string memory)
    {
        string memory valStr = string(abi.encodePacked("$", _formatUSD(meta.valuationUSD)));
        string memory idStr  = string(abi.encodePacked("#", LibString.toString(tokenId)));

        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 300" width="480" height="300">',
            '<defs>',
              '<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">',
                '<stop offset="0%" style="stop-color:#0f0f0f"/>',
                '<stop offset="100%" style="stop-color:#1a1a2e"/>',
              '</linearGradient>',
              '<linearGradient id="gold" x1="0%" y1="0%" x2="100%" y2="0%">',
                '<stop offset="0%" style="stop-color:#b8860b"/>',
                '<stop offset="50%" style="stop-color:#ffd700"/>',
                '<stop offset="100%" style="stop-color:#b8860b"/>',
              '</linearGradient>',
            '</defs>',
            // Background
            '<rect width="480" height="300" fill="url(#bg)"/>',
            // Gold outer border
            '<rect x="4" y="4" width="472" height="292" rx="12" ry="12" fill="none" stroke="url(#gold)" stroke-width="2.5"/>',
            // Inner border
            '<rect x="10" y="10" width="460" height="280" rx="8" ry="8" fill="none" stroke="#b8860b" stroke-width="0.5" opacity="0.5"/>',
            // Header band
            '<rect x="4" y="4" width="472" height="44" rx="12" ry="12" fill="#b8860b" opacity="0.15"/>',
            // "PROPERTY DEED" title
            '<text x="240" y="32" font-family="Georgia,serif" font-size="11" fill="#ffd700" text-anchor="middle" letter-spacing="4" font-weight="bold">PROPERTY DEED</text>',
            // Divider
            '<line x1="40" y1="54" x2="440" y2="54" stroke="url(#gold)" stroke-width="0.8"/>',
            // Property name
            '<text x="240" y="90" font-family="Georgia,serif" font-size="20" fill="#ffffff" text-anchor="middle" font-weight="bold">',
                _escapeXml(meta.name),
            '</text>',
            // Location
            '<text x="240" y="118" font-family="Arial,sans-serif" font-size="11" fill="#a0a0b0" text-anchor="middle">',
                _escapeXml(meta.location),
            '</text>',
            // Divider
            '<line x1="120" y1="132" x2="360" y2="132" stroke="#b8860b" stroke-width="0.5" opacity="0.6"/>',
            // Valuation label + value
            '<text x="110" y="162" font-family="Arial,sans-serif" font-size="9" fill="#808090" text-anchor="middle">VALUATION</text>',
            '<text x="110" y="180" font-family="Georgia,serif" font-size="16" fill="#ffd700" text-anchor="middle" font-weight="bold">',
                valStr,
            '</text>',
            // Vertical separator
            '<line x1="240" y1="150" x2="240" y2="195" stroke="#b8860b" stroke-width="0.5" opacity="0.5"/>',
            // Legal ID label + value
            '<text x="360" y="162" font-family="Arial,sans-serif" font-size="9" fill="#808090" text-anchor="middle">LEGAL IDENTIFIER</text>',
            '<text x="360" y="180" font-family="Courier New,monospace" font-size="11" fill="#c0c0d0" text-anchor="middle">',
                _escapeXml(meta.legalIdentifier),
            '</text>',
            // Bottom divider
            '<line x1="40" y1="210" x2="440" y2="210" stroke="url(#gold)" stroke-width="0.8"/>',
            // Token ID badge
            '<rect x="20" y="255" width="68" height="24" rx="4" ry="4" fill="#b8860b" opacity="0.2" stroke="#ffd700" stroke-width="0.5"/>',
            '<text x="54" y="271" font-family="Courier New,monospace" font-size="10" fill="#ffd700" text-anchor="middle">TOKEN ', idStr, '</text>',
            // RWA stamp
            '<text x="240" y="270" font-family="Georgia,serif" font-size="9" fill="#505060" text-anchor="middle" letter-spacing="2">REAL WORLD ASSET TOKENIZATION</text>',
            // Blockchain verified badge
            '<rect x="368" y="255" width="88" height="24" rx="4" ry="4" fill="#0a2a0a" stroke="#00cc44" stroke-width="0.5"/>',
            '<text x="412" y="271" font-family="Arial,sans-serif" font-size="8" fill="#00cc44" text-anchor="middle" letter-spacing="1">&#x2713; ON-CHAIN</text>',
            '</svg>'
        ));
    }

    /// @notice Formats a USD integer with comma separators (e.g. 1200000 → "1,200,000").
    function _formatUSD(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        string memory raw = LibString.toString(value);
        bytes memory b   = bytes(raw);
        uint256 len      = b.length;
        if (len <= 3) return raw;

        // Count commas needed
        uint256 commas  = (len - 1) / 3;
        bytes memory out = new bytes(len + commas);
        uint256 j = out.length - 1;
        uint256 cnt = 0;
        for (uint256 i = len; i > 0; ) {
            unchecked { --i; }
            out[j] = b[i];
            unchecked { --j; ++cnt; }
            if (cnt % 3 == 0 && i > 0) {
                out[j] = ",";
                unchecked { --j; }
            }
        }
        return string(out);
    }

    /// @notice Escapes XML special characters for safe SVG embedding.
    function _escapeXml(string memory s) internal pure returns (string memory) {
        bytes memory b   = bytes(s);
        bytes memory out = new bytes(b.length * 6); // worst case: every char → &amp;
        uint256 j = 0;
        for (uint256 i = 0; i < b.length; ) {
            bytes1 c = b[i];
            if (c == "<") {
                out[j++] = "&"; out[j++] = "l"; out[j++] = "t"; out[j++] = ";";
            } else if (c == ">") {
                out[j++] = "&"; out[j++] = "g"; out[j++] = "t"; out[j++] = ";";
            } else if (c == "&") {
                out[j++] = "&"; out[j++] = "a"; out[j++] = "m"; out[j++] = "p"; out[j++] = ";";
            } else if (c == '"') {
                out[j++] = "&"; out[j++] = "q"; out[j++] = "u"; out[j++] = "o"; out[j++] = "t"; out[j++] = ";";
            } else {
                out[j++] = c;
            }
            unchecked { ++i; }
        }
        bytes memory trimmed = new bytes(j);
        for (uint256 k = 0; k < j; ) {
            trimmed[k] = out[k];
            unchecked { ++k; }
        }
        return string(trimmed);
    }

    /// @notice Escapes double-quotes and backslashes for JSON string safety.
    function _escapeJson(string memory s) internal pure returns (string memory) {
        bytes memory b   = bytes(s);
        bytes memory out = new bytes(b.length * 2);
        uint256 j = 0;
        for (uint256 i = 0; i < b.length; ) {
            bytes1 c = b[i];
            if (c == '"' || c == "\\") {
                out[j++] = "\\";
            }
            out[j++] = c;
            unchecked { ++i; }
        }
        bytes memory trimmed = new bytes(j);
        for (uint256 k = 0; k < j; ) {
            trimmed[k] = out[k];
            unchecked { ++k; }
        }
        return string(trimmed);
    }

    /// @notice Returns true if a token with the given ID has been minted.
    function _exists(uint256 tokenId) internal view returns (bool) {
        return tokenId < _nextTokenId;
    }

    // ─── OZ v5 Required Overrides ─────────────────────────────────────────────

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
