// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {DeployUsdtRiskCapital} from "../../script/usdt_risk_capital/DeployUsdtRiskCapital.s.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";

import {Constants} from "../../src/lib/Constants.sol";
import {BaseVaultTest} from "../base/BaseVaultTest.sol";

/**
 * @title DeployUsdtRiskCapitalScriptTest
 * @notice Tests for DeployUsdtRiskCapital deployment script
 * @dev Extends BaseVaultTest for common tests, adds USDT-specific tests
 */
contract DeployUsdtRiskCapitalScriptTest is BaseVaultTest {
    DeployUsdtRiskCapital public deployScript;
    DeployUsdtRiskCapital.DeploymentResult public result;

    function _loanTokenAddress() internal pure override returns (address) {
        return Constants.USDT;
    }

    function _depositAmount() internal pure override returns (uint256) {
        return 1000e6;
    }

    function setUp() public override {
        super.setUp();
        deployScript = new DeployUsdtRiskCapital();
    }

    function _deployVault() internal override {
        deal(Constants.USDT, deployer, 10e6);
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

    // ============ USDT RISK CAPITAL SPECIFIC TESTS ============

    function testRunScript() public {
        deal(Constants.USDT, deployer, 10e6);
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
        assertEq(totalAssets, Constants.INITIAL_DEAD_DEPOSIT_6DEC, "Total assets should equal dead deposit");
    }

    function testVaultOperations() public {
        deal(Constants.USDT, deployer, 10e6);
        deal(Constants.ST_USDS, deployer, 3e18);
        result = deployScript.run();
        vault = IVaultV2(result.vaultV2);

        address user = makeAddr("vaultUser");
        uint256 depositAmount = _depositAmount();

        deal(Constants.USDT, user, depositAmount);

        vm.startPrank(user);
        loanToken.approve(address(vault), depositAmount);
        uint256 expectedShares = vault.convertToShares(depositAmount);
        uint256 sharesReceived = vault.deposit(depositAmount, user);

        assertEq(sharesReceived, expectedShares, "Shares received mismatch");
        assertEq(vault.balanceOf(user), sharesReceived, "User vault balance mismatch");
        assertEq(vault.totalAssets(), depositAmount + Constants.INITIAL_DEAD_DEPOSIT_6DEC, "Total assets mismatch");

        uint256 withdrawShares = sharesReceived / 2;
        uint256 assetsWithdrawn = vault.redeem(withdrawShares, user, user);

        assertEq(vault.balanceOf(user), sharesReceived - withdrawShares, "User remaining shares mismatch");
        assertEq(loanToken.balanceOf(user), assetsWithdrawn, "User loan token balance mismatch");

        console.log("Deposit and Withdraw steps passed");
        vm.stopPrank();
    }
}
