// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {MarketParams} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";

import {Constants} from "../../../src/lib/Constants.sol";
import {BaseMigrationTest} from "./BaseMigrationTest.sol";

/**
 * @title DeployedSubmitCapsTest
 * @notice Run after Step 1 (submit cap increases on curator app). Verifies:
 *   - Cap increases are pending (executableAt > 0)
 *   - Caps are NOT yet active (still 0)
 */
contract DeployedSubmitCapsTest is BaseMigrationTest {
    function testAbsoluteCapPending() public view {
        bytes memory increaseAbsData =
            abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, abi.encode("this/marketParams", adapter, newParams), type(uint128).max);

        uint256 executableAt = vault.executableAt(increaseAbsData);
        console.log("Absolute cap executableAt:", executableAt);

        assertGt(executableAt, 0, "Absolute cap increase should be pending");
    }

    function testRelativeCapPending() public view {
        bytes memory increaseRelData =
            abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, abi.encode("this/marketParams", adapter, newParams), uint256(1e18));

        uint256 executableAt = vault.executableAt(increaseRelData);
        console.log("Relative cap executableAt:", executableAt);

        assertGt(executableAt, 0, "Relative cap increase should be pending");
    }

    function testCapsNotYetActive() public view {
        assertEq(vault.absoluteCap(newMarketCapId), 0, "New market absolute cap should still be 0");
        assertEq(vault.relativeCap(newMarketCapId), 0, "New market relative cap should still be 0");
    }

    function testOldMarketCapsUnchanged() public view {
        assertGt(vault.absoluteCap(oldMarketCapId), 0, "Old market absolute cap should still be set");
        assertGt(vault.relativeCap(oldMarketCapId), 0, "Old market relative cap should still be set");
        console.log("Old market absolute cap:", vault.absoluteCap(oldMarketCapId));
        console.log("Old market relative cap:", vault.relativeCap(oldMarketCapId));
    }

    function testLiquidityAdapterStillPointsToOldMarket() public view {
        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory currentParams = abi.decode(liquidityData, (MarketParams));

        assertEq(
            currentParams.oracle,
            Constants.EXISTING_SUSDS_USDT_ORACLE,
            "Liquidity adapter should still point to old oracle"
        );
    }
}
