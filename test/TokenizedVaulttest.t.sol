// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/TokenizedVault.sol";

/**
 * @title MockERC20
 * @notice Simple ERC20 token for testing the vault.
 */
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1_000_000 ether); // Mint tokens to deployer
    }
}

/**
 * @title TokenVaultTest
 * @notice Foundry test suite for TokenizedVault and VaultFactory
 */
contract TokenVaultTest is Test {
    VaultFactory factory;
    TokenizedVault vault;
    MockERC20 token;

    address owner = address(this); // Test contract is the deployer
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        // Deploy mock token and factory
        token = new MockERC20();
        factory = new VaultFactory();

        // Deploy a vault for this token
        address vaultAddr = factory.createVault(token);
        vault = TokenizedVault(vaultAddr);

        // Fund Alice and Bob
        token.transfer(alice, 1_000 ether);
        token.transfer(bob, 1_000 ether);

        // Impersonate Alice & Bob for testing
        vm.startPrank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @notice Test that factory deploys a vault correctly
     */
    function testCreateVault() public view {
        assertEq(factory.totalVaults(), 1, "Factory should have one vault");
        assertEq(address(vault.asset()), address(token), "Vault should manage correct asset");
    }

    /**
     * @notice Alice deposits tokens and receives vault shares
     */
    function testDeposit() public {
        vm.startPrank(alice);

        vault.deposit(100 ether, alice);

        assertEq(vault.balanceOf(alice), 100 ether, "Alice should get shares");
        assertEq(token.balanceOf(alice), 900 ether, "Alice's token balance reduced");

        vm.stopPrank();
    }

    /**
     * @notice Alice deposits and then withdraws tokens
     */
    function testWithdraw() public {
        vm.startPrank(alice);
        vault.deposit(100 ether, alice);

        vault.withdraw(50 ether, alice, alice);

        assertEq(token.balanceOf(alice), 950 ether, "Alice should get tokens back");
        vm.stopPrank();
    }

    /**
     * @notice Alice deposits and redeems all shares
     */
    function testRedeem() public {
        vm.startPrank(alice);
        vault.deposit(100 ether, alice);

        vault.redeem(100 ether, alice, alice);

        assertEq(token.balanceOf(alice), 1000 ether, "Alice should get all tokens back");
        assertEq(vault.balanceOf(alice), 0, "Shares should be burned");
        vm.stopPrank();
    }

    /**
     * @notice Simulate vault earning yield (increasing totalAssets)
     */
    function testSharePriceIncreaseWithYield() public {
        vm.startPrank(alice);
        vault.deposit(100 ether, alice);
        vm.stopPrank();

        // Simulate yield by sending tokens directly to vault
        token.transfer(address(vault), 50 ether);

        uint256 aliceAssets = vault.convertToAssets(vault.balanceOf(alice));

        // Approximate equality to handle rounding
        assertApproxEqAbs(aliceAssets, 150 ether, 1, "Alice's shares should now be worth ~150");
    }

    /**
     * @notice Ensure only owner can create new vaults
     */
    function testOnlyOwnerCanCreateVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        factory.createVault(token);
        vm.stopPrank();
    }

    /**
     * @notice Fuzz deposit amounts to ensure vault correctly mints shares.
     */
    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= token.balanceOf(alice));

        vm.startPrank(alice);
        vault.deposit(amount, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), amount, "Shares should equal deposit");
        assertEq(token.balanceOf(alice), 1000 ether - amount, "Tokens should decrease");
    }

    /**
     * @notice Fuzz withdraw amounts and ensure withdrawals are correct.
     */
    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);
        vm.assume(withdrawAmount <= depositAmount);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);

        uint256 aliceBalBefore = token.balanceOf(alice);
        vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        assertEq(
            token.balanceOf(alice),
            aliceBalBefore - depositAmount + withdrawAmount,
            "Tokens should match expected balance"
        );
    }

    /**
     * @notice Fuzz redeem amounts and ensure correctness.
     */
    function testFuzz_Redeem(uint256 depositAmount, uint256 redeemAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);
        vm.assume(redeemAmount <= depositAmount);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        vault.redeem(redeemAmount, alice, alice);
        vm.stopPrank();

        // After redeem, Alice's shares should decrease by redeemAmount
        assertEq(vault.balanceOf(alice), depositAmount - redeemAmount, "Remaining shares should match");
    }

    /**
     * @notice Fuzzing test: multiple deposits and withdrawals
     */
    function testFuzz_MultiDepositWithdraw(uint256 deposit1, uint256 deposit2, uint256 withdraw) public {
        vm.assume(deposit1 > 0 && deposit1 <= 500 ether);
        vm.assume(deposit2 > 0 && deposit2 <= 500 ether);
        vm.assume(withdraw <= deposit1 + deposit2);

        vm.startPrank(alice);
        vault.deposit(deposit1, alice);
        vault.deposit(deposit2, alice);
        vault.withdraw(withdraw, alice, alice);
        vm.stopPrank();

        assertTrue(vault.balanceOf(alice) + withdraw <= deposit1 + deposit2, "Consistency check");
    }

    /**
     * @notice Fuzz test: random users interact with vault
     */
    function testFuzz_MultiUserInteraction(uint256 aliceDeposit, uint256 bobDeposit) public {
        vm.assume(aliceDeposit > 0 && aliceDeposit <= 1000 ether);
        vm.assume(bobDeposit > 0 && bobDeposit <= 1000 ether);

        // Alice deposits
        vm.startPrank(alice);
        vault.deposit(aliceDeposit, alice);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        vault.deposit(bobDeposit, bob);
        vm.stopPrank();

        // Simulate yield
        token.transfer(address(vault), 50 ether);

        uint256 aliceAssets = vault.convertToAssets(vault.balanceOf(alice));
        uint256 bobAssets = vault.convertToAssets(vault.balanceOf(bob));

        assertTrue(aliceAssets >= aliceDeposit, "Alice should not lose value");
        assertTrue(bobAssets >= bobDeposit, "Bob should not lose value");
    }

    function testFuzz_ZeroDeposit() public {
        vm.startPrank(alice);
        vm.expectRevert("ERC4626: deposit amount must be greater than zero");
        vault.deposit(0, alice);
        vm.stopPrank();
    }

    function testFuzz_ZeroWithdraw() public {
        vm.startPrank(alice);
        vm.expectRevert("ERC4626: withdraw amount must be greater than zero");
        vault.withdraw(0, alice, alice);
        vm.stopPrank();
    }

    function testFuzz_ZeroRedeem() public {
        vm.startPrank(alice);
        vm.expectRevert("ERC4626: redeem amount must be greater than zero");
        vault.redeem(0, alice, alice);
        vm.stopPrank();
    }

    function testFuzz_InsufficientBalance() public {
        vm.startPrank(alice);
        vault.deposit(100 ether, alice);
        vm.expectRevert("ERC4626: withdraw amount exceeds balance");
        vault.withdraw(200 ether, alice, alice);
        vm.stopPrank();
    }

    function testFuzz_InsufficientShares() public {
        vm.startPrank(alice);
        vault.deposit(100 ether, alice);
        vm.expectRevert("ERC4626: redeem amount exceeds balance");
        vault.redeem(200 ether, alice, alice);
        vm.stopPrank();
    }

    function testFuzz_ApproveZeroAddress() public {
        vm.startPrank(alice);
        vm.expectRevert("ERC20: approve to the zero address");
        token.approve(address(0), 100 ether);
        vm.stopPrank();
    }

    function testFuzz_TransferZeroAddress() public {
        vm.startPrank(alice);
        vm.expectRevert("ERC20: transfer to the zero address");
        token.transfer(address(0), 100 ether);
        vm.stopPrank();
    }

    function testFuzz_TransferFromZeroAddress() public {
        vm.startPrank(alice);
        vm.expectRevert("ERC20: transfer from the zero address");
        token.transferFrom(address(0), bob, 100 ether);
        vm.stopPrank();
    }

    function testFuzz_TransferExceedsBalance() public {
        vm.startPrank(alice);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        token.transfer(bob, 2000 ether); // Alice only has 1000 ether
        vm.stopPrank();
    }

    function testFuzz_TransferFromExceedsAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 100 ether); // Allow Bob to spend 100 ether
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        token.transferFrom(alice, bob, 200 ether); // Bob tries to transfer more than allowed
        vm.stopPrank();
    }

    function testFuzz_TransferFromZeroAddressToNonZero() public {
        vm.startPrank(alice);
        vm.expectRevert("ERC20: transfer from the zero address");
        token.transferFrom(address(0), bob, 100 ether);
        vm.stopPrank();
    }

    function testFuzz_TransferFromNonZeroToZeroAddress() public {
        vm.startPrank(alice);
        vm.expectRevert("ERC20: transfer to the zero address");
        token.transferFrom(alice, address(0), 100 ether);
        vm.stopPrank();
    }
}
