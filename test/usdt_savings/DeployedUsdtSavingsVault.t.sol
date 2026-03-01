// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, MarketParams, Id, Market} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

import {Constants} from "../../src/lib/Constants.sol";
import {IMorphoChainlinkOracleV2} from "../../src/lib/DeployHelpers.sol";
import {BaseDeployedVaultTest} from "../base/BaseDeployedVaultTest.sol";

/**
 * @title DeployedUsdtSavingsVaultTest
 * @notice Tests against already-deployed USDT Savings vault on Tenderly or mainnet fork
 * @dev Set VAULT_ADDRESS env var to test a specific deployed vault.
 *      This vault reuses an existing market with high usage. On stale forks, the adaptive IRM
 *      overflows when accruing interest over a large time gap. Deposit/withdraw tests warp
 *      to the market's lastUpdate to avoid this.
 */
contract DeployedUsdtSavingsVaultTest is BaseDeployedVaultTest {
    using SafeERC20 for IERC20;

    function _loanTokenAddress() internal pure override returns (address) {
        return Constants.USDT;
    }

    function _initialDeadDeposit() internal pure override returns (uint256) {
        return Constants.INITIAL_DEAD_DEPOSIT_6DEC;
    }

    function _depositAmount() internal pure override returns (uint256) {
        return 100e6;
    }

    function _expectedVaultName() internal pure override returns (string memory) {
        return "sky.money USDT Savings";
    }

    function _expectedVaultSymbol() internal pure override returns (string memory) {
        return "skyMoneyUsdtSavings";
    }

    // ============ USDT SAVINGS SPECIFIC TESTS ============

    function testLiquidityAdapterSet() public view {
        console.log("=== Liquidity Adapter Check ===");
        address liquidityAdapter = vault.liquidityAdapter();
        console.log("Liquidity Adapter:", liquidityAdapter);

        assertEq(liquidityAdapter, vault.adapters(0), "Liquidity adapter should match first adapter");
    }

    function testMorphoMarketUtilizationIsHighAndHealthy() public view {
        console.log("=== Morpho Market Utilization ===");

        bytes memory liquidityData = vault.liquidityData();
        require(liquidityData.length > 0, "Vault has no liquidity data set");

        MarketParams memory params = abi.decode(liquidityData, (MarketParams));
        console.log("Oracle (from vault):", params.oracle);

        Id marketId = Id.wrap(keccak256(abi.encode(params)));
        IMorpho morpho = IMorpho(Constants.MORPHO_BLUE);
        Market memory marketState = morpho.market(marketId);

        console.log("Market totalSupplyAssets:", marketState.totalSupplyAssets);
        console.log("Market totalBorrowAssets:", marketState.totalBorrowAssets);

        uint256 utilizationBps = (uint256(marketState.totalBorrowAssets) * 10000) / uint256(marketState.totalSupplyAssets);
        console.log("Utilization (bps):", utilizationBps);

        // Existing market — utilization varies with market dynamics, just check it's in a healthy range
        assertGt(utilizationBps, 5000, "Market utilization should be > 50%");
        assertLt(utilizationBps, 9900, "Market utilization should be < 99%");
    }

    function testMarketLltvIs96Point5Percent() public view {
        console.log("=== Market LLTV Check ===");

        bytes memory liquidityData = vault.liquidityData();
        require(liquidityData.length > 0, "Vault has no liquidity data set");

        MarketParams memory params = abi.decode(liquidityData, (MarketParams));
        console.log("LLTV:", params.lltv);

        assertEq(params.lltv, Constants.LLTV_SAVINGS, "LLTV should be 96.5%");
    }

    function testOracleReturnsValidPrice() public view {
        console.log("=== Oracle Price Check ===");

        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory params = abi.decode(liquidityData, (MarketParams));

        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(params.oracle);
        uint256 price = oracle.price();

        // Scale = 10^(36 + 6 - 18) = 10^24. sUSDS ~$1.05 USDT
        uint256 expectedScale = 1e24;
        assertGt(price, expectedScale * 100 / 100, "Price should be >= 1.00 * scale");
        assertLt(price, expectedScale * 120 / 100, "Price should be < 1.20 * scale");
        console.log("Oracle price:", price);
    }

    function testOracleFeedConfiguration() public view {
        console.log("=== Oracle Feed Configuration ===");

        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory params = abi.decode(liquidityData, (MarketParams));

        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(params.oracle);

        assertEq(oracle.BASE_VAULT(), Constants.S_USDS, "Base vault should be sUSDS");
        assertEq(oracle.BASE_VAULT_CONVERSION_SAMPLE(), 1e18, "Base vault conversion sample should be 1e18");
        assertEq(oracle.BASE_FEED_1(), Constants.CHAINLINK_DAI_USD, "Base feed 1 should be DAI/USD");
        assertEq(oracle.BASE_FEED_2(), address(0), "Base feed 2 should be zero");
        assertEq(oracle.QUOTE_VAULT(), address(0), "Quote vault should be zero");
        assertEq(oracle.QUOTE_FEED_1(), Constants.CHAINLINK_USDT_USD, "Quote feed 1 should be USDT/USD");
        assertEq(oracle.QUOTE_FEED_2(), address(0), "Quote feed 2 should be zero");
    }

    function testMarketParams() public view {
        console.log("=== Market Params Check ===");

        bytes memory liquidityData = vault.liquidityData();
        MarketParams memory params = abi.decode(liquidityData, (MarketParams));

        assertEq(params.loanToken, Constants.USDT, "Loan token should be USDT");
        assertEq(params.collateralToken, Constants.S_USDS, "Collateral should be sUSDS");
        assertEq(params.oracle, Constants.EXISTING_SUSDS_USDT_ORACLE, "Oracle should be existing sUSDS/USDT oracle");
        assertEq(params.irm, Constants.IRM_ADAPTIVE, "IRM should be adaptive");
        assertEq(params.lltv, Constants.LLTV_SAVINGS, "LLTV should be 96.5%");

        bytes32 expectedMarketId = Constants.EXISTING_SUSDS_USDT_MARKET_ID;
        assertEq(keccak256(abi.encode(params)), expectedMarketId, "Market ID should match existing sUSDS/USDT market");
    }

    // ============ OVERRIDES: WARP TO MARKET lastUpdate TO AVOID IRM OVERFLOW ============

    /// @dev Warps to the market's lastUpdate + 1 so the adaptive IRM only computes 1 second of interest.
    ///      Without this, stale forks cause arithmetic overflow in exp(speed * elapsed) for large elapsed.
    function _warpToMarketLastUpdate() internal {
        Id marketId = Id.wrap(Constants.EXISTING_SUSDS_USDT_MARKET_ID);
        Market memory marketState = IMorpho(Constants.MORPHO_BLUE).market(marketId);
        console.log("Market lastUpdate:", marketState.lastUpdate);
        vm.warp(marketState.lastUpdate + 1);
    }

    function testUserDeposit() public override {
        _warpToMarketLastUpdate();

        address user = makeAddr("testUser");
        uint256 depositAmount = _depositAmount();

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.forceApprove(address(vault), depositAmount);

        uint256 sharesBefore = vault.balanceOf(user);
        uint256 expectedShares = vault.previewDeposit(depositAmount);

        console.log("=== User Deposit Test (warped) ===");
        console.log("Deposit amount:", depositAmount);
        console.log("Expected shares:", expectedShares);

        uint256 sharesReceived = vault.deposit(depositAmount, user);

        console.log("Shares received:", sharesReceived);

        assertEq(sharesReceived, expectedShares, "Shares should match preview");
        assertEq(vault.balanceOf(user), sharesBefore + sharesReceived, "Balance should increase");

        vm.stopPrank();
    }

    function testUserWithdraw() public override {
        _warpToMarketLastUpdate();

        address user = makeAddr("testUser2");
        uint256 depositAmount = _depositAmount();

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.forceApprove(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);

        console.log("=== User Withdraw Test (warped) ===");
        console.log("Deposited, got shares:", shares);

        uint256 withdrawShares = shares / 2;
        uint256 expectedAssets = vault.previewRedeem(withdrawShares);

        console.log("Redeeming shares:", withdrawShares);
        console.log("Expected assets:", expectedAssets);

        uint256 assetsReceived = vault.redeem(withdrawShares, user, user);

        console.log("Assets received:", assetsReceived);

        assertEq(assetsReceived, expectedAssets, "Assets should match preview");
        assertEq(vault.balanceOf(user), shares - withdrawShares, "Shares should decrease");
        assertEq(loanToken.balanceOf(user), assetsReceived, "Loan token balance should match");

        vm.stopPrank();
    }

    function testFullDepositWithdrawCycle() public override {
        _warpToMarketLastUpdate();

        address user = makeAddr("cycleUser");
        uint256 depositAmount = _depositAmount() * 10;

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.forceApprove(address(vault), depositAmount);

        console.log("=== Full Cycle Test (warped) ===");
        console.log("Initial deposit:", depositAmount);

        uint256 shares = vault.deposit(depositAmount, user);
        console.log("Shares after deposit:", shares);

        uint256 assetsBack = vault.redeem(shares, user, user);
        console.log("Assets after full redeem:", assetsBack);

        assertApproxEqAbs(assetsBack, depositAmount, 2, "Should get back ~same amount");
        assertEq(vault.balanceOf(user), 0, "Should have 0 shares");

        vm.stopPrank();
    }

    // ============ ADAPTER CHECKS ============

    function testAdapterTimelocks() public view {
        console.log("=== Adapter Timelocks Check ===");

        IMorphoMarketV1AdapterV2 adapter = IMorphoMarketV1AdapterV2(vault.adapters(0));

        assertEq(adapter.timelock(IMorphoMarketV1AdapterV2.burnShares.selector), Constants.TIMELOCK_LOW, "burnShares timelock should be 3 days");
        assertEq(adapter.timelock(IMorphoMarketV1AdapterV2.setSkimRecipient.selector), Constants.TIMELOCK_LOW, "setSkimRecipient timelock should be 3 days");
        assertEq(adapter.timelock(IMorphoMarketV1AdapterV2.abdicate.selector), Constants.TIMELOCK_HIGH, "abdicate timelock should be 7 days");
        assertEq(adapter.timelock(IMorphoMarketV1AdapterV2.increaseTimelock.selector), Constants.TIMELOCK_HIGH, "increaseTimelock timelock should be 7 days");
    }
}
