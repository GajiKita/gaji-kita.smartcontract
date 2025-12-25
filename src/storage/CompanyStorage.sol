// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Enums} from "../utils/Enums.sol";

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
        Enums.CompanyStatus status;
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
