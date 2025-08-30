// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// --- Importing OpenZeppelin Contracts ---
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokenizedVault
 * @notice A vault that accepts a single ERC20 token (like DAI, USDC)
 *         and issues shares in return, following ERC4626 standard.
 */
contract TokenizedVault is ERC4626, Ownable {
    /**
     * @dev Constructor:
     * @param asset The ERC20 token this vault will accept (DAI, USDC, etc.)
     */
    constructor(IERC20 asset)
        ERC20(
            string(abi.encodePacked("Vault Share - ", ERC20(address(asset)).symbol())),
            string(abi.encodePacked("v", ERC20(address(asset)).symbol()))
        )
        ERC4626(asset)
        Ownable(msg.sender)
    {}

    // We don't need to manually code deposit, mint, withdraw, redeem
    // because ERC4626 already provides:
    // - deposit(uint256 assets, address receiver)
    // - mint(uint256 shares, address receiver)
    // - withdraw(uint256 assets, address receiver, address owner)
    // - redeem(uint256 shares, address receiver, address owner)
}

/**
 * @title VaultFactory
 * @notice Deploys a vault for any ERC20 token.
 */
contract VaultFactory is Ownable {
    // List of deployed vaults
    TokenizedVault[] public allVaults;

    event VaultCreated(address vault, address asset);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Deploy a new vault for a given token.
     * @param asset Address of the ERC20 token (DAI, USDC, etc.)
     */
    function createVault(IERC20 asset) external onlyOwner returns (address) {
        TokenizedVault vault = new TokenizedVault(asset);
        allVaults.push(vault);
        emit VaultCreated(address(vault), address(asset));
        return address(vault);
    }

    /**
     * @dev Get total number of vaults created.
     */
    function totalVaults() external view returns (uint256) {
        return allVaults.length;
    }
}
