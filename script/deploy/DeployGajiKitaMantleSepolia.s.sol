// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/GajiKita.sol";

contract DeployGajiKitaMantleSepolia is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy GajiKita with the deployer as the initial owner
        // For Mantle Sepolia deployment
        address initialOwner = msg.sender;
        GajiKita gajiKita = new GajiKita(initialOwner);

        vm.stopBroadcast();

        console.log("GajiKita deployed on Mantle Sepolia at:", address(gajiKita));
        console.log("Initial owner:", initialOwner);
    }
}