// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployScript}   from "../script/Deploy.s.sol";
import {DemoScript}     from "../script/Demo.s.sol";
import {GrantRoleScript} from "../script/GrantRole.s.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {PropertyNFT}      from "../src/assets/PropertyNFT.sol";
import {FractionalToken}  from "../src/tokens/FractionalToken.sol";
import {RWAFactory}       from "../src/factory/RWAFactory.sol";

contract ScriptsTest is Test {
    string  constant PK       = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        vm.setEnv("PRIVATE_KEY", PK);
    }

    // ─── Deploy ───────────────────────────────────────────────────────────────

    function test_DeployScript_DeploysAllThreeContracts() public {
        DeployScript s = new DeployScript();
        s.run();
    }

    function test_DeployScript_RegistryIsDeployedFirst() public {
        DeployScript s1 = new DeployScript();
        DeployScript s2 = new DeployScript();
        s1.run();
        s2.run();
    }

    // ─── Demo ─────────────────────────────────────────────────────────────────

    function test_DemoScript_FullLifecycle() public {
        DemoScript s = new DemoScript();
        s.run();
    }

    function test_DemoScript_KYCsInvestors() public {
        DemoScript s = new DemoScript();
        s.run();

        address inv1 = vm.addr(1);
        address inv2 = vm.addr(2);
        address inv3 = vm.addr(3);

        IdentityRegistry registry = new IdentityRegistry();
        uint128 expiry = uint128(block.timestamp + 365 days);
        registry.addInvestor(inv1, expiry, bytes32("US"), 1);
        registry.addInvestor(inv2, expiry, bytes32("US"), 2);
        registry.addInvestor(inv3, expiry, bytes32("US"), 3);

        assertTrue(registry.isVerified(inv1));
        assertTrue(registry.isVerified(inv2));
        assertTrue(registry.isVerified(inv3));
    }

    function test_DemoScript_ComplianceBlocksUnverified() public {
        DemoScript s = new DemoScript();
        s.run();

        IdentityRegistry registry = new IdentityRegistry();
        address ghost = makeAddr("ghost");

        uint128 expiry = uint128(block.timestamp + 365 days);
        registry.addInvestor(DEPLOYER, expiry, bytes32("US"), 3);

        (bool valid, string memory reason) = registry.validateTransfer(
            DEPLOYER, ghost, 100 * 1e18
        );
        assertFalse(valid);
        assertEq(reason, "RECEIVER_NOT_VERIFIED");
    }

    // ─── GrantRole ────────────────────────────────────────────────────────────

    function test_GrantRoleScript_GrantsAgentRoleToDeployer() public {
        vm.prank(DEPLOYER);
        IdentityRegistry registry = new IdentityRegistry();

        vm.setEnv("IDENTITY_REGISTRY_ADDRESS", vm.toString(address(registry)));

        GrantRoleScript s = new GrantRoleScript();
        s.run();

        assertTrue(registry.hasRole(registry.AGENT_ROLE(), DEPLOYER));
    }

    function test_GrantRoleScript_GrantsAgentRoleToCustomAddress() public {
        address customAgent = makeAddr("customAgent");

        vm.prank(DEPLOYER);
        IdentityRegistry registry = new IdentityRegistry();

        vm.setEnv("IDENTITY_REGISTRY_ADDRESS", vm.toString(address(registry)));
        vm.setEnv("AGENT_ADDRESS", vm.toString(customAgent));

        GrantRoleScript s = new GrantRoleScript();
        s.run();

        assertTrue(registry.hasRole(registry.AGENT_ROLE(), customAgent));
    }

    function test_GrantRoleScript_AgentCanAddInvestorAfterGrant() public {
        address agent = makeAddr("agent");

        vm.prank(DEPLOYER);
        IdentityRegistry registry = new IdentityRegistry();

        vm.setEnv("IDENTITY_REGISTRY_ADDRESS", vm.toString(address(registry)));
        vm.setEnv("AGENT_ADDRESS", vm.toString(agent));

        GrantRoleScript s = new GrantRoleScript();
        s.run();

        vm.prank(agent);
        registry.addInvestor(
            makeAddr("investor"),
            uint128(block.timestamp + 365 days),
            bytes32("US"),
            2
        );
        assertTrue(registry.isVerified(makeAddr("investor")));
    }
}
