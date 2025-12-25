// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FeeStorage} from "../storage/FeeStorage.sol";
import {Constants} from "../utils/Constants.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

/**
 * @title FeeModule
 * @dev Module for handling fee calculations
 */
contract FeeModule is FeeStorage {
    /**
     * @dev Initializes the fee configuration
     */
    function _initializeFeeConfig(
        uint256 _platformShare, 
        uint256 _companyShare, 
        uint256 _investorShare, 
        uint256 _feeBps
    ) internal {
        // Validate that shares sum to 100% (10000 basis points)
        if ((_platformShare + _companyShare + _investorShare) > Constants.BPS_DENOMINATOR) {
            revert Errors.InvalidFeeConfiguration();
        }
        
        feeConfig = FeeConfig({
            platformShare: _platformShare,
            companyShare: _companyShare,
            investorShare: _investorShare,
            feeBps: _feeBps
        });
    }

    /**
     * @dev Calculates fees based on amount and configuration
     */
    function _calculateFee(uint256 amount) internal view virtual returns (
        uint256 feeTotal,
        uint256 platformPart,
        uint256 companyPart,
        uint256 investorPart
    ) {
        // Calculate base fee
        feeTotal = (amount * feeConfig.feeBps) / Constants.BPS_DENOMINATOR;

        // Calculate portions based on configuration
        platformPart = (feeTotal * feeConfig.platformShare) / Constants.BPS_DENOMINATOR;
        companyPart = (feeTotal * feeConfig.companyShare) / Constants.BPS_DENOMINATOR;
        investorPart = (feeTotal * feeConfig.investorShare) / Constants.BPS_DENOMINATOR;
    }

    /**
     * @dev Updates the fee configuration (only callable by owner in the main contract)
     */
    function _updateFeeConfig(
        uint256 _platformShare, 
        uint256 _companyShare, 
        uint256 _investorShare, 
        uint256 _feeBps
    ) internal {
        // Validate that shares sum to 100% (10000 basis points)
        if ((_platformShare + _companyShare + _investorShare) > Constants.BPS_DENOMINATOR) {
            revert Errors.InvalidFeeConfiguration();
        }
        
        feeConfig = FeeConfig({
            platformShare: _platformShare,
            companyShare: _companyShare,
            investorShare: _investorShare,
            feeBps: _feeBps
        });
        
        emit Events.FeeConfigUpdated(_platformShare, _companyShare, _investorShare, _feeBps);
    }
}
