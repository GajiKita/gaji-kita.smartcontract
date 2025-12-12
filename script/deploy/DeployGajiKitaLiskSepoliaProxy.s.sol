// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/GajiKita.sol";
import "../../src/Proxy.sol";

contract DeployGajiKitaLiskSepoliaProxy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy the implementation contract first
        address initialOwner = msg.sender;
        GajiKita implementation = new GajiKita(initialOwner);

        // Deploy the proxy and initialize it with the implementation
        Proxy proxy = new Proxy(address(implementation), initialOwner);

        // Cast the proxy to GajiKita for interaction
        GajiKita gajiKitaProxy = GajiKita(payable(proxy));

        // Initialize the contract state in the proxy's storage
        gajiKitaProxy.initialize(initialOwner);

        vm.stopBroadcast();

        console.log("GajiKita implementation deployed on Lisk Sepolia at:", address(implementation));
        console.log("Proxy deployed on Lisk Sepolia at:", address(proxy));
        console.log("Initial owner:", initialOwner);
    }
}