// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IOracle} from "metamorpho-v1.1-morpho-blue/src/interfaces/IOracle.sol";

import {Constants} from "../../src/lib/Constants.sol";
import {IMorphoChainlinkOracleV2, AggregatorV3Interface} from "../../src/lib/DeployHelpers.sol";

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
        assertGt(price, 1_000e36, "WETH: price too low (< $1,000)");
        assertLt(price, 8_000e36, "WETH: price too high (> $8,000)");
    }

    function testOracleFeedConfiguration() public view {
        console.log("=== Oracle Feed Configuration ===");

        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(oracleWeth);

        address baseFeed1 = oracle.BASE_FEED_1();
        address baseFeed2 = oracle.BASE_FEED_2();
        address quoteFeed1 = oracle.QUOTE_FEED_1();
        address quoteFeed2 = oracle.QUOTE_FEED_2();
        address baseVault = oracle.BASE_VAULT();
        address quoteVault = oracle.QUOTE_VAULT();

        console.log("BASE_FEED_1 (ETH/USD):", baseFeed1);
        console.log("BASE_FEED_2:", baseFeed2);
        console.log("QUOTE_FEED_1 (USDS/USD):", quoteFeed1);
        console.log("QUOTE_FEED_2:", quoteFeed2);
        console.log("BASE_VAULT:", baseVault);
        console.log("QUOTE_VAULT:", quoteVault);

        assertEq(baseFeed1, Constants.CHAINLINK_ETH_USD, "BASE_FEED_1 should be ETH/USD");
        assertEq(baseFeed2, address(0), "BASE_FEED_2 should be unused");
        assertEq(quoteFeed1, Constants.CHAINLINK_USDS_USD, "QUOTE_FEED_1 should be USDS/USD");
        assertEq(quoteFeed2, address(0), "QUOTE_FEED_2 should be unused");
        assertEq(baseVault, address(0), "BASE_VAULT should be unused");
        assertEq(quoteVault, address(0), "QUOTE_VAULT should be unused");

        // Verify feed decimals
        uint8 ethDecimals = AggregatorV3Interface(baseFeed1).decimals();
        uint8 usdsDecimals = AggregatorV3Interface(quoteFeed1).decimals();

        console.log("ETH/USD decimals:", ethDecimals);
        console.log("USDS/USD decimals:", usdsDecimals);

        assertEq(ethDecimals, 8, "ETH/USD feed should have 8 decimals");
        assertEq(usdsDecimals, 8, "USDS/USD feed should have 8 decimals");
    }

    function testOraclePriceCrossValidation() public view {
        console.log("=== Oracle Price Cross-Validation ===");

        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(oracleWeth);
        uint256 oraclePrice = oracle.price();
        uint256 scaleFactor = oracle.SCALE_FACTOR();

        // Read raw Chainlink answers
        (, int256 ethUsdAnswer,,,) = AggregatorV3Interface(Constants.CHAINLINK_ETH_USD).latestRoundData();
        (, int256 usdsUsdAnswer,,,) = AggregatorV3Interface(Constants.CHAINLINK_USDS_USD).latestRoundData();

        console.log("Raw ETH/USD:", uint256(ethUsdAnswer));
        console.log("Raw USDS/USD:", uint256(usdsUsdAnswer));
        console.log("Scale factor:", scaleFactor);

        // price = SCALE_FACTOR * ethUsd / usdsUsd
        uint256 expectedPrice = scaleFactor * uint256(ethUsdAnswer) / uint256(usdsUsdAnswer);

        console.log("Oracle price:", oraclePrice);
        console.log("Expected from feeds:", expectedPrice);

        assertApproxEqAbs(oraclePrice, expectedPrice, 1, "Oracle price should match computed price from feeds");
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
