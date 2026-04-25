// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {PropertyNFT} from "../src/assets/PropertyNFT.sol";
import {FractionalToken} from "../src/tokens/FractionalToken.sol";
import {RWAFactory} from "../src/factory/RWAFactory.sol";

/// @dev End-to-end integration tests for the full RWA compliance flow.
contract ComplianceTest is Test {
    IdentityRegistry public registry;
    PropertyNFT      public nft;
    RWAFactory       public factory;

    address public admin = address(this);
    address public agent = makeAddr("agent");

    address public inv1 = makeAddr("investor1");
    address public inv2 = makeAddr("investor2");
    address public inv3 = makeAddr("investor3");
    address public unverified = makeAddr("unverified");

    uint128 public expiry;
    bytes32 public constant JURISDICTION_US = bytes32("US");

    uint256 public constant SUPPLY = 100_000 * 1e18;

    PropertyNFT.PropertyMetadata public meta;

    function setUp() public {
        registry = new IdentityRegistry();
        registry.grantRole(registry.AGENT_ROLE(), agent);

        nft = new PropertyNFT();
        factory = new RWAFactory(address(registry));
        nft.transferOwnership(address(factory));

        expiry = uint128(block.timestamp + 365 days);

        // Admin (property owner) must be a verified investor to distribute initial supply.
        // In a real system the asset manager would hold institutional tier clearance.
        vm.prank(agent);
        registry.addInvestor(admin, expiry, JURISDICTION_US, 3); // tier-3: institutional

        meta = PropertyNFT.PropertyMetadata({
            name:            "Sunset Apartments",
            location:        "Miami, FL",
            valuationUSD:    1_200_000,
            legalIdentifier: "DEED-FL-2024-00101",
            mintedAt:        0,
            originalOwner:   address(0)
        });
    }

    function _addInvestor(address inv, uint8 tier) internal {
        vm.prank(agent);
        registry.addInvestor(inv, expiry, JURISDICTION_US, tier);
    }

    function _createAsset() internal returns (uint256 tokenId, FractionalToken token) {
        address tokenAddr;
        (tokenId, tokenAddr) = factory.createAsset(
            meta, "Sunset Token", "SSET", SUPPLY, address(nft)
        );
        token = FractionalToken(payable(tokenAddr));
    }

    // ─── Full flow ────────────────────────────────────────────────────────────

    function test_FullFlow_CreateAsset_AddInvestors_Distribute_Transfer() public {
        // Create property
        (, FractionalToken token) = _createAsset();

        // Add 3 investors: tier1, tier2, tier3
        _addInvestor(inv1, 1); // retail — 10k cap
        _addInvestor(inv2, 2); // accredited
        _addInvestor(inv3, 3); // institutional

        // Distribute tokens — admin holds SUPPLY, distribute portions
        // Tier1 limit is 10_000 tokens
        token.transfer(inv1, 5_000 * 1e18);
        token.transfer(inv2, 300 * 1e18);
        token.transfer(inv3, 200 * 1e18);
        // admin keeps 495 tokens + dust

        // Transfer between tier2 and tier3 → succeeds
        vm.prank(inv2); token.delegate(inv2);
        vm.prank(inv3); token.delegate(inv3);
        vm.roll(block.number + 1);

        vm.prank(inv2);
        token.transfer(inv3, 100 * 1e18);
        assertEq(token.balanceOf(inv3), 300 * 1e18);

        // Attempt transfer to non-whitelisted address → reverts
        vm.prank(inv3);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.ComplianceTransferBlocked.selector,
            "RECEIVER_NOT_VERIFIED"
        ));
        token.transfer(unverified, 10 * 1e18);
    }

    // ─── Admin revokes investor mid-flow ──────────────────────────────────────

    function test_AdminRevokesInvestorMidFlow() public {
        (, FractionalToken token) = _createAsset();
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 2);

        token.transfer(inv1, 100 * 1e18);
        vm.prank(inv1); token.delegate(inv1);

        // First transfer succeeds
        vm.prank(inv1); token.transfer(inv2, 10 * 1e18);
        assertEq(token.balanceOf(inv2), 10 * 1e18);

        // Admin revokes inv2
        vm.prank(agent);
        registry.revokeInvestor(inv2);

        // Now sending to inv2 reverts
        vm.prank(inv1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.ComplianceTransferBlocked.selector,
            "RECEIVER_NOT_VERIFIED"
        ));
        token.transfer(inv2, 10 * 1e18);
    }

    // ─── Expired KYC blocks transfer ──────────────────────────────────────────

    function test_ExpiredKYC_BlocksTransfer() public {
        (, FractionalToken token) = _createAsset();
        _addInvestor(inv1, 2);

        uint128 shortExpiry = uint128(block.timestamp + 1 days);
        vm.prank(agent);
        registry.addInvestor(inv2, shortExpiry, JURISDICTION_US, 2);

        token.transfer(inv1, 100 * 1e18);
        vm.prank(inv1); token.delegate(inv1);

        vm.warp(block.timestamp + 2 days);

        vm.prank(inv1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.ComplianceTransferBlocked.selector,
            "RECEIVER_KYC_EXPIRED"
        ));
        token.transfer(inv2, 10 * 1e18);
    }

    // ─── Full dividend cycle ──────────────────────────────────────────────────

    function test_DividendFullCycle() public {
        (, FractionalToken token) = _createAsset();
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 2);

        // Distribute ALL tokens: inv1 gets 60%, inv2 gets 40%, admin keeps none
        uint256 total = token.totalSupply();
        uint256 inv1Share = (total * 60) / 100;
        uint256 inv2Share = total - inv1Share;

        token.transfer(inv1, inv1Share);
        token.transfer(inv2, inv2Share);

        vm.prank(inv1); token.delegate(inv1);
        vm.prank(inv2); token.delegate(inv2);

        vm.roll(block.number + 1);

        // Owner deposits 1 ETH dividend
        vm.deal(admin, 1 ether);
        token.depositDividend{value: 1 ether}();
        assertEq(token.roundCount(), 1);

        vm.roll(block.number + 1);

        uint256 b1before = inv1.balance;
        uint256 b2before = inv2.balance;

        // Both investors claim
        vm.prank(inv1); token.claimDividend(0);
        vm.prank(inv2); token.claimDividend(0);

        // With ALL tokens distributed at 60/40, payouts are 0.6 ETH / 0.4 ETH
        assertEq(inv1.balance - b1before, 0.6 ether);
        assertEq(inv2.balance - b2before, 0.4 ether);

        // Third claim attempt from inv1 reverts
        vm.prank(inv1);
        vm.expectRevert(abi.encodeWithSelector(FractionalToken.AlreadyClaimed.selector, inv1, 0));
        token.claimDividend(0);
    }

    // ─── Jurisdiction block mid-flight ────────────────────────────────────────

    function test_JurisdictionBlock_MidFlight() public {
        (, FractionalToken token) = _createAsset();
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 2);

        token.transfer(inv1, 200 * 1e18);
        vm.prank(inv1); token.delegate(inv1);

        // First transfer succeeds
        vm.prank(inv1); token.transfer(inv2, 50 * 1e18);
        assertEq(token.balanceOf(inv2), 50 * 1e18);

        // Admin blocks "US" jurisdiction
        registry.blockJurisdiction(JURISDICTION_US);

        // Second transfer reverts — sender is blocked
        vm.prank(inv1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.ComplianceTransferBlocked.selector,
            "SENDER_JURISDICTION_BLOCKED"
        ));
        token.transfer(inv2, 50 * 1e18);
    }

    // ─── transferFrom via approval ────────────────────────────────────────────

    function test_TransferFrom_ApprovedSpender_ComplianceEnforced() public {
        (, FractionalToken token) = _createAsset();
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 2);

        token.transfer(inv1, 200 * 1e18);

        // inv1 approves inv2 to spend
        vm.prank(inv1);
        token.approve(inv2, 100 * 1e18);

        // inv2 executes transferFrom to themselves — passes compliance
        vm.prank(inv2);
        token.transferFrom(inv1, inv2, 50 * 1e18);
        assertEq(token.balanceOf(inv2), 50 * 1e18);

        // Try transferFrom to unverified — fails compliance
        vm.prank(inv2);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.ComplianceTransferBlocked.selector,
            "RECEIVER_NOT_VERIFIED"
        ));
        token.transferFrom(inv1, unverified, 50 * 1e18);
    }

    // ─── Tier 1 cap in full flow ──────────────────────────────────────────────

    function test_Tier1Cap_InFullFlow() public {
        (, FractionalToken token) = _createAsset();
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 1); // retail tier1

        // Give inv1 15_000 tokens; transfer 9_000 to inv2 (under the 10k cap) — succeeds
        token.transfer(inv1, 15_000 * 1e18);
        vm.prank(inv1); token.delegate(inv1);

        vm.prank(inv1);
        token.transfer(inv2, 9_000 * 1e18);
        assertEq(token.balanceOf(inv2), 9_000 * 1e18);
    }

    function test_Tier1Cap_ExactlyAtLimit_Succeeds() public {
        (, FractionalToken token) = _createAsset();
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 1);

        uint256 cap = token.TIER1_MAX_BALANCE(); // pre-cache to avoid consuming prank
        token.transfer(inv1, cap);
        vm.prank(inv1); token.delegate(inv1);

        // Send exactly 10_000 tokens to tier-1 investor — should succeed
        vm.prank(inv1);
        token.transfer(inv2, cap);
        assertEq(token.balanceOf(inv2), cap);
    }

    function test_Tier1Cap_OneBeyondLimit_Reverts() public {
        (, FractionalToken token) = _createAsset();
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 1);

        uint256 cap = token.TIER1_MAX_BALANCE(); // pre-cache to avoid consuming prank
        token.transfer(inv1, cap + 1);
        vm.prank(inv1); token.delegate(inv1);

        vm.prank(inv1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.TierLimitExceeded.selector,
            inv2, 0, cap + 1, cap
        ));
        token.transfer(inv2, cap + 1);
    }
}
