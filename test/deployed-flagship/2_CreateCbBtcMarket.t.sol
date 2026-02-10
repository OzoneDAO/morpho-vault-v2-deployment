// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IOracle} from "metamorpho-v1.1-morpho-blue/src/interfaces/IOracle.sol";

import {Constants} from "../../src/lib/Constants.sol";

/**
 * @title DeployedCreateCbBtcMarketTest
 * @notice Tests after Script 2: Verify cbBTC/USDS oracle and market
 * @dev Run after deploying script 2 on mainnet/Tenderly
 *
 * Required env vars:
 *   ORACLE_CBBTC - Deployed oracle address
 */
contract DeployedCreateCbBtcMarketTest is Test {
    address public oracleCbBtc;
    MarketParams public params;
    Id public marketId;

    function setUp() public {
        oracleCbBtc = vm.envAddress("ORACLE_CBBTC");

        params = MarketParams({
            loanToken: Constants.USDS,
            collateralToken: Constants.CBBTC,
            oracle: oracleCbBtc,
            irm: Constants.IRM_ADAPTIVE,
            lltv: Constants.LLTV_VOLATILE
        });
        marketId = Id.wrap(keccak256(abi.encode(params)));
    }

    function testOracleReturnsValidPrice() public view {
        // IOracle.price() scale = 10^(36 + loanDecimals - collateralDecimals) = 10^(36+18-8) = 10^46
        // cbBTC ~$97k → price ~ 97_000 * 1e46
        uint256 price = IOracle(oracleCbBtc).price();
        console.log("Oracle cbBTC/USDS price:", price);
        assertGt(price, 10_000e46, "price too low (< $10k)");
        assertLt(price, 500_000e46, "price too high (> $500k)");
    }

    function testMarketParams() public view {
        assertEq(params.loanToken, Constants.USDS, "loanToken should be USDS");
        assertEq(params.collateralToken, Constants.CBBTC, "collateralToken should be CBBTC");
        assertEq(params.oracle, oracleCbBtc, "oracle should match deployed oracle");
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
        console.log("cbBTC/USDS utilization (bps):", utilizationBps);
        assertEq(utilizationBps, 9000, "utilization should be 90%");
    }
}
