// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IOracle} from "metamorpho-v1.1-morpho-blue/src/interfaces/IOracle.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";

import {CappedOracleFeed} from "capped-oracle-feed/CappedOracleFeed.sol";
import {Constants} from "../../../src/lib/Constants.sol";
import {IMorphoChainlinkOracleV2, AggregatorV3Interface} from "../../../src/lib/DeployHelpers.sol";

/**
 * @title BaseMigrationTest
 * @notice Shared setup and helpers for migration deployed tests
 *
 * Required env vars:
 *   VAULT_ADDRESS     - The USDT Savings vault
 *   NEW_ORACLE        - The new Morpho oracle (from DeployOracleAndMarket)
 *   CAPPED_USDT_FEED  - The deployed CappedOracleFeed
 */
abstract contract BaseMigrationTest is Test {
    using SafeERC20 for IERC20;

    IVaultV2 public vault;
    address public adapter;
    address public curator;

    // Old market (DAI/USD oracle, uncapped USDT)
    MarketParams public oldParams;
    bytes32 public oldMarketCapId;

    // New market (USDS/USD oracle, capped USDT)
    address public newOracle;
    address public cappedUsdtFeed;
    MarketParams public newParams;
    bytes32 public newMarketCapId;

    function setUp() public virtual {
        vault = IVaultV2(vm.envAddress("VAULT_ADDRESS"));
        adapter = vault.adapters(0);
        curator = vault.curator();

        newOracle = vm.envAddress("NEW_ORACLE");
        cappedUsdtFeed = vm.envAddress("CAPPED_USDT_FEED");

        oldParams = MarketParams({
            loanToken: Constants.USDT,
            collateralToken: Constants.S_USDS,
            oracle: Constants.EXISTING_SUSDS_USDT_ORACLE,
            irm: Constants.IRM_ADAPTIVE,
            lltv: Constants.LLTV_SAVINGS
        });

        newParams = MarketParams({
            loanToken: Constants.USDT,
            collateralToken: Constants.S_USDS,
            oracle: newOracle,
            irm: Constants.IRM_ADAPTIVE,
            lltv: Constants.LLTV_SAVINGS
        });

        oldMarketCapId = keccak256(abi.encode("this/marketParams", adapter, oldParams));
        newMarketCapId = keccak256(abi.encode("this/marketParams", adapter, newParams));
    }
}
