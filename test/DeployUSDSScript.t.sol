// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {DeployUSDSVaultV2} from "../script/DeployUSDSVaultV2.s.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";

import {Constants} from "../src/lib/Constants.sol";
import {BaseVaultTest} from "./base/BaseVaultTest.sol";

/**
 * @title DeployUSDSScriptTest
 * @notice Tests for DeployUSDSVaultV2 deployment script
 * @dev Extends BaseVaultTest for common tests, adds USDS-specific tests
 */
contract DeployUSDSScriptTest is BaseVaultTest {
    DeployUSDSVaultV2 public deployScript;
    DeployUSDSVaultV2.DeploymentResult public result;

    function setUp() public override {
        super.setUp();
        deployScript = new DeployUSDSVaultV2();
    }

    function _deployVault() internal override {
        deal(Constants.USDS, deployer, 10e18);
        deal(Constants.ST_USDS, deployer, 3e18);
        result = deployScript.run();
        vault = IVaultV2(result.vaultV2);
    }

    function _deployVaultWithRoles(
        address owner,
        address curator,
        address allocator,
        address sentinel
    ) internal override {
        if (owner != address(0)) vm.setEnv("OWNER", vm.toString(owner));
        if (curator != address(0)) vm.setEnv("CURATOR", vm.toString(curator));
        if (allocator != address(0)) vm.setEnv("ALLOCATOR", vm.toString(allocator));
        if (sentinel != address(0)) vm.setEnv("SENTINEL", vm.toString(sentinel));

        _deployVault();
    }

    // ============ USDS-SPECIFIC TESTS ============

    function testRunScript() public {
        deal(Constants.USDS, deployer, 2e18);
        deal(Constants.ST_USDS, deployer, 3e18);
        result = deployScript.run();

        console.log("Verified Oracle Address:", result.oracle);
        console.log("Verified VaultV2 Address:", result.vaultV2);
        console.log("Verified Adapter Address:", result.adapter);

        assertTrue(result.oracle != address(0), "Oracle address should not be zero");
        assertTrue(result.vaultV2 != address(0), "VaultV2 address should not be zero");
        assertTrue(result.adapter != address(0), "Adapter address should not be zero");
    }

    function testLiquidityAdapterSet() public {
        _deployVault();

        // USDS vault has liquidity adapter (auto-allocation)
        assertEq(vault.liquidityAdapter(), result.adapter, "Liquidity adapter should match");
    }

    function testMorphoMarketUtilizationIs90Percent() public {
        _deployVault();

        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory params = abi.decode(liquidityData, (MarketParams));

        Id marketId = Id.wrap(keccak256(abi.encode(params)));
        IMorpho morpho = IMorpho(Constants.MORPHO_BLUE);
        Market memory marketState = morpho.market(marketId);

        console.log("Market totalSupplyAssets:", marketState.totalSupplyAssets);
        console.log("Market totalBorrowAssets:", marketState.totalBorrowAssets);

        uint256 utilizationBps = (uint256(marketState.totalBorrowAssets) * 10000) / uint256(marketState.totalSupplyAssets);
        console.log("Utilization (bps):", utilizationBps);

        assertEq(utilizationBps, 9000, "Market utilization should be 90% (9000 bps)");
    }

    function testDeadDepositToMorphoMarket() public {
        _deployVault();

        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, Constants.INITIAL_DEAD_DEPOSIT, "Total assets should equal dead deposit");
    }

    function testSentinelNotSetByDefault() public {
        _deployVault();

        address randomAddr = makeAddr("random");
        assertFalse(vault.isSentinel(randomAddr), "Random address should not be sentinel");
    }

    function testPartialRoleTransfer_OnlyOwner() public {
        address customOwner = makeAddr("customOwner");

        vm.setEnv("OWNER", vm.toString(customOwner));
        _deployVault();

        assertEq(vault.owner(), customOwner, "Owner should be custom");
        assertTrue(vault.curator() != address(0), "Curator should be set");
    }

    function testOwnerCanTransferAllRolesAfterDeployment() public {
        _deployVault();

        address currentOwner = vault.owner();
        address newOwner = makeAddr("newOwner");
        address newCurator = makeAddr("newCurator");
        address newAllocator = makeAddr("newAllocator");
        address newSentinel = makeAddr("newSentinel");

        vm.startPrank(currentOwner);
        vault.setCurator(newCurator);
        assertEq(vault.curator(), newCurator);

        vault.setIsSentinel(newSentinel, true);
        assertTrue(vault.isSentinel(newSentinel));

        vault.setOwner(newOwner);
        assertEq(vault.owner(), newOwner);
        vm.stopPrank();

        vm.startPrank(newCurator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, true));
        vault.setIsAllocator(newAllocator, true);
        vm.stopPrank();

        assertTrue(vault.isAllocator(newAllocator), "New allocator should be set");
    }

    // ============ INTEGRATION TEST ============

    function testVaultOperations() public {
        deal(Constants.USDS, deployer, 2e18);
        deal(Constants.ST_USDS, deployer, 3e18);
        result = deployScript.run();
        vault = IVaultV2(result.vaultV2);

        address user = makeAddr("vaultUser");
        uint256 depositAmount = 1000 * 1e18;

        deal(Constants.USDS, user, depositAmount);

        vm.startPrank(user);
        usds.approve(address(vault), depositAmount);
        uint256 expectedShares = vault.convertToShares(depositAmount);
        uint256 sharesReceived = vault.deposit(depositAmount, user);

        assertEq(sharesReceived, expectedShares, "Shares received mismatch");
        assertEq(vault.balanceOf(user), sharesReceived, "User vault balance mismatch");
        assertEq(vault.totalAssets(), depositAmount + Constants.INITIAL_DEAD_DEPOSIT, "Total assets mismatch");

        uint256 withdrawShares = sharesReceived / 2;
        uint256 assetsWithdrawn = vault.redeem(withdrawShares, user, user);

        assertEq(vault.balanceOf(user), sharesReceived - withdrawShares, "User remaining shares mismatch");
        assertEq(usds.balanceOf(user), assetsWithdrawn, "User USDS balance mismatch");

        console.log("Deposit and Withdraw steps passed");
        vm.stopPrank();
    }
}
