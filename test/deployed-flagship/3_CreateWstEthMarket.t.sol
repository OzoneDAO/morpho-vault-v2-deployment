// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IOracle} from "metamorpho-v1.1-morpho-blue/src/interfaces/IOracle.sol";

import {Constants} from "../../src/lib/Constants.sol";
import {IMorphoChainlinkOracleV2, AggregatorV3Interface} from "../../src/lib/DeployHelpers.sol";

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
        assertGt(price, 1_500e36, "wstETH: price too low (< $1,500)");
        assertLt(price, 10_000e36, "wstETH: price too high (> $10,000)");
    }

    function testOracleFeedConfiguration() public view {
        console.log("=== Oracle Feed Configuration ===");

        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(oracleWstEth);

        address baseFeed1 = oracle.BASE_FEED_1();
        address baseFeed2 = oracle.BASE_FEED_2();
        address quoteFeed1 = oracle.QUOTE_FEED_1();
        address quoteFeed2 = oracle.QUOTE_FEED_2();
        address baseVault = oracle.BASE_VAULT();
        address quoteVault = oracle.QUOTE_VAULT();

        console.log("BASE_FEED_1 (wstETH/stETH):", baseFeed1);
        console.log("BASE_FEED_2 (stETH/USD):", baseFeed2);
        console.log("QUOTE_FEED_1 (USDS/USD):", quoteFeed1);
        console.log("QUOTE_FEED_2:", quoteFeed2);
        console.log("BASE_VAULT:", baseVault);
        console.log("QUOTE_VAULT:", quoteVault);

        assertEq(baseFeed1, Constants.MORPHO_WSTETH_STETH_ADAPTER, "BASE_FEED_1 should be Morpho wstETH/stETH adapter");
        assertEq(baseFeed2, Constants.CHAINLINK_STETH_USD, "BASE_FEED_2 should be stETH/USD");
        assertEq(quoteFeed1, Constants.CHAINLINK_USDS_USD, "QUOTE_FEED_1 should be USDS/USD");
        assertEq(quoteFeed2, address(0), "QUOTE_FEED_2 should be unused");
        assertEq(baseVault, address(0), "BASE_VAULT should be unused");
        assertEq(quoteVault, address(0), "QUOTE_VAULT should be unused");

        // Verify feed decimals
        uint8 wstEthStEthDecimals = AggregatorV3Interface(baseFeed1).decimals();
        uint8 stEthDecimals = AggregatorV3Interface(baseFeed2).decimals();
        uint8 usdsDecimals = AggregatorV3Interface(quoteFeed1).decimals();

        console.log("wstETH/stETH adapter decimals:", wstEthStEthDecimals);
        console.log("stETH/USD decimals:", stEthDecimals);
        console.log("USDS/USD decimals:", usdsDecimals);

        assertEq(wstEthStEthDecimals, 18, "wstETH/stETH adapter should have 18 decimals");
        assertEq(stEthDecimals, 8, "stETH/USD feed should have 8 decimals");
        assertEq(usdsDecimals, 8, "USDS/USD feed should have 8 decimals");
    }

    function testOraclePriceCrossValidation() public view {
        console.log("=== Oracle Price Cross-Validation ===");

        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(oracleWstEth);
        uint256 oraclePrice = oracle.price();
        uint256 scaleFactor = oracle.SCALE_FACTOR();

        // Read raw feed answers
        (, int256 wstEthStEthAnswer,,,) = AggregatorV3Interface(Constants.MORPHO_WSTETH_STETH_ADAPTER).latestRoundData();
        (, int256 stEthUsdAnswer,,,) = AggregatorV3Interface(Constants.CHAINLINK_STETH_USD).latestRoundData();
        (, int256 usdsUsdAnswer,,,) = AggregatorV3Interface(Constants.CHAINLINK_USDS_USD).latestRoundData();

        console.log("Raw wstETH/stETH:", uint256(wstEthStEthAnswer));
        console.log("Raw stETH/USD:", uint256(stEthUsdAnswer));
        console.log("Raw USDS/USD:", uint256(usdsUsdAnswer));
        console.log("Scale factor:", scaleFactor);

        // price = SCALE_FACTOR * wstEthStEth * stEthUsd / usdsUsd
        uint256 expectedPrice = scaleFactor * uint256(wstEthStEthAnswer) * uint256(stEthUsdAnswer) / uint256(usdsUsdAnswer);

        console.log("Oracle price:", oraclePrice);
        console.log("Expected from feeds:", expectedPrice);

        assertApproxEqAbs(oraclePrice, expectedPrice, 1, "Oracle price should match computed price from feeds");
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
