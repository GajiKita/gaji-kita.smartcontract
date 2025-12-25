// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title Enums
 * @dev Enumerations used across the system
 */
library Enums {
    enum TxType {
        CompanyLiquidityLock,
        CompanyLiquidityUnlock,
        InvestorDeposit,
        InvestorWithdraw,
        EmployeeWithdrawSalary,
        CompanyRewardWithdraw,
        InvestorRewardWithdraw,
        PlatformFeeWithdraw
    }

    enum CompanyStatus {
        Disabled,
        Enabled
    }
}
