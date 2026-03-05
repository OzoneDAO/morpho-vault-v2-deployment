// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IOracle} from "metamorpho-v1.1-morpho-blue/src/interfaces/IOracle.sol";

import {Constants} from "../../../src/lib/Constants.sol";
import {BaseMigrationTest} from "./BaseMigrationTest.sol";

/**
 * @title DeployedReallocateTest
 * @notice Run after Step 4 (reallocate capital from old to new market). Verifies:
 *   - Old market has near-zero allocation
 *   - New market has allocation
 *   - Users can deposit and withdraw
 */
contract DeployedReallocateTest is BaseMigrationTest {
    using SafeERC20 for IERC20;

    function testOldMarketAllocationNearZero() public view {
        uint256 oldAlloc = vault.allocation(oldMarketCapId);
        console.log("Old market allocation:", oldAlloc);

        // Allow for dust (rounding in Morpho shares)
        assertLt(oldAlloc, 1e5, "Old market should have near-zero allocation (dust only)");
    }

    function testNewMarketHasAllocation() public view {
        uint256 newAlloc = vault.allocation(newMarketCapId);
        console.log("New market allocation:", newAlloc);

        assertGt(newAlloc, 0, "New market should have allocation");
    }

    function testLiquidityAdapterPointsToNewMarket() public view {
        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory currentParams = abi.decode(liquidityData, (MarketParams));

        assertEq(currentParams.oracle, newOracle, "Liquidity adapter should use new oracle");
    }

    function testNewOracleReturnsValidPrice() public view {
        uint256 price = IOracle(newOracle).price();
        uint256 scale = 1e24;

        assertGt(price, scale, "Price should be >= 1.00 * scale");
        assertLt(price, scale * 120 / 100, "Price should be < 1.20 * scale");
        console.log("New oracle price:", price);
    }

    function testUserDeposit() public {
        _warpToLatestMarketUpdate();

        address user = makeAddr("depositUser");
        uint256 depositAmount = 100e6;

        deal(Constants.USDT, user, depositAmount);

        vm.startPrank(user);
        IERC20(Constants.USDT).forceApprove(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();

        assertGt(shares, 0, "User should receive shares");
        console.log("Deposited 100 USDT, received shares:", shares);
    }

    function testUserWithdraw() public {
        _warpToLatestMarketUpdate();

        address user = makeAddr("withdrawUser");
        uint256 depositAmount = 100e6;

        deal(Constants.USDT, user, depositAmount);

        vm.startPrank(user);
        IERC20(Constants.USDT).forceApprove(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);

        uint256 assets = vault.redeem(shares, user, user);
        vm.stopPrank();

        assertGt(assets, 0, "User should receive assets");
        assertEq(vault.balanceOf(user), 0, "User should have no shares left");
        console.log("Withdrew:", assets, "USDT");
    }

    function _warpToLatestMarketUpdate() internal {
        IMorpho morpho = IMorpho(Constants.MORPHO_BLUE);

        Market memory oldState = morpho.market(Id.wrap(Constants.EXISTING_SUSDS_USDT_MARKET_ID));
        Market memory newState = morpho.market(Id.wrap(keccak256(abi.encode(newParams))));

        uint256 latest = oldState.lastUpdate > newState.lastUpdate ? oldState.lastUpdate : newState.lastUpdate;
        vm.warp(latest + 1);
    }
}
