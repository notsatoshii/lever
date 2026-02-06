// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RiskEngine
 * @author LEVER Protocol
 * @notice Margin calculations, borrow fees, and risk parameters
 * @dev Answers: "How expensive is it to use LP capital right now?"
 * 
 * Controls:
 * - Initial margin (IM) requirements
 * - Maintenance margin (MM) requirements
 * - Borrow fees based on utilization
 * - Leverage limits per market
 * - OI caps
 * - Emergency throttles
 */

import {IPositionLedger} from "./interfaces/IPositionLedger.sol";

contract RiskEngine {
    
    // ============ Structs ============
    
    struct RiskParams {
        uint256 initialMarginBps;    // Initial margin in basis points (e.g., 1000 = 10%)
        uint256 maintenanceMarginBps; // Maintenance margin in bps (e.g., 500 = 5%)
        uint256 maxLeverage;         // Max leverage (e.g., 10 = 10x)
        uint256 baseBorrowRate;      // Base borrow rate per year (18 decimals)
        uint256 maxBorrowRate;       // Max borrow rate at full utilization
        uint256 optimalUtilization;  // Utilization target (e.g., 0.8e18 = 80%)
        uint256 liquidationPenaltyBps; // Liquidation penalty in bps
    }
    
    struct UtilizationData {
        uint256 totalOI;             // Total open interest
        uint256 totalLPCapital;      // Total LP capital available
        uint256 utilization;         // Current utilization rate
        uint256 currentBorrowRate;   // Current annualized borrow rate
    }
    
    // ============ State ============
    
    address public owner;
    IPositionLedger public immutable ledger;
    
    // marketId => RiskParams
    mapping(uint256 => RiskParams) public riskParams;
    
    // Total LP capital per market (set by LP engine or admin)
    mapping(uint256 => uint256) public lpCapital;
    
    // marketId => cumulative borrow index
    mapping(uint256 => uint256) public borrowIndex;
    mapping(uint256 => uint256) public lastBorrowUpdate;
    
    // Emergency controls
    mapping(uint256 => bool) public marketPaused;
    bool public globalPause;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    
    // ============ Events ============
    
    event RiskParamsSet(uint256 indexed marketId, uint256 imBps, uint256 mmBps, uint256 maxLeverage);
    event LPCapitalUpdated(uint256 indexed marketId, uint256 newCapital);
    event BorrowIndexUpdated(uint256 indexed marketId, uint256 newIndex, uint256 borrowRate);
    event MarketPaused(uint256 indexed marketId, bool paused);
    event GlobalPauseSet(bool paused);
    
    // ============ Errors ============
    
    error Unauthorized();
    error MarketNotConfigured();
    error MarketPausedError();
    error InsufficientMargin();
    error ExceedsMaxLeverage();
    error GloballyPaused();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier notPaused(uint256 marketId) {
        if (globalPause) revert GloballyPaused();
        if (marketPaused[marketId]) revert MarketPausedError();
        _;
    }
    
    modifier marketConfigured(uint256 marketId) {
        if (riskParams[marketId].initialMarginBps == 0) revert MarketNotConfigured();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _ledger) {
        owner = msg.sender;
        ledger = IPositionLedger(_ledger);
    }
    
    // ============ Admin Functions ============
    
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
    
    function setRiskParams(
        uint256 marketId,
        uint256 initialMarginBps,
        uint256 maintenanceMarginBps,
        uint256 maxLeverage,
        uint256 baseBorrowRate,
        uint256 maxBorrowRate,
        uint256 optimalUtilization,
        uint256 liquidationPenaltyBps
    ) external onlyOwner {
        require(maintenanceMarginBps < initialMarginBps, "MM must be < IM");
        require(maxLeverage > 0, "Invalid leverage");
        
        riskParams[marketId] = RiskParams({
            initialMarginBps: initialMarginBps,
            maintenanceMarginBps: maintenanceMarginBps,
            maxLeverage: maxLeverage,
            baseBorrowRate: baseBorrowRate,
            maxBorrowRate: maxBorrowRate,
            optimalUtilization: optimalUtilization,
            liquidationPenaltyBps: liquidationPenaltyBps
        });
        
        // Initialize borrow index
        if (borrowIndex[marketId] == 0) {
            borrowIndex[marketId] = PRECISION;
            lastBorrowUpdate[marketId] = block.timestamp;
        }
        
        emit RiskParamsSet(marketId, initialMarginBps, maintenanceMarginBps, maxLeverage);
    }
    
    function setLPCapital(uint256 marketId, uint256 capital) external onlyOwner {
        lpCapital[marketId] = capital;
        emit LPCapitalUpdated(marketId, capital);
    }
    
    function setMarketPaused(uint256 marketId, bool paused) external onlyOwner {
        marketPaused[marketId] = paused;
        emit MarketPaused(marketId, paused);
    }
    
    function setGlobalPause(bool paused) external onlyOwner {
        globalPause = paused;
        emit GlobalPauseSet(paused);
    }
    
    // ============ Core Functions ============
    
    /**
     * @notice Update borrow index for a market
     * @dev Should be called before any position changes
     */
    function accrueInterest(uint256 marketId) external marketConfigured(marketId) {
        _accrueInterest(marketId);
    }
    
    /**
     * @notice Check if a position meets initial margin requirements
     * @param marketId Market ID
     * @param size Position size (absolute value)
     * @param collateral Collateral amount
     * @param price Current mark price
     */
    function checkInitialMargin(
        uint256 marketId,
        uint256 size,
        uint256 collateral,
        uint256 price
    ) external view marketConfigured(marketId) returns (bool) {
        RiskParams storage params = riskParams[marketId];
        
        // Notional = size * price
        uint256 notional = (size * price) / PRECISION;
        
        // Required margin = notional * IM%
        uint256 requiredMargin = (notional * params.initialMarginBps) / BASIS_POINTS;
        
        // Check leverage
        uint256 leverage = notional * PRECISION / collateral;
        if (leverage > params.maxLeverage * PRECISION) return false;
        
        return collateral >= requiredMargin;
    }
    
    /**
     * @notice Check if a position is liquidatable
     * @param trader Position owner
     * @param marketId Market ID
     * @param currentPrice Current mark price
     * @return liquidatable Whether position can be liquidated
     * @return shortfall Amount below maintenance margin (0 if healthy)
     */
    function isLiquidatable(
        address trader,
        uint256 marketId,
        uint256 currentPrice
    ) external view marketConfigured(marketId) returns (bool liquidatable, uint256 shortfall) {
        IPositionLedger.Position memory pos = ledger.getPosition(trader, marketId);
        if (pos.size == 0) return (false, 0);
        
        RiskParams storage params = riskParams[marketId];
        
        // Calculate current equity
        int256 pnl = ledger.getUnrealizedPnL(trader, marketId, currentPrice);
        int256 equity = int256(pos.collateral) + pnl;
        
        // Calculate maintenance margin requirement
        uint256 absSize = pos.size >= 0 ? uint256(pos.size) : uint256(-pos.size);
        uint256 notional = (absSize * currentPrice) / PRECISION;
        uint256 maintenanceMargin = (notional * params.maintenanceMarginBps) / BASIS_POINTS;
        
        if (equity < int256(maintenanceMargin)) {
            liquidatable = true;
            shortfall = uint256(int256(maintenanceMargin) - equity);
        }
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get current utilization and borrow rate for a market
     */
    function getUtilization(uint256 marketId) external view returns (UtilizationData memory data) {
        IPositionLedger.Market memory market = ledger.getMarket(marketId);
        
        data.totalOI = market.totalLongOI + market.totalShortOI;
        data.totalLPCapital = lpCapital[marketId];
        
        if (data.totalLPCapital == 0) {
            data.utilization = 0;
            data.currentBorrowRate = 0;
        } else {
            data.utilization = (data.totalOI * PRECISION) / data.totalLPCapital;
            data.currentBorrowRate = _calculateBorrowRate(marketId, data.utilization);
        }
    }
    
    /**
     * @notice Calculate required collateral for a position
     */
    function getRequiredCollateral(
        uint256 marketId,
        uint256 size,
        uint256 price
    ) external view marketConfigured(marketId) returns (uint256 initial, uint256 maintenance) {
        RiskParams storage params = riskParams[marketId];
        
        uint256 notional = (size * price) / PRECISION;
        initial = (notional * params.initialMarginBps) / BASIS_POINTS;
        maintenance = (notional * params.maintenanceMarginBps) / BASIS_POINTS;
    }
    
    /**
     * @notice Get current borrow fee owed by a position
     */
    function getPendingBorrowFee(
        address trader,
        uint256 marketId
    ) external view returns (uint256 fee) {
        IPositionLedger.Position memory pos = ledger.getPosition(trader, marketId);
        if (pos.size == 0) return 0;
        
        uint256 currentIndex = _getProjectedBorrowIndex(marketId);
        uint256 indexDelta = currentIndex - pos.lastBorrowIndex;
        
        // Fee = collateral * indexDelta / PRECISION
        fee = (pos.collateral * indexDelta) / PRECISION;
    }
    
    /**
     * @notice Get liquidation penalty for a position
     */
    function getLiquidationPenalty(
        uint256 marketId,
        uint256 collateral
    ) external view marketConfigured(marketId) returns (uint256) {
        return (collateral * riskParams[marketId].liquidationPenaltyBps) / BASIS_POINTS;
    }
    
    /**
     * @notice Get max position size for given collateral
     */
    function getMaxPositionSize(
        uint256 marketId,
        uint256 collateral,
        uint256 price
    ) external view marketConfigured(marketId) returns (uint256) {
        RiskParams storage params = riskParams[marketId];
        
        // maxNotional = collateral * maxLeverage
        uint256 maxNotional = collateral * params.maxLeverage;
        
        // maxSize = maxNotional / price
        return (maxNotional * PRECISION) / price;
    }
    
    // ============ Internal Functions ============
    
    function _accrueInterest(uint256 marketId) internal {
        uint256 elapsed = block.timestamp - lastBorrowUpdate[marketId];
        if (elapsed == 0) return;
        
        // Get current utilization
        IPositionLedger.Market memory market = ledger.getMarket(marketId);
        uint256 totalOI = market.totalLongOI + market.totalShortOI;
        uint256 capital = lpCapital[marketId];
        
        uint256 utilization = capital > 0 ? (totalOI * PRECISION) / capital : 0;
        uint256 borrowRate = _calculateBorrowRate(marketId, utilization);
        
        // Calculate interest accrued
        // newIndex = oldIndex * (1 + rate * elapsed / year)
        uint256 interest = (borrowIndex[marketId] * borrowRate * elapsed) / (PRECISION * SECONDS_PER_YEAR);
        borrowIndex[marketId] += interest;
        lastBorrowUpdate[marketId] = block.timestamp;
        
        // Update ledger
        ledger.updateIndices(marketId, PRECISION, borrowIndex[marketId]);
        
        emit BorrowIndexUpdated(marketId, borrowIndex[marketId], borrowRate);
    }
    
    function _calculateBorrowRate(uint256 marketId, uint256 utilization) internal view returns (uint256) {
        RiskParams storage params = riskParams[marketId];
        
        if (utilization <= params.optimalUtilization) {
            // Below optimal: linear increase from base to optimal rate
            uint256 optimalRate = (params.baseBorrowRate + params.maxBorrowRate) / 2;
            return params.baseBorrowRate + (optimalRate - params.baseBorrowRate) * utilization / params.optimalUtilization;
        } else {
            // Above optimal: steep increase to max rate
            uint256 optimalRate = (params.baseBorrowRate + params.maxBorrowRate) / 2;
            uint256 excessUtilization = utilization - params.optimalUtilization;
            uint256 maxExcess = PRECISION - params.optimalUtilization;
            return optimalRate + (params.maxBorrowRate - optimalRate) * excessUtilization / maxExcess;
        }
    }
    
    function _getProjectedBorrowIndex(uint256 marketId) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - lastBorrowUpdate[marketId];
        if (elapsed == 0) return borrowIndex[marketId];
        
        IPositionLedger.Market memory market = ledger.getMarket(marketId);
        uint256 totalOI = market.totalLongOI + market.totalShortOI;
        uint256 capital = lpCapital[marketId];
        
        uint256 utilization = capital > 0 ? (totalOI * PRECISION) / capital : 0;
        uint256 borrowRate = _calculateBorrowRate(marketId, utilization);
        
        uint256 interest = (borrowIndex[marketId] * borrowRate * elapsed) / (PRECISION * SECONDS_PER_YEAR);
        return borrowIndex[marketId] + interest;
    }
}
