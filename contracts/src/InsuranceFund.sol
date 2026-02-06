// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title InsuranceFund
 * @author LEVER Protocol
 * @notice Insurance fund that covers bad debt and affects risk parameters
 * @dev Funded by:
 *      - Portion of liquidation penalties
 *      - Portion of trading fees
 *      - Portion of borrow fees
 *      
 * Used for:
 *      - Covering bad debt (underwater liquidations)
 *      - Dynamic risk parameter adjustment
 */

import {IERC20} from "./interfaces/IERC20.sol";

contract InsuranceFund {
    
    // ============ State ============
    
    address public owner;
    IERC20 public immutable collateralToken;  // USDT
    
    // Fund balance
    uint256 public totalFunds;
    
    // Fee allocation (basis points)
    uint256 public liquidationFeeShare = 4000;  // 40% of liquidation penalty
    uint256 public tradingFeeShare = 2000;      // 20% of trading fees
    uint256 public borrowFeeShare = 1000;       // 10% of borrow fees
    
    // Thresholds for risk adjustment
    uint256 public healthyThreshold = 100_000e18;    // 100k USDT = healthy
    uint256 public warningThreshold = 50_000e18;     // 50k USDT = warning
    uint256 public criticalThreshold = 10_000e18;    // 10k USDT = critical
    
    // Authorized contracts
    mapping(address => bool) public authorizedDepositors;
    mapping(address => bool) public authorizedWithdrawers;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant PRECISION = 1e18;
    
    // ============ Events ============
    
    event FundsDeposited(address indexed from, uint256 amount, string reason);
    event FundsWithdrawn(address indexed to, uint256 amount, string reason);
    event BadDebtCovered(uint256 amount, uint256 remainingFunds);
    event ThresholdsUpdated(uint256 healthy, uint256 warning, uint256 critical);
    
    // ============ Errors ============
    
    error Unauthorized();
    error InsufficientFunds();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyDepositor() {
        if (!authorizedDepositors[msg.sender]) revert Unauthorized();
        _;
    }
    
    modifier onlyWithdrawer() {
        if (!authorizedWithdrawers[msg.sender]) revert Unauthorized();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _collateralToken) {
        owner = msg.sender;
        collateralToken = IERC20(_collateralToken);
    }
    
    // ============ Admin Functions ============
    
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
    
    function setDepositorAuthorization(address depositor, bool authorized) external onlyOwner {
        authorizedDepositors[depositor] = authorized;
    }
    
    function setWithdrawerAuthorization(address withdrawer, bool authorized) external onlyOwner {
        authorizedWithdrawers[withdrawer] = authorized;
    }
    
    function setFeeShares(
        uint256 _liquidationShare,
        uint256 _tradingShare,
        uint256 _borrowShare
    ) external onlyOwner {
        liquidationFeeShare = _liquidationShare;
        tradingFeeShare = _tradingShare;
        borrowFeeShare = _borrowShare;
    }
    
    function setThresholds(
        uint256 _healthy,
        uint256 _warning,
        uint256 _critical
    ) external onlyOwner {
        require(_healthy > _warning && _warning > _critical, "Invalid thresholds");
        healthyThreshold = _healthy;
        warningThreshold = _warning;
        criticalThreshold = _critical;
        emit ThresholdsUpdated(_healthy, _warning, _critical);
    }
    
    // ============ Deposit Functions ============
    
    /**
     * @notice Deposit funds from liquidation penalties
     */
    function depositFromLiquidation(uint256 totalPenalty) external onlyDepositor {
        uint256 amount = (totalPenalty * liquidationFeeShare) / BASIS_POINTS;
        _deposit(amount, "liquidation");
    }
    
    /**
     * @notice Deposit funds from trading fees
     */
    function depositFromTradingFees(uint256 totalFees) external onlyDepositor {
        uint256 amount = (totalFees * tradingFeeShare) / BASIS_POINTS;
        _deposit(amount, "trading_fees");
    }
    
    /**
     * @notice Deposit funds from borrow fees
     */
    function depositFromBorrowFees(uint256 totalFees) external onlyDepositor {
        uint256 amount = (totalFees * borrowFeeShare) / BASIS_POINTS;
        _deposit(amount, "borrow_fees");
    }
    
    /**
     * @notice Direct deposit (for initial funding or top-ups)
     */
    function deposit(uint256 amount) external {
        collateralToken.transferFrom(msg.sender, address(this), amount);
        totalFunds += amount;
        emit FundsDeposited(msg.sender, amount, "direct");
    }
    
    // ============ Withdrawal Functions ============
    
    /**
     * @notice Cover bad debt from underwater liquidation
     * @param amount Amount of bad debt to cover
     * @return covered Amount actually covered (may be less if fund depleted)
     */
    function coverBadDebt(uint256 amount) external onlyWithdrawer returns (uint256 covered) {
        covered = amount > totalFunds ? totalFunds : amount;
        
        if (covered > 0) {
            totalFunds -= covered;
            collateralToken.transfer(msg.sender, covered);
            emit BadDebtCovered(covered, totalFunds);
        }
    }
    
    /**
     * @notice Emergency withdrawal by owner
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        require(amount <= totalFunds, "Insufficient funds");
        totalFunds -= amount;
        collateralToken.transfer(to, amount);
        emit FundsWithdrawn(to, amount, "emergency");
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get current health status of the insurance fund
     * @return status 0 = critical, 1 = warning, 2 = healthy
     */
    function getHealthStatus() external view returns (uint8 status) {
        if (totalFunds >= healthyThreshold) return 2;  // Healthy
        if (totalFunds >= warningThreshold) return 1;  // Warning
        return 0;  // Critical
    }
    
    /**
     * @notice Get risk adjustment factor based on fund health
     * @return factor Multiplier for risk parameters (1e18 = 100%)
     * 
     * When fund is healthy: factor = 1.0 (no adjustment)
     * When fund is warning: factor = 0.75 (reduce leverage by 25%)
     * When fund is critical: factor = 0.5 (reduce leverage by 50%)
     */
    function getRiskAdjustmentFactor() external view returns (uint256 factor) {
        if (totalFunds >= healthyThreshold) {
            return PRECISION;  // 100%
        } else if (totalFunds >= warningThreshold) {
            // Linear interpolation between warning (75%) and healthy (100%)
            uint256 range = healthyThreshold - warningThreshold;
            uint256 position = totalFunds - warningThreshold;
            return (75 * PRECISION / 100) + (25 * PRECISION / 100) * position / range;
        } else if (totalFunds >= criticalThreshold) {
            // Linear interpolation between critical (50%) and warning (75%)
            uint256 range = warningThreshold - criticalThreshold;
            uint256 position = totalFunds - criticalThreshold;
            return (50 * PRECISION / 100) + (25 * PRECISION / 100) * position / range;
        } else {
            // Below critical - minimum 50%
            return 50 * PRECISION / 100;
        }
    }
    
    /**
     * @notice Get maximum OI adjustment based on fund health
     * @param baseMaxOI The base maximum OI
     * @return adjustedMaxOI The adjusted maximum OI
     */
    function getAdjustedMaxOI(uint256 baseMaxOI) external view returns (uint256) {
        uint256 factor = this.getRiskAdjustmentFactor();
        return (baseMaxOI * factor) / PRECISION;
    }
    
    /**
     * @notice Get maximum leverage adjustment based on fund health
     * @param baseMaxLeverage The base maximum leverage
     * @return adjustedMaxLeverage The adjusted maximum leverage
     */
    function getAdjustedMaxLeverage(uint256 baseMaxLeverage) external view returns (uint256) {
        uint256 factor = this.getRiskAdjustmentFactor();
        return (baseMaxLeverage * factor) / PRECISION;
    }
    
    /**
     * @notice Check if fund can cover potential bad debt
     * @param potentialLoss Estimated potential loss
     */
    function canCoverLoss(uint256 potentialLoss) external view returns (bool) {
        return totalFunds >= potentialLoss;
    }
    
    // ============ Internal Functions ============
    
    function _deposit(uint256 amount, string memory reason) internal {
        if (amount == 0) return;
        
        collateralToken.transferFrom(msg.sender, address(this), amount);
        totalFunds += amount;
        
        emit FundsDeposited(msg.sender, amount, reason);
    }
}
