// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";

import {Constants} from "../../src/lib/Constants.sol";
import {BaseDeployedVaultTest} from "../base/BaseDeployedVaultTest.sol";

/**
 * @title DeployedUsdtRiskCapitalVaultTest
 * @notice Tests against already-deployed USDT Risk Capital vault on Tenderly or mainnet fork
 * @dev Set VAULT_ADDRESS env var to test a specific deployed vault
 */
contract DeployedUsdtRiskCapitalVaultTest is BaseDeployedVaultTest {
    function _loanTokenAddress() internal pure override returns (address) {
        return Constants.USDT;
    }

    function _initialDeadDeposit() internal pure override returns (uint256) {
        return Constants.INITIAL_DEAD_DEPOSIT_6DEC;
    }

    function _depositAmount() internal pure override returns (uint256) {
        return 100e6;
    }

    // ============ USDT RISK CAPITAL SPECIFIC TESTS ============

    function testLiquidityAdapterSet() public view {
        console.log("=== Liquidity Adapter Check ===");
        address liquidityAdapter = vault.liquidityAdapter();
        console.log("Liquidity Adapter:", liquidityAdapter);

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

        assertApproxEqAbs(utilizationBps, 9000, 50, "Market utilization should be ~90% (9000 bps, +/- 50 bps)");
    }
}
