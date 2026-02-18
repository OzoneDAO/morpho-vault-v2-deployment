// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IVaultV2} from "vault-v2/interfaces/IVaultV2.sol";
import {Constants} from "../../src/lib/Constants.sol";

/**
 * @title BaseVaultTest
 * @notice Base test contract with common tests for all Vault V2 deployments
 * @dev Inherit this and implement _deployVault() to use common tests
 */
abstract contract BaseVaultTest is Test {
    // State (set by child contracts)
    IVaultV2 public vault;
    IERC20 public loanToken;
    address public deployer;
    uint256 public deployerPrivateKey;

    // ============ VIRTUAL FUNCTIONS ============

    /// @notice Deploy the vault and set state variables
    function _deployVault() internal virtual;

    /// @notice Deploy vault with custom roles
    function _deployVaultWithRoles(
        address owner,
        address curator,
        address allocator,
        address sentinel
    ) internal virtual;

    /// @notice Loan token address (override for non-USDS vaults)
    function _loanTokenAddress() internal pure virtual returns (address) {
        return Constants.USDS;
    }

    /// @notice Deposit amount scaled to token decimals (override for 6-dec tokens)
    function _depositAmount() internal pure virtual returns (uint256) {
        return 1000e18;
    }

    // ============ SETUP ============

    function setUp() public virtual {
        vm.setEnv("PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        // Reset role env vars to deployer address (empty string doesn't work properly with envOr for addresses)
        vm.setEnv("OWNER", vm.toString(deployer));
        vm.setEnv("CURATOR", vm.toString(deployer));
        vm.setEnv("ALLOCATOR", vm.toString(deployer));
        vm.setEnv("SENTINEL", vm.toString(address(0)));

        loanToken = IERC20(_loanTokenAddress());
    }

    // ============ ROLE VERIFICATION TESTS ============

    function testRolesAreProperlyConfigured() public {
        _deployVault();

        address currentOwner = vault.owner();
        address currentCurator = vault.curator();

        assertTrue(currentOwner != address(0), "Owner should be set");
        assertTrue(currentCurator != address(0), "Curator should be set");

        console.log("Owner:", currentOwner);
        console.log("Curator:", currentCurator);
        console.log("Deployer:", deployer);
    }

    function testRoleTransferToCustomAddresses() public {
        address customOwner = makeAddr("customOwner");
        address customCurator = makeAddr("customCurator");
        address customAllocator = makeAddr("customAllocator");
        address customSentinel = makeAddr("customSentinel");

        _deployVaultWithRoles(customOwner, customCurator, customAllocator, customSentinel);

        assertEq(vault.owner(), customOwner, "Owner should be custom address");
        assertEq(vault.curator(), customCurator, "Curator should be custom address");
        assertTrue(vault.isAllocator(customAllocator), "Custom allocator should be set");
        assertFalse(vault.isAllocator(deployer), "Deployer should NOT be allocator");
        assertTrue(vault.isSentinel(customSentinel), "Sentinel should be set");
    }

    // ============ TIMELOCK CONFIGURATION TESTS ============

    function testTimelockConfiguration_LowPriority() public {
        _deployVault();

        assertEq(vault.timelock(IVaultV2.addAdapter.selector), Constants.TIMELOCK_LOW, "addAdapter timelock");
        assertEq(vault.timelock(IVaultV2.increaseAbsoluteCap.selector), Constants.TIMELOCK_LOW, "increaseAbsoluteCap timelock");
        assertEq(vault.timelock(IVaultV2.increaseRelativeCap.selector), Constants.TIMELOCK_LOW, "increaseRelativeCap timelock");
        assertEq(vault.timelock(IVaultV2.setForceDeallocatePenalty.selector), Constants.TIMELOCK_LOW, "setForceDeallocatePenalty timelock");
    }

    function testTimelockConfiguration_HighPriority() public {
        _deployVault();

        assertEq(vault.timelock(IVaultV2.increaseTimelock.selector), Constants.TIMELOCK_HIGH, "increaseTimelock timelock");
        assertEq(vault.timelock(IVaultV2.removeAdapter.selector), Constants.TIMELOCK_HIGH, "removeAdapter timelock");
        assertEq(vault.timelock(IVaultV2.abdicate.selector), Constants.TIMELOCK_HIGH, "abdicate timelock");
    }

    // ============ GATE ABDICATION TESTS ============

    function testGatesAbdicated() public {
        _deployVault();

        assertTrue(vault.abdicated(IVaultV2.setReceiveAssetsGate.selector), "setReceiveAssetsGate should be abdicated");
        assertTrue(vault.abdicated(IVaultV2.setSendSharesGate.selector), "setSendSharesGate should be abdicated");
        assertTrue(vault.abdicated(IVaultV2.setReceiveSharesGate.selector), "setReceiveSharesGate should be abdicated");
        assertTrue(vault.abdicated(IVaultV2.setAdapterRegistry.selector), "setAdapterRegistry should be abdicated");
    }

    function testGatesAreZero() public {
        _deployVault();

        assertEq(vault.receiveAssetsGate(), address(0), "receiveAssetsGate should be zero");
        assertEq(vault.sendSharesGate(), address(0), "sendSharesGate should be zero");
        assertEq(vault.receiveSharesGate(), address(0), "receiveSharesGate should be zero");
    }

    // ============ ADAPTER CONFIGURATION TESTS ============

    function testAdapterConfiguration() public {
        _deployVault();

        assertEq(vault.adaptersLength(), 1, "Should have exactly 1 adapter");
        assertTrue(vault.isAdapter(vault.adapters(0)), "Adapter should be registered");
    }

    function testAdapterRegistrySet() public {
        _deployVault();

        assertEq(vault.adapterRegistry(), Constants.ADAPTER_REGISTRY, "Adapter registry should be set");
    }

    // ============ MAX RATE TEST ============

    function testMaxRateSet() public {
        _deployVault();

        assertEq(vault.maxRate(), Constants.MAX_RATE, "Max rate should be 200% APR");
    }

    // ============ DEAD DEPOSIT TESTS ============

    function testDeadDepositToVault() public {
        _deployVault();

        address dead = address(0xdEaD);
        uint256 deadShares = vault.balanceOf(dead);

        assertGt(deadShares, 0, "Dead address should have shares");
        console.log("Dead deposit shares:", deadShares);
    }

    // ============ USER DEPOSIT/WITHDRAW TESTS ============

    function testVaultDeposit() public {
        _deployVault();

        address user = makeAddr("user");
        uint256 depositAmount = _depositAmount();

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.approve(address(vault), depositAmount);

        uint256 expectedShares = vault.convertToShares(depositAmount);
        uint256 sharesReceived = vault.deposit(depositAmount, user);
        vm.stopPrank();

        assertEq(sharesReceived, expectedShares, "Shares received mismatch");
        assertEq(vault.balanceOf(user), sharesReceived, "User vault balance mismatch");
        assertEq(loanToken.balanceOf(user), 0, "User should have no loan token left");
    }

    function testVaultWithdraw() public {
        _deployVault();

        address user = makeAddr("user");
        uint256 depositAmount = _depositAmount();

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

        uint256 withdrawAmount = depositAmount / 2;
        vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();

        assertEq(loanToken.balanceOf(user), withdrawAmount, "User should receive withdrawn amount");
        assertGt(vault.balanceOf(user), 0, "User should have remaining shares");
    }

    function testVaultRedeem() public {
        _deployVault();

        address user = makeAddr("user");
        uint256 depositAmount = _depositAmount();

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);

        uint256 redeemShares = shares / 2;
        uint256 assetsReceived = vault.redeem(redeemShares, user, user);
        vm.stopPrank();

        assertGt(assetsReceived, 0, "Should receive assets");
        assertEq(vault.balanceOf(user), shares - redeemShares, "Remaining shares mismatch");
    }

    function testFullWithdrawal() public {
        _deployVault();

        address user = makeAddr("user");
        uint256 depositAmount = _depositAmount();

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);

        uint256 assetsReceived = vault.redeem(shares, user, user);
        vm.stopPrank();

        assertEq(vault.balanceOf(user), 0, "User should have no shares");
        assertApproxEqAbs(assetsReceived, depositAmount, 1, "Should receive approximately all assets");
    }

    function testMultipleUsersDeposit() public {
        _deployVault();

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        uint256 amount1 = _depositAmount();
        uint256 amount2 = _depositAmount() * 2;
        uint256 amount3 = _depositAmount() / 2;

        deal(_loanTokenAddress(), user1, amount1);
        deal(_loanTokenAddress(), user2, amount2);
        deal(_loanTokenAddress(), user3, amount3);

        vm.startPrank(user1);
        loanToken.approve(address(vault), amount1);
        vault.deposit(amount1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        loanToken.approve(address(vault), amount2);
        vault.deposit(amount2, user2);
        vm.stopPrank();

        vm.startPrank(user3);
        loanToken.approve(address(vault), amount3);
        vault.deposit(amount3, user3);
        vm.stopPrank();

        assertGt(vault.balanceOf(user1), 0, "User1 should have shares");
        assertGt(vault.balanceOf(user2), 0, "User2 should have shares");
        assertGt(vault.balanceOf(user3), 0, "User3 should have shares");
    }

    // ============ ACCESS CONTROL TESTS ============

    function testOnlyOwnerCanSetCurator() public {
        _deployVault();

        address currentOwner = vault.owner();
        address newCurator = makeAddr("newCurator");
        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert();
        vault.setCurator(newCurator);

        vm.prank(currentOwner);
        vault.setCurator(newCurator);
        assertEq(vault.curator(), newCurator, "Curator should be updated");
    }

    function testOnlyOwnerCanSetOwner() public {
        _deployVault();

        address currentOwner = vault.owner();
        address newOwner = makeAddr("newOwner");
        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert();
        vault.setOwner(newOwner);

        vm.prank(currentOwner);
        vault.setOwner(newOwner);
        assertEq(vault.owner(), newOwner, "Owner should be updated");
    }

    function testOnlyCuratorCanSubmit() public {
        _deployVault();

        address notCurator = makeAddr("notCurator");
        bytes memory data = abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, notCurator, true);

        vm.prank(notCurator);
        vm.expectRevert();
        vault.submit(data);
    }

    function testOnlyAllocatorCanAllocate() public {
        _deployVault();

        // Get the actual allocator from env (may be deployer or custom address from .env)
        address expectedAllocator = vm.envOr("ALLOCATOR", deployer);

        // Verify the expected allocator IS an allocator
        assertTrue(vault.isAllocator(expectedAllocator), "Expected allocator should have allocator role");

        // Verify non-allocator cannot allocate
        address notAllocator = makeAddr("notAllocator");
        assertFalse(vault.isAllocator(notAllocator), "Random address should not be allocator");

        // NOTE: Full allocation functionality is tested in vault-specific tests
    }

    // ============ VAULT METADATA TESTS ============

    function testVaultMetadata() public {
        _deployVault();

        assertEq(vault.asset(), _loanTokenAddress(), "Asset should match loan token");
        assertGt(vault.decimals(), 0, "Vault decimals should be > 0");

        string memory name = vault.name();
        string memory symbol = vault.symbol();

        assertTrue(bytes(name).length > 0, "Name should be set");
        assertTrue(bytes(symbol).length > 0, "Symbol should be set");

        console.log("Vault name:", name);
        console.log("Vault symbol:", symbol);
    }

    // ============ EDGE CASE TESTS ============

    function testZeroDepositBehavior() public {
        _deployVault();

        address user = makeAddr("user");

        vm.prank(user);
        uint256 shares = vault.deposit(0, user);
        assertEq(shares, 0, "Zero deposit should return zero shares");
    }

    function testWithdrawMoreThanBalanceReverts() public {
        _deployVault();

        address user = makeAddr("user");
        uint256 depositAmount = _depositAmount() / 10;

        deal(_loanTokenAddress(), user, depositAmount);

        vm.startPrank(user);
        loanToken.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

        vm.expectRevert();
        vault.withdraw(depositAmount * 2, user, user);
        vm.stopPrank();
    }

    function testDepositWithoutApprovalReverts() public {
        _deployVault();

        address user = makeAddr("user");
        uint256 amount = _depositAmount() / 10;

        deal(_loanTokenAddress(), user, amount);

        vm.prank(user);
        vm.expectRevert();
        vault.deposit(amount, user);
    }
}
