// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";

/// @title PropertyNFTV2
/// @notice UUPS-upgradeable version of PropertyNFT.
///         Demonstrates the upgrade path: preserves all V1 state and adds
///         a per-token description field (simulating a regulatory annotation system).
/// @dev    Deploy via ERC1967Proxy pointing at this implementation.
///         State layout must be identical to V1 up to the new field to avoid storage collisions.
contract PropertyNFTV2 is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ─── Storage — must exactly mirror PropertyNFT V1 layout ──────────────────

    struct PropertyMetadata {
        string  name;
        string  location;
        uint256 valuationUSD;
        string  legalIdentifier;
        uint64  mintedAt;
        address originalOwner;
    }

    uint256 private _nextTokenId;
    mapping(uint256 => PropertyMetadata) public properties;
    mapping(uint256 => address)          public fractionToken;

    // ─── V2 Storage (appended after V1 — never reorder above) ─────────────────

    mapping(uint256 => string) public descriptions;

    // ─── Custom Errors ────────────────────────────────────────────────────────

    error FractionTokenAlreadyLinked(uint256 tokenId);
    error PropertyDoesNotExist(uint256 tokenId);
    error ZeroAddress();

    // ─── Events ───────────────────────────────────────────────────────────────

    event PropertyMinted(uint256 indexed tokenId, address indexed owner, string legalIdentifier);
    event FractionTokenLinked(uint256 indexed tokenId, address indexed tokenContract);
    event ValuationUpdated(uint256 indexed tokenId, uint256 oldValuation, uint256 newValuation);
    event DescriptionUpdated(uint256 indexed tokenId, string description);

    // ─── Initializer ──────────────────────────────────────────────────────────

    /// @notice Replaces constructor for upgradeable contracts.
    /// @param initialOwner  The address that will own the proxy.
    function initialize(address initialOwner) public initializer {
        __ERC721_init("RWA Property Deed", "DEED");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __Ownable_init(initialOwner);
    }

    // ─── V2 New Feature ───────────────────────────────────────────────────────

    /// @notice Appends or updates a regulatory/legal description for a token.
    ///         In production this would store jurisdiction-specific annotations.
    /// @param tokenId      Token to annotate.
    /// @param description  Free-text description (e.g. "Lien released 2025-01-01").
    function updateDescription(uint256 tokenId, string calldata description) external onlyOwner {
        if (!_exists(tokenId)) revert PropertyDoesNotExist(tokenId);
        descriptions[tokenId] = description;
        emit DescriptionUpdated(tokenId, description);
    }

    // ─── Carried-over V1 Functions ────────────────────────────────────────────

    /// @notice Mints a new property NFT. Identical to V1.
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

        _mint(to, tokenId);
        _setTokenURI(tokenId, _generateTokenURI(tokenId, meta));

        emit PropertyMinted(tokenId, to, meta.legalIdentifier);
    }

    /// @notice Links a FractionalToken to this NFT. One-time.
    function linkFractionToken(uint256 tokenId, address token) external onlyOwner {
        if (!_exists(tokenId)) revert PropertyDoesNotExist(tokenId);
        if (fractionToken[tokenId] != address(0)) revert FractionTokenAlreadyLinked(tokenId);
        if (token == address(0)) revert ZeroAddress();
        fractionToken[tokenId] = token;
        emit FractionTokenLinked(tokenId, token);
    }

    /// @notice Updates stored USD valuation.
    function updateValuation(uint256 tokenId, uint256 newValuation) external onlyOwner {
        if (!_exists(tokenId)) revert PropertyDoesNotExist(tokenId);
        uint256 old = properties[tokenId].valuationUSD;
        properties[tokenId].valuationUSD = newValuation;
        emit ValuationUpdated(tokenId, old, newValuation);
    }

    /// @notice Returns full property metadata.
    function getPropertyDetails(uint256 tokenId) external view returns (PropertyMetadata memory) {
        if (!_exists(tokenId)) revert PropertyDoesNotExist(tokenId);
        return properties[tokenId];
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return tokenId < _nextTokenId;
    }

    function _generateTokenURI(uint256 tokenId, PropertyMetadata memory meta)
        internal
        pure
        returns (string memory)
    {
        string memory json = string(abi.encodePacked(
            '{"name":"', meta.name, '"',
            ',"description":"Tokenized real estate property deed."',
            ',"attributes":[',
                '{"trait_type":"Location","value":"',         meta.location, '"},',
                '{"trait_type":"Valuation USD","value":"',    LibString.toString(meta.valuationUSD), '"},',
                '{"trait_type":"Legal Identifier","value":"', meta.legalIdentifier, '"},',
                '{"trait_type":"Token ID","value":"',         LibString.toString(tokenId), '"}',
            ']}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    // ─── UUPS Authorization ───────────────────────────────────────────────────

    /// @dev Only the owner can authorize a contract upgrade.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ─── OZ Required Overrides ────────────────────────────────────────────────

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
