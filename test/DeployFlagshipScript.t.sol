// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {DeployFlagshipVaultV2} from "../script/DeployFlagshipVaultV2.s.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

import {Constants} from "../src/lib/Constants.sol";
import {BaseVaultTest} from "./base/BaseVaultTest.sol";

/**
 * @title DeployFlagshipScriptTest
 * @notice Tests for DeployFlagshipVaultV2 deployment script
 * @dev Extends BaseVaultTest for common tests, adds Flagship-specific tests
 *      Tests run on forked mainnet where stUSDS/USDS market already exists
 */
contract DeployFlagshipScriptTest is BaseVaultTest {
    DeployFlagshipVaultV2 public deployScript;
    DeployFlagshipVaultV2.DeploymentResult public result;

    uint256 constant ADAPTER_RELATIVE_CAP = 20e16; // 20%
    uint256 constant MARKET_RELATIVE_CAP = 5e16; // 5%

    function setUp() public override {
        super.setUp();
        deployScript = new DeployFlagshipVaultV2();
    }

    function _deployVault() internal override {
        // Deal USDS for vault dead deposit + market seeding (3 markets x 1 USDS each)
        deal(Constants.USDS, deployer, 10e18);

        // Deal collateral tokens for market seeding
        deal(Constants.WSTETH, deployer, 1e15); // 0.001 wstETH
        deal(Constants.WETH, deployer, 1e15); // 0.001 WETH
        deal(Constants.CBBTC, deployer, 10000); // 0.0001 cbBTC (8 decimals)

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

    // ============ FLAGSHIP-SPECIFIC TESTS ============

    function testRunScript() public {
        _deployVault();

        console.log("Flagship VaultV2 Address:", result.vaultV2);
        console.log("Adapter Address:", result.adapter);
        console.log("Oracle stUSDS/USDS:", result.oracleStUsds);
        console.log("Oracle cbBTC/USDS:", result.oracleCbBtc);
        console.log("Oracle wstETH/USDS:", result.oracleWstEth);
        console.log("Oracle WETH/USDS:", result.oracleWeth);

        assertTrue(result.vaultV2 != address(0), "VaultV2 address should not be zero");
        assertTrue(result.adapter != address(0), "Adapter address should not be zero");
        assertTrue(result.oracleStUsds != address(0), "Oracle stUSDS should not be zero");
        assertTrue(result.oracleCbBtc != address(0), "Oracle cbBTC should not be zero");
        assertTrue(result.oracleWstEth != address(0), "Oracle wstETH should not be zero");
        assertTrue(result.oracleWeth != address(0), "Oracle WETH should not be zero");
    }

    function testFourMarketsCreated() public {
        _deployVault();

        assertTrue(result.marketIdStUsds != bytes32(0), "stUSDS market should exist");
        assertTrue(result.marketIdCbBtc != bytes32(0), "cbBTC market should exist");
        assertTrue(result.marketIdWstEth != bytes32(0), "wstETH market should exist");
        assertTrue(result.marketIdWeth != bytes32(0), "WETH market should exist");

        console.log("Market ID stUSDS:", vm.toString(result.marketIdStUsds));
        console.log("Market ID cbBTC:", vm.toString(result.marketIdCbBtc));
        console.log("Market ID wstETH:", vm.toString(result.marketIdWstEth));
        console.log("Market ID WETH:", vm.toString(result.marketIdWeth));
    }

    function testMarketParamsExported() public {
        _deployVault();

        assertEq(result.paramsStUsds.loanToken, Constants.USDS, "stUSDS market loan token should be USDS");
        assertEq(result.paramsStUsds.collateralToken, Constants.ST_USDS, "stUSDS market collateral should be ST_USDS");

        assertEq(result.paramsCbBtc.loanToken, Constants.USDS, "cbBTC market loan token should be USDS");
        assertEq(result.paramsCbBtc.collateralToken, Constants.CBBTC, "cbBTC market collateral should be CBBTC");

        assertEq(result.paramsWstEth.loanToken, Constants.USDS, "wstETH market loan token should be USDS");
        assertEq(result.paramsWstEth.collateralToken, Constants.WSTETH, "wstETH market collateral should be WSTETH");

        assertEq(result.paramsWeth.loanToken, Constants.USDS, "WETH market loan token should be USDS");
        assertEq(result.paramsWeth.collateralToken, Constants.WETH, "WETH market collateral should be WETH");
    }

    // ============ NO LIQUIDITY ADAPTER TESTS ============

    function testNoLiquidityAdapterSet() public {
        _deployVault();

        assertEq(vault.liquidityAdapter(), address(0), "Liquidity adapter should NOT be set");
        assertEq(vault.liquidityData().length, 0, "Liquidity data should be empty");
    }

    function testDepositsStayIdle() public {
        _deployVault();

        address user = makeAddr("user");
        uint256 depositAmount = 1000 * 1e18;

        deal(Constants.USDS, user, depositAmount);

        vm.startPrank(user);
        usds.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 vaultBalance = usds.balanceOf(address(vault));
        assertEq(vaultBalance, depositAmount + Constants.INITIAL_DEAD_DEPOSIT, "All deposits should be idle in vault");

        IMorphoMarketV1AdapterV2 adapter = IMorphoMarketV1AdapterV2(result.adapter);
        assertEq(adapter.realAssets(), 0, "Adapter should have 0 assets (no allocation yet)");
    }

    // ============ ALLOCATOR TESTS ============

    function testAllocatorIsProperlySet() public {
        _deployVault();

        // Verify deployer is allocator
        assertTrue(vault.isAllocator(deployer), "Deployer should be allocator");

        // Verify caps are set for the adapter
        bytes memory adapterIdData = abi.encode("this", result.adapter);
        bytes32 adapterCapId = keccak256(adapterIdData);
        assertGt(vault.relativeCap(adapterCapId), 0, "Adapter relative cap should be set");

        // Verify caps are set for the stUSDS market
        bytes memory marketIdData = abi.encode("this/marketParams", result.adapter, result.paramsStUsds);
        bytes32 marketCapId = keccak256(marketIdData);
        assertGt(vault.relativeCap(marketCapId), 0, "Market relative cap should be set");
    }

    function testCapsConfiguredForAllMarkets() public {
        _deployVault();

        // Verify caps are set for each collateral token
        address[] memory collaterals = new address[](4);
        collaterals[0] = Constants.ST_USDS;
        collaterals[1] = Constants.CBBTC;
        collaterals[2] = Constants.WSTETH;
        collaterals[3] = Constants.WETH;

        for (uint256 i = 0; i < collaterals.length; i++) {
            bytes memory collateralIdData = abi.encode("collateralToken", collaterals[i]);
            bytes32 collateralCapId = keccak256(collateralIdData);
            assertGt(vault.relativeCap(collateralCapId), 0, "Collateral relative cap should be set");
        }
    }

    function testOnlyAllocatorCanDeallocate() public {
        _deployVault();

        address notAllocator = makeAddr("notAllocator");

        vm.prank(notAllocator);
        vm.expectRevert();
        vault.deallocate(result.adapter, "", 100);
    }

    // ============ 80% IDLE STRATEGY TESTS ============

    function testIdleDepositsRemainInVault() public {
        _deployVault();

        // Verify no liquidity adapter is set (80% idle strategy)
        assertEq(vault.liquidityAdapter(), address(0), "Liquidity adapter should NOT be set");

        address user = makeAddr("user");
        uint256 depositAmount = 10000 * 1e18;

        deal(Constants.USDS, user, depositAmount);

        vm.startPrank(user);
        usds.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Without liquidity adapter, 100% of deposits stay idle in vault
        uint256 vaultBalance = usds.balanceOf(address(vault));
        assertEq(vaultBalance, depositAmount + Constants.INITIAL_DEAD_DEPOSIT, "All deposits should be idle in vault");

        // User should have received shares for their deposit
        uint256 userShares = vault.balanceOf(user);
        assertGt(userShares, 0, "User should have vault shares");

        // User can redeem their shares
        uint256 redeemableAssets = vault.convertToAssets(userShares);
        assertApproxEqAbs(redeemableAssets, depositAmount, 1, "Shares should convert to approximately deposited amount");
    }

    function testCapsEnforced() public {
        _deployVault();

        address user = makeAddr("user");
        uint256 depositAmount = 10000 * 1e18;

        deal(Constants.USDS, user, depositAmount);

        vm.startPrank(user);
        usds.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 overAllocation = (depositAmount + Constants.INITIAL_DEAD_DEPOSIT) * 6 / 100; // 6% > 5% cap

        vm.prank(deployer);
        vm.expectRevert();
        vault.allocate(result.adapter, abi.encode(result.paramsStUsds), overAllocation);
    }

    // ============ INTEGRATION TEST ============

    function testVaultConfigurationComplete() public {
        _deployVault();

        // Verify vault has non-zero owner, curator, and at least one allocator
        assertTrue(vault.owner() != address(0), "Owner should be set");
        assertTrue(vault.curator() != address(0), "Curator should be set");

        // Verify adapter is properly registered
        assertEq(vault.adaptersLength(), 1, "Should have exactly 1 adapter");
        assertTrue(vault.isAdapter(result.adapter), "Adapter should be registered");

        // Verify adapter registry is set
        assertEq(vault.adapterRegistry(), Constants.ADAPTER_REGISTRY, "Adapter registry should be set");

        // Verify max rate is set
        assertEq(vault.maxRate(), Constants.MAX_RATE, "Max rate should be 200% APR");

        // Verify timelocks are configured
        assertEq(vault.timelock(IVaultV2.addAdapter.selector), Constants.TIMELOCK_LOW, "addAdapter timelock should be set");
        assertEq(vault.timelock(IVaultV2.removeAdapter.selector), Constants.TIMELOCK_HIGH, "removeAdapter timelock should be set");

        console.log("Vault configuration complete and verified");
        console.log("Owner:", vault.owner());
        console.log("Curator:", vault.curator());
    }
}
