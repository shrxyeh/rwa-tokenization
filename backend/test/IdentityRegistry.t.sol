// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";

contract IdentityRegistryTest is Test {
    IdentityRegistry public registry;

    address public admin   = address(this);
    address public agent   = makeAddr("agent");
    address public inv1    = makeAddr("investor1");
    address public inv2    = makeAddr("investor2");
    address public nobody  = makeAddr("nobody");

    bytes32 public constant JURISDICTION_US   = bytes32("US");
    bytes32 public constant JURISDICTION_OFAC = bytes32("OFAC");

    uint128 public expiry;

    function setUp() public {
        registry = new IdentityRegistry();
        registry.grantRole(registry.AGENT_ROLE(), agent);

        expiry = uint128(block.timestamp + 365 days);
    }

    // ─── addInvestor ──────────────────────────────────────────────────────────

    function test_AddInvestor_Success() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);

        assertTrue(registry.isVerified(inv1));
    }

    function test_AddInvestor_EmitsEvent() public {
        vm.prank(agent);
        vm.expectEmit(true, false, false, true);
        emit IdentityRegistry.InvestorAdded(inv1, 2, JURISDICTION_US, expiry);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);
    }

    function test_AddInvestor_InvalidTier_Reverts() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IdentityRegistry.InvalidTier.selector, 4));
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 4);
    }

    function test_AddInvestor_TierZero_Reverts() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IdentityRegistry.InvalidTier.selector, 0));
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 0);
    }

    // ─── revokeInvestor ───────────────────────────────────────────────────────

    function test_RevokeInvestor_Success() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);

        vm.prank(agent);
        registry.revokeInvestor(inv1);

        assertFalse(registry.isVerified(inv1));
    }

    function test_RevokeInvestor_NotVerifiedAfter() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 1);
        assertTrue(registry.isVerified(inv1));

        vm.prank(agent);
        registry.revokeInvestor(inv1);
        assertFalse(registry.isVerified(inv1));

        (bool valid,) = registry.validateTransfer(inv1, inv2, 100);
        assertFalse(valid);
    }

    // ─── batchAddInvestors ────────────────────────────────────────────────────

    function test_BatchAddInvestors_Success() public {
        address[] memory investors = new address[](2);
        investors[0] = inv1;
        investors[1] = inv2;

        IdentityRegistry.InvestorData[] memory data = new IdentityRegistry.InvestorData[](2);
        data[0] = IdentityRegistry.InvestorData(expiry, 2, JURISDICTION_US, true);
        data[1] = IdentityRegistry.InvestorData(expiry, 3, JURISDICTION_US, true);

        vm.prank(agent);
        registry.batchAddInvestors(investors, data);

        assertTrue(registry.isVerified(inv1));
        assertTrue(registry.isVerified(inv2));
    }

    function test_BatchAddInvestors_RevertsOnLengthMismatch() public {
        address[] memory investors = new address[](2);
        investors[0] = inv1;
        investors[1] = inv2;

        IdentityRegistry.InvestorData[] memory data = new IdentityRegistry.InvestorData[](1);
        data[0] = IdentityRegistry.InvestorData(expiry, 2, JURISDICTION_US, true);

        vm.prank(agent);
        vm.expectRevert(IdentityRegistry.ArrayLengthMismatch.selector);
        registry.batchAddInvestors(investors, data);
    }

    // ─── blockJurisdiction ────────────────────────────────────────────────────

    function test_BlockJurisdiction_BlocksTransfer() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);
        vm.prank(agent);
        registry.addInvestor(inv2, expiry, JURISDICTION_US, 2);

        registry.blockJurisdiction(JURISDICTION_US);

        (bool valid, string memory reason) = registry.validateTransfer(inv1, inv2, 100);
        assertFalse(valid);
        assertEq(reason, "SENDER_JURISDICTION_BLOCKED");
    }

    function test_UnblockJurisdiction_AllowsTransfer() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);
        vm.prank(agent);
        registry.addInvestor(inv2, expiry, JURISDICTION_US, 2);

        registry.blockJurisdiction(JURISDICTION_US);
        registry.unblockJurisdiction(JURISDICTION_US);

        (bool valid,) = registry.validateTransfer(inv1, inv2, 100);
        assertTrue(valid);
    }

    // ─── KYC expiry ───────────────────────────────────────────────────────────

    function test_KYCExpiry_FailsValidation() public {
        uint128 shortExpiry = uint128(block.timestamp + 1 days);

        vm.prank(agent);
        registry.addInvestor(inv1, shortExpiry, JURISDICTION_US, 2);
        vm.prank(agent);
        registry.addInvestor(inv2, expiry, JURISDICTION_US, 2);

        vm.warp(block.timestamp + 2 days);

        (bool valid, string memory reason) = registry.validateTransfer(inv1, inv2, 100);
        assertFalse(valid);
        assertEq(reason, "SENDER_KYC_EXPIRED");
    }

    // ─── pause / unpause ──────────────────────────────────────────────────────

    function test_GlobalPause_BlocksAllTransfers() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);
        vm.prank(agent);
        registry.addInvestor(inv2, expiry, JURISDICTION_US, 2);

        registry.pauseAllTransfers();

        (bool valid, string memory reason) = registry.validateTransfer(inv1, inv2, 100);
        assertFalse(valid);
        assertEq(reason, "TRANSFERS_PAUSED");
    }

    function test_GlobalUnpause_RestoresTransfers() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);
        vm.prank(agent);
        registry.addInvestor(inv2, expiry, JURISDICTION_US, 2);

        registry.pauseAllTransfers();
        registry.unpauseAllTransfers();

        (bool valid,) = registry.validateTransfer(inv1, inv2, 100);
        assertTrue(valid);
    }

    // ─── access control ───────────────────────────────────────────────────────

    function test_OnlyAgentCanAddInvestor() public {
        vm.prank(nobody);
        vm.expectRevert();
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);
    }

    function test_OnlyAdminCanPause() public {
        vm.prank(nobody);
        vm.expectRevert();
        registry.pauseAllTransfers();
    }

    // ─── validateTransfer ─────────────────────────────────────────────────────

    function test_ValidateTransfer_SenderNotVerified() public {
        vm.prank(agent);
        registry.addInvestor(inv2, expiry, JURISDICTION_US, 2);

        (bool valid, string memory reason) = registry.validateTransfer(inv1, inv2, 100);
        assertFalse(valid);
        assertEq(reason, "SENDER_NOT_VERIFIED");
    }

    function test_ValidateTransfer_ReceiverNotVerified() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);

        (bool valid, string memory reason) = registry.validateTransfer(inv1, inv2, 100);
        assertFalse(valid);
        assertEq(reason, "RECEIVER_NOT_VERIFIED");
    }

    function test_ValidateTransfer_BothVerified_ReturnsTrue() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);
        vm.prank(agent);
        registry.addInvestor(inv2, expiry, JURISDICTION_US, 3);

        (bool valid, string memory reason) = registry.validateTransfer(inv1, inv2, 100);
        assertTrue(valid);
        assertEq(reason, "");
    }

    function test_ValidateTransfer_SenderJurisdictionBlocked() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_OFAC, 2);
        vm.prank(agent);
        registry.addInvestor(inv2, expiry, JURISDICTION_US, 2);

        registry.blockJurisdiction(JURISDICTION_OFAC);

        (bool valid, string memory reason) = registry.validateTransfer(inv1, inv2, 100);
        assertFalse(valid);
        assertEq(reason, "SENDER_JURISDICTION_BLOCKED");
    }

    function test_ValidateTransfer_ReceiverJurisdictionBlocked() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);
        vm.prank(agent);
        registry.addInvestor(inv2, expiry, JURISDICTION_OFAC, 2);

        registry.blockJurisdiction(JURISDICTION_OFAC);

        (bool valid, string memory reason) = registry.validateTransfer(inv1, inv2, 100);
        assertFalse(valid);
        assertEq(reason, "RECEIVER_JURISDICTION_BLOCKED");
    }

    function test_ReceiverKYCExpired_FailsValidation() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);

        uint128 shortExpiry = uint128(block.timestamp + 1 days);
        vm.prank(agent);
        registry.addInvestor(inv2, shortExpiry, JURISDICTION_US, 2);

        vm.warp(block.timestamp + 2 days);

        (bool valid, string memory reason) = registry.validateTransfer(inv1, inv2, 100);
        assertFalse(valid);
        assertEq(reason, "RECEIVER_KYC_EXPIRED");
    }

    function test_GetInvestor_ReturnsCorrectData() public {
        vm.prank(agent);
        registry.addInvestor(inv1, expiry, JURISDICTION_US, 2);

        IdentityRegistry.InvestorData memory d = registry.getInvestor(inv1);
        assertEq(d.kycExpiry, expiry);
        assertEq(d.investorTier, 2);
        assertEq(d.jurisdiction, JURISDICTION_US);
        assertTrue(d.active);
    }
}
