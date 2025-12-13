// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {CompanyModule} from "./modules/CompanyModule.sol";
import {EmployeeModule} from "./modules/EmployeeModule.sol";
import {WithdrawalModule} from "./modules/WithdrawalModule.sol";
import {FeeModule} from "./modules/FeeModule.sol";
import {LiquidityPoolModule} from "./modules/LiquidityPoolModule.sol";
import {ReceiptNFTModule} from "./modules/ReceiptNFTModule.sol";
import {Constants} from "./utils/Constants.sol";
import {Enums} from "./utils/Enums.sol";
import {Errors} from "./utils/Errors.sol";
import {Events} from "./utils/Events.sol";
import {IAgniRouter} from "./utils/TokenInterfaces.sol";


/**
 * @title GajiKita
 * @dev Main contract that combines all modules for the salary management system
 */
contract GajiKita is
    CompanyModule,
    EmployeeModule,
    WithdrawalModule,
    FeeModule,
    LiquidityPoolModule,
    ReceiptNFTModule,
    IERC721Receiver,
    ReentrancyGuard
{
    mapping(address => bool) private admins;

    // ERC20 Settlement Token Variables
    address public settlementToken;  // ERC20 used as accounting base (e.g., USDC)
    address public agniRouter;       // router on Mantle
    mapping(address => address) public preferredPayoutToken; // employee -> token
    bool public erc20Enabled;        // switch mode (ETH legacy vs ERC20)

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    function _onlyAdmin() internal view {
        if (!admins[msg.sender]) {
            revert Errors.Unauthorized();
        }
    }

    /**
     * @dev Initialize ERC20 configuration
     * Can be called only by owner or admin, and only once
     */
    function initializeErc20(
        address _settlementToken,
        address _agniRouter
    ) external {
        // Check if caller is either owner or admin
        if ((msg.sender != owner()) && !admins[msg.sender]) {
            revert Errors.Unauthorized();
        }

        // Check if already initialized
        if (erc20Enabled) {
            revert Errors.Unauthorized(); // Using Unauthorized as "already initialized"
        }

        // Initialize ERC20 configuration
        settlementToken = _settlementToken;
        agniRouter = _agniRouter;
        erc20Enabled = true;

        emit Events.Erc20Initialized(_settlementToken, _agniRouter);
    }

    /**
     * @dev Constructor - Initializes the contract and default fee configuration
     */
    constructor(address _initialOwner) ReceiptNFTModule(_initialOwner) {
        admins[_initialOwner] = true;

        // Initialize default fee configuration: 80% platform, 20% company, 0% investor, 1% fee
        _initializeFeeConfig(8000, 2000, 0, 100); // 80% platform, 20% company, 0% investor, 1% fee (100 bps)
    }

    /**
     * @dev Function to set preferred payout token for employee
     */
    function setPreferredPayoutToken(address token) external onlyEmployee(msg.sender) {
        preferredPayoutToken[msg.sender] = token;

        emit Events.PreferredPayoutTokenSet(msg.sender, token);
    }

    /**
     * @dev Function to register a new company
     */
    function registerCompany(
        address _companyId,
        string memory _name
    ) external onlyAdmin {
        _addCompany(_companyId, _name);
    }

    /**
     * @dev Function to add an employee
     */
    function addEmployee(
        address _employeeId,
        address _companyId,
        string memory _name,
        uint256 _monthlySalary
    ) external onlyAdmin {
        _addEmployee(_employeeId, _companyId, _name, _monthlySalary);
    }

    /**
     * @dev Allows a company to lock liquidity
     */
    function lockCompanyLiquidity(
        uint256 _amount,
        string memory _cid
    ) external payable onlyCompany(msg.sender) nonReentrant {
        if (msg.value != _amount) {
            revert Errors.InvalidAmount();
        }
        _lockCompanyLiquidity(msg.sender, _amount, _cid);
    }

    /**
     * @dev Allows an investor to deposit liquidity
     */
    function depositInvestorLiquidity(string memory _cid) external payable nonReentrant {
        if (msg.value == 0) {
            revert Errors.InvalidAmount();
        }
        _depositInvestorLiquidity(msg.sender, msg.value, _cid);
    }

    /**
     * @dev Allows a company to lock liquidity using tokens
     */
    function lockCompanyLiquidityToken(uint256 amount, string calldata cid) external onlyCompany(msg.sender) nonReentrant {
        require(erc20Enabled, "ERC20 not enabled");
        SafeERC20.safeTransferFrom(IERC20(settlementToken), msg.sender, address(this), amount);
        _lockCompanyLiquidity(msg.sender, amount, cid);
    }

    /**
     * @dev Allows an investor to deposit liquidity using tokens
     */
    function depositInvestorLiquidityToken(uint256 amount, string calldata cid) external nonReentrant {
        require(erc20Enabled, "ERC20 not enabled");
        SafeERC20.safeTransferFrom(IERC20(settlementToken), msg.sender, address(this), amount);
        _depositInvestorLiquidity(msg.sender, amount, cid);
    }

    /**
     * @dev Allows an employee to withdraw salary
     */
    function withdrawSalary(
        string memory _cid
    ) external onlyEmployee(msg.sender) nonReentrant {
        _withdrawEmployeeSalary(msg.sender, _cid);
    }

    /**
     * @dev Allows a company to withdraw reward
     */
    function withdrawCompanyReward(
        uint256 _amount,
        string memory _cid
    ) external onlyCompany(msg.sender) nonReentrant {
        _withdrawCompanyReward(msg.sender, _amount, _cid);
    }

    /**
     * @dev Allows an investor to withdraw reward
     */
    function withdrawInvestorReward(
        uint256 _amount,
        string memory _cid
    ) external nonReentrant {
        if (!investors[msg.sender].exists) {
            revert Errors.InvestorNotFound();
        }
        _withdrawInvestorReward(msg.sender, _amount, _cid);
    }

    /**
     * @dev Allows an investor to withdraw all liquidity
     */
    function withdrawAllInvestorLiquidity(string memory _cid) external nonReentrant {
        if (!investors[msg.sender].exists) {
            revert Errors.InvestorNotFound();
        }
        uint256 amount = investors[msg.sender].deposited;
        _withdrawInvestorLiquidity(msg.sender, amount, _cid);
    }

    /**
     * @dev Allows platform owner to withdraw fee
     */
    function withdrawPlatformFee(uint256 _amount, string memory _cid) external nonReentrant {
        // Check if caller is either the owner (via Ownable) or in our admin mapping
        if ((msg.sender != owner()) && !admins[msg.sender]) {
            revert Errors.Unauthorized();
        }
        _withdrawPlatformFee(owner(), _amount, _cid);
    }

    /**
     * @dev Override the _calculateEmployeeEligibleWithdrawal function from WithdrawalModule
     */
    function _calculateEmployeeEligibleWithdrawal(
        address _employeeId
    )
        internal
        view
        override(EmployeeModule, WithdrawalModule)
        returns (uint256)
    {
        Employee memory emp = employees[_employeeId];
        uint256 salaryPerDay = emp.monthlySalary / 30; // Assuming 30 days in a month
        uint256 amountBasedOnDays = salaryPerDay * emp.daysWorked;

        // Calculate max allowed based on percentage of monthly salary
        uint256 maxAllowed = (emp.monthlySalary *
            Constants.MAX_SALARY_PERCENTAGE) / 100; // 30% of monthly salary

        // Return the minimum of the two amounts to limit withdrawal
        uint256 eligibleAmount = amountBasedOnDays < maxAllowed
            ? amountBasedOnDays
            : maxAllowed;

        // Subtract already withdrawn amount
        if (eligibleAmount <= emp.withdrawnAmount) {
            return 0;
        }

        return eligibleAmount - emp.withdrawnAmount;
    }

    /**
     * @dev Override the _calculateFee function from FeeModule
     */
    function _calculateFee(
        uint256 amount
    )
        internal
        view
        override(FeeModule, WithdrawalModule)
        returns (
            uint256 feeTotal,
            uint256 platformPart,
            uint256 companyPart,
            uint256 investorPart
        )
    {
        // Calculate base fee
        feeTotal = (amount * feeConfig.feeBps) / Constants.BPS_DENOMINATOR;

        // Calculate portions based on configuration
        platformPart =
            (feeTotal * feeConfig.platformShare) /
            Constants.BPS_DENOMINATOR;
        companyPart =
            (feeTotal * feeConfig.companyShare) /
            Constants.BPS_DENOMINATOR;
        investorPart =
            (feeTotal * feeConfig.investorShare) /
            Constants.BPS_DENOMINATOR;
    }

    /**
     * @dev Override the _updateCompanyLiquidity function to resolve multiple inheritance
     */
    function _updateCompanyLiquidity(
        address _companyId,
        uint256 _amount,
        bool _add
    ) internal override(CompanyModule, LiquidityPoolModule) {
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
     * @dev Override the _updateCompanyReward function to resolve multiple inheritance
     */
    function _updateCompanyReward(
        address _companyId,
        uint256 _amount,
        bool _add
    ) internal override(CompanyModule, LiquidityPoolModule, WithdrawalModule) {
        if (_add) {
            companies[_companyId].rewardBalance += _amount;
        } else {
            if (companies[_companyId].rewardBalance < _amount) {
                revert Errors.InsufficientBalance();
            }
            companies[_companyId].rewardBalance -= _amount;
        }
    }

    /**
     * @dev Override the _updateEmployeeWithdrawnAmount function to resolve multiple inheritance
     */
    function _updateEmployeeWithdrawnAmount(
        address _employeeId,
        uint256 _amount
    ) internal override(EmployeeModule, WithdrawalModule) {
        employees[_employeeId].withdrawnAmount += _amount;
    }

    /**
     * @dev Override the _updatePoolLiquidity function from LiquidityPoolModule
     */
    function _updatePoolLiquidity(
        uint256 _amount,
        bool _add
    ) internal override(LiquidityPoolModule, WithdrawalModule) {
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
     * @dev Override the _mintReceipt function from ReceiptNFTModule
     */
    function _mintReceipt(
        address _to,
        Enums.TxType _txType,
        uint256 _amount,
        string memory _cid
    )
        internal
        override(ReceiptNFTModule, LiquidityPoolModule, WithdrawalModule)
    {
        super._mintReceipt(_to, _txType, _amount, _cid);
    }

    /**
     * @dev Route investor fee distribution to LiquidityPoolModule implementation
     */
    function _handleInvestorFeeDistribution(
        uint256 investorPart
    ) internal override {
        LiquidityPoolModule._distributeInvestorFee(investorPart);
    }

    /**
     * @dev Function to update fee configuration (only owner)
     */
    function updateFeeConfig(
        uint256 _platformShare,
        uint256 _companyShare,
        uint256 _investorShare,
        uint256 _feeBps
    ) external {
        // Check if caller is either the owner (via Ownable) or in our admin mapping
        if ((msg.sender != owner()) && !admins[msg.sender]) {
            revert Errors.Unauthorized();
        }
        _updateFeeConfig(
            _platformShare,
            _companyShare,
            _investorShare,
            _feeBps
        );
    }

    /**
     * @dev Function to add an admin (only owner)
     */
    function addAdmin(address _admin) external {
        // Check if caller is either the owner (via Ownable) or in our admin mapping
        if ((msg.sender != owner()) && !admins[msg.sender]) {
            revert Errors.Unauthorized();
        }
        admins[_admin] = true;
    }

    /**
     * @dev Function to remove an admin (owner or admin only)
     */
    function removeAdmin(address _admin) external {
        // Check if caller is either the owner (via Ownable) or in our admin mapping
        if ((msg.sender != owner()) && !admins[msg.sender]) {
            revert Errors.Unauthorized();
        }
        if (_admin == owner()) {
            revert Errors.Unauthorized(); // Cannot remove owner
        }
        admins[_admin] = false;
    }

    /**
     * @dev Function to update employee days worked (only admin)
     */
    function updateEmployeeDaysWorked(
        address _employeeId,
        uint256 _days
    ) external onlyAdmin {
        if (!employees[_employeeId].exists) {
            revert Errors.EmployeeNotFound();
        }
        _updateEmployeeDaysWorked(_employeeId, _days);
    }

    /**
     * @dev Function to accept ETH transfers
     */
    receive() external payable {}

    /**
     * @dev Function to accept ETH transfers
     */
    fallback() external payable {}

    /**
     * @dev Implementation of IERC721Receiver interface
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev Initialize the contract state when used behind a proxy
     * This can only be called once to prevent misuse
     */
    function initialize(address _initialOwner) external {
        // Prevent re-initialization - check that the contract hasn't been initialized
        // In the proxy context, the owner should still be address(0) if not init
        // However, Ownable doesn't offer an easy initialization check
        // We'll use our admin mapping as a proxy for initialization
        require(!admins[_initialOwner], "Already initialized");

        // Initialize the admin
        admins[_initialOwner] = true;
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the owner of the contract
     */
    function contractOwner() public view returns (address) {
        return owner();
    }

    /**
     * @dev Returns if an address is an admin
     */
    function isAdmin(address _admin) public view returns (bool) {
        return admins[_admin];
    }

    /**
     * @dev Returns company data
     */
    function getCompanyInfo(
        address _companyId
    ) external view returns (bool exists, string memory name) {
        Company memory company = companies[_companyId];
        return (company.exists, company.name);
    }

    /**
     * @dev Returns employee data
     */
    function getEmployeeInfo(
        address _employeeId
    )
        external
        view
        returns (
            bool exists,
            address companyId,
            string memory name,
            uint256 monthlySalary,
            uint256 daysWorked,
            uint256 withdrawnAmount
        )
    {
        Employee memory emp = employees[_employeeId];
        return (
            emp.exists,
            emp.companyId,
            emp.name,
            emp.monthlySalary,
            emp.daysWorked,
            emp.withdrawnAmount
        );
    }

    /**
     * @dev Returns the eligible withdrawal amount for an employee
     */
    function calculateEmployeeEligibleWithdrawal(
        address _employeeId
    ) external view returns (uint256) {
        return _calculateEmployeeEligibleWithdrawal(_employeeId);
    }

    /**
     * @dev Returns company liquidity data
     */
    function getCompanyLiquidity(
        address _companyId
    )
        external
        view
        returns (uint256 locked, uint256 totalRewards, uint256 withdrawnRewards)
    {
        Company memory company = companies[_companyId];
        return (
            company.lockedLiquidity,
            company.rewardBalance, // Available rewards to withdraw
            company.withdrawnRewards // Total rewards withdrawn so far
        );
    }

    /**
     * @dev Returns investor data
     */
    function getInvestor(
        address _investorId
    )
        external
        view
        returns (
            bool exists,
            uint256 deposited,
            uint256 totalRewards,
            uint256 withdrawnRewards
        )
    {
        Investor memory investor = investors[_investorId];
        return (
            investor.exists,
            investor.deposited,
            investor.rewardBalance, // Available rewards to withdraw
            investor.withdrawnRewards // Total rewards withdrawn so far
        );
    }

    /**
     * @dev Returns the fee configuration
     */
    function getFeeConfiguration()
        external
        view
        returns (
            uint256 platformShare,
            uint256 companyShare,
            uint256 investorShare,
            uint256 feeBps
        )
    {
        FeeConfig memory config = feeConfig;
        return (
            config.platformShare,
            config.companyShare,
            config.investorShare,
            config.feeBps
        );
    }

    /*//////////////////////////////////////////////////////////////
                            PAYOUT FUNCTION IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Implementation of the employee payout function
     * If erc20Enabled is false, pays in ETH
     * If erc20Enabled is true, pays in settlementToken or swapped token
     */
    function _payoutEmployee(address to, uint256 amount) internal override(WithdrawalModule) {
        if (!erc20Enabled) {
            // Legacy ETH payout
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) {
                revert Errors.TransferNotAllowed();
            }
        } else {
            // ERC20 payout in settlement token only (no swap)
            SafeERC20.safeTransfer(IERC20(settlementToken), to, amount);
        }
    }

    /**
     * @dev Implementation of the general payout function
     * If erc20Enabled is false, pays in ETH
     * If erc20Enabled is true, pays in settlementToken (no swaps for rewards)
     */
    function _payout(address to, uint256 amount) internal override(LiquidityPoolModule) {
        if (!erc20Enabled) {
            // Legacy ETH payout
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) {
                revert Errors.TransferNotAllowed();
            }
        } else {
            // ERC20 payout in settlement token (no swaps for rewards/principal)
            SafeERC20.safeTransfer(IERC20(settlementToken), to, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SWAPPING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allows an employee to withdraw salary with optional token swap for preferred payout
     */
    function withdrawSalaryWithSwap(
        string calldata cid,
        uint256 minOut,
        uint256 deadline
    ) external onlyEmployee(msg.sender) nonReentrant {
        require(erc20Enabled, "ERC20 not enabled");
        _withdrawEmployeeSalaryWithSwap(msg.sender, cid, minOut, deadline);
    }

    /**
     * @dev Internal function to withdraw employee salary with token swap
     */
    function _withdrawEmployeeSalaryWithSwap(
        address employeeId,
        string memory cid,
        uint256 minOut,
        uint256 deadline
    ) internal virtual {
        Employee storage emp = employees[employeeId];
        if (!emp.exists) {
            revert Errors.EmployeeNotFound();
        }

        uint256 eligibleAmount = _calculateEmployeeEligibleWithdrawal(employeeId);
        if (eligibleAmount == 0) {
            revert Errors.InvalidAmount();
        }

        // Calculate fees
        (uint256 feeTotal, uint256 platformPart, uint256 companyPart,) =
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

        // Investors get a portion too
        // Note: This is simplified; in practice, investor rewards are typically handled differently

        // Update employee withdrawn amount
        _updateEmployeeWithdrawnAmount(employeeId, netAmount);

        // Mint receipt NFT
        _mintReceipt(msg.sender, Enums.TxType.EmployeeWithdrawSalary, eligibleAmount, cid);

        // Determine desired token for payout
        address desiredToken = preferredPayoutToken[employeeId];
        if (desiredToken == address(0)) {
            desiredToken = settlementToken;
        }

        if (desiredToken == settlementToken) {
            // Direct settlement token payout
            SafeERC20.safeTransfer(IERC20(settlementToken), employeeId, netAmount);
        } else {
            // Approve settlement token for swap - first reset to 0, then set desired amount
            IERC20(settlementToken).approve(agniRouter, 0);
            IERC20(settlementToken).approve(agniRouter, netAmount);
            address[] memory path = new address[](2);
            path[0] = settlementToken;
            path[1] = desiredToken;

            IAgniRouter(agniRouter).swapExactTokensForTokens(
                netAmount,
                minOut,
                path,
                employeeId,
                deadline
            );
        }

        emit Events.EmployeeSalaryWithdrawn(employeeId, netAmount);
    }
}
