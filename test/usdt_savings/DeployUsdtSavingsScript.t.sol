// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {DeployUsdtSavings} from "../../script/usdt_savings/DeployUsdtSavings.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";

import {IMorphoMarketV1AdapterV2} from "vault-v2/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

import {Constants} from "../../src/lib/Constants.sol";
import {IMorphoChainlinkOracleV2} from "../../src/lib/DeployHelpers.sol";
import {BaseVaultTest} from "../base/BaseVaultTest.sol";

/**
 * @title DeployUsdtSavingsScriptTest
 * @notice Tests for DeployUsdtSavings deployment script
 * @dev Extends BaseVaultTest for common tests, adds USDT Savings-specific tests (96.5% LLTV)
 */
contract DeployUsdtSavingsScriptTest is BaseVaultTest {
    using SafeERC20 for IERC20;
    DeployUsdtSavings public deployScript;
    DeployUsdtSavings.DeploymentResult public result;

    function _loanTokenAddress() internal pure override returns (address) {
        return Constants.USDT;
    }

    function _depositAmount() internal pure override returns (uint256) {
        return 1000e6;
    }

    function setUp() public override {
        super.setUp();
        deployScript = new DeployUsdtSavings();
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

    // ============ USDT SAVINGS SPECIFIC TESTS ============

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

    function testMarketLltvIs96Point5Percent() public {
        _deployVault();

        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory params = abi.decode(liquidityData, (MarketParams));

        assertEq(params.lltv, Constants.LLTV_SAVINGS, "LLTV should be 96.5%");
    }

    function testDeadDepositToMorphoMarket() public {
        _deployVault();

        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, Constants.INITIAL_DEAD_DEPOSIT_6DEC, "Total assets should equal dead deposit");
    }

    function testOracleReturnsValidPrice() public {
        _deployVault();

        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory params = abi.decode(liquidityData, (MarketParams));

        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(params.oracle);
        uint256 price = oracle.price();

        // Scale = 10^(36 + 6 - 18) = 10^24. stUSDS ~$1.05 USDT
        uint256 expectedScale = 1e24;
        assertGt(price, expectedScale * 100 / 100, "Price should be >= 1.00 * scale");
        assertLt(price, expectedScale * 120 / 100, "Price should be < 1.20 * scale");
        console.log("Oracle price:", price);
    }

    function testOracleFeedConfiguration() public {
        _deployVault();

        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory params = abi.decode(liquidityData, (MarketParams));

        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(params.oracle);

        assertEq(oracle.BASE_VAULT(), Constants.ST_USDS, "Base vault should be stUSDS");
        assertEq(oracle.BASE_VAULT_CONVERSION_SAMPLE(), 1e18, "Base vault conversion sample should be 1e18");
        assertEq(oracle.BASE_FEED_1(), Constants.CHAINLINK_USDS_USD, "Base feed 1 should be USDS/USD");
        assertEq(oracle.BASE_FEED_2(), address(0), "Base feed 2 should be zero");
        assertEq(oracle.QUOTE_VAULT(), address(0), "Quote vault should be zero");
        assertEq(oracle.QUOTE_FEED_1(), Constants.CHAINLINK_USDT_USD, "Quote feed 1 should be USDT/USD");
        assertEq(oracle.QUOTE_FEED_2(), address(0), "Quote feed 2 should be zero");
    }

    function testMarketParams() public {
        _deployVault();

        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory params = abi.decode(liquidityData, (MarketParams));

        assertEq(params.loanToken, Constants.USDT, "Loan token should be USDT");
        assertEq(params.collateralToken, Constants.ST_USDS, "Collateral should be stUSDS");
        assertEq(params.irm, Constants.IRM_ADAPTIVE, "IRM should be adaptive");
        assertEq(params.lltv, Constants.LLTV_SAVINGS, "LLTV should be 96.5%");
        assertTrue(params.oracle != address(0), "Oracle should not be zero");
    }

    function testAdapterTimelocks() public {
        _deployVault();

        IMorphoMarketV1AdapterV2 adapter = IMorphoMarketV1AdapterV2(result.adapter);

        assertEq(adapter.timelock(IMorphoMarketV1AdapterV2.burnShares.selector), Constants.TIMELOCK_LOW, "burnShares timelock should be 3 days");
        assertEq(adapter.timelock(IMorphoMarketV1AdapterV2.setSkimRecipient.selector), Constants.TIMELOCK_LOW, "setSkimRecipient timelock should be 3 days");
        assertEq(adapter.timelock(IMorphoMarketV1AdapterV2.abdicate.selector), Constants.TIMELOCK_HIGH, "abdicate timelock should be 7 days");
        assertEq(adapter.timelock(IMorphoMarketV1AdapterV2.increaseTimelock.selector), Constants.TIMELOCK_HIGH, "increaseTimelock timelock should be 7 days");
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
        loanToken.forceApprove(address(vault), depositAmount);
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
