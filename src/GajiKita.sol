// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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
    address public settlementToken; // ERC20 used as accounting base (e.g., USDC)
    address public agniRouter; // active DEX router
    address public dexFactory; // active DEX factory
    address public wNative; // wrapped native for routing
    address public anchorStable; // anchor stable (e.g., USDC/USDT) for routing
    mapping(address => address) public preferredPayoutToken; // employee -> token
    mapping(address => address) public preferredPayoutTokenCompany; // company -> token
    mapping(address => address) public preferredPayoutTokenInvestor; // investor -> token
    mapping(address => bool) public supportedPayoutToken;
    address[] public supportedPayoutTokens;

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
     * @dev Constructor - Initializes the contract and fee config in ERC20-only mode
     * @param _initialOwner owner/admin address
     * @param _settlementToken ERC20 token used as settlement (required, non-zero)
     * @param _router DEX router address (required, non-zero)
     * @param _factory DEX factory address (required, non-zero)
     * @param _wNative Wrapped native token for routing
     * @param _anchorStable Anchor stable token for routing (e.g., USDC/USDT)
     */
    constructor(
        address _initialOwner,
        address _settlementToken,
        address _router,
        address _factory,
        address _wNative,
        address _anchorStable
    ) ReceiptNFTModule(_initialOwner) {
        admins[_initialOwner] = true;

        // Initialize default fee configuration: 80% platform, 20% company, 0% investor, 1% fee
        _initializeFeeConfig(8000, 2000, 0, 100); // 80% platform, 20% company, 0% investor, 1% fee (100 bps)

        if (_settlementToken == address(0) || _router == address(0) || _factory == address(0)) {
            revert Errors.ZeroAddress();
        }

        settlementToken = _settlementToken;
        agniRouter = _router;
        dexFactory = _factory;
        wNative = _wNative;
        anchorStable = _anchorStable;
        supportedPayoutToken[_settlementToken] = true;
        supportedPayoutTokens.push(_settlementToken);
        emit Events.Erc20Initialized(_settlementToken, _router);
    }

    /**
     * @dev Function to set preferred payout token for employee
     */
    function setPreferredPayoutToken(
        address token
    ) external onlyEmployee(msg.sender) {
        if (!supportedPayoutToken[token]) {
            revert Errors.TokenNotSupported();
        }
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
     * @dev Update company address (admin/owner only)
     */
    function updateCompanyAddress(address _oldCompanyId, address _newCompanyId) external {
        if ((msg.sender != owner()) && !admins[msg.sender]) {
            revert Errors.Unauthorized();
        }
        _updateCompanyAddress(_oldCompanyId, _newCompanyId);
    }

    /**
     * @dev Enable a company (admin/owner only)
     */
    function enableCompany(address _companyId) external {
        if ((msg.sender != owner()) && !admins[msg.sender]) {
            revert Errors.Unauthorized();
        }
        _setCompanyStatus(_companyId, Enums.CompanyStatus.Enabled);
    }

    /**
     * @dev Disable a company (admin/owner only)
     */
    function disableCompany(address _companyId) external {
        if ((msg.sender != owner()) && !admins[msg.sender]) {
            revert Errors.Unauthorized();
        }
        _setCompanyStatus(_companyId, Enums.CompanyStatus.Disabled);
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
     * @dev Allows a company to lock liquidity using tokens
     */
    function lockCompanyLiquidityToken(
        uint256 amount,
        string calldata cid
    ) external onlyCompany(msg.sender) nonReentrant {
        SafeERC20.safeTransferFrom(
            IERC20(settlementToken),
            msg.sender,
            address(this),
            amount
        );
        _lockCompanyLiquidity(msg.sender, amount, cid);
    }

    /**
     * @dev Allows an investor to deposit liquidity using tokens
     */
    function depositInvestorLiquidityToken(
        uint256 amount,
        string calldata cid
    ) external nonReentrant {
        SafeERC20.safeTransferFrom(
            IERC20(settlementToken),
            msg.sender,
            address(this),
            amount
        );
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
    function withdrawAllInvestorLiquidity(
        string memory _cid
    ) external nonReentrant {
        if (!investors[msg.sender].exists) {
            revert Errors.InvestorNotFound();
        }
        uint256 amount = investors[msg.sender].deposited;
        _withdrawInvestorLiquidity(msg.sender, amount, _cid);
    }

    /**
     * @dev Allows platform owner to withdraw fee
     */
    function withdrawPlatformFee(
        uint256 _amount,
        string memory _cid
    ) external nonReentrant {
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
    function removeAdmin(address _admin) external onlyAdmin {
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
     * @dev Set preferred payout token for a company
     */
    function setCompanyPayoutToken(address _companyId, address token) external {
        if ((msg.sender != owner()) && !admins[msg.sender] && msg.sender != _companyId) {
            revert Errors.Unauthorized();
        }
        if (!supportedPayoutToken[token]) {
            revert Errors.TokenNotSupported();
        }
        preferredPayoutTokenCompany[_companyId] = token;
        emit Events.PreferredCompanyPayoutTokenSet(_companyId, token);
    }

    /**
     * @dev Set preferred payout token for an investor
     */
    function setInvestorPayoutToken(address token) external {
        if (!investors[msg.sender].exists) {
            revert Errors.InvestorNotFound();
        }
        if (!supportedPayoutToken[token]) {
            revert Errors.TokenNotSupported();
        }
        preferredPayoutTokenInvestor[msg.sender] = token;
        emit Events.PreferredInvestorPayoutTokenSet(msg.sender, token);
    }

    /**
     * @dev Add a supported payout token (admin/owner only)
     */
    function addSupportedPayoutToken(address token) external {
        if ((msg.sender != owner()) && !admins[msg.sender]) {
            revert Errors.Unauthorized();
        }
        if (token == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (supportedPayoutToken[token]) {
            return;
        }
        supportedPayoutToken[token] = true;
        supportedPayoutTokens.push(token);
        emit Events.SupportedPayoutTokenAdded(token);
    }

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
    function initialize(address _initialOwner) external onlyAdmin {
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
     * @dev Returns supported payout tokens
     */
    function getSupportedPayoutTokens() external view returns (address[] memory) {
        return supportedPayoutTokens;
    }

    /**
     * @dev Returns company status
     */
    function getCompanyStatus(address _companyId)
        external
        view
        returns (Enums.CompanyStatus status)
    {
        return companies[_companyId].status;
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
     * Pays in settlement token or swapped token (ERC20-only)
     */
    function _payoutEmployee(
        address to,
        uint256 amount
    ) internal override(WithdrawalModule) {
        _payoutWithPreference(to, amount, preferredPayoutToken[to]);
    }

    /**
     * @dev Implementation of the general payout function
     * Pays in settlementToken (no swaps for rewards in this path)
     */
    function _payout(
        address to,
        uint256 amount
    ) internal override(LiquidityPoolModule) {
        address pref;
        if (companies[to].exists) {
            pref = preferredPayoutTokenCompany[to];
        } else if (investors[to].exists) {
            pref = preferredPayoutTokenInvestor[to];
        }
        _payoutWithPreference(to, amount, pref, 0, block.timestamp + 300);
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

        uint256 eligibleAmount = _calculateEmployeeEligibleWithdrawal(
            employeeId
        );
        if (eligibleAmount == 0) {
            revert Errors.InvalidAmount();
        }

        // Calculate fees
        (
            uint256 feeTotal,
            uint256 platformPart,
            uint256 companyPart,

        ) = _calculateFee(eligibleAmount);

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
        _distributeInvestorFee(eligibleAmount - netAmount - platformPart - companyPart);

        // Update employee withdrawn amount
        _updateEmployeeWithdrawnAmount(employeeId, netAmount);

        // Mint receipt NFT
        _mintReceipt(
            msg.sender,
            Enums.TxType.EmployeeWithdrawSalary,
            eligibleAmount,
            cid
        );

        // Payout with swap based on preference
        _payoutWithPreference(employeeId, netAmount, preferredPayoutToken[employeeId], minOut, deadline);

        emit Events.EmployeeSalaryWithdrawn(employeeId, netAmount);
    }

    /**
     * @dev Internal helper to payout in settlement token or swap to preferred token
     */
    function _payoutWithPreference(
        address to,
        uint256 amount,
        address desiredToken
    ) internal {
        _payoutWithPreference(to, amount, desiredToken, 0, block.timestamp + 300);
    }

    function _payoutWithPreference(
        address to,
        uint256 amount,
        address desiredToken,
        uint256 minOut,
        uint256 deadline
    ) internal {
        if (amount == 0) {
            return;
        }

        address target = desiredToken;
        if (target == address(0) || !supportedPayoutToken[target]) {
            target = settlementToken;
        }

        if (target == settlementToken) {
            SafeERC20.safeTransfer(IERC20(settlementToken), to, amount);
            return;
        }

        // Swap settlementToken -> target via simple 2-hop path
        address[] memory path = new address[](2);
        path[0] = settlementToken;
        path[1] = target;

        IERC20(settlementToken).approve(agniRouter, 0);
        IERC20(settlementToken).approve(agniRouter, amount);
        IAgniRouter(agniRouter).swapExactTokensForTokens(
            amount,
            minOut,
            path,
            to,
            deadline
        );
    }
}
