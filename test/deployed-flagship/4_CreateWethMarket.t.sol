// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IOracle} from "metamorpho-v1.1-morpho-blue/src/interfaces/IOracle.sol";

import {Constants} from "../../src/lib/Constants.sol";

/**
 * @title DeployedCreateWethMarketTest
 * @notice Tests after Script 4: Verify WETH/USDS oracle and market
 * @dev Run after deploying script 4 on mainnet/Tenderly
 *
 * Required env vars:
 *   ORACLE_WETH - Deployed oracle address
 */
contract DeployedCreateWethMarketTest is Test {
    address public oracleWeth;
    MarketParams public params;
    Id public marketId;

    function setUp() public {
        oracleWeth = vm.envAddress("ORACLE_WETH");

        params = MarketParams({
            loanToken: Constants.USDS,
            collateralToken: Constants.WETH,
            oracle: oracleWeth,
            irm: Constants.IRM_ADAPTIVE,
            lltv: Constants.LLTV_VOLATILE
        });
        marketId = Id.wrap(keccak256(abi.encode(params)));
    }

    function testOracleReturnsValidPrice() public view {
        // IOracle.price() scale = 10^(36 + 18 - 18) = 10^36
        // WETH ~$2.7k → price ~ 2_700 * 1e36
        uint256 price = IOracle(oracleWeth).price();
        console.log("Oracle WETH/USDS price:", price);
        assertGt(price, 500e36, "price too low (< $500)");
        assertLt(price, 20_000e36, "price too high (> $20k)");
    }

    function testMarketParams() public view {
        assertEq(params.loanToken, Constants.USDS, "loanToken should be USDS");
        assertEq(params.collateralToken, Constants.WETH, "collateralToken should be WETH");
        assertEq(params.oracle, oracleWeth, "oracle should match deployed oracle");
        assertEq(params.irm, Constants.IRM_ADAPTIVE, "irm should be adaptive");
        assertEq(params.lltv, Constants.LLTV_VOLATILE, "lltv should be 86%");
    }

    function testMarketSeeding() public view {
        Market memory m = IMorpho(Constants.MORPHO_BLUE).market(marketId);
        assertEq(m.totalSupplyAssets, 1e18, "dead supply should be 1 USDS");
        assertEq(m.totalBorrowAssets, 9e17, "dead borrow should be 0.9 USDS");
    }

    function testMarketUtilization() public view {
        Market memory m = IMorpho(Constants.MORPHO_BLUE).market(marketId);
        uint256 utilizationBps = (uint256(m.totalBorrowAssets) * 10000) / uint256(m.totalSupplyAssets);
        console.log("WETH/USDS utilization (bps):", utilizationBps);
        assertEq(utilizationBps, 9000, "utilization should be 90%");
    }
}
