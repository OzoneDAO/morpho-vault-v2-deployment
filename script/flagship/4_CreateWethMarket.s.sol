// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IMorpho, MarketParams} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";

import {Constants} from "../../src/lib/Constants.sol";
import {IMorphoChainlinkOracleV2Factory} from "../../src/lib/DeployHelpers.sol";

/**
 * @title 4_CreateWethMarket
 * @notice Step 4/5: Create WETH/USDS oracle and market, seed with 90% utilization
 *
 * @dev This script:
 *   1. Deploys WETH/USDS Chainlink oracle
 *   2. Creates WETH/USDS market on Morpho Blue
 *   3. Seeds market with 90% utilization (1 USDS supply, 0.9 USDS borrow)
 *
 * Prerequisites:
 *   - Deployer needs: 1 USDS, 0.001 WETH
 *
 * After running, set this env var for script 5:
 *   ORACLE_WETH=<deployed oracle address>
 */
contract CreateWethMarket is Script {
    // Market seeding parameters
    uint256 constant DEAD_SUPPLY_AMOUNT = 1e18; // 1 USDS
    uint256 constant DEAD_BORROW_AMOUNT = 9e17; // 0.9 USDS (90% utilization)
    uint256 constant DEAD_COLLATERAL_WETH = 1e15; // 0.001 WETH

    struct DeploymentResult {
        address oracle;
        bytes32 marketId;
        MarketParams params;
    }

    function run() external returns (DeploymentResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Step 4/5: Create WETH/USDS Market ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Create Oracle
        result.oracle = _createOracle();

        // 2. Create Market
        result.params = _createMarket(result.oracle);
        result.marketId = keccak256(abi.encode(result.params));
        console.log("Market ID:", vm.toString(result.marketId));

        // 3. Seed Market
        _seedMarket(result.params, deployer);

        vm.stopBroadcast();

        // Instructions for next steps
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("Set this environment variable:");
        console.log("");
        console.log("export ORACLE_WETH=%s", result.oracle);
        console.log("");
        console.log("Then run: forge script script/flagship/5_ConfigureVault.s.sol ...");
    }

    function _createOracle() internal returns (address oracle) {
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, "OracleWeth"));
        // WETH/USDS = ETH/USD / USDS/USD
        oracle = IMorphoChainlinkOracleV2Factory(Constants.ORACLE_FACTORY).createMorphoChainlinkOracleV2(
            address(0), 1, Constants.CHAINLINK_ETH_USD, address(0), Constants.DECIMALS_WETH,
            address(0), 1, Constants.CHAINLINK_USDS_USD, address(0), Constants.DECIMALS_USDS,
            salt
        );
        console.log("Oracle WETH/USDS deployed at:", oracle);
    }

    function _createMarket(address oracle) internal returns (MarketParams memory params) {
        params = MarketParams({
            loanToken: Constants.USDS,
            collateralToken: Constants.WETH,
            oracle: oracle,
            irm: Constants.IRM_ADAPTIVE,
            lltv: Constants.LLTV_VOLATILE
        });

        IMorpho morpho = IMorpho(Constants.MORPHO_BLUE);
        try morpho.createMarket(params) {
            console.log("Market created for WETH/USDS");
        } catch {
            console.log("Market already exists for WETH/USDS");
        }
    }

    function _seedMarket(MarketParams memory params, address deployer) internal {
        IMorpho morpho = IMorpho(Constants.MORPHO_BLUE);

        // 1. Supply USDS to market (to dead address)
        IERC20(Constants.USDS).approve(Constants.MORPHO_BLUE, DEAD_SUPPLY_AMOUNT);
        morpho.supply(params, DEAD_SUPPLY_AMOUNT, 0, address(0xdEaD), bytes(""));
        console.log("Dead supply: 1 USDS");

        // 2. Supply collateral
        IERC20(Constants.WETH).approve(Constants.MORPHO_BLUE, DEAD_COLLATERAL_WETH);
        morpho.supplyCollateral(params, DEAD_COLLATERAL_WETH, deployer, bytes(""));
        console.log("Dead collateral: 0.001 WETH");

        // 3. Borrow USDS for 90% utilization
        morpho.borrow(params, DEAD_BORROW_AMOUNT, 0, deployer, deployer);
        console.log("Dead borrow: 0.9 USDS (90% utilization)");
    }
}
