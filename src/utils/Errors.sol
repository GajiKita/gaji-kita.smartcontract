// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Errors
 * @dev Custom error definitions used across the system
 */
library Errors {
    error NotCompany();
    error NotEmployee();
    error NotInvestor();
    error InsufficientLiquidity();
    error InvalidAmount();
    error TransferNotAllowed();
    error CompanyNotFound();
    error EmployeeNotFound();
    error InvestorNotFound();
    error Unauthorized();
    error ZeroAddress();
    error InvalidFeeConfiguration();
    error InsufficientBalance();
}