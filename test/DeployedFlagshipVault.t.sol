// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";

import {Constants} from "../src/lib/Constants.sol";
import {BaseDeployedVaultTest} from "./base/BaseDeployedVaultTest.sol";

/**
 * @title DeployedFlagshipVaultTest
 * @notice Tests against already-deployed Flagship vault contracts on Tenderly or mainnet fork
 * @dev Set VAULT_ADDRESS env var to test a specific deployed vault
 *
 * FLAGSHIP VAULT CHARACTERISTICS:
 * - No liquidity adapter (deposits stay 100% idle)
 * - 20% max allocation to adapter (across all markets)
 * - 5% max per market (stUSDS, cbBTC, wstETH, WETH)
 * - Allocator bot is responsible for manual allocation/rebalancing
 */
contract DeployedFlagshipVaultTest is BaseDeployedVaultTest {
    // ============ FLAGSHIP-SPECIFIC TESTS ============

    function testNoLiquidityAdapterSet() public view {
        console.log("=== Liquidity Adapter Check ===");
        address liquidityAdapter = vault.liquidityAdapter();
        console.log("Liquidity Adapter:", liquidityAdapter);

        // Flagship vault should NOT have a liquidity adapter (deposits stay idle)
        assertEq(liquidityAdapter, address(0), "Liquidity adapter should NOT be set for Flagship vault");
    }

    function testDepositsStayIdle() public {
        console.log("=== Deposits Stay Idle Test ===");

        address user = makeAddr("idleUser");
        uint256 depositAmount = 1000 * 1e18;

        uint256 vaultBalanceBefore = usds.balanceOf(address(vault));

        deal(Constants.USDS, user, depositAmount);

        vm.startPrank(user);
        usds.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 vaultBalanceAfter = usds.balanceOf(address(vault));
        assertEq(vaultBalanceAfter, vaultBalanceBefore + depositAmount, "Deposits should stay idle in vault");

        console.log("Vault balance before:", vaultBalanceBefore);
        console.log("Vault balance after:", vaultBalanceAfter);
        console.log("Deposit stayed idle: true");
    }

    function testUnauthorizedAllocate() public {
        address attacker = makeAddr("attacker");
        address adapter = vault.adapters(0);

        vm.prank(attacker);
        vm.expectRevert();
        vault.allocate(adapter, "", 100);

        console.log("Unauthorized allocate test passed");
    }
}
