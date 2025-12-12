// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CompanyStorage} from "./CompanyStorage.sol";

/**
 * @title EmployeeStorage
 * @dev Storage contract for employee-related data
 */
contract EmployeeStorage is CompanyStorage {
    struct Employee {
        address employeeAddress;
        address companyId;
        string name;
        uint256 monthlySalary;
        uint256 daysWorked;
        uint256 withdrawnAmount;
        bool exists;
    }

    mapping(address => Employee) internal employees;
    address[] internal employeeList;

    /**
     * @dev Returns the count of registered employees
     */
    function getEmployeeCount() external view returns (uint256) {
        return employeeList.length;
    }
}
