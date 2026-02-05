// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IMorpho, MarketParams} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {VaultV2} from "vault-v2/VaultV2.sol";
import {VaultV2Factory} from "vault-v2/VaultV2Factory.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

import {Constants} from "../src/lib/Constants.sol";
import {DeployHelpers, IMorphoChainlinkOracleV2Factory, IMorphoMarketV1AdapterV2Factory} from "../src/lib/DeployHelpers.sol";

/**
 * @title DeployFlagshipVaultV2
 * @notice Deploys Flagship Vault V2 for USDS with multi-market allocation strategy
 *
 * @dev ALLOCATION STRATEGY:
 * This vault is designed for an 80% idle / 20% allocated strategy across 4 markets.
 *
 * KEY DESIGN DECISIONS:
 * 1. NO LIQUIDITY ADAPTER - Deposits stay 100% idle by default
 * 2. CAPS ARE LIMITS, NOT TARGETS - Actual allocation is done by the Allocator
 * 3. ALLOCATOR RESPONSIBILITY - Off-chain bot calls vault.allocate() / vault.deallocate()
 *
 * MARKETS:
 * - stUSDS/USDS: Uses EXISTING market (deployed by USDS vault script)
 * - cbBTC/USDS, wstETH/USDS, WETH/USDS: NEW markets created and seeded with 90% utilization
 *
 * MARKET CAPS (Maximum Allowed Allocation):
 * - Adapter total: 20% relative cap
 * - Each market: 5% relative cap
 */
