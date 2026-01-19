// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";

/**
 * @title DeployedVaultTest
 * @notice Tests against already-deployed contracts on Tenderly or mainnet fork
 * @dev Set VAULT_ADDRESS env var or update the constant below
 */
contract DeployedVaultTest is Test {
    // ============ DEPLOYED ADDRESSES ============

    // Constants
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    uint256 public constant TIMELOCK_LOW = 3 days;
    uint256 public constant TIMELOCK_HIGH = 7 days;

    // State
    IVaultV2 public vault;
    IERC20 public usds;

    function setUp() public {
        // Allow override via env var
        address vaultAddr = vm.envOr("VAULT_ADDRESS", address(0));
        vault = IVaultV2(vaultAddr);
        usds = IERC20(USDS);

        console.log("Testing vault at:", address(vault));
    }

    // ============ CONFIGURATION VERIFICATION ============

    function testVaultBasicInfo() public view {
        console.log("=== Vault Basic Info ===");
        console.log("Name:", vault.name());
        console.log("Symbol:", vault.symbol());
        console.log("Asset:", vault.asset());
        console.log("Decimals:", vault.decimals());
        console.log("Total Assets:", vault.totalAssets());
        console.log("Total Supply:", vault.totalSupply());

        assertEq(vault.asset(), USDS, "Asset should be USDS");
    }

    function testRoleConfiguration() public view {
        console.log("=== Role Configuration ===");
        console.log("Owner:", vault.owner());
        console.log("Curator:", vault.curator());

        assertTrue(vault.owner() != address(0), "Owner should be set");
        assertTrue(vault.curator() != address(0), "Curator should be set");
    }

    function testExpectedOwner() public view {
        address expectedOwner = vm.envOr("OWNER", address(0));
        if (expectedOwner != address(0)) {
            console.log("=== Expected Owner Check ===");
            console.log("Expected Owner:", expectedOwner);
            console.log("Actual Owner:", vault.owner());
            assertEq(vault.owner(), expectedOwner, "Owner should match expected");
        }
    }

    function testExpectedCurator() public view {
        address expectedCurator = vm.envOr("CURATOR", address(0));
        if (expectedCurator != address(0)) {
            console.log("=== Expected Curator Check ===");
            console.log("Expected Curator:", expectedCurator);
            console.log("Actual Curator:", vault.curator());
            assertEq(vault.curator(), expectedCurator, "Curator should match expected");
        }
    }

    function testExpectedAllocator() public view {
        address expectedAllocator = vm.envOr("ALLOCATOR", address(0));
        if (expectedAllocator != address(0)) {
            console.log("=== Expected Allocator Check ===");
            console.log("Expected Allocator:", expectedAllocator);
            console.log("Is Allocator:", vault.isAllocator(expectedAllocator));
            assertTrue(vault.isAllocator(expectedAllocator), "Expected address should be allocator");
        }
    }

    function testExpectedSentinel() public view {
        address expectedSentinel = vm.envOr("SENTINEL", address(0));
        if (expectedSentinel != address(0)) {
            console.log("=== Expected Sentinel Check ===");
            console.log("Expected Sentinel:", expectedSentinel);
            console.log("Is Sentinel:", vault.isSentinel(expectedSentinel));
            assertTrue(vault.isSentinel(expectedSentinel), "Expected address should be sentinel");
        }
    }

    function testExpectedVaultName() public view {
        string memory expectedName = vm.envOr("VAULT_NAME", string(""));
        if (bytes(expectedName).length > 0) {
            console.log("=== Expected Vault Name Check ===");
            console.log("Expected Name:", expectedName);
            console.log("Actual Name:", vault.name());
            assertEq(vault.name(), expectedName, "Vault name should match expected");
        }
    }

    function testExpectedVaultSymbol() public view {
        string memory expectedSymbol = vm.envOr("VAULT_SYMBOL", string(""));
        if (bytes(expectedSymbol).length > 0) {
            console.log("=== Expected Vault Symbol Check ===");
            console.log("Expected Symbol:", expectedSymbol);
            console.log("Actual Symbol:", vault.symbol());
            assertEq(vault.symbol(), expectedSymbol, "Vault symbol should match expected");
        }
    }

    function testAdapterConfiguration() public view {
        console.log("=== Adapter Configuration ===");

        uint256 adapterCount = vault.adaptersLength();
        console.log("Adapters count:", adapterCount);
        assertEq(adapterCount, 1, "Should have exactly 1 adapter");

        address adapter = vault.adapters(0);
        console.log("Adapter[0]:", adapter);
        assertTrue(adapter != address(0), "Adapter should be set");
        assertTrue(vault.isAdapter(adapter), "Adapter should be registered");

        address liquidityAdapter = vault.liquidityAdapter();
        console.log("Liquidity Adapter:", liquidityAdapter);
        assertEq(liquidityAdapter, adapter, "Liquidity adapter should match first adapter");
    }

    function testTimelockConfiguration() public view {
        console.log("=== Timelock Configuration ===");

        // High priority (7 days)
        uint256 increaseTimelockTL = vault.timelock(IVaultV2.increaseTimelock.selector);
        uint256 removeAdapterTL = vault.timelock(IVaultV2.removeAdapter.selector);
        uint256 abdicateTL = vault.timelock(IVaultV2.abdicate.selector);

        console.log("increaseTimelock:", increaseTimelockTL);
        console.log("removeAdapter:", removeAdapterTL);
        console.log("abdicate:", abdicateTL);

        assertEq(increaseTimelockTL, TIMELOCK_HIGH, "increaseTimelock should be 7 days");
        assertEq(removeAdapterTL, TIMELOCK_HIGH, "removeAdapter should be 7 days");
        assertEq(abdicateTL, TIMELOCK_HIGH, "abdicate should be 7 days");

        // Low priority (3 days)
        uint256 addAdapterTL = vault.timelock(IVaultV2.addAdapter.selector);
        uint256 increaseAbsoluteCapTL = vault.timelock(IVaultV2.increaseAbsoluteCap.selector);
        uint256 increaseRelativeCapTL = vault.timelock(IVaultV2.increaseRelativeCap.selector);

        console.log("addAdapter:", addAdapterTL);
        console.log("increaseAbsoluteCap:", increaseAbsoluteCapTL);
        console.log("increaseRelativeCap:", increaseRelativeCapTL);

        assertEq(addAdapterTL, TIMELOCK_LOW, "addAdapter should be 3 days");
        assertEq(increaseAbsoluteCapTL, TIMELOCK_LOW, "increaseAbsoluteCap should be 3 days");
        assertEq(increaseRelativeCapTL, TIMELOCK_LOW, "increaseRelativeCap should be 3 days");
    }

    function testGateAbdication() public view {
        console.log("=== Gate Abdication ===");

        bool receiveAssetsAbdicated = vault.abdicated(IVaultV2.setReceiveAssetsGate.selector);
        bool sendSharesAbdicated = vault.abdicated(IVaultV2.setSendSharesGate.selector);
        bool receiveSharesAbdicated = vault.abdicated(IVaultV2.setReceiveSharesGate.selector);
        bool adapterRegistryAbdicated = vault.abdicated(IVaultV2.setAdapterRegistry.selector);

        console.log("setReceiveAssetsGate abdicated:", receiveAssetsAbdicated);
        console.log("setSendSharesGate abdicated:", sendSharesAbdicated);
        console.log("setReceiveSharesGate abdicated:", receiveSharesAbdicated);
        console.log("setAdapterRegistry abdicated:", adapterRegistryAbdicated);

        assertTrue(receiveAssetsAbdicated, "setReceiveAssetsGate should be abdicated");
        assertTrue(sendSharesAbdicated, "setSendSharesGate should be abdicated");
        assertTrue(receiveSharesAbdicated, "setReceiveSharesGate should be abdicated");
        assertTrue(adapterRegistryAbdicated, "setAdapterRegistry should be abdicated");
    }

    function testDeadDeposit() public view {
        console.log("=== Dead Deposit ===");

        address dead = address(0xdEaD);
        uint256 deadShares = vault.balanceOf(dead);

        console.log("Dead address shares:", deadShares);
        assertGt(deadShares, 0, "Dead address should have shares");
    }

    function testMaxRate() public view {
        console.log("=== Max Rate ===");

        uint256 maxRate = vault.maxRate();
        console.log("Max Rate:", maxRate);
        assertGt(maxRate, 0, "Max rate should be > 0");
    }

    // ============ USER OPERATIONS ============

    function testUserDeposit() public {
        address user = makeAddr("testUser");
        uint256 depositAmount = 100 * 1e18; // 100 USDS

        // Fund user with USDS
        deal(USDS, user, depositAmount);

        vm.startPrank(user);
        usds.approve(address(vault), depositAmount);

        uint256 sharesBefore = vault.balanceOf(user);
        uint256 expectedShares = vault.previewDeposit(depositAmount);

        console.log("=== User Deposit Test ===");
        console.log("Deposit amount:", depositAmount);
        console.log("Expected shares:", expectedShares);

        uint256 sharesReceived = vault.deposit(depositAmount, user);

        console.log("Shares received:", sharesReceived);

        assertEq(sharesReceived, expectedShares, "Shares should match preview");
        assertEq(vault.balanceOf(user), sharesBefore + sharesReceived, "Balance should increase");

        vm.stopPrank();
    }

    function testUserWithdraw() public {
        address user = makeAddr("testUser2");
        uint256 depositAmount = 100 * 1e18; // 100 USDS

        // Fund and deposit
        deal(USDS, user, depositAmount);

        vm.startPrank(user);
        usds.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);

        console.log("=== User Withdraw Test ===");
        console.log("Deposited, got shares:", shares);

        // Withdraw half
        uint256 withdrawShares = shares / 2;
        uint256 expectedAssets = vault.previewRedeem(withdrawShares);

        console.log("Redeeming shares:", withdrawShares);
        console.log("Expected assets:", expectedAssets);

        uint256 assetsReceived = vault.redeem(withdrawShares, user, user);

        console.log("Assets received:", assetsReceived);

        assertEq(assetsReceived, expectedAssets, "Assets should match preview");
        assertEq(vault.balanceOf(user), shares - withdrawShares, "Shares should decrease");
        assertEq(usds.balanceOf(user), assetsReceived, "USDS balance should match");

        vm.stopPrank();
    }

    function testFullDepositWithdrawCycle() public {
        address user = makeAddr("cycleUser");
        uint256 depositAmount = 1000 * 1e18; // 1000 USDS

        deal(USDS, user, depositAmount);

        vm.startPrank(user);
        usds.approve(address(vault), depositAmount);

        console.log("=== Full Cycle Test ===");
        console.log("Initial USDS:", depositAmount);

        // Deposit
        uint256 shares = vault.deposit(depositAmount, user);
        console.log("Shares after deposit:", shares);

        // Full redeem
        uint256 assetsBack = vault.redeem(shares, user, user);
        console.log("USDS after full redeem:", assetsBack);

        // Should get back approximately the same amount (minus any fees/rounding)
        assertApproxEqAbs(assetsBack, depositAmount, 2, "Should get back ~same amount");
        assertEq(vault.balanceOf(user), 0, "Should have 0 shares");

        vm.stopPrank();
    }

    // ============ SHARE PRICE ============

    function testSharePrice() public view {
        console.log("=== Share Price ===");

        uint256 oneShare = 1e18; // Vault has 18 decimals
        uint256 assetsPerShare = vault.convertToAssets(oneShare);

        uint256 oneUSDS = 1e18;
        uint256 sharesPerUSDS = vault.convertToShares(oneUSDS);

        console.log("Assets per 1e18 shares:", assetsPerShare);
        console.log("Shares per 1 USDS:", sharesPerUSDS);

        // Share price should be close to 1:1 for a new vault
        // 1e18 shares should give ~1e18 assets (1 USDS)
        assertGt(assetsPerShare, 0, "Should have positive conversion");
    }

    // ============ ACCESS CONTROL ============

    function testUnauthorizedAccess() public {
        address attacker = makeAddr("attacker");

        vm.startPrank(attacker);

        // Should not be able to set curator
        vm.expectRevert();
        vault.setCurator(attacker);

        // Should not be able to set owner
        vm.expectRevert();
        vault.setOwner(attacker);

        // Should not be able to submit (not curator)
        vm.expectRevert();
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, attacker, true));

        vm.stopPrank();

        console.log("Access control tests passed");
    }
}
