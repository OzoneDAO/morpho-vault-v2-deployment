// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IOracle} from "metamorpho-v1.1-morpho-blue/src/interfaces/IOracle.sol";
import {IMorphoMarketV1AdapterV2} from "vault-v2/adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

import {Constants} from "../../src/lib/Constants.sol";
import {IMorphoChainlinkOracleV2} from "../../src/lib/DeployHelpers.sol";
import {BaseDeployedVaultTest} from "../base/BaseDeployedVaultTest.sol";

/// @dev Minimal interface for ERC4626 convertToAssets (avoids import conflicts)
interface IERC4626Minimal {
    function convertToAssets(uint256 shares) external view returns (uint256);
}

/**
 * @title DeployedConfigureVaultTest
 * @notice Tests after Script 5: Verify full vault configuration
 * @dev Extends BaseDeployedVaultTest to inherit all common deployed-vault tests
 *      (roles, timelocks, gates, adapter, dead deposit, user ops, etc.)
 *      plus adds Flagship-specific tests.
 *
 * Required env vars:
 *   VAULT_ADDRESS - Deployed vault address
 *   OWNER, CURATOR, ALLOCATOR - Expected role addresses
 *   VAULT_NAME, VAULT_SYMBOL - Expected vault metadata
 *
 * Optional env vars:
 *   SENTINEL - Expected sentinel address
 */
