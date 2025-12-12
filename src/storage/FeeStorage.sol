// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FeeStorage
 * @dev Storage contract for fee-related data
 */
contract FeeStorage {
    struct FeeConfig {
        uint256 platformShare;  // percentage in basis points (1/100th of a percent)
        uint256 companyShare;   // percentage in basis points
        uint256 investorShare;  // percentage in basis points
        uint256 feeBps;         // base fee in basis points
    }

    FeeConfig internal feeConfig;

    /**
     * @dev Returns the current fee configuration
     */
    function getFeeConfig() external view virtual returns (FeeConfig memory) {
        return feeConfig;
    }
}