contract DeployFlagshipVaultV2 is DeployHelpers, StdCheats {
    // Allocation caps
    uint256 constant ADAPTER_RELATIVE_CAP = 20e16; // 20%
    uint256 constant MARKET_RELATIVE_CAP = 5e16; // 5%

    // Existing stUSDS/USDS market (from USDS vault deployment)
    bytes32 constant EXISTING_STUSDS_MARKET_ID = 0x77e624dd9dd980810c2b804249e88f3598d9c7ec91f16aa5fbf6e3fdf6087f82;
    address constant EXISTING_STUSDS_ORACLE = 0x0A976226d113B67Bd42D672Ac9f83f92B44b454C;

    // Market seeding parameters (for 90% utilization)
    uint256 constant DEAD_SUPPLY_AMOUNT = 1e18; // 1 USDS supplied to each market
    uint256 constant DEAD_BORROW_AMOUNT = 9e17; // 0.9 USDS borrowed (90% utilization)

    // Collateral amounts for dead borrows (generous buffer above minimum required)
    // At 86% LLTV, need ~1.05 USDS worth of collateral to borrow 0.9 USDS
    uint256 constant DEAD_COLLATERAL_WSTETH = 1e15; // 0.001 wstETH (~$2.6 at $2600/wstETH)
    uint256 constant DEAD_COLLATERAL_WETH = 1e15; // 0.001 WETH (~$2.1 at $2100/ETH)
    uint256 constant DEAD_COLLATERAL_CBBTC = 10000; // 0.0001 cbBTC (~$7.3 at $73k/BTC) - 8 decimals

    struct DeploymentResult {
        address vaultV2;
        address adapter;
        // Oracles (stUSDS oracle is from existing market)
        address oracleStUsds;
        address oracleCbBtc;
        address oracleWstEth;
        address oracleWeth;
        // Market IDs
        bytes32 marketIdStUsds;
        bytes32 marketIdCbBtc;
        bytes32 marketIdWstEth;
        bytes32 marketIdWeth;
        // Market Params (for allocator bot)
        MarketParams paramsStUsds;
        MarketParams paramsCbBtc;
        MarketParams paramsWstEth;
        MarketParams paramsWeth;
    }

    function run() external returns (DeploymentResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address finalOwner = vm.envOr("OWNER", deployer);
        address finalCurator = vm.envOr("CURATOR", deployer);
        address finalAllocator = vm.envOr("ALLOCATOR", deployer);
        address sentinel = vm.envOr("SENTINEL", address(0));

        string memory vaultName = vm.envOr("VAULT_NAME", string("sky.money USDS Flagship Capital"));
        string memory vaultSymbol = vm.envOr("VAULT_SYMBOL", string("skyMoneyUsdsFlagshipCapital"));

        vm.startBroadcast(deployerPrivateKey);

        IMorpho morpho = IMorpho(Constants.MORPHO_BLUE);

        // Step 1: Setup stUSDS/USDS market (USE EXISTING - don't create new)
        result.oracleStUsds = EXISTING_STUSDS_ORACLE;
        result.paramsStUsds = MarketParams({
            loanToken: Constants.USDS,
            collateralToken: Constants.ST_USDS,
            oracle: EXISTING_STUSDS_ORACLE,
            irm: Constants.IRM_ADAPTIVE,
            lltv: Constants.LLTV_STUSDS
        });
        result.marketIdStUsds = keccak256(abi.encode(result.paramsStUsds));

        // Verify the existing market ID matches
        require(result.marketIdStUsds == EXISTING_STUSDS_MARKET_ID, "stUSDS market ID mismatch");
        console.log("Using existing stUSDS/USDS market:", vm.toString(EXISTING_STUSDS_MARKET_ID));

        // Step 2: Create oracles for the 3 NEW markets
        result.oracleCbBtc = _createOracleCbBtc();
        result.oracleWstEth = _createOracleWstEth();
        result.oracleWeth = _createOracleWeth();

        // Step 3: Create the 3 NEW markets
        result.paramsCbBtc = _createMarket(morpho, Constants.CBBTC, result.oracleCbBtc, Constants.LLTV_VOLATILE);
        result.paramsWstEth = _createMarket(morpho, Constants.WSTETH, result.oracleWstEth, Constants.LLTV_VOLATILE);
        result.paramsWeth = _createMarket(morpho, Constants.WETH, result.oracleWeth, Constants.LLTV_VOLATILE);

        result.marketIdCbBtc = keccak256(abi.encode(result.paramsCbBtc));
        result.marketIdWstEth = keccak256(abi.encode(result.paramsWstEth));
        result.marketIdWeth = keccak256(abi.encode(result.paramsWeth));

        // Step 4: Seed the 3 NEW markets with 90% utilization
        _seedMarket(morpho, result.paramsCbBtc, Constants.CBBTC, DEAD_COLLATERAL_CBBTC, deployer);
        _seedMarket(morpho, result.paramsWstEth, Constants.WSTETH, DEAD_COLLATERAL_WSTETH, deployer);
        _seedMarket(morpho, result.paramsWeth, Constants.WETH, DEAD_COLLATERAL_WETH, deployer);

        // Step 5: Deploy Vault V2
        bytes32 vaultSalt = keccak256(abi.encodePacked(block.timestamp, "FlagshipVaultV2"));
        result.vaultV2 = VaultV2Factory(Constants.VAULT_V2_FACTORY).createVaultV2(deployer, Constants.USDS, vaultSalt);
        console.log("Flagship VaultV2 deployed at:", result.vaultV2);
        VaultV2 vault = VaultV2(result.vaultV2);

        vault.setName(vaultName);
        vault.setSymbol(vaultSymbol);
        console.log("Vault Name:", vaultName);
        console.log("Vault Symbol:", vaultSymbol);

        // Step 6: Deploy Market Adapter
        result.adapter = IMorphoMarketV1AdapterV2Factory(Constants.ADAPTER_FACTORY)
            .createMorphoMarketV1AdapterV2(result.vaultV2);
        console.log("Adapter deployed at:", result.adapter);

        // Step 7: Configuration
        _configureVault(vault, result.adapter, result.paramsStUsds, result.paramsCbBtc, result.paramsWstEth, result.paramsWeth, deployer);

        // Step 8: Dead Deposit to Vault
        IERC20(Constants.USDS).approve(address(vault), Constants.INITIAL_DEAD_DEPOSIT);
        vault.deposit(Constants.INITIAL_DEAD_DEPOSIT, address(0xdEaD));
        console.log("Dead deposit to vault executed.");

        // Step 9: Timelocks
        _configureTimelocks(vault);
        _configureAdapterTimelocks(IMorphoMarketV1AdapterV2(result.adapter));

        // Step 10: Finalize Ownership
        _finalizeOwnership(vault, deployer, finalOwner, finalCurator, finalAllocator, sentinel);

        // Log for allocator bot
        console.log("");
        console.log("=== ALLOCATOR BOT CONFIGURATION ===");
        console.log("To allocate: vault.allocate(adapter, abi.encode(marketParams), assets)");
        console.log("Caps: 5% per market, 20% total. Allocator maintains 80% idle.");
        console.log("");
        console.log("Market IDs:");
        console.log("  stUSDS/USDS (existing):", vm.toString(result.marketIdStUsds));
        console.log("  cbBTC/USDS (new):", vm.toString(result.marketIdCbBtc));
        console.log("  wstETH/USDS (new):", vm.toString(result.marketIdWstEth));
        console.log("  WETH/USDS (new):", vm.toString(result.marketIdWeth));

        vm.stopBroadcast();
    }

    // ============ ORACLE CREATION ============

    function _createOracleCbBtc() internal returns (address oracle) {
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, "OracleCbBtc"));
        // cbBTC/USDS = cbBTC/USD / USDS/USD
        oracle = IMorphoChainlinkOracleV2Factory(Constants.ORACLE_FACTORY).createMorphoChainlinkOracleV2(
            address(0), 1, Constants.CHAINLINK_CBBTC_USD, address(0), Constants.DECIMALS_CBBTC,
            address(0), 1, Constants.CHAINLINK_USDS_USD, address(0), Constants.DECIMALS_USDS,
            salt
        );
        console.log("Oracle cbBTC/USDS deployed at:", oracle);
    }

    function _createOracleWstEth() internal returns (address oracle) {
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, "OracleWstEth"));
        // wstETH/USDS = (wstETH/stETH * stETH/USD) / USDS/USD
        // Using Morpho's official wstETH/stETH adapter + Chainlink stETH/USD feed
        oracle = IMorphoChainlinkOracleV2Factory(Constants.ORACLE_FACTORY).createMorphoChainlinkOracleV2(
            address(0), 1, Constants.MORPHO_WSTETH_STETH_ADAPTER, Constants.CHAINLINK_STETH_USD, Constants.DECIMALS_WSTETH,
            address(0), 1, Constants.CHAINLINK_USDS_USD, address(0), Constants.DECIMALS_USDS,
            salt
        );
        console.log("Oracle wstETH/USDS deployed at:", oracle);
    }

    function _createOracleWeth() internal returns (address oracle) {
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, "OracleWeth"));
        // WETH/USDS = ETH/USD / USDS/USD
        oracle = IMorphoChainlinkOracleV2Factory(Constants.ORACLE_FACTORY).createMorphoChainlinkOracleV2(
            address(0), 1, Constants.CHAINLINK_ETH_USD, address(0), Constants.DECIMALS_WETH,
            address(0), 1, Constants.CHAINLINK_USDS_USD, address(0), Constants.DECIMALS_USDS,
            salt
        );
        console.log("Oracle WETH/USDS deployed at:", oracle);
    }

    // ============ MARKET CREATION ============

    function _createMarket(IMorpho morpho, address collateral, address oracle, uint256 lltv)
        internal
        returns (MarketParams memory params)
    {
        params = MarketParams({
            loanToken: Constants.USDS,
            collateralToken: collateral,
            oracle: oracle,
            irm: Constants.IRM_ADAPTIVE,
            lltv: lltv
        });

        try morpho.createMarket(params) {
            console.log("Market created for collateral:", collateral);
        } catch {
            console.log("Market already exists for collateral:", collateral);
        }
    }

    // ============ MARKET SEEDING (90% Utilization) ============

    /**
     * @notice Seeds a market with 90% utilization
     * @dev 1. Supply USDS to market (dead address)
     *      2. Supply collateral (deployer)
     *      3. Borrow USDS (to deployer) for 90% utilization
     */
    function _seedMarket(
        IMorpho morpho,
        MarketParams memory params,
        address collateralToken,
        uint256 collateralAmount,
        address deployer
    ) internal {
        // 1. Supply USDS to market (to dead address)
        IERC20(Constants.USDS).approve(Constants.MORPHO_BLUE, DEAD_SUPPLY_AMOUNT);
        morpho.supply(params, DEAD_SUPPLY_AMOUNT, 0, address(0xdEaD), bytes(""));
        console.log("Dead supply to market:", collateralToken);

        // 2. Supply collateral (from deployer, stays as deployer's position)
        IERC20(collateralToken).approve(Constants.MORPHO_BLUE, collateralAmount);
        morpho.supplyCollateral(params, collateralAmount, deployer, bytes(""));
        console.log("Dead collateral supplied:", collateralAmount);

        // 3. Borrow USDS to reach 90% utilization (borrowed USDS goes to deployer)
        morpho.borrow(params, DEAD_BORROW_AMOUNT, 0, deployer, deployer);
        console.log("Dead borrow executed for 90% utilization");
    }

    // ============ VAULT CONFIGURATION ============

    function _configureVault(
        VaultV2 vault,
        address adapter,
        MarketParams memory paramsStUsds,
        MarketParams memory paramsCbBtc,
        MarketParams memory paramsWstEth,
        MarketParams memory paramsWeth,
        address deployer
    ) internal {
        // Setup roles
        vault.setCurator(deployer);
        console.log("Defined Deployer as Curator");

        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, deployer, true));

        // Abdicate gates and registry
        _abdicateGatesAndRegistry(vault);

        // NO liquidity adapter - deposits stay 100% idle
        console.log("No liquidity adapter set - deposits stay idle for 80%% idle strategy.");

        // Add adapter
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.addAdapter.selector, adapter));

        // Set adapter caps (20% max total)
        bytes memory adapterIdData = abi.encode("this", adapter);
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, adapterIdData, type(uint128).max));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, adapterIdData, ADAPTER_RELATIVE_CAP));

        // Set market caps (5% max each)
        _setMarketCaps(vault, adapter, paramsStUsds, Constants.ST_USDS);
        _setMarketCaps(vault, adapter, paramsCbBtc, Constants.CBBTC);
        _setMarketCaps(vault, adapter, paramsWstEth, Constants.WSTETH);
        _setMarketCaps(vault, adapter, paramsWeth, Constants.WETH);

        console.log("Caps configured: 5%% max per market, 20%% max to adapter.");

        vault.setMaxRate(Constants.MAX_RATE);
        console.log("Max Rate set to 200%% APR");
    }

    function _setMarketCaps(VaultV2 vault, address adapter, MarketParams memory params, address collateral) internal {
        bytes memory marketIdData = abi.encode("this/marketParams", adapter, params);
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, marketIdData, type(uint128).max));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, marketIdData, MARKET_RELATIVE_CAP));

        bytes memory collateralIdData = abi.encode("collateralToken", collateral);
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, collateralIdData, type(uint128).max));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, collateralIdData, MARKET_RELATIVE_CAP));
    }
}
