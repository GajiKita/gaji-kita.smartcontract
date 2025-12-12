// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CompanyStorage
 * @dev Storage contract for company-related data
 */
contract CompanyStorage {
    struct Company {
        address owner;
        string name;
        uint256 totalSalary;
        uint256 lockedLiquidity;
        uint256 rewardBalance;  // Available rewards to withdraw
        uint256 withdrawnRewards; // Total rewards withdrawn so far
        bool exists;
    }

    mapping(address => Company) internal companies;
    address[] internal companyList;

    /**
     * @dev Returns the count of registered companies
     */
    function getCompanyCount() external view returns (uint256) {
        return companyList.length;
    }
}