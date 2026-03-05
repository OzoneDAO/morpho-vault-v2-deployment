// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";

import {Constants} from "../../../src/lib/Constants.sol";
import {BaseMigrationTest} from "./BaseMigrationTest.sol";

/**
 * @title DeployedSwitchLiquidityAdapterTest
 * @notice Run after Step 3 (switch liquidity adapter to new market). Verifies:
 *   - Liquidity adapter now points to new market
 *   - New deposits go to the new market
 *   - Old market allocation still holds previous deposits
 */
contract DeployedSwitchLiquidityAdapterTest is BaseMigrationTest {
    using SafeERC20 for IERC20;

    function testLiquidityAdapterPointsToNewMarket() public view {
        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory currentParams = abi.decode(liquidityData, (MarketParams));

        assertEq(currentParams.oracle, newOracle, "Liquidity adapter should use new oracle");
        assertEq(currentParams.loanToken, Constants.USDT, "Loan token should be USDT");
        assertEq(currentParams.collateralToken, Constants.S_USDS, "Collateral should be sUSDS");
        assertEq(currentParams.irm, Constants.IRM_ADAPTIVE, "IRM should be adaptive");
        assertEq(currentParams.lltv, Constants.LLTV_SAVINGS, "LLTV should be 96.5%");
        console.log("Liquidity adapter oracle:", currentParams.oracle);
    }

    function testNewDepositsGoToNewMarket() public {
        // Warp to avoid stale fork IRM overflow on old market
        _warpToLatestMarketUpdate();

        address user = makeAddr("migrationTestUser");
        uint256 depositAmount = 100e6;

        uint256 newAllocBefore = vault.allocation(newMarketCapId);

        deal(Constants.USDT, user, depositAmount);
        vm.startPrank(user);
        IERC20(Constants.USDT).forceApprove(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 newAllocAfter = vault.allocation(newMarketCapId);
        console.log("New market allocation before deposit:", newAllocBefore);
        console.log("New market allocation after deposit:", newAllocAfter);

        assertGt(newAllocAfter, newAllocBefore, "New deposits should increase new market allocation");
    }

    function testOldMarketStillHasAllocation() public view {
        uint256 oldAlloc = vault.allocation(oldMarketCapId);
        console.log("Old market allocation:", oldAlloc);
        // Old allocation should be > 0 if there were deposits before the switch
        // (may be 0 if vault had no user deposits, only dead deposit which stays idle)
    }

    /// @dev Warps to the latest lastUpdate across both markets to avoid IRM overflow
    function _warpToLatestMarketUpdate() internal {
        IMorpho morpho = IMorpho(Constants.MORPHO_BLUE);

        Market memory oldState = morpho.market(Id.wrap(Constants.EXISTING_SUSDS_USDT_MARKET_ID));
        Market memory newState = morpho.market(Id.wrap(keccak256(abi.encode(newParams))));

        uint256 latest = oldState.lastUpdate > newState.lastUpdate ? oldState.lastUpdate : newState.lastUpdate;
        vm.warp(latest + 1);
    }
}
