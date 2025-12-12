// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LiquidityStorage
 * @dev Storage contract for liquidity-related data
 */
contract LiquidityStorage {
    struct Investor {
        address investorAddress;
        uint256 deposited;
        uint256 rewardBalance;  // Available rewards to withdraw
        uint256 withdrawnRewards; // Total rewards withdrawn so far
        bool exists;
    }

    struct PoolData {
        uint256 totalLiquidity;
        uint256 platformFeeBalance;
    }

    mapping(address => Investor) internal investors;
    address[] internal investorList;
    PoolData internal poolData;
    uint256 internal totalInvestorLiquidity;

    /**
     * @dev Returns the count of registered investors
     */
    function getInvestorCount() external view returns (uint256) {
        return investorList.length;
    }

    /**
     * @dev Returns the total liquidity in the pool
     */
    function getTotalLiquidity() external view returns (uint256) {
        return poolData.totalLiquidity;
    }

    /**
     * @dev Returns the platform fee balance
     */
    function getPlatformFeeBalance() external view returns (uint256) {
        return poolData.platformFeeBalance;
    }

    /**
     * @dev Returns the total liquidity provided by investors only
     */
    function getTotalInvestorLiquidity() external view returns (uint256) {
        return totalInvestorLiquidity;
    }
}
