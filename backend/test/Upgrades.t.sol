// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IdentityRegistry} from "../src/identity/IdentityRegistry.sol";
import {PropertyNFTV2} from "../src/upgrades/PropertyNFTV2.sol";
import {FractionalTokenV2} from "../src/upgrades/FractionalTokenV2.sol";

contract UpgradesTest is Test {
    PropertyNFTV2    public impl;
    ERC1967Proxy     public proxy;
    PropertyNFTV2    public nftProxy;

    IdentityRegistry public registry;
    FractionalTokenV2 public ftImpl;
    ERC1967Proxy      public ftProxy;
    FractionalTokenV2 public ftProxied;

    address public owner   = address(this);
    address public user1   = makeAddr("user1");
    address public nobody  = makeAddr("nobody");
    address public agent   = makeAddr("agent");

    uint256 public constant SUPPLY = 1_000 * 1e18;
    uint128 public expiry;

    PropertyNFTV2.PropertyMetadata public meta;

    function setUp() public {
        // Deploy PropertyNFTV2 proxy
        impl  = new PropertyNFTV2();
        bytes memory initData = abi.encodeWithSelector(PropertyNFTV2.initialize.selector, owner);
        proxy = new ERC1967Proxy(address(impl), initData);
        nftProxy = PropertyNFTV2(address(proxy));

        meta = PropertyNFTV2.PropertyMetadata({
            name: "Harbor View", location: "San Francisco, CA",
            valuationUSD: 2_500_000, legalIdentifier: "DEED-CA-2024-00777",
            mintedAt: 0, originalOwner: address(0)
        });

        // Deploy FractionalTokenV2 proxy
        registry = new IdentityRegistry();
        registry.grantRole(registry.AGENT_ROLE(), agent);
        expiry = uint128(block.timestamp + 365 days);

        ftImpl = new FractionalTokenV2();
        bytes memory ftInit = abi.encodeWithSelector(
            FractionalTokenV2.initialize.selector,
            "Harbor Token", "HBR", 0, address(nftProxy), address(registry), SUPPLY, owner
        );
        ftProxy   = new ERC1967Proxy(address(ftImpl), ftInit);
        ftProxied = FractionalTokenV2(payable(address(ftProxy)));
    }

    // ─── PropertyNFTV2 proxy tests ────────────────────────────────────────────

    function test_DeployProxy_V1_Works() public {
        uint256 tokenId = nftProxy.mintProperty(user1, meta);
        assertEq(nftProxy.ownerOf(tokenId), user1);
    }

    function test_V2_NewFunctionAccessible() public {
        uint256 tokenId = nftProxy.mintProperty(owner, meta);

        // V2 function: updateDescription
        nftProxy.updateDescription(tokenId, "Lien released 2025-01-01");
        assertEq(nftProxy.descriptions(tokenId), "Lien released 2025-01-01");
    }

    function test_UpgradeToV2_PreservesState() public {
        // Mint a token on the proxy
        uint256 tokenId = nftProxy.mintProperty(user1, meta);
        assertEq(nftProxy.ownerOf(tokenId), user1);

        // Deploy a new implementation (simulating a V2 upgrade)
        PropertyNFTV2 newImpl = new PropertyNFTV2();

        // Upgrade the proxy
        nftProxy.upgradeToAndCall(address(newImpl), "");

        // State persists: token still exists, owner still correct
        assertEq(nftProxy.ownerOf(tokenId), user1);

        // V2 function still works after upgrade
        nftProxy.updateDescription(tokenId, "Post-upgrade description");
        assertEq(nftProxy.descriptions(tokenId), "Post-upgrade description");
    }

    function test_NonOwner_CannotUpgrade() public {
        PropertyNFTV2 newImpl = new PropertyNFTV2();

        vm.prank(nobody);
        vm.expectRevert();
        nftProxy.upgradeToAndCall(address(newImpl), "");
    }

    // ─── FractionalTokenV2 proxy tests ────────────────────────────────────────

    function test_FTV2_DeployProxy_Works() public {
        ftProxied.mintInitialSupply(owner);
        assertEq(ftProxied.totalSupply(), SUPPLY);
    }

    function test_FTV2_LockTokens_PreventsTransfer() public {
        // Add investors to registry
        vm.prank(agent);
        registry.addInvestor(user1, expiry, bytes32("US"), 2);
        vm.prank(agent);
        registry.addInvestor(nobody, expiry, bytes32("US"), 2);

        ftProxied.mintInitialSupply(user1);

        // Lock user1's tokens until far future
        ftProxied.lockTokens(user1, block.timestamp + 30 days);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalTokenV2.TokensLocked.selector,
            user1,
            block.timestamp + 30 days
        ));
        ftProxied.transfer(nobody, 100 * 1e18);
    }

    function test_FTV2_LockExpires_AllowsTransfer() public {
        vm.prank(agent);
        registry.addInvestor(user1, expiry, bytes32("US"), 2);
        vm.prank(agent);
        registry.addInvestor(nobody, expiry, bytes32("US"), 2);

        ftProxied.mintInitialSupply(user1);
        ftProxied.lockTokens(user1, block.timestamp + 1 days);

        vm.warp(block.timestamp + 2 days);

        vm.prank(user1);
        ftProxied.transfer(nobody, 100 * 1e18);
        assertEq(ftProxied.balanceOf(nobody), 100 * 1e18);
    }

    function test_FTV2_UnlockTokens_AllowsImmediateTransfer() public {
        vm.prank(agent);
        registry.addInvestor(user1, expiry, bytes32("US"), 2);
        vm.prank(agent);
        registry.addInvestor(nobody, expiry, bytes32("US"), 2);

        ftProxied.mintInitialSupply(user1);
        ftProxied.lockTokens(user1, block.timestamp + 30 days);

        // Admin unlocks early
        ftProxied.unlockTokens(user1);

        vm.prank(user1);
        ftProxied.transfer(nobody, 50 * 1e18);
        assertEq(ftProxied.balanceOf(nobody), 50 * 1e18);
    }

    function test_FTV2_OnlyOwner_CanLock() public {
        vm.prank(nobody);
        vm.expectRevert();
        ftProxied.lockTokens(user1, block.timestamp + 1 days);
    }

    function test_FTV2_UpgradePreservesState() public {
        ftProxied.mintInitialSupply(owner);
        assertEq(ftProxied.totalSupply(), SUPPLY);

        FractionalTokenV2 newFtImpl = new FractionalTokenV2();
        ftProxied.upgradeToAndCall(address(newFtImpl), "");

        // State intact after upgrade
        assertEq(ftProxied.totalSupply(), SUPPLY);
        assertEq(ftProxied.maxSupply(), SUPPLY);
    }

    // ─── PropertyNFTV2 error + branch coverage ────────────────────────────────

    function test_NFTV2_MintToZero_Reverts() public {
        vm.expectRevert(PropertyNFTV2.ZeroAddress.selector);
        nftProxy.mintProperty(address(0), meta);
    }

    function test_NFTV2_UpdateDescription_NonExistent_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PropertyNFTV2.PropertyDoesNotExist.selector, 999));
        nftProxy.updateDescription(999, "some note");
    }

    function test_NFTV2_UpdateDescription_EmitsEvent() public {
        uint256 tid = nftProxy.mintProperty(owner, meta);
        vm.expectEmit(true, false, false, true);
        emit PropertyNFTV2.DescriptionUpdated(tid, "Lien cleared");
        nftProxy.updateDescription(tid, "Lien cleared");
    }

    function test_NFTV2_LinkFractionToken_Success() public {
        uint256 tid = nftProxy.mintProperty(owner, meta);
        address mockFt = makeAddr("mockFt");
        nftProxy.linkFractionToken(tid, mockFt);
        assertEq(nftProxy.fractionToken(tid), mockFt);
    }

    function test_NFTV2_LinkFractionToken_RevertsIfCalledTwice() public {
        uint256 tid = nftProxy.mintProperty(owner, meta);
        nftProxy.linkFractionToken(tid, makeAddr("ft1"));
        vm.expectRevert(abi.encodeWithSelector(PropertyNFTV2.FractionTokenAlreadyLinked.selector, tid));
        nftProxy.linkFractionToken(tid, makeAddr("ft2"));
    }

    function test_NFTV2_LinkFractionToken_ZeroAddress_Reverts() public {
        uint256 tid = nftProxy.mintProperty(owner, meta);
        vm.expectRevert(PropertyNFTV2.ZeroAddress.selector);
        nftProxy.linkFractionToken(tid, address(0));
    }

    function test_NFTV2_LinkFractionToken_NonExistent_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PropertyNFTV2.PropertyDoesNotExist.selector, 999));
        nftProxy.linkFractionToken(999, makeAddr("ft"));
    }

    function test_NFTV2_UpdateValuation_Success() public {
        uint256 tid = nftProxy.mintProperty(owner, meta);
        nftProxy.updateValuation(tid, 3_000_000);
        PropertyNFTV2.PropertyMetadata memory stored = nftProxy.getPropertyDetails(tid);
        assertEq(stored.valuationUSD, 3_000_000);
    }

    function test_NFTV2_UpdateValuation_NonExistent_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PropertyNFTV2.PropertyDoesNotExist.selector, 0));
        nftProxy.updateValuation(0, 1_000_000);
    }

    function test_NFTV2_GetPropertyDetails_Success() public {
        uint256 tid = nftProxy.mintProperty(owner, meta);
        PropertyNFTV2.PropertyMetadata memory stored = nftProxy.getPropertyDetails(tid);
        assertEq(stored.name, meta.name);
        assertEq(stored.valuationUSD, meta.valuationUSD);
    }

    function test_NFTV2_GetPropertyDetails_NonExistent_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(PropertyNFTV2.PropertyDoesNotExist.selector, 0));
        nftProxy.getPropertyDetails(0);
    }

    function test_NFTV2_TokenURI_ReturnsBase64Json() public {
        uint256 tid = nftProxy.mintProperty(owner, meta);
        string memory uri = nftProxy.tokenURI(tid);
        bytes memory uriBytes  = bytes(uri);
        bytes memory prefix    = bytes("data:application/json;base64,");
        assertTrue(uriBytes.length > prefix.length, "URI too short");
        for (uint256 i = 0; i < prefix.length; i++) {
            assertEq(uriBytes[i], prefix[i]);
        }
    }

    function test_NFTV2_SupportsInterface_ERC721() public view {
        assertTrue(nftProxy.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(nftProxy.supportsInterface(0x780e9d63)); // ERC721Enumerable
    }

    // ─── FractionalTokenV2 extended coverage ─────────────────────────────────

    function test_FTV2_InitialMint_RevertsIfCalledTwice() public {
        ftProxied.mintInitialSupply(owner);
        vm.expectRevert(FractionalTokenV2.InitialMintAlreadyDone.selector);
        ftProxied.mintInitialSupply(owner);
    }

    function test_FTV2_Burn_ReducesSupply() public {
        ftProxied.mintInitialSupply(owner);
        uint256 before = ftProxied.totalSupply();
        ftProxied.burn(100 * 1e18);
        assertEq(ftProxied.totalSupply(), before - 100 * 1e18);
    }

    function test_FTV2_DepositDividend_ZeroETH_Reverts() public {
        ftProxied.mintInitialSupply(owner);
        vm.expectRevert(FractionalTokenV2.ZeroETH.selector);
        ftProxied.depositDividend{value: 0}();
    }

    function test_FTV2_DepositDividend_CreatesRound() public {
        ftProxied.mintInitialSupply(owner);
        vm.deal(owner, 1 ether);
        vm.roll(block.number + 1);
        ftProxied.depositDividend{value: 1 ether}();
        assertEq(ftProxied.roundCount(), 1);
        (uint256 total,,,) = ftProxied.dividendRounds(0);
        assertEq(total, 1 ether);
    }

    function test_FTV2_DividendFullCycle() public {
        vm.prank(agent);
        registry.addInvestor(user1, expiry, bytes32("US"), 2);

        ftProxied.mintInitialSupply(user1);
        vm.prank(user1); ftProxied.delegate(user1);
        vm.roll(block.number + 1);

        vm.deal(owner, 1 ether);
        ftProxied.depositDividend{value: 1 ether}();
        vm.roll(block.number + 1);

        uint256 before = user1.balance;
        vm.prank(user1);
        ftProxied.claimDividend(0);
        assertEq(user1.balance - before, 1 ether);
    }

    function test_FTV2_DividendClaim_InvalidRound_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(FractionalTokenV2.InvalidRound.selector, 99));
        ftProxied.claimDividend(99);
    }

    function test_FTV2_DividendClaim_AlreadyClaimed_Reverts() public {
        vm.prank(agent);
        registry.addInvestor(user1, expiry, bytes32("US"), 2);

        ftProxied.mintInitialSupply(user1);
        vm.prank(user1); ftProxied.delegate(user1);
        vm.roll(block.number + 1);
        vm.deal(owner, 1 ether);
        ftProxied.depositDividend{value: 1 ether}();
        vm.roll(block.number + 1);

        vm.prank(user1); ftProxied.claimDividend(0);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(FractionalTokenV2.AlreadyClaimed.selector, user1, 0));
        ftProxied.claimDividend(0);
    }

    function test_FTV2_DividendClaim_ZeroBalance_Reverts() public {
        ftProxied.mintInitialSupply(owner);
        vm.roll(block.number + 1);
        vm.deal(owner, 1 ether);
        ftProxied.depositDividend{value: 1 ether}();
        vm.roll(block.number + 1);
        vm.prank(nobody);
        vm.expectRevert(abi.encodeWithSelector(FractionalTokenV2.NoDividendToClaim.selector, nobody, 0));
        ftProxied.claimDividend(0);
    }

    function test_FTV2_DividendClaim_InsufficientBalance_Reverts() public {
        vm.prank(agent);
        registry.addInvestor(user1, expiry, bytes32("US"), 2);

        ftProxied.mintInitialSupply(user1);
        vm.prank(user1); ftProxied.delegate(user1);
        vm.roll(block.number + 1);
        vm.deal(owner, 1 ether);
        ftProxied.depositDividend{value: 1 ether}();
        vm.deal(address(ftProxied), 0); // drain the proxy's ETH balance
        vm.roll(block.number + 1);
        vm.prank(user1);
        vm.expectRevert(FractionalTokenV2.InsufficientContractBalance.selector);
        ftProxied.claimDividend(0);
    }

    function test_FTV2_ComplianceBlocked_ReceiverNotVerified() public {
        // Mint bypasses compliance; user1 gets tokens without registry entry
        ftProxied.mintInitialSupply(user1);
        // Add user1 to registry so the sender check passes
        vm.prank(agent);
        registry.addInvestor(user1, expiry, bytes32("US"), 2);
        // nobody is not in registry → RECEIVER_NOT_VERIFIED
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalTokenV2.ComplianceTransferBlocked.selector,
            "RECEIVER_NOT_VERIFIED"
        ));
        ftProxied.transfer(nobody, 100 * 1e18);
    }

    function test_FTV2_Tier1Cap_Reverts() public {
        // Use an isolated registry where the test contract is its own agent,
        // avoiding any vm.prank ordering issues with the shared setUp registry.
        IdentityRegistry bigRegistry = new IdentityRegistry();
        bigRegistry.grantRole(bigRegistry.AGENT_ROLE(), address(this));

        FractionalTokenV2 bigImpl = new FractionalTokenV2();
        bytes memory bigInit = abi.encodeWithSelector(
            FractionalTokenV2.initialize.selector,
            "Big Token", "BIG", 0, address(nftProxy), address(bigRegistry), 20_000 * 1e18, owner
        );
        FractionalTokenV2 bigFt = FractionalTokenV2(payable(address(new ERC1967Proxy(address(bigImpl), bigInit))));

        uint128 fut = uint128(block.timestamp + 365 days);
        bigRegistry.addInvestor(user1, fut, bytes32("US"), 2); // tier-2 sender
        bigRegistry.addInvestor(nobody, fut, bytes32("US"), 1); // tier-1 receiver: 10k cap

        bigFt.mintInitialSupply(user1); // mint bypasses compliance
        uint256 cap    = bigFt.TIER1_MAX_BALANCE(); // pre-cache before prank
        uint256 overCap = cap + 1;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(
            FractionalTokenV2.TierLimitExceeded.selector,
            nobody, 0, overCap, cap
        ));
        bigFt.transfer(nobody, overCap);
    }

    function test_FTV2_Clock_ReturnsBlockNumber() public view {
        assertEq(ftProxied.clock(), uint48(block.number));
    }

    function test_FTV2_ClockMode_ReturnsBlockNumberMode() public view {
        assertEq(ftProxied.CLOCK_MODE(), "mode=blocknumber&from=default");
    }

    function test_FTV2_NonOwner_CannotUpgrade() public {
        FractionalTokenV2 newImpl = new FractionalTokenV2();
        vm.prank(nobody);
        vm.expectRevert();
        ftProxied.upgradeToAndCall(address(newImpl), "");
    }

    function test_FTV2_ReceiveETH_DirectTransfer() public {
        vm.deal(owner, 0.5 ether);
        (bool ok,) = address(ftProxied).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(address(ftProxied).balance, 0.5 ether);
    }

    function test_FTV2_Immutables_SetCorrectly() public view {
        assertEq(ftProxied.linkedNFTId(), 0);
        assertEq(ftProxied.propertyNFT(), address(nftProxy));
        assertEq(ftProxied.identityRegistry(), address(registry));
        assertEq(ftProxied.maxSupply(), SUPPLY);
    }
}
