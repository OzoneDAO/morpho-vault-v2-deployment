// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";

import {Constants} from "../../src/lib/Constants.sol";

/**
 * @title DeployedCreateVaultTest
 * @notice Tests after Script 1: Verify vault and adapter are deployed
 * @dev Run after deploying script 1 on mainnet/Tenderly
 *
 * Required env vars:
 *   VAULT_ADDRESS  - Deployed vault address
 *   ADAPTER_ADDRESS - Deployed adapter address
 */
contract DeployedCreateVaultTest is Test {
    address public vaultAddress;
    address public adapterAddress;

    function setUp() public {
        vaultAddress = vm.envAddress("VAULT_ADDRESS");
        adapterAddress = vm.envAddress("ADAPTER_ADDRESS");
    }

    function testVaultDeployed() public view {
        assertGt(vaultAddress.code.length, 0, "Vault should have code");
        console.log("Vault deployed at:", vaultAddress);
    }

    function testAdapterDeployed() public view {
        uint256 codeSize = adapterAddress.code.length;
        assertGt(codeSize, 0, "Adapter should have code");
        console.log("Adapter deployed at:", adapterAddress);
    }

    function testVaultAsset() public view {
        IVaultV2 vault = IVaultV2(vaultAddress);
        assertEq(vault.asset(), Constants.USDS, "Asset should be USDS");
    }

    function testVaultMetadata() public view {
        IVaultV2 vault = IVaultV2(vaultAddress);
        string memory name = vault.name();
        string memory symbol = vault.symbol();

        assertTrue(bytes(name).length > 0, "Name should be set");
        assertTrue(bytes(symbol).length > 0, "Symbol should be set");

        console.log("Vault name:", name);
        console.log("Vault symbol:", symbol);
    }
}
