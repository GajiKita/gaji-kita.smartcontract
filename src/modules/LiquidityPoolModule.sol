// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LiquidityStorage} from "../storage/LiquidityStorage.sol";
import {CompanyStorage} from "../storage/CompanyStorage.sol";
import {Enums} from "../utils/Enums.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

/**
 * @title LiquidityPoolModule
 * @dev Module for managing liquidity pools and related operations
 */
abstract contract LiquidityPoolModule is LiquidityStorage, CompanyStorage {
    /**
     * @dev Updates company locked liquidity (abstract function to be implemented by main contract)
     */
    function _updateCompanyLiquidity(address _companyId, uint256 _amount, bool _add) internal virtual;

    /**
     * @dev Updates company reward balance (abstract function to be implemented by main contract)
     */
    function _updateCompanyReward(address _companyId, uint256 _amount, bool _add) internal virtual;
    /**
     * @dev Locks company liquidity in the pool
     */
    function _lockCompanyLiquidity(address _companyId, uint256 _amount, string memory _cid) internal {
        if (!companies[_companyId].exists) {
            revert Errors.CompanyNotFound();
        }
        
        if (_amount == 0) {
            revert Errors.InvalidAmount();
        }
        
        // Update company liquidity
        _updateCompanyLiquidity(_companyId, _amount, true); // add
        
        // Add to total pool liquidity
        _updatePoolLiquidity(_amount, true); // add
        
        // Emit event and mint receipt
        emit Events.CompanyLiquidityLocked(_companyId, _amount);
        _mintReceipt(msg.sender, Enums.TxType.CompanyLiquidityLock, _amount, _cid);
    }

    /**
     * @dev Deposits liquidity from an investor
     */
    function _depositInvestorLiquidity(address _investorId, uint256 _amount, string memory _cid) internal {
        if (_amount == 0) {
            revert Errors.InvalidAmount();
        }
        
        // Add investor if doesn't exist
        if (!investors[_investorId].exists) {
            investors[_investorId] = Investor({
                investorAddress: _investorId,
                deposited: 0,
                rewardBalance: 0,
                withdrawnRewards: 0,
                exists: true
            });
            investorList.push(_investorId);
        }
        
        // Update investor deposit
        investors[_investorId].deposited += _amount;
        totalInvestorLiquidity += _amount;
        
        // Add to total pool liquidity
        _updatePoolLiquidity(_amount, true); // add
        
        emit Events.InvestorDeposited(_investorId, _amount);
        _mintReceipt(msg.sender, Enums.TxType.InvestorDeposit, _amount, _cid);
    }

    /**
     * @dev Withdraws liquidity for an investor
     */
    function _withdrawInvestorLiquidity(address _investorId, uint256 _amount, string memory _cid) internal {
        if (!investors[_investorId].exists) {
            revert Errors.InvestorNotFound();
        }
        
        if (investors[_investorId].deposited < _amount) {
            revert Errors.InsufficientBalance();
        }
        if (totalInvestorLiquidity < _amount) {
            revert Errors.InsufficientLiquidity();
        }
        
        // Update investor deposit
        investors[_investorId].deposited -= _amount;
        totalInvestorLiquidity -= _amount;
        
        // Deduct from total pool liquidity
        _updatePoolLiquidity(_amount, false); // subtract
        
        // Transfer amount to investor
        (bool success, ) = payable(_investorId).call{value: _amount}("");
        if (!success) {
            revert Errors.TransferNotAllowed();
        }
        
        emit Events.InvestorWithdrawn(_investorId, _amount);
        _mintReceipt(msg.sender, Enums.TxType.InvestorWithdraw, _amount, _cid);
    }

    /**
     * @dev Withdraws company reward
     */
    function _withdrawCompanyReward(address _companyId, uint256 _amount, string memory _cid) internal {
        if (!companies[_companyId].exists) {
            revert Errors.CompanyNotFound();
        }

        if (companies[_companyId].rewardBalance < _amount) {
            revert Errors.InsufficientBalance();
        }

        // Update company reward balance (reduce available rewards)
        _updateCompanyReward(_companyId, _amount, false); // subtract from available rewards

        // Increase total withdrawn rewards counter
        companies[_companyId].withdrawnRewards += _amount;

        // Transfer amount to company
        (bool success, ) = payable(_companyId).call{value: _amount}("");
        if (!success) {
            revert Errors.TransferNotAllowed();
        }

        emit Events.CompanyRewardWithdrawn(_companyId, _amount);
        _mintReceipt(msg.sender, Enums.TxType.CompanyRewardWithdraw, _amount, _cid);
    }

    /**
     * @dev Withdraws investor reward
     */
    function _withdrawInvestorReward(address _investorId, uint256 /* _amount */, string memory _cid) internal {
        if (!investors[_investorId].exists) {
            revert Errors.InvestorNotFound();
        }

        uint256 reward = investors[_investorId].rewardBalance;
        if (reward == 0) {
            revert Errors.InsufficientBalance();
        }

        // Update investor reward balance (withdraw full reward)
        investors[_investorId].rewardBalance = 0;

        // Increase total withdrawn rewards counter
        investors[_investorId].withdrawnRewards += reward;

        // Transfer amount to investor
        (bool success, ) = payable(_investorId).call{value: reward}("");
        if (!success) {
            revert Errors.TransferNotAllowed();
        }

        emit Events.InvestorRewardWithdrawn(_investorId, reward);
        _mintReceipt(msg.sender, Enums.TxType.InvestorRewardWithdraw, reward, _cid);
    }

    /**
     * @dev Withdraws platform fee
     */
    function _withdrawPlatformFee(address _platform, uint256 _amount, string memory _cid) internal {
        if (poolData.platformFeeBalance < _amount) {
            revert Errors.InsufficientBalance();
        }
        
        // Update platform fee balance
        poolData.platformFeeBalance -= _amount;
        
        // Transfer amount to platform
        (bool success, ) = payable(_platform).call{value: _amount}("");
        if (!success) {
            revert Errors.TransferNotAllowed();
        }
        
        emit Events.PlatformFeeWithdrawn(_platform, _amount);
        _mintReceipt(msg.sender, Enums.TxType.PlatformFeeWithdraw, _amount, _cid);
    }

    /**
     * @dev Updates pool liquidity
     */
    function _updatePoolLiquidity(uint256 _amount, bool _add) internal virtual {
        if (_add) {
            poolData.totalLiquidity += _amount;
        } else {
            if (poolData.totalLiquidity < _amount) {
                revert Errors.InsufficientLiquidity();
            }
            poolData.totalLiquidity -= _amount;
        }
    }

    /**
     * @dev Internal function to mint receipt NFT
     * This must be overridden in the main contract to access NFT minting
     */
    function _mintReceipt(address _to, Enums.TxType _txType, uint256 _amount, string memory _cid) internal virtual;

    /**
     * @dev Distributes investor fee portion proportionally to investor liquidity share.
     * Note: naive loop, acceptable for MVP; optimize with index-based accounting for scale.
     */
    function _distributeInvestorFee(uint256 investorPart) internal virtual {
        if (investorPart == 0 || totalInvestorLiquidity == 0) {
            return;
        }

        uint256 investorsLength = investorList.length;
        for (uint256 i = 0; i < investorsLength; i++) {
            address investorAddr = investorList[i];
            uint256 share = (investors[investorAddr].deposited * investorPart) / totalInvestorLiquidity;
            investors[investorAddr].rewardBalance += share;
        }
    }
}
