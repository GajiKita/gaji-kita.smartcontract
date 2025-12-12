// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EmployeeStorage} from "../storage/EmployeeStorage.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

/**
 * @title EmployeeModule
 * @dev Module for handling employee-related operations
 */
contract EmployeeModule is EmployeeStorage {
    modifier onlyEmployee(address _employeeId) {
        _onlyEmployee(_employeeId);
        _;
    }

    function _onlyEmployee(address _employeeId) internal view {
        if (!employees[_employeeId].exists) {
            revert Errors.EmployeeNotFound();
        }
        if (employees[_employeeId].employeeAddress != msg.sender) {
            revert Errors.NotEmployee();
        }
    }

    /**
     * @dev Adds a new employee to the system
     */
    function _addEmployee(
        address _employeeId, 
        address _companyId, 
        string memory _name, 
        uint256 _monthlySalary
    ) internal {
        if (employees[_employeeId].exists) {
            return; // Employee already exists
        }
        
        // Verify company exists
        if (!companies[_companyId].exists) {
            revert Errors.CompanyNotFound();
        }
        
        employees[_employeeId] = Employee({
            employeeAddress: _employeeId,
            companyId: _companyId,
            name: _name,
            monthlySalary: _monthlySalary,
            daysWorked: 0,
            withdrawnAmount: 0,
            exists: true
        });
        
        employeeList.push(_employeeId);
        
        emit Events.EmployeeAdded(_employeeId, _companyId, _name);
    }

    /**
     * @dev Updates employee days worked
     */
    function _updateEmployeeDaysWorked(address _employeeId, uint256 _days) internal {
        employees[_employeeId].daysWorked = _days;
    }

    /**
     * @dev Updates employee withdrawn amount
     */
    function _updateEmployeeWithdrawnAmount(address _employeeId, uint256 _amount) internal virtual {
        employees[_employeeId].withdrawnAmount += _amount;
    }

    /**
     * @dev Calculates eligible withdrawal amount based on days worked and max percentage
     */
    function _calculateEmployeeEligibleWithdrawal(address _employeeId) internal view virtual returns (uint256) {
        Employee memory emp = employees[_employeeId];
        uint256 salaryPerDay = emp.monthlySalary / 30; // Assuming 30 days in a month
        uint256 amountBasedOnDays = salaryPerDay * emp.daysWorked;

        // Calculate max allowed based on percentage of monthly salary
        uint256 maxAllowed = (emp.monthlySalary * 30) / 100; // 30% of monthly salary

        // Return the minimum of the two amounts to limit withdrawal
        uint256 eligibleAmount = amountBasedOnDays < maxAllowed ? amountBasedOnDays : maxAllowed;

        // Subtract already withdrawn amount
        if (eligibleAmount <= emp.withdrawnAmount) {
            return 0;
        }

        return eligibleAmount - emp.withdrawnAmount;
    }

    /**
     * @dev Gets employee data
     */
    function getEmployee(address _employeeId) external view virtual returns (Employee memory) {
        return employees[_employeeId];
    }
}
