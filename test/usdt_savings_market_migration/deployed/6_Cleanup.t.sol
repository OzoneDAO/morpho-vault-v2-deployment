// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";

import {Constants} from "../../../src/lib/Constants.sol";
import {BaseMigrationTest} from "./BaseMigrationTest.sol";

/**
 * @title DeployedCleanupTest
 * @notice Run after Step 5 (zero out old market caps). Verifies:
 *   - Old market caps are zero
 *   - New market is fully operational
 *   - Vault still works end-to-end
 */
contract DeployedCleanupTest is BaseMigrationTest {
    using SafeERC20 for IERC20;

    function testOldMarketCapsZeroed() public view {
        assertEq(vault.absoluteCap(oldMarketCapId), 0, "Old market absolute cap should be zero");
        assertEq(vault.relativeCap(oldMarketCapId), 0, "Old market relative cap should be zero");
        console.log("Old market caps zeroed out");
    }

    function testOldMarketAllocationZero() public view {
        uint256 oldAlloc = vault.allocation(oldMarketCapId);
        console.log("Old market allocation:", oldAlloc);
        assertLt(oldAlloc, 1e5, "Old market should have near-zero allocation");
    }

    function testNewMarketCapsActive() public view {
        uint256 absCap = vault.absoluteCap(newMarketCapId);
        uint256 relCap = vault.relativeCap(newMarketCapId);

        assertEq(absCap, type(uint128).max, "New market absolute cap should be max");
        assertEq(relCap, 1e18, "New market relative cap should be 100%");
        console.log("New market caps: abs=%d, rel=%d", absCap, relCap);
    }

    function testNewMarketHasAllocation() public view {
        uint256 newAlloc = vault.allocation(newMarketCapId);
        console.log("New market allocation:", newAlloc);
        assertGt(newAlloc, 0, "New market should have allocation");
    }

    function testFullDepositWithdrawCycle() public {
        _warpToLatestMarketUpdate();

        address user = makeAddr("cycleUser");
        uint256 depositAmount = 1000e6;

        deal(Constants.USDT, user, depositAmount);

        vm.startPrank(user);
        IERC20(Constants.USDT).forceApprove(address(vault), depositAmount);

        uint256 shares = vault.deposit(depositAmount, user);
        console.log("Deposited 1000 USDT, shares:", shares);

        uint256 assets = vault.redeem(shares, user, user);
        console.log("Withdrew:", assets, "USDT");
        vm.stopPrank();

        assertGt(assets, 0, "Should receive assets");
        assertApproxEqAbs(assets, depositAmount, 2, "Should get back ~same amount");
        assertEq(vault.balanceOf(user), 0, "Should have 0 shares");
    }

    function _warpToLatestMarketUpdate() internal {
        IMorpho morpho = IMorpho(Constants.MORPHO_BLUE);

        Market memory oldState = morpho.market(Id.wrap(Constants.EXISTING_SUSDS_USDT_MARKET_ID));
        Market memory newState = morpho.market(Id.wrap(keccak256(abi.encode(newParams))));

        uint256 latest = oldState.lastUpdate > newState.lastUpdate ? oldState.lastUpdate : newState.lastUpdate;
        vm.warp(latest + 1);
    }
}
