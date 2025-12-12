// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/GajiKita.sol";
import "../../src/Proxy.sol";

/**
 * @title Deployment Configuration
 * @notice This file contains deployment scripts for multiple networks
 */
contract DeploymentConfig is Script {
    struct ChainConfig {
        string name;
        uint256 chainId;
        address initialOwner;
        uint256 gasPrice;
        uint256 priorityGasPrice;
    }

    // Lisk Sepolia configuration
    ChainConfig public liskSepoliaConfig = ChainConfig({
        name: "Lisk Sepolia",
        chainId: 4202,
        initialOwner: address(0), // Will be set dynamically
        gasPrice: 1 gwei,
        priorityGasPrice: 1 gwei
    });

    // Mantle Sepolia configuration
    ChainConfig public mantleSepoliaConfig = ChainConfig({
        name: "Mantle Sepolia", 
        chainId: 5003,
        initialOwner: address(0), // Will be set dynamically
        gasPrice: 1 gwei,
        priorityGasPrice: 1 gwei
    });

    // Base Sepolia configuration
    ChainConfig public baseSepoliaConfig = ChainConfig({
        name: "Base Sepolia",
        chainId: 84532,
        initialOwner: address(0), // Will be set dynamically
        gasPrice: 1 gwei,
        priorityGasPrice: 1 gwei
    });
}

// Individual deployment scripts for each chain

/**
 * @title Lisk Sepolia Deployments
 */
contract DeployToLiskSepolia is DeploymentConfig {
    function setUp() public {}

    function deployDirect() public {
        vm.startBroadcast();
        
        // Deploy GajiKita directly (non-proxy)
        GajiKita gajiKita = new GajiKita(msg.sender);
        
        vm.stopBroadcast();
        
        console.log("GajiKita deployed on Lisk Sepolia at:", address(gajiKita));
        console.log("Contract owner:", msg.sender);
    }
    
    function deployWithProxy() public {
        vm.startBroadcast();
        
        // Deploy the implementation
        GajiKita implementation = new GajiKita(msg.sender);
        
        // Deploy the proxy
        Proxy proxy = new Proxy(address(implementation), msg.sender);
        
        // Cast to GajiKita for interaction
        GajiKita gajiKitaProxy = GajiKita(payable(proxy));
        
        // Initialize state in proxy storage (if needed)
        // Note: Only call if the implementation isn't already initialized in constructor
        if (!gajiKitaProxy.isAdmin(msg.sender)) {
            gajiKitaProxy.initialize(msg.sender);
        }
        
        vm.stopBroadcast();
        
        console.log("GajiKita implementation deployed on Lisk Sepolia at:", address(implementation));
        console.log("Proxy deployed on Lisk Sepolia at:", address(proxy));
        console.log("Proxy admin:", msg.sender);
    }
}

/**
 * @title Mantle Sepolia Deployments
 */
contract DeployToMantleSepolia is DeploymentConfig {
    function setUp() public {}

    function deployDirect() public {
        vm.startBroadcast();
        
        // Deploy GajiKita directly (non-proxy)
        GajiKita gajiKita = new GajiKita(msg.sender);
        
        vm.stopBroadcast();
        
        console.log("GajiKita deployed on Mantle Sepolia at:", address(gajiKita));
        console.log("Contract owner:", msg.sender);
    }
    
    function deployWithProxy() public {
        vm.startBroadcast();
        
        // Deploy the implementation
        GajiKita implementation = new GajiKita(msg.sender);
        
        // Deploy the proxy
        Proxy proxy = new Proxy(address(implementation), msg.sender);
        
        // Cast to GajiKita for interaction
        GajiKita gajiKitaProxy = GajiKita(payable(proxy));
        
        // Initialize state in proxy storage (if needed)
        if (!gajiKitaProxy.isAdmin(msg.sender)) {
            gajiKitaProxy.initialize(msg.sender);
        }
        
        vm.stopBroadcast();
        
        console.log("GajiKita implementation deployed on Mantle Sepolia at:", address(implementation));
        console.log("Proxy deployed on Mantle Sepolia at:", address(proxy));
        console.log("Proxy admin:", msg.sender);
    }
}

/**
 * @title Base Sepolia Deployments
 */
contract DeployToBaseSepolia is DeploymentConfig {
    function setUp() public {}

    function deployDirect() public {
        vm.startBroadcast();
        
        // Deploy GajiKita directly (non-proxy)
        GajiKita gajiKita = new GajiKita(msg.sender);
        
        vm.stopBroadcast();
        
        console.log("GajiKita deployed on Base Sepolia at:", address(gajiKita));
        console.log("Contract owner:", msg.sender);
    }
    
    function deployWithProxy() public {
        vm.startBroadcast();
        
        // Deploy the implementation
        GajiKita implementation = new GajiKita(msg.sender);
        
        // Deploy the proxy
        Proxy proxy = new Proxy(address(implementation), msg.sender);
        
        // Cast to GajiKita for interaction
        GajiKita gajiKitaProxy = GajiKita(payable(proxy));
        
        // Initialize state in proxy storage (if needed)
        if (!gajiKitaProxy.isAdmin(msg.sender)) {
            gajiKitaProxy.initialize(msg.sender);
        }
        
        vm.stopBroadcast();
        
        console.log("GajiKita implementation deployed on Base Sepolia at:", address(implementation));
        console.log("Proxy deployed on Base Sepolia at:", address(proxy));
        console.log("Proxy admin:", msg.sender);
    }
}