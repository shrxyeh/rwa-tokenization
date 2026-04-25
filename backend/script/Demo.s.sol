// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {PropertyNFT} from "../src/assets/PropertyNFT.sol";
import {FractionalToken} from "../src/tokens/FractionalToken.sol";
import {RWAFactory} from "../src/factory/RWAFactory.sol";

/// @notice Full end-to-end demo: deploy, KYC 3 investors, create property,
///         distribute tokens, execute a valid transfer, catch a blocked transfer.
///
/// Usage (local anvil):
///   anvil &
///   source .env
///   forge script script/Demo.s.sol --rpc-url localhost --broadcast
contract DemoScript is Script {
    // Shared state threaded through internal helpers to keep stack depth low
    IdentityRegistry internal _registry;
    PropertyNFT      internal _nft;
    RWAFactory       internal _factory;
    FractionalToken  internal _ft;

    address internal _deployer;
    address internal _inv1;
    address internal _inv2;
    address internal _inv3;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        _deployer = vm.addr(deployerKey);
        _inv1     = vm.addr(1);
        _inv2     = vm.addr(2);
        _inv3     = vm.addr(3);

        console.log("=== RWA Tokenization Demo ===");
        console.log("Deployer:   ", _deployer);
        console.log("Investor 1: ", _inv1);
        console.log("Investor 2: ", _inv2);
        console.log("Investor 3: ", _inv3);
        console.log("---");

        vm.startBroadcast(deployerKey);
        _deployContracts();
        _kycInvestors();
        _createProperty();
        _distributeTokens();
        _demonstrateCompliance();
        vm.stopBroadcast();

        console.log("---");
        console.log("=== Demo complete ===");
    }

    function _deployContracts() internal {
        _registry = new IdentityRegistry();
        _nft      = new PropertyNFT();
        _factory  = new RWAFactory(address(_registry));
        _nft.transferOwnership(address(_factory));

        console.log("[1] Contracts deployed");
        console.log("    IdentityRegistry:", address(_registry));
        console.log("    PropertyNFT:     ", address(_nft));
        console.log("    RWAFactory:      ", address(_factory));
    }

    function _kycInvestors() internal {
        uint128 kycExpiry    = uint128(block.timestamp + 365 days);
        bytes32 jurisdiction = bytes32("US");

        // Deployer must also be verified to distribute tokens as asset manager
        _registry.addInvestor(_deployer, kycExpiry, jurisdiction, 3);
        _registry.addInvestor(_inv1,     kycExpiry, jurisdiction, 1); // retail
        _registry.addInvestor(_inv2,     kycExpiry, jurisdiction, 2); // accredited
        _registry.addInvestor(_inv3,     kycExpiry, jurisdiction, 3); // institutional

        console.log("[2] Investors KYC'd");
        console.log("    inv1 tier-1 (retail, 10k cap)");
        console.log("    inv2 tier-2 (accredited)");
        console.log("    inv3 tier-3 (institutional)");
    }

    function _createProperty() internal {
        PropertyNFT.PropertyMetadata memory meta = PropertyNFT.PropertyMetadata({
            name:            "Sunset Apartments, Miami, FL",
            location:        "1234 Ocean Drive, Miami Beach, FL 33139",
            valuationUSD:    1_200_000,
            legalIdentifier: "DEED-FL-2024-00101",
            mintedAt:        0,
            originalOwner:   address(0)
        });

        address tokenAddr;
        uint256 tokenId;
        (tokenId, tokenAddr) = _factory.createAsset(
            meta, "Sunset Apartments Token", "SSAT", 1_000_000 * 1e18, address(_nft)
        );
        _ft = FractionalToken(payable(tokenAddr));

        console.log("[3] Property NFT minted");
        console.log("    Token ID:        ", tokenId);
        console.log("    NFT owner:       ", _nft.ownerOf(tokenId));
        console.log("    Fraction token:  ", tokenAddr);
        console.log("    Total supply:    ", _ft.totalSupply() / 1e18, "tokens");
    }

    function _distributeTokens() internal {
        _ft.transfer(_inv1, 333_000 * 1e18);
        _ft.transfer(_inv2, 333_000 * 1e18);
        _ft.transfer(_inv3, 334_000 * 1e18);

        console.log("[4] Tokens distributed");
        console.log("    inv1:", _ft.balanceOf(_inv1) / 1e18, "tokens (33.3%)");
        console.log("    inv2:", _ft.balanceOf(_inv2) / 1e18, "tokens (33.3%)");
        console.log("    inv3:", _ft.balanceOf(_inv3) / 1e18, "tokens (33.4%)");
    }

    function _demonstrateCompliance() internal {
        // Valid transfer: inv2 → inv3 (both tier-2/3, no cap issues)
        (bool valid, string memory reason) = _registry.validateTransfer(_inv2, _inv3, 1_000 * 1e18);
        if (valid) {
            console.log("[5] Compliance check inv2->inv3: PASSED");
        } else {
            console.log("[5] Compliance check FAILED:", reason);
        }

        // Blocked transfer: inv1 → non-whitelisted address
        address ghost = makeAddr("ghost");
        (bool blocked, string memory blockReason) = _registry.validateTransfer(_inv1, ghost, 100 * 1e18);
        if (!blocked) {
            console.log("[6] Transfer to unverified BLOCKED:", blockReason);
        }

        // Jurisdiction block demo
        _registry.blockJurisdiction(bytes32("OFAC"));
        console.log("[7] Jurisdiction 'OFAC' blocked");
        console.log("    All transfers involving OFAC addresses are now rejected.");
    }
}
