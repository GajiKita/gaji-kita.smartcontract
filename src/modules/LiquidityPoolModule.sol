// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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
        
        // Transfer amount to investor using payout hook
        _payout(_investorId, _amount);
        
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

        // Transfer amount to company using payout hook
        _payout(_companyId, _amount);

        emit Events.CompanyRewardWithdrawn(_companyId, _amount);
        _mintReceipt(msg.sender, Enums.TxType.CompanyRewardWithdraw, _amount, _cid);
    }

    /**
     * @dev Withdraws investor reward
     */
    function _withdrawInvestorReward(address _investorId, uint256 _amount, string memory _cid) internal {
        if (!investors[_investorId].exists) {
            revert Errors.InvestorNotFound();
        }

        uint256 reward = investors[_investorId].rewardBalance;
        if (_amount == 0 || reward < _amount) {
            revert Errors.InsufficientBalance();
        }

        // Update investor reward balance (partial or full withdraw)
        investors[_investorId].rewardBalance = reward - _amount;

        // Increase total withdrawn rewards counter
        investors[_investorId].withdrawnRewards += _amount;

        // Transfer amount to investor using payout hook
        _payout(_investorId, _amount);

        emit Events.InvestorRewardWithdrawn(_investorId, _amount);
        _mintReceipt(msg.sender, Enums.TxType.InvestorRewardWithdraw, _amount, _cid);
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
        
        // Transfer amount to platform using payout hook
        _payout(_platform, _amount);
        
        emit Events.PlatformFeeWithdrawn(_platform, _amount);
        _mintReceipt(msg.sender, Enums.TxType.PlatformFeeWithdraw, _amount, _cid);
    }

    /**
     * @dev Internal function to payout rewards
     * This must be overridden in the main contract to handle ETH vs ERC20 payouts
     */
    function _payout(address to, uint256 amount) internal virtual;

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
