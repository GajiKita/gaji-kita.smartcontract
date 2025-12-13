// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Enums} from "./Enums.sol";

/**
 * @title Events
 * @dev Event definitions used across the system
 */
library Events {
    event CompanyRegistered(address indexed company, string name);
    event EmployeeAdded(address indexed employee, address indexed company, string name);
    event CompanyLiquidityLocked(address indexed company, uint256 amount);
    event InvestorDeposited(address indexed investor, uint256 amount);
    event EmployeeSalaryWithdrawn(address indexed employee, uint256 amount);
    event CompanyRewardWithdrawn(address indexed company, uint256 amount);
    event InvestorRewardWithdrawn(address indexed investor, uint256 amount);
    event InvestorWithdrawn(address indexed investor, uint256 amount);
    event PlatformFeeWithdrawn(address indexed platform, uint256 amount);
    event ReceiptMinted(uint256 indexed tokenId, address indexed to, Enums.TxType txType, uint256 amount, string cid);
    event FeeConfigUpdated(uint256 platformShare, uint256 companyShare, uint256 investorShare, uint256 feeBps);
    event Erc20Initialized(address settlementToken, address agniRouter);
    event PreferredPayoutTokenSet(address indexed employee, address token);
}
