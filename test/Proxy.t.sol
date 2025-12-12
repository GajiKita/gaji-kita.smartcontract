// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GajiKita} from "../src/GajiKita.sol";
import {Proxy} from "../src/Proxy.sol";

contract ProxyTest is Test {
    GajiKita gajiKitaImplementation;
    Proxy proxy;
    GajiKita gajiKitaProxy;

    address owner = address(1);
    address admin = address(2);
    address company1 = address(3);
    address company2 = address(4);
    address employee1 = address(5);
    address employee2 = address(6);
    address investor1 = address(7);
    address investor2 = address(8);

    function setUp() public {
        // Deploy the implementation contract
        gajiKitaImplementation = new GajiKita(owner);

        // Deploy the proxy and initialize it with the implementation
        proxy = new Proxy(address(gajiKitaImplementation), owner);

        // Create a reference to the proxy as a GajiKita contract
        gajiKitaProxy = GajiKita(payable(proxy));

        // Initialize the contract state in the proxy's storage
        vm.prank(owner);
        gajiKitaProxy.initialize(owner);
    }

    function testProxyInitialization() public view {
        assertEq(proxy.loadImplementation(), address(gajiKitaImplementation));
        assertEq(proxy.loadAdmin(), owner);
    }

    function testProxyConstructor() public {
        Proxy newProxy = new Proxy(address(gajiKitaImplementation), admin);
        assertEq(
            newProxy.loadImplementation(),
            address(gajiKitaImplementation)
        );
        assertEq(newProxy.loadAdmin(), admin);
    }

    function testProxyDelegatesCalls() public {
        // Add admin through the proxy
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);
        assertTrue(gajiKitaProxy.isAdmin(admin));

        // Register company through the proxy
        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Company ABC");

        (bool exists, string memory name) = gajiKitaProxy.getCompanyInfo(
            company1
        );
        assertTrue(exists);
        assertEq(name, "Company ABC");
    }

    function testProxyStateConsistency() public {
        // Add admin through the proxy
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        // Verify state is consistent between proxy and implementation
        assertTrue(gajiKitaProxy.isAdmin(admin));
        assertTrue(gajiKitaProxy.isAdmin(owner)); // Owner should also be an admin
    }

    function testProxyOwnerFunctions() public {
        vm.prank(owner);
        gajiKitaProxy.addAdmin(address(99));
        assertTrue(gajiKitaProxy.isAdmin(address(99)));

        vm.prank(owner);
        gajiKitaProxy.updateFeeConfig(7000, 3000, 0, 150);

        (
            uint256 platformShare,
            uint256 companyShare,
            uint256 investorShare,
            uint256 feeBps
        ) = gajiKitaProxy.getFeeConfiguration();
        assertEq(platformShare, 7000);
        assertEq(companyShare, 3000);
        assertEq(investorShare, 0);
        assertEq(feeBps, 150);
    }

    function testProxyAdminFunctions() public {
        // Add admin and use that admin to perform actions
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Test Company");

        (bool exists, string memory name) = gajiKitaProxy.getCompanyInfo(
            company1
        );
        assertTrue(exists);
        assertEq(name, "Test Company");
    }

    function testProxyEmployeeRegistrationAndSalaryWithdrawal() public {
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Company ABC");

        vm.prank(admin);
        gajiKitaProxy.addEmployee(employee1, company1, "John Doe", 3000 ether);

        // Update employee days worked
        vm.prank(admin);
        gajiKitaProxy.updateEmployeeDaysWorked(employee1, 15);

        // Company locks much more liquidity to cover salary withdrawal and fees
        vm.deal(company1, 1000 ether);
        vm.prank(company1);
        gajiKitaProxy.lockCompanyLiquidity{value: 1000 ether}(1000 ether, "CID001");

        // Check eligible withdrawal amount (limited by max percentage)
        uint256 eligible = gajiKitaProxy.calculateEmployeeEligibleWithdrawal(
            employee1
        );
        uint256 expected = (3000 ether * 30) / 100; // 30% of monthly salary is max allowed
        assertEq(eligible, expected);

        // Withdraw salary through proxy
        vm.prank(employee1);
        gajiKitaProxy.withdrawSalary("CID001");

        // Verify employee records updated
        (
            bool exists,
            address companyId,
            string memory empName,
            uint256 monthlySalary,
            uint256 daysWorked,
            uint256 withdrawnAmount
        ) = gajiKitaProxy.getEmployeeInfo(employee1);
        assertTrue(exists);
        assertEq(companyId, company1);
        assertEq(empName, "John Doe");
        assertEq(monthlySalary, 3000 ether);
        assertEq(daysWorked, 15);
        assertEq(withdrawnAmount, expected);
    }

    function testProxyInvestorOperations() public {
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Company ABC");

        // Investor deposits liquidity through proxy
        vm.deal(investor1, 5 ether);
        vm.prank(investor1);
        gajiKitaProxy.depositInvestorLiquidity{value: 5 ether}("CID001");

        (bool exists, uint256 deposited, , ) = gajiKitaProxy.getInvestor(
            investor1
        );
        assertTrue(exists);
        assertEq(deposited, 5 ether);
    }

    function testUpgradeImplementation() public {
        // Create a new version of the implementation
        GajiKita newImplementation = new GajiKita(owner);

        // Upgrade the proxy to the new implementation
        // Note: In a real scenario, upgrading would typically be done by the admin
        // For testing purposes, we'd need a mechanism to upgrade, so we'll test the concept

        // For this test, we'll simulate an upgrade by changing the implementation slot directly
        // This would normally be done through an admin function in a production proxy
        vm.store(
            address(proxy),
            keccak256(
                "org.gaji-kita.gaji-kita.smartcontract.proxy.implementation"
            ),
            bytes32(uint256(uint160(address(newImplementation))))
        );

        assertEq(proxy.loadImplementation(), address(newImplementation));
    }

    function testReceiveETHThroughProxy() public {
        vm.deal(address(this), 1 ether);
        (bool success, ) = address(proxy).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(address(proxy).balance, 1 ether);
    }

    function testReceiveETHToGajiKitaThroughProxy() public {
        vm.deal(address(this), 1 ether);
        (bool success, ) = address(gajiKitaProxy).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(address(gajiKitaProxy).balance, 1 ether);
    }

    function testIERC721ReceiverThroughProxy() public {
        // Test the IERC721Receiver interface implementation through the proxy
        bytes4 selector = gajiKitaProxy.onERC721Received(
            address(0),
            address(0),
            1,
            ""
        );
        assertEq(selector, gajiKitaProxy.onERC721Received.selector);
    }
}

