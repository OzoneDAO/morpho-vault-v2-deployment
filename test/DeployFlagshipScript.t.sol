// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {MarketParams} from "metamorpho-v1.1-morpho-blue/src/interfaces/IMorpho.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

import {CreateVault} from "../script/flagship/1_CreateVault.s.sol";
import {CreateCbBtcMarket} from "../script/flagship/2_CreateCbBtcMarket.s.sol";
import {CreateWstEthMarket} from "../script/flagship/3_CreateWstEthMarket.s.sol";
import {CreateWethMarket} from "../script/flagship/4_CreateWethMarket.s.sol";
import {ConfigureVault} from "../script/flagship/5_ConfigureVault.s.sol";

import {Constants} from "../src/lib/Constants.sol";
import {BaseVaultTest} from "./base/BaseVaultTest.sol";

/**
 * @title DeployFlagshipScriptTest
 * @notice Tests for Flagship Vault deployment scripts (5-script sequence)
 * @dev Extends BaseVaultTest for common tests, adds Flagship-specific tests
 *      Tests run on forked mainnet where stUSDS/USDS market already exists
 */
contract DeployFlagshipScriptTest is BaseVaultTest {
    // Scripts
    CreateVault public script1;
    CreateCbBtcMarket public script2;
    CreateWstEthMarket public script3;
    CreateWethMarket public script4;
    ConfigureVault public script5;

    // Deployment results
    address public vaultAddress;
    address public adapterAddress;
    address public oracleCbBtc;
    address public oracleWstEth;
    address public oracleWeth;

    // Market IDs
    bytes32 public marketIdCbBtc;
    bytes32 public marketIdWstEth;
    bytes32 public marketIdWeth;

    // Market params
    MarketParams public paramsCbBtc;
    MarketParams public paramsWstEth;
    MarketParams public paramsWeth;

    // Existing stUSDS market
    address constant EXISTING_STUSDS_ORACLE = 0x0A976226d113B67Bd42D672Ac9f83f92B44b454C;
    bytes32 constant EXISTING_STUSDS_MARKET_ID = 0x77e624dd9dd980810c2b804249e88f3598d9c7ec91f16aa5fbf6e3fdf6087f82;

    uint256 constant ADAPTER_RELATIVE_CAP = 20e16; // 20%
    uint256 constant MARKET_RELATIVE_CAP = 5e16; // 5%

    function setUp() public override {
        super.setUp();
        script1 = new CreateVault();
        script2 = new CreateCbBtcMarket();
        script3 = new CreateWstEthMarket();
        script4 = new CreateWethMarket();
        script5 = new ConfigureVault();
    }

    function _deployVault() internal override {
        // Deal tokens for all scripts
        deal(Constants.USDS, deployer, 10e18);
        deal(Constants.WSTETH, deployer, 1e15);
        deal(Constants.WETH, deployer, 1e15);
        deal(Constants.CBBTC, deployer, 10000);

        // Script 1: Create Vault
        CreateVault.DeploymentResult memory result1 = script1.run();
        vaultAddress = result1.vaultV2;
        adapterAddress = result1.adapter;

        // Set env vars for subsequent scripts
        vm.setEnv("VAULT_ADDRESS", vm.toString(vaultAddress));
        vm.setEnv("ADAPTER_ADDRESS", vm.toString(adapterAddress));

        // Script 2: Create cbBTC Market
        CreateCbBtcMarket.DeploymentResult memory result2 = script2.run();
        oracleCbBtc = result2.oracle;
        marketIdCbBtc = result2.marketId;
        paramsCbBtc = result2.params;
        vm.setEnv("ORACLE_CBBTC", vm.toString(oracleCbBtc));

        // Script 3: Create wstETH Market
        CreateWstEthMarket.DeploymentResult memory result3 = script3.run();
        oracleWstEth = result3.oracle;
        marketIdWstEth = result3.marketId;
        paramsWstEth = result3.params;
        vm.setEnv("ORACLE_WSTETH", vm.toString(oracleWstEth));

        // Script 4: Create WETH Market
        CreateWethMarket.DeploymentResult memory result4 = script4.run();
        oracleWeth = result4.oracle;
        marketIdWeth = result4.marketId;
        paramsWeth = result4.params;
        vm.setEnv("ORACLE_WETH", vm.toString(oracleWeth));

        // Script 5: Configure Vault
        script5.run();

        vault = IVaultV2(vaultAddress);
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

        console.log("Flagship VaultV2 Address:", vaultAddress);
        console.log("Adapter Address:", adapterAddress);
        console.log("Oracle stUSDS/USDS:", EXISTING_STUSDS_ORACLE);
        console.log("Oracle cbBTC/USDS:", oracleCbBtc);
        console.log("Oracle wstETH/USDS:", oracleWstEth);
        console.log("Oracle WETH/USDS:", oracleWeth);

        assertTrue(vaultAddress != address(0), "VaultV2 address should not be zero");
        assertTrue(adapterAddress != address(0), "Adapter address should not be zero");
        assertTrue(oracleCbBtc != address(0), "Oracle cbBTC should not be zero");
        assertTrue(oracleWstEth != address(0), "Oracle wstETH should not be zero");
        assertTrue(oracleWeth != address(0), "Oracle WETH should not be zero");
    }

    function testFourMarketsCreated() public {
        _deployVault();

        assertTrue(marketIdCbBtc != bytes32(0), "cbBTC market should exist");
        assertTrue(marketIdWstEth != bytes32(0), "wstETH market should exist");
        assertTrue(marketIdWeth != bytes32(0), "WETH market should exist");

        console.log("Market ID stUSDS:", vm.toString(EXISTING_STUSDS_MARKET_ID));
        console.log("Market ID cbBTC:", vm.toString(marketIdCbBtc));
        console.log("Market ID wstETH:", vm.toString(marketIdWstEth));
        console.log("Market ID WETH:", vm.toString(marketIdWeth));
    }

    function testMarketParamsExported() public {
        _deployVault();

        assertEq(paramsCbBtc.loanToken, Constants.USDS, "cbBTC market loan token should be USDS");
        assertEq(paramsCbBtc.collateralToken, Constants.CBBTC, "cbBTC market collateral should be CBBTC");

        assertEq(paramsWstEth.loanToken, Constants.USDS, "wstETH market loan token should be USDS");
        assertEq(paramsWstEth.collateralToken, Constants.WSTETH, "wstETH market collateral should be WSTETH");

        assertEq(paramsWeth.loanToken, Constants.USDS, "WETH market loan token should be USDS");
        assertEq(paramsWeth.collateralToken, Constants.WETH, "WETH market collateral should be WETH");
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

        IMorphoMarketV1AdapterV2 adapter = IMorphoMarketV1AdapterV2(adapterAddress);
        assertEq(adapter.realAssets(), 0, "Adapter should have 0 assets (no allocation yet)");
    }

    // ============ ALLOCATOR TESTS ============

    function testAllocatorIsProperlySet() public {
        _deployVault();

        // Verify deployer is allocator
        assertTrue(vault.isAllocator(deployer), "Deployer should be allocator");

        // Verify caps are set for the adapter
        bytes memory adapterIdData = abi.encode("this", adapterAddress);
        bytes32 adapterCapId = keccak256(adapterIdData);
        assertGt(vault.relativeCap(adapterCapId), 0, "Adapter relative cap should be set");
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
        vault.deallocate(adapterAddress, "", 100);
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

        // Build stUSDS market params
        MarketParams memory paramsStUsds = MarketParams({
            loanToken: Constants.USDS,
            collateralToken: Constants.ST_USDS,
            oracle: EXISTING_STUSDS_ORACLE,
            irm: Constants.IRM_ADAPTIVE,
            lltv: Constants.LLTV_STUSDS
        });

        uint256 overAllocation = (depositAmount + Constants.INITIAL_DEAD_DEPOSIT) * 6 / 100; // 6% > 5% cap

        vm.prank(deployer);
        vm.expectRevert();
        vault.allocate(adapterAddress, abi.encode(paramsStUsds), overAllocation);
    }

    // ============ INTEGRATION TEST ============

    function testVaultConfigurationComplete() public {
        _deployVault();

        // Verify vault has non-zero owner, curator, and at least one allocator
        assertTrue(vault.owner() != address(0), "Owner should be set");
        assertTrue(vault.curator() != address(0), "Curator should be set");

        // Verify adapter is properly registered
        assertEq(vault.adaptersLength(), 1, "Should have exactly 1 adapter");
        assertTrue(vault.isAdapter(adapterAddress), "Adapter should be registered");

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
