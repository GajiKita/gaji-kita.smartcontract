// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EmployeeStorage} from "../storage/EmployeeStorage.sol";
import {Enums} from "../utils/Enums.sol";
import {Errors} from "../utils/Errors.sol";
import {Events} from "../utils/Events.sol";

/**
 * @title CompanyModule
 * @dev Module for handling company-related operations
 */
contract CompanyModule is EmployeeStorage {
    modifier onlyCompany(address _companyId) {
        _onlyCompany(_companyId);
        _;
    }

    function _onlyCompany(address _companyId) internal view {
        if (!companies[_companyId].exists) {
            revert Errors.CompanyNotFound();
        }
        if (companies[_companyId].status != Enums.CompanyStatus.Enabled) {
            revert Errors.CompanyDisabled();
        }
        if (companies[_companyId].owner != msg.sender) {
            revert Errors.NotCompany();
        }
    }

    /**
     * @dev Adds a new company to the system
     */
    function _addCompany(address _companyId, string memory _name) internal {
        if (companies[_companyId].exists) {
            return; // Company already exists
        }

        // Company is always owned by itself
        companies[_companyId] = Company({
            owner: _companyId,  // Company owns itself
            name: _name,
            totalSalary: 0,
            lockedLiquidity: 0,
            rewardBalance: 0,
            withdrawnRewards: 0,
            status: Enums.CompanyStatus.Enabled,
            exists: true
        });

        companyList.push(_companyId);

        emit Events.CompanyRegistered(_companyId, _name);
    }

    /**
     * @dev Updates company total salary
     */
    function _updateCompanySalary(address _companyId, uint256 _salary) internal {
        companies[_companyId].totalSalary = _salary;
    }

    /**
     * @dev Updates company locked liquidity
     */
    function _updateCompanyLiquidity(address _companyId, uint256 _amount, bool _add) internal virtual {
        if (_add) {
            companies[_companyId].lockedLiquidity += _amount;
        } else {
            if (companies[_companyId].lockedLiquidity < _amount) {
                revert Errors.InsufficientLiquidity();
            }
            companies[_companyId].lockedLiquidity -= _amount;
        }
    }

    /**
     * @dev Updates company reward balance
     */
    function _updateCompanyReward(address _companyId, uint256 _amount, bool _add) internal virtual {
        if (_add) {
            companies[_companyId].rewardBalance += _amount;
        } else {
            if (companies[_companyId].rewardBalance < _amount) {
                revert Errors.InsufficientBalance();
            }
        companies[_companyId].rewardBalance -= _amount;
        }
    }

    function _updateCompanyAddress(address _oldCompanyId, address _newCompanyId) internal {
        if (_oldCompanyId == address(0) || _newCompanyId == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (!companies[_oldCompanyId].exists) {
            revert Errors.CompanyNotFound();
        }
        if (companies[_newCompanyId].exists) {
            revert Errors.CompanyAlreadyExists();
        }

        // Copy company data and retarget owner/address
        Company memory comp = companies[_oldCompanyId];
        comp.owner = _newCompanyId;

        companies[_newCompanyId] = comp;
        delete companies[_oldCompanyId];

        // Update companyList entry
        uint256 len = companyList.length;
        for (uint256 i = 0; i < len; i++) {
            if (companyList[i] == _oldCompanyId) {
                companyList[i] = _newCompanyId;
                break;
            }
        }

        // Repoint employees to new company id
        uint256 empLen = employeeList.length;
        for (uint256 j = 0; j < empLen; j++) {
            address empAddr = employeeList[j];
            if (employees[empAddr].companyId == _oldCompanyId) {
                employees[empAddr].companyId = _newCompanyId;
            }
        }
    }

    function _setCompanyStatus(address _companyId, Enums.CompanyStatus _status) internal {
        if (!companies[_companyId].exists) {
            revert Errors.CompanyNotFound();
        }
        companies[_companyId].status = _status;
    }

    /**
     * @dev Gets company data
     */
    function getCompany(address _companyId) external view virtual returns (Company memory) {
        return companies[_companyId];
    }
}
