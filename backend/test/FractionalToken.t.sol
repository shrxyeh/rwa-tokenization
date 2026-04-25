// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {PropertyNFT} from "../src/assets/PropertyNFT.sol";
import {FractionalToken} from "../src/tokens/FractionalToken.sol";

contract FractionalTokenTest is Test {
    IdentityRegistry public registry;
    PropertyNFT      public nft;
    FractionalToken  public token;

    address public owner  = address(this);
    address public agent  = makeAddr("agent");
    address public inv1   = makeAddr("investor1");
    address public inv2   = makeAddr("investor2");
    address public nobody = makeAddr("nobody");

    uint256 public constant SUPPLY = 1_000 * 1e18;
    uint128 public expiry;
    uint256 public tokenId;

    function setUp() public {
        registry = new IdentityRegistry();
        registry.grantRole(registry.AGENT_ROLE(), agent);
        nft = new PropertyNFT();

        // Mint an NFT for context (token is not linked via factory here, just direct)
        PropertyNFT.PropertyMetadata memory meta = PropertyNFT.PropertyMetadata({
            name: "Test Property", location: "NY", valuationUSD: 500_000,
            legalIdentifier: "DEED-NY-001", mintedAt: 0, originalOwner: address(0)
        });
        tokenId = nft.mintProperty(owner, meta);

        token = new FractionalToken(
            "Test Property Token", "TPT",
            tokenId, address(nft), address(registry), SUPPLY
        );

        expiry = uint128(block.timestamp + 365 days);
    }

    function _addInvestor(address inv, uint8 tier) internal {
        vm.prank(agent);
        registry.addInvestor(inv, expiry, bytes32("US"), tier);
    }

    // ─── mintInitialSupply ────────────────────────────────────────────────────

    function test_InitialMint_Success() public {
        token.mintInitialSupply(owner);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(owner), SUPPLY);
    }

    function test_InitialMint_RevertsIfCalledTwice() public {
        token.mintInitialSupply(owner);
        vm.expectRevert(FractionalToken.InitialMintAlreadyDone.selector);
        token.mintInitialSupply(owner);
    }

    // ─── transfers ────────────────────────────────────────────────────────────

    function test_Transfer_BetweenVerifiedInvestors_Succeeds() public {
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 2);

        token.mintInitialSupply(inv1);
        // Self-delegate so votes are tracked
        vm.prank(inv1); token.delegate(inv1);

        vm.prank(inv1);
        token.transfer(inv2, 100 * 1e18);

        assertEq(token.balanceOf(inv2), 100 * 1e18);
    }

    function test_Transfer_ToUnverifiedInvestor_Reverts() public {
        _addInvestor(inv1, 2);
        token.mintInitialSupply(inv1);

        vm.prank(inv1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.ComplianceTransferBlocked.selector,
            "RECEIVER_NOT_VERIFIED"
        ));
        token.transfer(nobody, 100 * 1e18);
    }

    function test_Transfer_FromUnverifiedInvestor_Reverts() public {
        _addInvestor(inv2, 2);
        token.mintInitialSupply(nobody); // nobody is unverified

        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.ComplianceTransferBlocked.selector,
            "SENDER_NOT_VERIFIED"
        ));
        token.transfer(inv2, 100 * 1e18);
    }

    function test_Transfer_RevertsWithReasonString() public {
        _addInvestor(inv1, 2);
        token.mintInitialSupply(inv1);

        vm.prank(inv1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.ComplianceTransferBlocked.selector,
            "RECEIVER_NOT_VERIFIED"
        ));
        token.transfer(nobody, 1 * 1e18);
    }

    // ─── Tier-1 cap ───────────────────────────────────────────────────────────

    function test_Tier1Cap_RevertsWhenExceeded() public {
        _addInvestor(inv1, 2); // tier 2 sender — no cap
        _addInvestor(inv2, 1); // tier 1 receiver — 10k cap

        // Give inv1 enough tokens to exceed the cap
        token.mintInitialSupply(inv1);
        // Also mint extra tokens directly to inv1 via a second token for testing purposes
        // Actually, adjust the test: just mint enough to inv1 by using a fresh token
        // with higher supply so we can actually attempt the over-cap transfer.
        // Use a separate token instance to avoid the supply limit.
        FractionalToken bigToken = new FractionalToken(
            "Big Token", "BIG", tokenId, address(nft), address(registry), 20_000 * 1e18
        );
        bigToken.mintInitialSupply(inv1);

        uint256 cap    = bigToken.TIER1_MAX_BALANCE(); // pre-cache to avoid consuming prank
        uint256 overCap = cap + 1;

        vm.prank(inv1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.TierLimitExceeded.selector,
            inv2, 0, overCap, cap
        ));
        bigToken.transfer(inv2, overCap);
    }

    function test_Tier2_NoCapEnforced() public {
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 2);

        token.mintInitialSupply(inv1);
        vm.prank(inv1); token.delegate(inv1);

        // Transfer all 1000 tokens — should succeed for tier 2
        vm.prank(inv1);
        token.transfer(inv2, SUPPLY);
        assertEq(token.balanceOf(inv2), SUPPLY);
    }

    // ─── paused registry ──────────────────────────────────────────────────────

    function test_PausedRegistry_BlocksTransfers() public {
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 2);
        token.mintInitialSupply(inv1);
        vm.prank(inv1); token.delegate(inv1);

        registry.pauseAllTransfers();

        vm.prank(inv1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalToken.ComplianceTransferBlocked.selector,
            "TRANSFERS_PAUSED"
        ));
        token.transfer(inv2, 100 * 1e18);
    }

    // ─── burn ─────────────────────────────────────────────────────────────────

    function test_Burn_ReducesSupply() public {
        token.mintInitialSupply(owner);
        uint256 before = token.totalSupply();

        token.burn(100 * 1e18);
        assertEq(token.totalSupply(), before - 100 * 1e18);
    }

    // ─── dividends ────────────────────────────────────────────────────────────

    function test_DividendDeposit_CreatesRound() public {
        token.mintInitialSupply(owner);

        vm.deal(owner, 1 ether);
        vm.roll(block.number + 1);
        token.depositDividend{value: 1 ether}();

        assertEq(token.roundCount(), 1);
        (uint256 totalETH,,,) = token.dividendRounds(0);
        assertEq(totalETH, 1 ether);
    }

    function test_DividendClaim_SingleInvestor_ReceivesFullAmount() public {
        _addInvestor(inv1, 2);
        token.mintInitialSupply(inv1);
        vm.prank(inv1); token.delegate(inv1);

        vm.roll(block.number + 1);

        vm.deal(owner, 1 ether);
        token.depositDividend{value: 1 ether}();

        vm.roll(block.number + 1);

        uint256 before = inv1.balance;
        vm.prank(inv1);
        token.claimDividend(0);

        assertEq(inv1.balance - before, 1 ether);
    }

    function test_DividendClaim_TwoInvestors_ProRataSplit() public {
        _addInvestor(inv1, 2);
        _addInvestor(inv2, 2);

        // Give inv1 600, inv2 400 (after minting to inv1 first then transferring)
        token.mintInitialSupply(inv1);
        vm.prank(inv1); token.delegate(inv1);

        vm.prank(inv1); token.transfer(inv2, 400 * 1e18);
        vm.prank(inv2); token.delegate(inv2);

        // Roll forward so votes are checkpointed
        vm.roll(block.number + 1);

        vm.deal(owner, 1 ether);
        token.depositDividend{value: 1 ether}();

        vm.roll(block.number + 1);

        uint256 b1 = inv1.balance;
        uint256 b2 = inv2.balance;

        vm.prank(inv1); token.claimDividend(0);
        vm.prank(inv2); token.claimDividend(0);

        uint256 gain1 = inv1.balance - b1;
        uint256 gain2 = inv2.balance - b2;

        // inv1: 600/1000 = 0.6 ETH, inv2: 400/1000 = 0.4 ETH
        assertEq(gain1, 0.6 ether);
        assertEq(gain2, 0.4 ether);
    }

    function test_DividendClaim_RevertsIfClaimedTwice() public {
        _addInvestor(inv1, 2);
        token.mintInitialSupply(inv1);
        vm.prank(inv1); token.delegate(inv1);

        vm.roll(block.number + 1);
        vm.deal(owner, 1 ether);
        token.depositDividend{value: 1 ether}();
        vm.roll(block.number + 1);

        vm.prank(inv1); token.claimDividend(0);

        vm.prank(inv1);
        vm.expectRevert(abi.encodeWithSelector(FractionalToken.AlreadyClaimed.selector, inv1, 0));
        token.claimDividend(0);
    }

    function test_DividendClaim_RevertsIfZeroBalance() public {
        token.mintInitialSupply(owner);
        // owner has no votes (never delegated), nobody does

        vm.roll(block.number + 1);
        vm.deal(owner, 1 ether);
        token.depositDividend{value: 1 ether}();
        vm.roll(block.number + 1);

        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(FractionalToken.NoDividendToClaim.selector, nobody, 0));
        token.claimDividend(0);
    }

    function test_DividendClaim_RevertsInvalidRound() public {
        vm.expectRevert(abi.encodeWithSelector(FractionalToken.InvalidRound.selector, 99));
        token.claimDividend(99);
    }

    // ─── ERC20Permit ─────────────────────────────────────────────────────────

    function test_ERC20Permit_Works() public {
        _addInvestor(inv2, 2);

        uint256 signerKey = 0xA11CE;
        address signer = vm.addr(signerKey);
        _addInvestor(signer, 2);

        token.mintInitialSupply(signer);

        uint256 nonce   = token.nonces(signer);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount  = 100 * 1e18;

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 permitHash = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            keccak256(abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer, inv2, amount, nonce, deadline
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, permitHash);

        // Submit permit on-chain — no prior approval needed
        token.permit(signer, inv2, amount, deadline, v, r, s);
        assertEq(token.allowance(signer, inv2), amount);

        // inv2 executes the approved transfer (signer→inv2)
        vm.prank(inv2);
        token.transferFrom(signer, inv2, amount);
        assertEq(token.balanceOf(inv2), amount);
    }

    // ─── Immutables ───────────────────────────────────────────────────────────

    function test_Immutables_SetCorrectly() public view {
        assertEq(token.linkedNFTId(), tokenId);
        assertEq(token.propertyNFT(), address(nft));
        assertEq(token.identityRegistry(), address(registry));
        assertEq(token.maxSupply(), SUPPLY);
    }

    // ─── ZeroETH revert ───────────────────────────────────────────────────────

    function test_DepositDividend_ZeroETH_Reverts() public {
        token.mintInitialSupply(owner);
        vm.expectRevert(FractionalToken.ZeroETH.selector);
        token.depositDividend{value: 0}();
    }

    // ─── Clock and ClockMode ──────────────────────────────────────────────────

    function test_Clock_ReturnsCurrentBlock() public view {
        assertEq(token.clock(), uint48(block.number));
    }

    function test_ClockMode_ReturnsBlockNumberMode() public view {
        assertEq(token.CLOCK_MODE(), "mode=blocknumber&from=default");
    }

    // ─── InsufficientContractBalance ─────────────────────────────────────────

    function test_ClaimDividend_InsufficientBalance_Reverts() public {
        _addInvestor(inv1, 2);
        token.mintInitialSupply(inv1);
        vm.prank(inv1); token.delegate(inv1);
        vm.roll(block.number + 1);
        vm.deal(owner, 1 ether);
        token.depositDividend{value: 1 ether}();
        vm.deal(address(token), 0); // drain the contract's ETH balance
        vm.roll(block.number + 1);
        vm.prank(inv1);
        vm.expectRevert(FractionalToken.InsufficientContractBalance.selector);
        token.claimDividend(0);
    }

    // ─── receive() ────────────────────────────────────────────────────────────

    function test_ReceiveETH_DirectTransfer() public {
        vm.deal(owner, 0.5 ether);
        (bool ok,) = address(token).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(address(token).balance, 0.5 ether);
    }
}
