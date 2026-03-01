// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {Constants} from "../../src/lib/Constants.sol";

/**
 * @title BaseDeployedVaultTest
 * @notice Base test contract for testing already-deployed vaults
 * @dev Set VAULT_ADDRESS env var to specify the vault to test
 */
abstract contract BaseDeployedVaultTest is Test {
    using SafeERC20 for IERC20;
    // State
    IVaultV2 public vault;
    IERC20 public loanToken;

    // ============ VIRTUAL FUNCTIONS ============

    /// @notice Loan token address (override for non-USDS vaults)
    function _loanTokenAddress() internal pure virtual returns (address) {
        return Constants.USDS;
    }

    /// @notice Initial dead deposit amount (override for 6-dec tokens)
    function _initialDeadDeposit() internal pure virtual returns (uint256) {
        return Constants.INITIAL_DEAD_DEPOSIT;
    }

    /// @notice Deposit amount scaled to token decimals (override for 6-dec tokens)
    function _depositAmount() internal pure virtual returns (uint256) {
        return 100e18;
    }

    /// @notice Expected allocator address (override for flagship vault)
    function _expectedAllocator() internal pure virtual returns (address) {
        return Constants.SKY_MONEY_CURATOR;
    }

    /// @notice Expected vault name (must override per vault)
    function _expectedVaultName() internal pure virtual returns (string memory);

    /// @notice Expected vault symbol (must override per vault)
    function _expectedVaultSymbol() internal pure virtual returns (string memory);

    function setUp() public virtual {
        address vaultAddr = vm.envOr("VAULT_ADDRESS", address(0));
        vault = IVaultV2(vaultAddr);
        loanToken = IERC20(_loanTokenAddress());

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

        assertEq(vault.asset(), _loanTokenAddress(), "Asset should match loan token");
    }

    function testRoleConfiguration() public view {
        console.log("=== Role Configuration ===");
        console.log("Owner:", vault.owner());
        console.log("Curator:", vault.curator());

        assertTrue(vault.owner() != address(0), "Owner should be set");
        assertTrue(vault.curator() != address(0), "Curator should be set");
    }

    function testExpectedOwner() public view {
        console.log("=== Expected Owner Check ===");
        console.log("Expected Owner:", Constants.SKY_MONEY_CURATOR);
        console.log("Actual Owner:", vault.owner());
        assertEq(vault.owner(), Constants.SKY_MONEY_CURATOR, "Owner should match expected");
    }

    function testExpectedCurator() public view {
        console.log("=== Expected Curator Check ===");
        console.log("Expected Curator:", Constants.SKY_MONEY_CURATOR);
        console.log("Actual Curator:", vault.curator());
        assertEq(vault.curator(), Constants.SKY_MONEY_CURATOR, "Curator should match expected");
    }

    function testExpectedAllocator() public view {
        address expectedAllocator = _expectedAllocator();
        console.log("=== Expected Allocator Check ===");
        console.log("Expected Allocator:", expectedAllocator);
        console.log("Is Allocator:", vault.isAllocator(expectedAllocator));
        assertTrue(vault.isAllocator(expectedAllocator), "Expected address should be allocator");
    }

    function testExpectedSentinel() public view {
        console.log("=== Expected Sentinel Check ===");
        console.log("Expected Sentinel:", Constants.SKY_MONEY_CURATOR);
        console.log("Is Sentinel:", vault.isSentinel(Constants.SKY_MONEY_CURATOR));
        assertTrue(vault.isSentinel(Constants.SKY_MONEY_CURATOR), "Expected address should be sentinel");
    }

    function testExpectedVaultName() public view {
        string memory expectedName = _expectedVaultName();
        console.log("=== Expected Vault Name Check ===");
        console.log("Expected Name:", expectedName);
        console.log("Actual Name:", vault.name());
        assertEq(vault.name(), expectedName, "Vault name should match expected");
    }

    function testExpectedVaultSymbol() public view {
        string memory expectedSymbol = _expectedVaultSymbol();
        console.log("=== Expected Vault Symbol Check ===");
        console.log("Expected Symbol:", expectedSymbol);
        console.log("Actual Symbol:", vault.symbol());
        assertEq(vault.symbol(), expectedSymbol, "Vault symbol should match expected");
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

        assertEq(increaseTimelockTL, Constants.TIMELOCK_HIGH, "increaseTimelock should be 7 days");
        assertEq(removeAdapterTL, Constants.TIMELOCK_HIGH, "removeAdapter should be 7 days");
        assertEq(abdicateTL, Constants.TIMELOCK_HIGH, "abdicate should be 7 days");

        // Low priority (3 days)
        uint256 addAdapterTL = vault.timelock(IVaultV2.addAdapter.selector);
        uint256 increaseAbsoluteCapTL = vault.timelock(IVaultV2.increaseAbsoluteCap.selector);
        uint256 increaseRelativeCapTL = vault.timelock(IVaultV2.increaseRelativeCap.selector);

        console.log("addAdapter:", addAdapterTL);
        console.log("increaseAbsoluteCap:", increaseAbsoluteCapTL);
        console.log("increaseRelativeCap:", increaseRelativeCapTL);

        uint256 setForceDeallocatePenaltyTL = vault.timelock(IVaultV2.setForceDeallocatePenalty.selector);
        console.log("setForceDeallocatePenalty:", setForceDeallocatePenaltyTL);

        assertEq(addAdapterTL, Constants.TIMELOCK_LOW, "addAdapter should be 3 days");
        assertEq(increaseAbsoluteCapTL, Constants.TIMELOCK_LOW, "increaseAbsoluteCap should be 3 days");
        assertEq(increaseRelativeCapTL, Constants.TIMELOCK_LOW, "increaseRelativeCap should be 3 days");
        assertEq(setForceDeallocatePenaltyTL, Constants.TIMELOCK_LOW, "setForceDeallocatePenalty should be 3 days");
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
        uint256 deadAssets = vault.convertToAssets(deadShares);
        uint256 expectedDeadDeposit = _initialDeadDeposit();

        console.log("Dead address shares:", deadShares);
        console.log("Dead assets:", deadAssets);
        console.log("Expected:", expectedDeadDeposit);

        assertGt(deadShares, 0, "Dead address should have shares");
        assertGe(deadAssets, expectedDeadDeposit, "Dead deposit should be >= initial (may have accrued interest)");
        assertLt(deadAssets, expectedDeadDeposit * 2, "Dead deposit should be < 2x initial");
    }

    function testMaxRate() public view {
        console.log("=== Max Rate ===");

        uint256 maxRate = vault.maxRate();
        console.log("Max Rate:", maxRate);
        console.log("Expected:", Constants.MAX_RATE);
        assertEq(maxRate, Constants.MAX_RATE, "Max rate should be 200% APR (63419583967)");
    }

    function testFeesAreZero() public view {
        console.log("=== Fee Configuration ===");

        uint256 performanceFee = vault.performanceFee();
        uint256 managementFee = vault.managementFee();

        console.log("Performance Fee:", performanceFee);
        console.log("Management Fee:", managementFee);

        assertEq(performanceFee, 0, "Performance fee should be 0%");
        assertEq(managementFee, 0, "Management fee should be 0%");
    }

    // ============ USER OPERATIONS ============

    function testUserDeposit() public virtual {
        address user = makeAddr("testUser");
        uint256 depositAmount = _depositAmount();

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.forceApprove(address(vault), depositAmount);

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

    function testUserWithdraw() public virtual {
        address user = makeAddr("testUser2");
        uint256 depositAmount = _depositAmount();

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.forceApprove(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);

        console.log("=== User Withdraw Test ===");
        console.log("Deposited, got shares:", shares);

        uint256 withdrawShares = shares / 2;
        uint256 expectedAssets = vault.previewRedeem(withdrawShares);

        console.log("Redeeming shares:", withdrawShares);
        console.log("Expected assets:", expectedAssets);

        uint256 assetsReceived = vault.redeem(withdrawShares, user, user);

        console.log("Assets received:", assetsReceived);

        assertEq(assetsReceived, expectedAssets, "Assets should match preview");
        assertEq(vault.balanceOf(user), shares - withdrawShares, "Shares should decrease");
        assertEq(loanToken.balanceOf(user), assetsReceived, "Loan token balance should match");

        vm.stopPrank();
    }

    function testFullDepositWithdrawCycle() public virtual {
        address user = makeAddr("cycleUser");
        uint256 depositAmount = _depositAmount() * 10;

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.forceApprove(address(vault), depositAmount);

        console.log("=== Full Cycle Test ===");
        console.log("Initial deposit:", depositAmount);

        uint256 shares = vault.deposit(depositAmount, user);
        console.log("Shares after deposit:", shares);

        uint256 assetsBack = vault.redeem(shares, user, user);
        console.log("Assets after full redeem:", assetsBack);

        assertApproxEqAbs(assetsBack, depositAmount, 2, "Should get back ~same amount");
        assertEq(vault.balanceOf(user), 0, "Should have 0 shares");

        vm.stopPrank();
    }

    // ============ SHARE PRICE ============

    function testSharePrice() public view {
        console.log("=== Share Price ===");

        uint256 oneShare = 10 ** vault.decimals();
        uint256 assetsPerShare = vault.convertToAssets(oneShare);

        uint256 oneUnit = 10 ** vault.decimals();
        uint256 sharesPerUnit = vault.convertToShares(oneUnit);

        console.log("Assets per 1 share:", assetsPerShare);
        console.log("Shares per 1 unit:", sharesPerUnit);

        assertGt(assetsPerShare, 0, "Should have positive conversion");
    }

    // ============ ACCESS CONTROL ============

    function testUnauthorizedAccess() public {
        address attacker = makeAddr("attacker");

        vm.startPrank(attacker);

        vm.expectRevert();
        vault.setCurator(attacker);

        vm.expectRevert();
        vault.setOwner(attacker);

        vm.expectRevert();
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, attacker, true));

        vm.stopPrank();

        console.log("Access control tests passed");
    }
}
