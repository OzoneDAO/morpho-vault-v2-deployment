// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Interfaces
import {IMorpho, MarketParams, Id} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {VaultV2} from "vault-v2/VaultV2.sol";
import {VaultV2Factory} from "vault-v2/VaultV2Factory.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

// Factory Interfaces
interface IMorphoChainlinkOracleV2Factory {
    function createMorphoChainlinkOracleV2(
        address baseVault,
        uint256 baseVaultConversionSample,
        address baseFeed1,
        address baseFeed2,
        uint256 baseTokenDecimals,
        address quoteVault,
        uint256 quoteVaultConversionSample,
        address quoteFeed1,
        address quoteFeed2,
        uint256 quoteTokenDecimals,
        bytes32 salt
    ) external returns (address);
}

interface IMorphoMarketV1AdapterV2Factory {
    function createMorphoMarketV1AdapterV2(address vaultV2Address) external returns (address);
}

/**
 * @title DeployUSDCVaultV2
 * @notice Deploys Vault V2 for USDC and connects it to the stUSDS/USDC Morpho Market
 * @dev Updated to include full security configuration (Timelocks, MaxRate, Registry Abdication)
 */
contract DeployUSDCVaultV2 is Script, StdCheats {
    // --- Constants & Addresses (Mainnet) ---
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ST_USDS = 0x99CD4Ec3f88A45940936F469E4bB72A2A701EEB9;
    address constant USDS_FEED = 0xfF30586cD0F29eD462364C7e81375FC0C71219b1;
    address constant USDC_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant IRM_ADAPTIVE = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address constant MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    // Factories & Registry
    address constant ORACLE_FACTORY = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;
    address constant VAULT_V2_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    address constant ADAPTER_FACTORY = 0x32BB1c0D48D8b1B3363e86eeB9A0300BAd61ccc1;
    address constant ADAPTER_REGISTRY = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;

    // Params
    uint256 constant LLTV = 860000000000000000; // 86%
    uint256 constant INITIAL_DEAD_DEPOSIT = 1e9; // 1000 USDC
    uint256 constant MAX_RATE = 63419583967; // 200% APR Cap (200e16 / 365 days)
    uint256 constant TIMELOCK_LOW = 3 days;
    uint256 constant TIMELOCK_HIGH = 7 days;

    struct DeploymentResult {
        address oracle;
        address vaultV2;
        address adapter;
        bytes32 marketId;
    }

    function run() external returns (DeploymentResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // --- Optional: Env Vars for Final Ownership ---
        // If not set, defaults to deployer
        address finalOwner = vm.envOr("OWNER", deployer);
        address finalCurator = vm.envOr("CURATOR", deployer);
        address finalAllocator = vm.envOr("ALLOCATOR", deployer);
        address sentinel = vm.envOr("SENTINEL", address(0));
        
        // Vault metadata
        string memory vaultName = vm.envOr("VAULT_NAME", string("Morpho USDC Vault V2"));
        string memory vaultSymbol = vm.envOr("VAULT_SYMBOL", string("mUSDCv2"));

        vm.startBroadcast(deployerPrivateKey);

        // --- Step 1: Create Oracle (stUSDS/USDC) ---
        bytes32 oracleSalt = keccak256(abi.encodePacked(block.timestamp, "Oracle"));
        result.oracle = IMorphoChainlinkOracleV2Factory(ORACLE_FACTORY).createMorphoChainlinkOracleV2(
            ST_USDS, 1e18, USDS_FEED, address(0), 18,
            address(0), 1, USDC_FEED, address(0), 6,
            oracleSalt
        );
        console.log("Oracle deployed at:", result.oracle);

        // --- Step 2: Create Market (USDC / stUSDS) ---
        IMorpho morpho = IMorpho(MORPHO_BLUE);
        MarketParams memory params = MarketParams({
            loanToken: USDC,
            collateralToken: ST_USDS,
            oracle: result.oracle,
            irm: IRM_ADAPTIVE,
            lltv: LLTV
        });

        result.marketId = keccak256(abi.encode(params));
        try morpho.createMarket(params) {
            console.log("Market created successfully");
        } catch {
            console.log("Market already exists, proceeding...");
        }

        // --- Step 3: Deploy Vault V2 ---
        bytes32 vaultSalt = keccak256(abi.encodePacked(block.timestamp, "VaultV2"));
        // Vault created with deployer as owner
        result.vaultV2 = VaultV2Factory(VAULT_V2_FACTORY).createVaultV2(deployer, USDC, vaultSalt);
        console.log("VaultV2 deployed at:", result.vaultV2);
        VaultV2 vault = VaultV2(result.vaultV2);

        // Set Vault Name and Symbol (Owner function - direct call)
        vault.setName(vaultName);
        vault.setSymbol(vaultSymbol);
        console.log("Vault Name:", vaultName);
        console.log("Vault Symbol:", vaultSymbol);

        // --- Step 4: Deploy Market Adapter ---
        result.adapter = IMorphoMarketV1AdapterV2Factory(ADAPTER_FACTORY)
            .createMorphoMarketV1AdapterV2(result.vaultV2);
        console.log("Adapter deployed at:", result.adapter);

        // --- Step 5: Configuration & Auth ---

        // A. Setup Initial Roles
        // deployer is Owner initially.
        // We need to be Curator to use 'submit'.
        vault.setCurator(deployer); 
        console.log("Defined Deployer as Curator");

        // Now we can use submit+execute pattern for Curator functions (timelocked)
        
        // 1. Set Allocator (Curator function)
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, deployer, true));

        // B. Set Registry & Abdicate 
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.setAdapterRegistry.selector, ADAPTER_REGISTRY));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.abdicate.selector, IVaultV2.setAdapterRegistry.selector));

        // Abdicate Gates (Security Requirement)
        // ensure valid exit/entry for users
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.abdicate.selector, IVaultV2.setSendSharesGate.selector));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.abdicate.selector, IVaultV2.setReceiveAssetsGate.selector));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.abdicate.selector, IVaultV2.setSendAssetsGate.selector));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.abdicate.selector, IVaultV2.setReceiveSharesGate.selector)); // NEW requirement

        console.log("Registry set and abdicated. Gates abdicated.");

        // C. Set Liquidity Adapter 
        // Allocator function (Direct call allowed if we are allocator)
        vault.setLiquidityAdapterAndData(result.adapter, abi.encode(params));

        // D. Add Adapter & Caps
        // Curator functions -> Submit+Execute
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.addAdapter.selector, result.adapter));
        
        // 1. Adapter Caps
        bytes memory adapterIdData = abi.encode("this", result.adapter);
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, adapterIdData, type(uint128).max));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, adapterIdData, 1e18));

        // 2. Market Specific Caps
        bytes memory marketIdData = abi.encode("this/marketParams", result.adapter, params);
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, marketIdData, type(uint128).max));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, marketIdData, 1e18));

        // 3. Collateral Specific Caps 
        bytes memory collateralIdData = abi.encode("collateralToken", ST_USDS);
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, collateralIdData, type(uint128).max));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, collateralIdData, 1e18));

        console.log("Caps and Adapter configured.");

        // E. Set Max Rate 
        // Allocator function -> Direct call
        vault.setMaxRate(MAX_RATE);
        console.log("Max Rate set to 200% APR");

        // --- Step 6: Dead Deposit (Security) ---
        // deal removed from script, assuming deployer has funds (prod) or dealing in test (local)
        IERC20(USDC).approve(address(vault), INITIAL_DEAD_DEPOSIT);
        vault.deposit(INITIAL_DEAD_DEPOSIT, address(0xdEaD));
        console.log("Dead deposit executed.");

        // --- Step 7: Timelocks  ---
        // Configure Granular Timelocks
        _configureTimelocks(vault);

        // Configure Adapter Timelocks
        _configureAdapterTimelocks(IMorphoMarketV1AdapterV2(result.adapter));

        // --- Step 8: Finalize Ownership  ---
        
        // Transfer roles to the real owners defined in Env Vars
        // Note: Removing allocator requires submit+execute if done by Curator, or we can just rely on finalOwner setting it later?
        // Actually setIsAllocator is a Curator function.
        
        if (finalAllocator != deployer) {
            _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, deployer, false));
            _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, finalAllocator, true));
        }
        
        if (finalCurator != deployer) {
            vault.setCurator(finalCurator);
        }
        // If Sentinel role is needed
        if (sentinel != address(0)) {
            vault.setIsSentinel(sentinel, true);
        }

        if (finalOwner != deployer) {
            vault.setOwner(finalOwner);
            console.log("Ownership transferred to:", finalOwner);
        }

        vm.stopBroadcast();
    }

    // --- Helper Functions from FullDeployment Script ---

    // Generic helper for Submit + Execute pattern on Timelock contracts (Vault, Adapter)
    function _submitAndExecute(address target, bytes memory data) internal {
        // 1. Submit
        // We use low-level call to support both Vault and Adapter interfaces indiscriminately 
        // (though they share the same signature for submit(bytes))
        (bool submitSuccess, ) = target.call(abi.encodeWithSignature("submit(bytes)", data));
        require(submitSuccess, "Submit failed");

        // 2. Execute
        // Since timelock is 0 at this stage for these functions, we can execute immediately.
        // The 'timelocked()' modifier in target checks 'executableAt'.
        (bool execSuccess, ) = target.call(data);
        require(execSuccess, "Execution failed");
    }

    function _configureTimelocks(VaultV2 vault) internal {
        // 1. Configure Low Timelocks (3 days)
        bytes4[] memory lowSelectors = new bytes4[](4);
        lowSelectors[0] = IVaultV2.addAdapter.selector;
        lowSelectors[1] = IVaultV2.increaseAbsoluteCap.selector;
        lowSelectors[2] = IVaultV2.increaseRelativeCap.selector;
        lowSelectors[3] = IVaultV2.setForceDeallocatePenalty.selector;

        for (uint256 i = 0; i < lowSelectors.length; i++) {
            _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseTimelock.selector, lowSelectors[i], TIMELOCK_LOW));
        }

        // 2. Configure High Timelocks (7 days) - except increaseTimelock
        bytes4[] memory highSelectors = new bytes4[](2);
        // highSelectors[0] = IVaultV2.increaseTimelock.selector; // MOVED TO END
        highSelectors[0] = IVaultV2.removeAdapter.selector;
        highSelectors[1] = IVaultV2.abdicate.selector;

        for (uint256 i = 0; i < highSelectors.length; i++) {
            _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseTimelock.selector, highSelectors[i], TIMELOCK_HIGH));
        }

        // 3. Finally, increase the timelock for "increaseTimelock" itself to 7 days.
        // Doing this last ensures we don't accidentally lock ourselves out of configuring the others.
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.increaseTimelock.selector, IVaultV2.increaseTimelock.selector, TIMELOCK_HIGH));
        
        console.log("Vault Timelocks configured (High: 7d, Low: 3d)");
    }

    function _configureAdapterTimelocks(IMorphoMarketV1AdapterV2 adapter) internal {
        // 1. Configure Low Timelocks (3 days)
        bytes4[] memory lowSelectors = new bytes4[](2);
        lowSelectors[0] = IMorphoMarketV1AdapterV2.setSkimRecipient.selector;
        lowSelectors[1] = IMorphoMarketV1AdapterV2.burnShares.selector;

        for (uint256 i = 0; i < lowSelectors.length; i++) {
             _submitAndExecute(address(adapter), abi.encodeWithSelector(IMorphoMarketV1AdapterV2.increaseTimelock.selector, lowSelectors[i], TIMELOCK_LOW));
        }

        // 2. Configure High Timelocks (7 days) - except increaseTimelock
        // abdicate only
        _submitAndExecute(address(adapter), abi.encodeWithSelector(IMorphoMarketV1AdapterV2.increaseTimelock.selector, IMorphoMarketV1AdapterV2.abdicate.selector, TIMELOCK_HIGH));

        // 3. Finally, increase the timelock for "increaseTimelock" itself to 7 days.
        _submitAndExecute(address(adapter), abi.encodeWithSelector(IMorphoMarketV1AdapterV2.increaseTimelock.selector, IMorphoMarketV1AdapterV2.increaseTimelock.selector, TIMELOCK_HIGH));

        console.log("Adapter Timelocks configured (High: 7d, Low: 3d)");
    }
}