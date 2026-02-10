// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IOracle} from "metamorpho-v1.1-morpho-blue/src/interfaces/IOracle.sol";

import {Constants} from "../../src/lib/Constants.sol";

/**
 * @title DeployedCreateWstEthMarketTest
 * @notice Tests after Script 3: Verify wstETH/USDS oracle and market
 * @dev Run after deploying script 3 on mainnet/Tenderly
 *
 * Required env vars:
 *   ORACLE_WSTETH - Deployed oracle address
 */
contract DeployedCreateWstEthMarketTest is Test {
    address public oracleWstEth;
    MarketParams public params;
    Id public marketId;

    function setUp() public {
        oracleWstEth = vm.envAddress("ORACLE_WSTETH");

        params = MarketParams({
            loanToken: Constants.USDS,
            collateralToken: Constants.WSTETH,
            oracle: oracleWstEth,
            irm: Constants.IRM_ADAPTIVE,
            lltv: Constants.LLTV_VOLATILE
        });
        marketId = Id.wrap(keccak256(abi.encode(params)));
    }

    function testOracleReturnsValidPrice() public view {
        // IOracle.price() scale = 10^(36 + 18 - 18) = 10^36
        // wstETH ~$3.8k → price ~ 3_800 * 1e36
        uint256 price = IOracle(oracleWstEth).price();
        console.log("Oracle wstETH/USDS price:", price);
        assertGt(price, 500e36, "price too low (< $500)");
        assertLt(price, 20_000e36, "price too high (> $20k)");
    }

    function testMarketParams() public view {
        assertEq(params.loanToken, Constants.USDS, "loanToken should be USDS");
        assertEq(params.collateralToken, Constants.WSTETH, "collateralToken should be WSTETH");
        assertEq(params.oracle, oracleWstEth, "oracle should match deployed oracle");
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
        console.log("wstETH/USDS utilization (bps):", utilizationBps);
        assertEq(utilizationBps, 9000, "utilization should be 90%");
    }
}
