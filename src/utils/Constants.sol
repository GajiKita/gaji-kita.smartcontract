// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title Constants
 * @dev Constant values used across the system
 */
library Constants {
    uint256 internal constant BPS_DENOMINATOR = 10000; // Basis points denominator (100% = 10000)
    uint256 internal constant MAX_DAYS_WORKED = 30;    // Maximum days worked in a month
    uint256 internal constant MAX_SALARY_PERCENTAGE = 30; // Max withdraw percentage of monthly salary
}