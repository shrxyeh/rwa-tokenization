// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {PropertyNFT} from "../src/assets/PropertyNFT.sol";
import {RWAFactory} from "../src/factory/RWAFactory.sol";

/// @notice Deploys the core RWA system contracts to the target network.
///
/// Usage:
///   # Sepolia testnet
///   source .env
///   forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
///
///   # Local anvil
///   forge script script/Deploy.s.sol --rpc-url localhost --broadcast
contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. Deploy compliance registry
        IdentityRegistry registry = new IdentityRegistry();
        console.log("IdentityRegistry deployed:", address(registry));

        // 2. Deploy property NFT
        PropertyNFT nft = new PropertyNFT();
        console.log("PropertyNFT deployed:     ", address(nft));

        // 3. Deploy factory — links registry
        RWAFactory factory = new RWAFactory(address(registry));
        console.log("RWAFactory deployed:      ", address(factory));

        // 4. Transfer NFT ownership to factory so it can mint on behalf of users
        nft.transferOwnership(address(factory));
        console.log("PropertyNFT ownership transferred to factory");

        vm.stopBroadcast();

        console.log("---");
        console.log("Deployer:", deployer);
        console.log("Network:  block", block.number);
        console.log("---");
        console.log("Next steps:");
        console.log("  1. Add yourself as AGENT_ROLE:  registry.grantRole(AGENT_ROLE, deployer)");
        console.log("  2. Run the demo script:         forge script script/Demo.s.sol --rpc-url localhost --broadcast");
    }
}
