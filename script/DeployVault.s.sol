// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/TokenizedVault.sol";

contract DeployVault is Script {
    function run() external {
        // 🔐 Load deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address asset = vm.envAddress("ASSET"); // The ERC20 token address on Sepolia

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the VaultFactory
        VaultFactory factory = new VaultFactory();
        console.log("VaultFactory deployed at:", address(factory));

        // 2. Deploy a TokenizedVault for the given asset
        address vaultAddr = factory.createVault(IERC20(asset));
        console.log("TokenizedVault deployed at:", vaultAddr);

        vm.stopBroadcast();
    }
}