contract DeployedConfigureVaultTest is BaseDeployedVaultTest {
    // Existing stUSDS oracle
    address constant EXISTING_STUSDS_ORACLE = 0x0A976226d113B67Bd42D672Ac9f83f92B44b454C;

    // ============ FLAGSHIP-SPECIFIC TESTS ============

    function testNoLiquidityAdapterSet() public view {
        console.log("=== Liquidity Adapter Check ===");
        address liquidityAdapter = vault.liquidityAdapter();
        console.log("Liquidity Adapter:", liquidityAdapter);

        assertEq(liquidityAdapter, address(0), "Liquidity adapter should NOT be set for Flagship vault");
    }

    function testAdapterRelativeCap() public view {
        console.log("=== Adapter Relative Cap ===");

        address adapter = vault.adapters(0);
        bytes32 adapterCapId = keccak256(abi.encode("this", adapter));

        uint256 relativeCap = vault.relativeCap(adapterCapId);
        console.log("Adapter address:", adapter);
        console.log("Relative cap:", relativeCap);
        console.log("Expected (20%):", uint256(20e16));

        assertEq(relativeCap, 20e16, "Adapter relative cap should be 20%");
    }

    function testAdapterTimelocks() public view {
        console.log("=== Adapter Timelocks ===");

        address adapter = vault.adapters(0);
        IMorphoMarketV1AdapterV2 adapterContract = IMorphoMarketV1AdapterV2(adapter);

        // Low priority (3 days)
        uint256 burnSharesTL = adapterContract.timelock(IMorphoMarketV1AdapterV2.burnShares.selector);
        uint256 setSkimRecipientTL = adapterContract.timelock(IMorphoMarketV1AdapterV2.setSkimRecipient.selector);

        console.log("burnShares timelock:", burnSharesTL);
        console.log("setSkimRecipient timelock:", setSkimRecipientTL);

        assertEq(burnSharesTL, Constants.TIMELOCK_LOW, "burnShares should have 3 day timelock");
        assertEq(setSkimRecipientTL, Constants.TIMELOCK_LOW, "setSkimRecipient should have 3 day timelock");

        // High priority (7 days)
        uint256 abdicateTL = adapterContract.timelock(IMorphoMarketV1AdapterV2.abdicate.selector);
        uint256 increaseTimelockTL = adapterContract.timelock(IMorphoMarketV1AdapterV2.increaseTimelock.selector);

        console.log("abdicate timelock:", abdicateTL);
        console.log("increaseTimelock timelock:", increaseTimelockTL);

        assertEq(abdicateTL, Constants.TIMELOCK_HIGH, "abdicate should have 7 day timelock");
        assertEq(increaseTimelockTL, Constants.TIMELOCK_HIGH, "increaseTimelock should have 7 day timelock");
    }

    function testDepositsStayIdle() public {
        console.log("=== Deposits Stay Idle Test ===");

        address user = makeAddr("idleUser");
        uint256 depositAmount = 1000 * 1e18;

        uint256 vaultBalanceBefore = usds.balanceOf(address(vault));

        deal(Constants.USDS, user, depositAmount);

        vm.startPrank(user);
        usds.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 vaultBalanceAfter = usds.balanceOf(address(vault));
        assertEq(vaultBalanceAfter, vaultBalanceBefore + depositAmount, "Deposits should stay idle in vault");

        console.log("Vault balance before:", vaultBalanceBefore);
        console.log("Vault balance after:", vaultBalanceAfter);
    }

    function testUnauthorizedAllocate() public {
        address attacker = makeAddr("attacker");
        address adapter = vault.adapters(0);

        vm.prank(attacker);
        vm.expectRevert();
        vault.allocate(adapter, "", 100);

        console.log("Unauthorized allocate test passed");
    }

    // ============ stUSDS ORACLE TESTS ============

    function testStUsdsOracleReturnsValidPrice() public view {
        // IOracle.price() scale = 10^(36 + 18 - 18) = 10^36
        // stUSDS ~$1.05 → price ~ 1.05 * 1e36
        uint256 price = IOracle(EXISTING_STUSDS_ORACLE).price();
        console.log("Oracle stUSDS/USDS price:", price);
        assertGt(price, 0.95e36, "stUSDS: price too low (< $0.95)");
        assertLt(price, 1.2e36, "stUSDS: price too high (> $1.2)");
    }

    function testStUsdsOracleFeedConfiguration() public view {
        console.log("=== stUSDS Oracle Feed Configuration ===");

        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(EXISTING_STUSDS_ORACLE);

        address baseVault = oracle.BASE_VAULT();
        address baseFeed1 = oracle.BASE_FEED_1();
        address baseFeed2 = oracle.BASE_FEED_2();
        address quoteVault = oracle.QUOTE_VAULT();
        address quoteFeed1 = oracle.QUOTE_FEED_1();
        address quoteFeed2 = oracle.QUOTE_FEED_2();

        console.log("BASE_VAULT (stUSDS):", baseVault);
        console.log("BASE_FEED_1:", baseFeed1);
        console.log("BASE_FEED_2:", baseFeed2);
        console.log("QUOTE_VAULT:", quoteVault);
        console.log("QUOTE_FEED_1:", quoteFeed1);
        console.log("QUOTE_FEED_2:", quoteFeed2);

        assertEq(baseVault, Constants.ST_USDS, "BASE_VAULT should be stUSDS");
        assertEq(baseFeed1, address(0), "BASE_FEED_1 should be unused");
        assertEq(baseFeed2, address(0), "BASE_FEED_2 should be unused");
        assertEq(quoteVault, address(0), "QUOTE_VAULT should be unused");
        assertEq(quoteFeed1, address(0), "QUOTE_FEED_1 should be unused");
        assertEq(quoteFeed2, address(0), "QUOTE_FEED_2 should be unused");
    }

    function testStUsdsOraclePriceCrossValidation() public view {
        console.log("=== stUSDS Oracle Price Cross-Validation ===");

        IMorphoChainlinkOracleV2 oracle = IMorphoChainlinkOracleV2(EXISTING_STUSDS_ORACLE);
        uint256 oraclePrice = oracle.price();
        uint256 scaleFactor = oracle.SCALE_FACTOR();

        // stUSDS oracle uses ERC4626 conversion rate (no Chainlink feeds)
        uint256 stUsdsConversion = IERC4626Minimal(Constants.ST_USDS).convertToAssets(1e18);

        console.log("stUSDS.convertToAssets(1e18):", stUsdsConversion);
        console.log("Scale factor:", scaleFactor);

        // price = SCALE_FACTOR * convertToAssets(conversionSample)
        // Note: SCALE_FACTOR already accounts for BASE_VAULT_CONVERSION_SAMPLE (1e18)
        uint256 expectedPrice = scaleFactor * stUsdsConversion;

        console.log("Oracle price:", oraclePrice);
        console.log("Expected from vault:", expectedPrice);

        assertApproxEqAbs(oraclePrice, expectedPrice, 1, "Oracle price should match stUSDS redemption rate");
    }
}
