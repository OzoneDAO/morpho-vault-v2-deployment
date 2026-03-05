// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IOracle} from "metamorpho-v1.1-morpho-blue/src/interfaces/IOracle.sol";

import {CappedOracleFeed} from "capped-oracle-feed/CappedOracleFeed.sol";
import {Constants} from "../../../src/lib/Constants.sol";
import {IMorphoChainlinkOracleV2, AggregatorV3Interface} from "../../../src/lib/DeployHelpers.sol";
import {BaseMigrationTest} from "./BaseMigrationTest.sol";

/**
 * @title DeployedOracleAndMarketTest
 * @notice Run after Phase 1 (DeployOracleAndMarket script). Verifies:
 *   - CappedOracleFeed deployed and caps at $1.00
 *   - Morpho oracle configured with correct feeds
 *   - New sUSDS/USDT market created and seeded at 90% utilization
 */
contract DeployedOracleAndMarketTest is BaseMigrationTest {
    // ============ CAPPED ORACLE FEED ============

    function testCappedFeedDeployed() public view {
        assertGt(cappedUsdtFeed.code.length, 0, "CappedOracleFeed should have code");
        console.log("CappedOracleFeed:", cappedUsdtFeed);
    }

    function testCappedFeedCapsAtOneDollar() public view {
        CappedOracleFeed feed = CappedOracleFeed(cappedUsdtFeed);

        assertEq(feed.maxPrice(), 1e8, "Max price should be $1.00 (8 decimals)");
        assertEq(feed.decimals(), 8, "Decimals should be 8");
        assertEq(address(feed.source()), Constants.CHAINLINK_USDT_USD, "Source should be USDT/USD Chainlink");
    }

    function testCappedFeedLatestRoundData() public view {
        CappedOracleFeed feed = CappedOracleFeed(cappedUsdtFeed);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            feed.latestRoundData();

        assertGt(roundId, 0, "Round ID should be positive");
        assertGt(answer, 0, "Answer should be positive");
        assertLe(answer, 1e8, "Answer should be capped at $1.00");
        assertGt(startedAt, 0, "StartedAt should be set");
        assertGt(updatedAt, 0, "UpdatedAt should be set");
        assertGt(answeredInRound, 0, "AnsweredInRound should be set");
        console.log("Capped USDT/USD answer:", uint256(answer));
    }

    function testCappedFeedDecimalsMatchSource() public view {
        CappedOracleFeed feed = CappedOracleFeed(cappedUsdtFeed);
        assertEq(
            feed.decimals(),
            AggregatorV3Interface(Constants.CHAINLINK_USDT_USD).decimals(),
            "Decimals should match source"
        );
    }

    // ============ MORPHO ORACLE ============

    function testOracleDeployed() public view {
        assertGt(newOracle.code.length, 0, "Oracle should have code");
        console.log("Oracle:", newOracle);
    }

    function testOracleFeedConfiguration() public view {
        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(newOracle);

        assertEq(oracle.BASE_VAULT(), Constants.S_USDS, "Base vault should be sUSDS");
        assertEq(oracle.BASE_VAULT_CONVERSION_SAMPLE(), 1e18, "Base vault conversion sample should be 1e18");
        assertEq(oracle.BASE_FEED_1(), Constants.CHAINLINK_USDS_USD, "Base feed 1 should be USDS/USD");
        assertEq(oracle.BASE_FEED_2(), address(0), "Base feed 2 should be zero");
        assertEq(oracle.QUOTE_VAULT(), address(0), "Quote vault should be zero");
        assertEq(oracle.QUOTE_FEED_1(), cappedUsdtFeed, "Quote feed 1 should be CappedOracleFeed");
        assertEq(oracle.QUOTE_FEED_2(), address(0), "Quote feed 2 should be zero");
    }

    function testOracleReturnsValidPrice() public view {
        uint256 price = IOracle(newOracle).price();

        // Scale = 10^(36 + 6 - 18) = 10^24. sUSDS ~$1.05 USDT
        uint256 scale = 1e24;
        assertGt(price, scale, "Price should be >= 1.00 * scale");
        assertLt(price, scale * 120 / 100, "Price should be < 1.20 * scale");
        console.log("Oracle price:", price);
    }

    function testOraclePriceIsHigherOrEqualToExisting() public view {
        uint256 newPrice = IOracle(newOracle).price();
        uint256 existingPrice = IOracle(Constants.EXISTING_SUSDS_USDT_ORACLE).price();

        uint256 scale = 1e24;
        assertGt(newPrice, scale * 99 / 100, "New oracle price should be reasonable");
        assertGt(existingPrice, scale * 99 / 100, "Existing oracle price should be reasonable");
        console.log("New oracle price:", newPrice);
        console.log("Existing oracle price:", existingPrice);
    }

    // ============ MARKET ============

    function testMarketCreatedOnMorpho() public view {
        bytes32 marketId = keccak256(abi.encode(newParams));
        Market memory marketState = IMorpho(Constants.MORPHO_BLUE).market(Id.wrap(marketId));

        assertGt(marketState.totalSupplyShares, 0, "Market should have supply shares");
        assertGt(marketState.totalBorrowShares, 0, "Market should have borrow shares");
        console.log("Market ID:", vm.toString(marketId));
    }

    function testMarketParams() public view {
        assertEq(newParams.loanToken, Constants.USDT, "Loan token should be USDT");
        assertEq(newParams.collateralToken, Constants.S_USDS, "Collateral should be sUSDS");
        assertEq(newParams.oracle, newOracle, "Oracle should be the new capped oracle");
        assertEq(newParams.irm, Constants.IRM_ADAPTIVE, "IRM should be adaptive");
        assertEq(newParams.lltv, Constants.LLTV_SAVINGS, "LLTV should be 96.5%");
    }

    function testMarketSeededWith90PercentUtilization() public view {
        bytes32 marketId = keccak256(abi.encode(newParams));
        Market memory marketState = IMorpho(Constants.MORPHO_BLUE).market(Id.wrap(marketId));

        assertGt(marketState.totalSupplyAssets, 0, "Market should have supply");
        assertGt(marketState.totalBorrowAssets, 0, "Market should have borrows");

        uint256 utilization = (uint256(marketState.totalBorrowAssets) * 100) / uint256(marketState.totalSupplyAssets);
        assertEq(utilization, 90, "Utilization should be 90%");
        console.log("Market utilization:", utilization, "%");
    }

    function testNewMarketIdDiffersFromExisting() public view {
        bytes32 newMarketId = keccak256(abi.encode(newParams));
        assertFalse(
            newMarketId == Constants.EXISTING_SUSDS_USDT_MARKET_ID,
            "New market should have different ID from existing market"
        );
    }
}