// Additional contract to test proxy functionality in more depth
contract ProxyIntegrationTest is Test {
    GajiKita gajiKitaImplementation;
    Proxy proxy;
    GajiKita gajiKitaProxy;

    address owner = address(1);
    address admin = address(2);

    function setUp() public {
        // Deploy the implementation contract
        gajiKitaImplementation = new GajiKita(owner);

        // Deploy the proxy and initialize it with the implementation
        proxy = new Proxy(address(gajiKitaImplementation), owner);

        // Create a reference to the proxy as a GajiKita contract
        gajiKitaProxy = GajiKita(payable(proxy));

        // Initialize the contract state in the proxy's storage
        vm.prank(owner);
        gajiKitaProxy.initialize(owner);
    }

    function testCompleteWorkflowThroughProxy() public {
        // Add admin first using owner
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        // Register company
        vm.prank(admin);
        gajiKitaProxy.registerCompany(address(3), "Tech Corp");

        // Add employee
        vm.prank(admin);
        gajiKitaProxy.addEmployee(
            address(4),
            address(3),
            "Alice Smith",
            5000 ether
        );

        // Update employee days worked
        vm.prank(admin);
        gajiKitaProxy.updateEmployeeDaysWorked(address(4), 22);

        // Company adds much more liquidity to cover salary withdrawal and fees
        vm.deal(address(3), 2000 ether);
        vm.prank(address(3));
        gajiKitaProxy.lockCompanyLiquidity{value: 2000 ether}(2000 ether, "CID001");

        // Investor also adds more liquidity to participate in fee distribution
        vm.deal(address(5), 500 ether);
        vm.prank(address(5));
        gajiKitaProxy.depositInvestorLiquidity{value: 500 ether}("CID001");

        // Employee withdraws salary
        vm.prank(address(4));
        gajiKitaProxy.withdrawSalary("CID001");

        // Verify everything worked correctly
        (
            bool empExists,
            address companyId,
            ,
            uint256 monthlySalary,
            uint256 daysWorked,
            uint256 withdrawnAmount
        ) = gajiKitaProxy.getEmployeeInfo(address(4));
        assertTrue(empExists);
        assertEq(companyId, address(3));
        assertEq(monthlySalary, 5000 ether);
        assertEq(daysWorked, 22);
        assertGt(withdrawnAmount, 0);

        // Check company rewards and withdraw some amount that should be available
        (, uint256 totalRewards, uint256 withdrawnRewards) = gajiKitaProxy.getCompanyLiquidity(address(3));
        uint256 availableReward = totalRewards - withdrawnRewards;

        if (availableReward > 0) {
            vm.prank(address(3));
            gajiKitaProxy.withdrawCompanyReward(availableReward, "CID001");
        }

        // Check investor rewards and withdraw some amount that should be available
        (, , uint256 invTotalRewards, uint256 invWithdrawnRewards) = gajiKitaProxy.getInvestor(address(5));
        uint256 availableInvReward = invTotalRewards - invWithdrawnRewards;

        if (availableInvReward > 0) {
            vm.prank(address(5));
            gajiKitaProxy.withdrawInvestorReward(availableInvReward, "CID001");
        }
    }
}
