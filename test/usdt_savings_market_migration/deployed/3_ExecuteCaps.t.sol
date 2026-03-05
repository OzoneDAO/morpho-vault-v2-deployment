// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {MarketParams} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";

import {Constants} from "../../../src/lib/Constants.sol";
import {BaseMigrationTest} from "./BaseMigrationTest.sol";

/**
 * @title DeployedExecuteCapsTest
 * @notice Run after Step 2 (execute cap increases after 3-day timelock). Verifies:
 *   - New market caps are active
 *   - Liquidity adapter still on old market (not switched yet)
 */
contract DeployedExecuteCapsTest is BaseMigrationTest {
    function testNewMarketAbsoluteCapSet() public view {
        uint256 absCap = vault.absoluteCap(newMarketCapId);
        console.log("New market absolute cap:", absCap);
        assertEq(absCap, type(uint128).max, "New market absolute cap should be max");
    }

    function testNewMarketRelativeCapSet() public view {
        uint256 relCap = vault.relativeCap(newMarketCapId);
        console.log("New market relative cap:", relCap);
        assertEq(relCap, 1e18, "New market relative cap should be 100%");
    }

    function testOldMarketCapsStillActive() public view {
        assertGt(vault.absoluteCap(oldMarketCapId), 0, "Old market absolute cap should still be set");
        assertGt(vault.relativeCap(oldMarketCapId), 0, "Old market relative cap should still be set");
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
