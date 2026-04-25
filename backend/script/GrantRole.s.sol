// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";

/// @notice Grants AGENT_ROLE to an address on a deployed IdentityRegistry.
///
/// Required env vars:
///   PRIVATE_KEY                    — deployer key (must be DEFAULT_ADMIN)
///   IDENTITY_REGISTRY_ADDRESS      — deployed registry address
///   AGENT_ADDRESS                  — address to grant the role to (defaults to deployer)
contract GrantRoleScript is Script {
    function run() external {
        uint256 key      = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);

        address registry = vm.envAddress("IDENTITY_REGISTRY_ADDRESS");
        address agent    = vm.envOr("AGENT_ADDRESS", deployer);

        vm.startBroadcast(key);
        bytes32 agentRole = IdentityRegistry(registry).AGENT_ROLE();
        IdentityRegistry(registry).grantRole(agentRole, agent);
        vm.stopBroadcast();

        console.log("AGENT_ROLE granted");
        console.log("  Registry:", registry);
        console.log("  Agent:   ", agent);
    }
}
