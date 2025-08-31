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
}
