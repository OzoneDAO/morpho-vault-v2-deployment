// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IOracle} from "metamorpho-v1.1-morpho-blue/src/interfaces/IOracle.sol";

import {Constants} from "../../src/lib/Constants.sol";
import {BaseDeployedVaultTest} from "../base/BaseDeployedVaultTest.sol";

/**
 * @title DeployedConfigureVaultTest
 * @notice Tests after Script 5: Verify full vault configuration
 * @dev Extends BaseDeployedVaultTest to inherit all common deployed-vault tests
 *      (roles, timelocks, gates, adapter, dead deposit, user ops, etc.)
 *      plus adds Flagship-specific tests.
 *
 * Required env vars:
 *   VAULT_ADDRESS - Deployed vault address
 *
 * Optional env vars:
 *   OWNER, CURATOR, ALLOCATOR, SENTINEL - Expected role addresses
 */
contract DeployedConfigureVaultTest is BaseDeployedVaultTest {
    // Existing stUSDS oracle
    address constant EXISTING_STUSDS_ORACLE = 0x0A976226d113B67Bd42D672Ac9f83f92B44b454C;

    // ============ FLAGSHIP-SPECIFIC TESTS ============

    function testNoLiquidityAdapterSet() public view {
        console.log("=== Liquidity Adapter Check ===");
        address liquidityAdapter = vault.liquidityAdapter();
        console.log("Liquidity Adapter:", liquidityAdapter);

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
    }

    function testUnauthorizedAllocate() public {
        address attacker = makeAddr("attacker");
        address adapter = vault.adapters(0);

        vm.prank(attacker);
        vm.expectRevert();
        vault.allocate(adapter, "", 100);

        console.log("Unauthorized allocate test passed");
    }

    function testStUsdsOracleReturnsValidPrice() public view {
        // IOracle.price() scale = 10^(36 + 18 - 18) = 10^36
        // stUSDS ~$1.05 → price ~ 1.05 * 1e36
        uint256 price = IOracle(EXISTING_STUSDS_ORACLE).price();
        console.log("Oracle stUSDS/USDS price:", price);
        assertGt(price, 0.9e36, "stUSDS: price too low (< 0.9)");
        assertLt(price, 1.5e36, "stUSDS: price too high (> 1.5)");
    }
}
