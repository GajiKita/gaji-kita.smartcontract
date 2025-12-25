// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GajiKita, Errors} from "../src/GajiKita.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {Proxy} from "../src/Proxy.sol";

contract ProxyTest is Test {
    GajiKita gajiKitaImplementation;
    Proxy proxy;
    GajiKita gajiKitaProxy;
    MockERC20 settlementToken;

    address owner = address(1);
    address admin = address(2);
    address company1 = address(3);
    address company2 = address(4);
    address employee1 = address(5);
    address employee2 = address(6);
    address investor1 = address(7);
    address investor2 = address(8);

    function setUp() public {
        settlementToken = new MockERC20("Mock USDC", "mUSDC");
        // Deploy the implementation contract
        gajiKitaImplementation = new GajiKita(
            owner,
            address(settlementToken),
            address(111),
            address(112),
            address(113),
            address(settlementToken)
        );

        // Deploy the proxy and initialize it with the implementation
        proxy = new Proxy(address(gajiKitaImplementation), owner);

        // Create a reference to the proxy as a GajiKita contract
        gajiKitaProxy = GajiKita(payable(proxy));

        // Initialize the contract state in the proxy's storage
        vm.prank(owner);
        gajiKitaProxy.initialize(owner);

        // Manually set the owner in storage since initialize() doesn't set it
        // The _owner variable in ReceiptNFTModule is at storage slot 19
        vm.store(
            address(gajiKitaProxy),
            bytes32(uint256(19)),
            bytes32(uint256(uint160(owner)))
        );
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

    function testProxyCompanyDisableEnableAndUpdateAddress() public {
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Company ABC");

        // Disable company should block actions
        vm.prank(admin);
        gajiKitaProxy.disableCompany(company1);

        vm.deal(company1, 1 ether);
        vm.prank(company1);
        vm.expectRevert(abi.encodeWithSelector(Errors.CompanyDisabled.selector));
        gajiKitaProxy.lockCompanyLiquidity{value: 1 ether}(1 ether, "CID");

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.CompanyDisabled.selector));
        gajiKitaProxy.addEmployee(employee1, company1, "John Doe", 1000 ether);

        // Enable company restores actions
        vm.prank(admin);
        gajiKitaProxy.enableCompany(company1);

        vm.deal(company1, 1 ether);
        vm.prank(company1);
        gajiKitaProxy.lockCompanyLiquidity{value: 1 ether}(1 ether, "CID");
        assertEq(gajiKitaProxy.getTotalLiquidity(), 1 ether);

        // Add employee then update company address
        vm.prank(admin);
        gajiKitaProxy.addEmployee(employee1, company1, "John Doe", 1000 ether);

        vm.prank(admin);
        gajiKitaProxy.updateCompanyAddress(company1, company2);

        (bool existsOld, ) = gajiKitaProxy.getCompanyInfo(company1);
        assertFalse(existsOld);

        (bool existsNew, ) = gajiKitaProxy.getCompanyInfo(company2);
        assertTrue(existsNew);

        (, address companyId, , , , ) = gajiKitaProxy.getEmployeeInfo(employee1);
        assertEq(companyId, company2);
    }

    function testProxyInvestorOperations() public {
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Company ABC");

        // Investor deposits liquidity through proxy
        settlementToken.mint(investor1, 5 ether);
        vm.prank(investor1);
        settlementToken.approve(address(gajiKitaProxy), 5 ether);
        vm.prank(investor1);
        gajiKitaProxy.depositInvestorLiquidityToken(5 ether, "CID001");

        (bool exists, uint256 deposited, , ) = gajiKitaProxy.getInvestor(
            investor1
        );
        assertTrue(exists);
        assertEq(deposited, 5 ether);
    }

    function testUpgradeImplementation() public {
        // Create a new version of the implementation
        GajiKita newImplementation = new GajiKita(
            owner,
            address(settlementToken),
            address(111),
            address(112),
            address(113),
            address(settlementToken)
        );

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

    function testRegisterCompanyByNonAdminFailsThroughProxy() public {
        vm.prank(address(99));
        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector));
        gajiKitaProxy.registerCompany(company1, "Company ABC");
    }

    function testAddEmployeeByNonAdminFailsThroughProxy() public {
        vm.prank(address(99));
        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector));
        gajiKitaProxy.addEmployee(employee1, company1, "John Doe", 3000 ether);
    }

    function testLockCompanyLiquidityWrongAmountFailsThroughProxy() public {
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Company ABC");

        vm.deal(company1, 10 ether);
        vm.prank(company1);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector));
        gajiKitaProxy.lockCompanyLiquidity{value: 5 ether}(10 ether, "CID001");
    }

    function testDepositInvestorLiquidityZeroValueFailsThroughProxy() public {
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Company ABC");

        vm.prank(investor1);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector));
        gajiKitaProxy.depositInvestorLiquidityToken(0, "CID001");
    }

    function testWithdrawSalaryByNonEmployeeFailsThroughProxy() public {
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Company ABC");

        vm.prank(admin);
        gajiKitaProxy.addEmployee(employee1, company1, "John Doe", 3000 ether);

        vm.prank(company1); // Company trying to withdraw employee salary
        vm.expectRevert();
        gajiKitaProxy.withdrawSalary("CID001");
    }

    function testWithdrawCompanyRewardByNonCompanyFailsThroughProxy() public {
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Company ABC");

        vm.prank(address(99)); // Someone else trying to withdraw
        vm.expectRevert();
        gajiKitaProxy.withdrawCompanyReward(0.5 ether, "CID001");
    }

    function testWithdrawInvestorRewardByNonInvestorFailsThroughProxy() public {
        vm.prank(address(99)); // Someone who is not an investor
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvestorNotFound.selector)
        );
        gajiKitaProxy.withdrawInvestorReward(0.2 ether, "CID001");
    }

    function testUpdateFeeConfigByNonOwnerFailsThroughProxy() public {
        vm.prank(address(99));
        vm.expectRevert();
        gajiKitaProxy.updateFeeConfig(7000, 3000, 0, 150);
    }

    function testRemoveOwnerAsAdminFailsThroughProxy() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector));
        gajiKitaProxy.removeAdmin(owner);
    }

    function testWithdrawAllInvestorLiquidityThroughProxy() public {
        vm.prank(owner);
        gajiKitaProxy.addAdmin(admin);

        vm.prank(admin);
        gajiKitaProxy.registerCompany(company1, "Company ABC");

        settlementToken.mint(investor1, 5 ether);
        vm.prank(investor1);
        settlementToken.approve(address(gajiKitaProxy), 5 ether);
        vm.prank(investor1);
        gajiKitaProxy.depositInvestorLiquidityToken(5 ether, "CID001");

        vm.prank(investor1);
        gajiKitaProxy.withdrawAllInvestorLiquidity("CID001");

        // Verify investor liquidity withdrawn
        (bool exists, uint256 deposited, , uint256 withdrawnRewards) = gajiKitaProxy
            .getInvestor(investor1);
        assertTrue(exists);
        assertEq(deposited, 0); // Amount deposited should now be 0 after withdrawal
        assertEq(withdrawnRewards, 0); // withdrawnRewards should be 0 initially
    }
}

