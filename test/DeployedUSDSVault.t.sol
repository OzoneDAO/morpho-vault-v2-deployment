// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";

import {Constants} from "../src/lib/Constants.sol";
import {BaseDeployedVaultTest} from "./base/BaseDeployedVaultTest.sol";

/**
 * @title DeployedUSDSVaultTest
 * @notice Tests against already-deployed USDS vault contracts on Tenderly or mainnet fork
 * @dev Set VAULT_ADDRESS env var to test a specific deployed vault
 */
contract DeployedUSDSVaultTest is BaseDeployedVaultTest {
    // ============ USDS-SPECIFIC TESTS ============

    function testLiquidityAdapterSet() public view {
        console.log("=== Liquidity Adapter Check ===");
        address liquidityAdapter = vault.liquidityAdapter();
        console.log("Liquidity Adapter:", liquidityAdapter);

        // USDS vault should have a liquidity adapter (deposits auto-allocated)
        assertEq(liquidityAdapter, vault.adapters(0), "Liquidity adapter should match first adapter");
    }

    function testMorphoMarketUtilizationIsApprox90Percent() public view {
        console.log("=== Morpho Market Utilization ===");

        bytes memory liquidityData = vault.liquidityData();
        require(liquidityData.length > 0, "Vault has no liquidity data set");

        MarketParams memory params = abi.decode(liquidityData, (MarketParams));
        console.log("Oracle (from vault):", params.oracle);

        Id marketId = Id.wrap(keccak256(abi.encode(params)));
        IMorpho morpho = IMorpho(Constants.MORPHO_BLUE);
        Market memory marketState = morpho.market(marketId);

        console.log("Market totalSupplyAssets:", marketState.totalSupplyAssets);
        console.log("Market totalBorrowAssets:", marketState.totalBorrowAssets);

        uint256 utilizationBps = (uint256(marketState.totalBorrowAssets) * 10000) / uint256(marketState.totalSupplyAssets);
        console.log("Utilization (bps):", utilizationBps);

        // Allow ±50 bps tolerance for interest accrual and rounding over time
        // Initial deployment targets 9000 bps (90%), but interest accrual shifts this slightly
        assertApproxEqAbs(utilizationBps, 9000, 50, "Market utilization should be ~90% (9000 bps, +/- 50 bps)");
    }
}
