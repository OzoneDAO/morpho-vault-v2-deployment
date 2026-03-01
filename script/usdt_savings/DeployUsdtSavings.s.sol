// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {MarketParams} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {VaultV2} from "vault-v2/VaultV2.sol";
import {VaultV2Factory} from "vault-v2/VaultV2Factory.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

import {Constants} from "../../src/lib/Constants.sol";
import {DeployHelpers, IMorphoMarketV1AdapterV2Factory} from "../../src/lib/DeployHelpers.sol";

/**
 * @title DeployUsdtSavings
 * @notice Deploys USDT Savings Vault V2 and connects it to an existing sUSDS/USDT Morpho Market (96.5% LLTV)
 * @dev Single-market vault with liquidity adapter. Reuses existing market (no oracle or market creation).
 */
contract DeployUsdtSavings is DeployHelpers {
    using SafeERC20 for IERC20;

    struct DeploymentResult {
        address vaultV2;
        address adapter;
    }

    function run() external returns (DeploymentResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address finalOwner = Constants.SKY_MONEY_CURATOR;
        address finalCurator = Constants.SKY_MONEY_CURATOR;
        address finalAllocator = Constants.SKY_MONEY_CURATOR;
        address sentinel = Constants.SKY_MONEY_CURATOR;

        string memory vaultName = "sky.money USDT Savings";
        string memory vaultSymbol = "skyMoneyUsdtSavings";

        // Build market params for existing sUSDS/USDT market
        MarketParams memory params = MarketParams({
            loanToken: Constants.USDT,
            collateralToken: Constants.S_USDS,
            oracle: Constants.EXISTING_SUSDS_USDT_ORACLE,
            irm: Constants.IRM_ADAPTIVE,
            lltv: Constants.LLTV_SAVINGS
        });

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy Vault V2
        bytes32 vaultSalt = keccak256(abi.encodePacked(block.timestamp, "VaultV2UsdtSavings"));
        result.vaultV2 = VaultV2Factory(Constants.VAULT_V2_FACTORY).createVaultV2(deployer, Constants.USDT, vaultSalt);
        console.log("VaultV2 deployed at:", result.vaultV2);
        VaultV2 vault = VaultV2(result.vaultV2);

        vault.setName(vaultName);
        vault.setSymbol(vaultSymbol);
        console.log("Vault Name:", vaultName);
        console.log("Vault Symbol:", vaultSymbol);

        // Step 2: Deploy Market Adapter
        result.adapter = IMorphoMarketV1AdapterV2Factory(Constants.ADAPTER_FACTORY)
            .createMorphoMarketV1AdapterV2(result.vaultV2);
        console.log("Adapter deployed at:", result.adapter);

        // Step 3: Dead deposit to vault (before liquidity adapter is set, so deposit stays idle)
        IERC20(Constants.USDT).forceApprove(address(vault), Constants.INITIAL_DEAD_DEPOSIT_6DEC);
        vault.deposit(Constants.INITIAL_DEAD_DEPOSIT_6DEC, address(0xdEaD));
        console.log("Dead deposit to vault executed.");

        // Step 4: Configuration (sets liquidity adapter — future deposits auto-allocate to market)
        _configureSingleMarketVault(vault, result.adapter, params, deployer);

        // Step 5: Timelocks
        _configureTimelocks(vault);
        _configureAdapterTimelocks(IMorphoMarketV1AdapterV2(result.adapter));

        // Step 6: Finalize Ownership
        _finalizeOwnership(vault, deployer, finalOwner, finalCurator, finalAllocator, sentinel);

        vm.stopBroadcast();
    }

}