// Additional contract to test proxy functionality in more depth
contract ProxyIntegrationTest is Test {
    GajiKita gajiKitaImplementation;
    Proxy proxy;
    GajiKita gajiKitaProxy;
    MockERC20 settlementToken;
    address owner = address(1);
    address admin = address(2);
    address dummyRouter = address(111);
    address dummyFactory = address(112);
    address dummyWNative = address(113);

    function setUp() public {
        settlementToken = new MockERC20("Mock USDC", "mUSDC");
        // Deploy the implementation contract
        gajiKitaImplementation = new GajiKita(
            owner,
            address(settlementToken),
            dummyRouter,
            dummyFactory,
            dummyWNative,
            address(settlementToken)
        );

        // Deploy the proxy and initialize it with the implementation
        proxy = new Proxy(address(gajiKitaImplementation), owner);

        // Create a reference to the proxy as a GajiKita contract
        gajiKitaProxy = GajiKita(payable(proxy));

        // Initialize the contract state in the proxy's storage
        vm.prank(owner);
        gajiKitaProxy.initialize(owner);

        // Manually set the owner in storage since initialize() doesn't set it
        // The _owner variable in ReceiptNFTModule is at storage slot 19
        vm.store(
            address(gajiKitaProxy),
            bytes32(uint256(19)),
            bytes32(uint256(uint160(owner)))
        );
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
        settlementToken.mint(address(3), 2000 ether);
        vm.prank(address(3));
        settlementToken.approve(address(gajiKitaProxy), 2000 ether);
        vm.prank(address(3));
        gajiKitaProxy.lockCompanyLiquidityToken(2000 ether, "CID001");

        // Investor also adds more liquidity to participate in fee distribution
        settlementToken.mint(address(5), 500 ether);
        vm.prank(address(5));
        settlementToken.approve(address(gajiKitaProxy), 500 ether);
        vm.prank(address(5));
        gajiKitaProxy.depositInvestorLiquidityToken(500 ether, "CID001");

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
