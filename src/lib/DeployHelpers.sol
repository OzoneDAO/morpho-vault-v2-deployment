// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {VaultV2} from "vault-v2/VaultV2.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";
import {Constants} from "./Constants.sol";

// ============ FACTORY INTERFACES ============

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
 * @title DeployHelpers
 * @notice Shared helper functions for Morpho Vault V2 deployment scripts
 * @dev Inherit this contract in deployment scripts to use common functions
 */
abstract contract DeployHelpers is Script {
    /**
     * @notice Submit and immediately execute a timelocked function call
     * @dev Works because timelock is 0 during initial configuration
     * @param target The contract to call (vault or adapter)
     * @param data The encoded function call
     */
    function _submitAndExecute(address target, bytes memory data) internal {
        (bool submitSuccess,) = target.call(abi.encodeWithSignature("submit(bytes)", data));
        require(submitSuccess, "Submit failed");

        (bool execSuccess,) = target.call(data);
        require(execSuccess, "Execution failed");
    }

    /**
     * @notice Configure vault timelocks according to Morpho listing requirements
     * @param vault The vault to configure
     */
    function _configureTimelocks(VaultV2 vault) internal {
        // Low Timelocks (3 days)
        bytes4[] memory lowSelectors = new bytes4[](4);
        lowSelectors[0] = IVaultV2.addAdapter.selector;
        lowSelectors[1] = IVaultV2.increaseAbsoluteCap.selector;
        lowSelectors[2] = IVaultV2.increaseRelativeCap.selector;
        lowSelectors[3] = IVaultV2.setForceDeallocatePenalty.selector;

        for (uint256 i = 0; i < lowSelectors.length; i++) {
            _submitAndExecute(
                address(vault),
                abi.encodeWithSelector(IVaultV2.increaseTimelock.selector, lowSelectors[i], Constants.TIMELOCK_LOW)
            );
        }

        // High Timelocks (7 days)
        bytes4[] memory highSelectors = new bytes4[](2);
        highSelectors[0] = IVaultV2.removeAdapter.selector;
        highSelectors[1] = IVaultV2.abdicate.selector;

        for (uint256 i = 0; i < highSelectors.length; i++) {
            _submitAndExecute(
                address(vault),
                abi.encodeWithSelector(IVaultV2.increaseTimelock.selector, highSelectors[i], Constants.TIMELOCK_HIGH)
            );
        }

        // Finally, lock increaseTimelock itself (must be last)
        _submitAndExecute(
            address(vault),
            abi.encodeWithSelector(IVaultV2.increaseTimelock.selector, IVaultV2.increaseTimelock.selector, Constants.TIMELOCK_HIGH)
        );

        console.log("Vault Timelocks configured (High: 7d, Low: 3d)");
    }

    /**
     * @notice Configure adapter timelocks
     * @param adapter The adapter to configure
     */
    function _configureAdapterTimelocks(IMorphoMarketV1AdapterV2 adapter) internal {
        // Low Timelocks (3 days)
        bytes4[] memory lowSelectors = new bytes4[](2);
        lowSelectors[0] = IMorphoMarketV1AdapterV2.setSkimRecipient.selector;
        lowSelectors[1] = IMorphoMarketV1AdapterV2.burnShares.selector;

        for (uint256 i = 0; i < lowSelectors.length; i++) {
            _submitAndExecute(
                address(adapter),
                abi.encodeWithSelector(IMorphoMarketV1AdapterV2.increaseTimelock.selector, lowSelectors[i], Constants.TIMELOCK_LOW)
            );
        }

        // High Timelocks (7 days)
        _submitAndExecute(
            address(adapter),
            abi.encodeWithSelector(IMorphoMarketV1AdapterV2.increaseTimelock.selector, IMorphoMarketV1AdapterV2.abdicate.selector, Constants.TIMELOCK_HIGH)
        );
        _submitAndExecute(
            address(adapter),
            abi.encodeWithSelector(IMorphoMarketV1AdapterV2.increaseTimelock.selector, IMorphoMarketV1AdapterV2.increaseTimelock.selector, Constants.TIMELOCK_HIGH)
        );

        console.log("Adapter Timelocks configured (High: 7d, Low: 3d)");
    }

    /**
     * @notice Abdicate gates and registry (security requirement)
     * @param vault The vault to configure
     */
    function _abdicateGatesAndRegistry(VaultV2 vault) internal {
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.setAdapterRegistry.selector, Constants.ADAPTER_REGISTRY));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.abdicate.selector, IVaultV2.setAdapterRegistry.selector));

        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.abdicate.selector, IVaultV2.setSendSharesGate.selector));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.abdicate.selector, IVaultV2.setReceiveAssetsGate.selector));
        _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.abdicate.selector, IVaultV2.setReceiveSharesGate.selector));

        console.log("Registry set and abdicated. Gates abdicated.");
    }

    /**
     * @notice Finalize ownership transfer
     * @param vault The vault to configure
     * @param deployer The deployer address
     * @param finalOwner The final owner
     * @param finalCurator The final curator
     * @param finalAllocator The final allocator
     * @param sentinel The sentinel address (can be address(0))
     */
    function _finalizeOwnership(
        VaultV2 vault,
        address deployer,
        address finalOwner,
        address finalCurator,
        address finalAllocator,
        address sentinel
    ) internal {
        if (finalAllocator != deployer) {
            _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, deployer, false));
            _submitAndExecute(address(vault), abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, finalAllocator, true));
        }

        if (finalCurator != deployer) {
            vault.setCurator(finalCurator);
        }

        if (sentinel != address(0)) {
            vault.setIsSentinel(sentinel, true);
        }

        if (finalOwner != deployer) {
            vault.setOwner(finalOwner);
            console.log("Ownership transferred to:", finalOwner);
        }
    }
}
