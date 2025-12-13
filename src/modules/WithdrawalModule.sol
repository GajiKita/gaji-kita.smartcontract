// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LiquidityStorage} from "../storage/LiquidityStorage.sol";
import {EmployeeStorage} from "../storage/EmployeeStorage.sol";
import {Enums} from "../utils/Enums.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

/**
 * @title WithdrawalModule
 * @dev Module for handling withdrawal operations
 */
abstract contract WithdrawalModule is LiquidityStorage, EmployeeStorage {
    /**
     * @dev Updates company reward balance (abstract function to be implemented by main contract)
     */
    function _updateCompanyReward(address _companyId, uint256 _amount, bool _add) internal virtual;

    /**
     * @dev Updates employee withdrawn amount (abstract function to be implemented by main contract)
     */
    function _updateEmployeeWithdrawnAmount(address _employeeId, uint256 _amount) internal virtual;

    /**
     * @dev Allows an employee to withdraw their salary based on days worked or max percentage
     */
    function _withdrawEmployeeSalary(address _employeeId, string memory _cid) internal {
        Employee memory emp = employees[_employeeId];
        if (!emp.exists) {
            revert Errors.EmployeeNotFound();
        }
        
        uint256 eligibleAmount = _calculateEmployeeEligibleWithdrawal(_employeeId);
        if (eligibleAmount == 0) {
            revert Errors.InvalidAmount();
        }
        
        // Calculate fees
        (uint256 feeTotal, uint256 platformPart, uint256 companyPart, uint256 investorPart) =
            _calculateFee(eligibleAmount);
        
        uint256 netAmount = eligibleAmount - feeTotal;
        
        // Check if there's enough liquidity in the pool
        if (poolData.totalLiquidity < eligibleAmount) {
            revert Errors.InsufficientLiquidity();
        }
        
        // Deduct from pool
        _updatePoolLiquidity(eligibleAmount, false); // subtract
        
        // Update fee balances
        poolData.platformFeeBalance += platformPart;
        
        // Add to company reward (as a portion goes to company)
        _updateCompanyReward(emp.companyId, companyPart, true);

        // Distribute investor portion of fees to liquidity providers
        _handleInvestorFeeDistribution(investorPart);
        
        // Update employee withdrawn amount
        _updateEmployeeWithdrawnAmount(_employeeId, netAmount);
        
        // Mint receipt NFT
        _mintReceipt(msg.sender, Enums.TxType.EmployeeWithdrawSalary, eligibleAmount, _cid);
        
        // Transfer the net amount to the employee using hook
        _payoutEmployee(_employeeId, netAmount);

        emit Events.EmployeeSalaryWithdrawn(_employeeId, netAmount);
    }

    /**
     * @dev Internal function to payout employee
     * This must be overridden in the main contract to handle ETH vs ERC20 payouts
     */
    function _payoutEmployee(address to, uint256 amount) internal virtual {
        // Default implementation transfers ETH; this will be overridden in main contract
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            revert Errors.TransferNotAllowed();
        }
    }

    /**
     * @dev Internal function to calculate employee eligible withdrawal
     * This must be overridden in the main contract to access the fee calculation
     */
    function _calculateEmployeeEligibleWithdrawal(address _employeeId) view internal virtual returns (uint256);

    /**
     * @dev Internal function to calculate fees
     * This must be overridden in the main contract to access the fee calculation
     */
    function _calculateFee(uint256 amount) internal view virtual returns (
        uint256 feeTotal,
        uint256 platformPart,
        uint256 companyPart,
        uint256 investorPart
    );

    /**
     * @dev Internal function to update pool liquidity
     * This must be overridden in the main contract to access liquidity updates
     */
    function _updatePoolLiquidity(uint256 _amount, bool _add) internal virtual;

    /**
     * @dev Internal function to distribute investor fee portion
     * This must be overridden in the main contract to access investor accounting
     */
    function _handleInvestorFeeDistribution(uint256 investorPart) internal virtual;

    /**
     * @dev Internal function to mint receipt NFT
     * This must be overridden in the main contract to access NFT minting
     */
    function _mintReceipt(address _to, Enums.TxType _txType, uint256 _amount, string memory _cid) internal virtual;
}
