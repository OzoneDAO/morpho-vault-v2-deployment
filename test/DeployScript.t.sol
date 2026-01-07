// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DeployUSDCVaultV2} from "../script/DeployUSDCVaultV2.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";

contract DeployScriptTest is Test {
    DeployUSDCVaultV2 public deployScript;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        // Mock the PRIVATE_KEY environment variable
        // Using a dummy private key (e.g. Anvil's account #0 default key)
        vm.setEnv("PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
        
        deployScript = new DeployUSDCVaultV2();
    }

    function testRunScript() public {
        // Fund the deployer (mocked in setUp)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        deal(USDC, deployer, 1e9); // Fund for dead deposit

        // Execute the script
        DeployUSDCVaultV2.DeploymentResult memory result = deployScript.run();

        // Verify deployments
        console.log("Verified Oracle Address:", result.oracle);
        console.log("Verified VaultV2 Address:", result.vaultV2);
        console.log("Verified Adapter Address:", result.adapter);

        assertTrue(result.oracle != address(0), "Oracle address should not be zero");
        assertTrue(result.vaultV2 != address(0), "VaultV2 address should not be zero");
        assertTrue(result.adapter != address(0), "Adapter address should not be zero");
    }

    function testVaultOperations() public {
        // 1. Fund Deployer & Run deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        deal(USDC, deployer, 1e9); // Fund for dead deposit

        DeployUSDCVaultV2.DeploymentResult memory result = deployScript.run();
        IVaultV2 vault = IVaultV2(result.vaultV2);
        IERC20 usdc = IERC20(USDC);

        // 2. Setup a test user
        address user = makeAddr("vaultUser");
        uint256 depositAmount = 1000 * 1e6; // 1000 USDC

        // Fund user
        deal(USDC, user, depositAmount);
        
        vm.startPrank(user);

        // 3. Deposit
        usdc.approve(address(vault), depositAmount);
        uint256 expectedShares = vault.convertToShares(depositAmount);
        uint256 sharesReceived = vault.deposit(depositAmount, user);

        assertEq(sharesReceived, expectedShares, "Shares received mismatch");
        assertEq(vault.balanceOf(user), sharesReceived, "User vault balance mismatch");
        
        // Assertion updated for 1e9 dead deposit
        assertEq(vault.totalAssets(), depositAmount + 1e9, "Total assets mismatch (inc. dead deposit of 1e9)");

        // 4. Withdraw
        // Withdraw half
        uint256 withdrawShares = sharesReceived / 2;
        uint256 assetsWithdrawn = vault.redeem(withdrawShares, user, user);

        assertEq(vault.balanceOf(user), sharesReceived - withdrawShares, "User remaining shares mismatch");
        assertEq(usdc.balanceOf(user), assetsWithdrawn, "User USDC balance mismatch");
        
        console.log("Deposit and Withdraw steps passed");
        vm.stopPrank();
    }
}
