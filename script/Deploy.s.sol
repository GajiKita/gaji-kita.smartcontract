// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/GajiKita.sol";
import "../src/Proxy.sol";

contract Deploy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address initialOwner = msg.sender;
        // Mantle deployment params
        address settlementToken = 0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9; // USDC (Mantle bridged)
        address router = 0xeaEE7EE68874218c3558b40063c42B82D3E7232a; // Moe router
        address factory = 0x5bEf015CA9424A7C07B68490616a4C1F094BEdEc; // Moe factory
        address wNative = 0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111; // WETH (Mantle bridged)
        address anchorStable = settlementToken; // anchor stable = USDC

        GajiKita gajiKita =
            new GajiKita(initialOwner, settlementToken, router, factory, wNative, anchorStable);
        Proxy proxy = new Proxy(address(gajiKita), initialOwner);

        vm.stopBroadcast();

        console.log("GajiKita deployed at       :", address(gajiKita));
        console.log("GajiKita Proxy deployed at :", address(proxy));
        console.log("Initial owner              :", initialOwner);
    }
}
