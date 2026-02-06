// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DynamicRiskEngine
 * @author LEVER Protocol
 * @notice Risk engine with dynamic parameters based on TVL, insurance, and utilization
 * @dev Extends base risk logic with automatic parameter adjustment
 * 
 * Dynamic adjustments:
 * - Max leverage decreases when utilization is high
 * - Max leverage decreases when insurance fund is low
 * - OI caps scale with LP TVL
 * - Margin requirements increase during high volatility
 */

import {IPositionLedger} from "./interfaces/IPositionLedger.sol";

interface IInsuranceFund {
    function getRiskAdjustmentFactor() external view returns (uint256);
    function getHealthStatus() external view returns (uint8);
    function totalFunds() external view returns (uint256);
}

interface ILPPool {
    function totalAssets() external view returns (uint256);
    function utilization() external view returns (uint256);
}

contract DynamicRiskEngine {
    
    // ============ Structs ============
    
    struct BaseRiskParams {
        uint256 initialMarginBps;     // Base initial margin (e.g., 1000 = 10%)
        uint256 maintenanceMarginBps; // Base maintenance margin (e.g., 500 = 5%)
        uint256 maxLeverage;          // Base max leverage (e.g., 10)
        uint256 baseBorrowRate;       // Base borrow rate APR
        uint256 maxBorrowRate;        // Max borrow rate at full utilization
        uint256 optimalUtilization;   // Target utilization
        uint256 liquidationPenaltyBps;// Liquidation penalty
    }
    
    struct DynamicParams {
        uint256 utilizationWeight;    // How much utilization affects leverage (0-100)
        uint256 insuranceWeight;      // How much insurance affects leverage (0-100)
        uint256 minLeverageRatio;     // Minimum leverage as % of base (e.g., 30 = 30%)
        uint256 oiToTvlRatio;         // Max OI as ratio of TVL (e.g., 200 = 200%)
        uint256 oiToInsuranceRatio;   // Max OI as ratio of insurance (e.g., 1000 = 10x)
    }
    
    struct EffectiveParams {
        uint256 maxLeverage;
        uint256 maxOI;
        uint256 initialMarginBps;
        uint256 maintenanceMarginBps;
        uint256 currentBorrowRate;
    }
    
    // ============ State ============
    
    address public owner;
    IPositionLedger public immutable ledger;
    IInsuranceFund public insuranceFund;
    ILPPool public lpPool;
    
    // marketId => BaseRiskParams
    mapping(uint256 => BaseRiskParams) public baseParams;
    
    // marketId => DynamicParams
    mapping(uint256 => DynamicParams) public dynamicParams;
    
    // Cumulative borrow index per market
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
    
    event BaseParamsSet(uint256 indexed marketId);
    event DynamicParamsSet(uint256 indexed marketId);
    event EffectiveParamsCalculated(uint256 indexed marketId, uint256 maxLeverage, uint256 maxOI);
    
    // ============ Errors ============
    
    error Unauthorized();
    error MarketNotConfigured();
    error MarketPausedError();
    error GloballyPaused();
    error InsufficientMargin();
    
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
    
    // ============ Constructor ============
    
    constructor(address _ledger) {
        owner = msg.sender;
        ledger = IPositionLedger(_ledger);
    }
    
    // ============ Admin Functions ============
    
    function setInsuranceFund(address _insuranceFund) external onlyOwner {
        insuranceFund = IInsuranceFund(_insuranceFund);
    }
    
    function setLPPool(address _lpPool) external onlyOwner {
        lpPool = ILPPool(_lpPool);
    }
    
    function setBaseParams(
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
        
        baseParams[marketId] = BaseRiskParams({
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
        
        emit BaseParamsSet(marketId);
    }
    
    function setDynamicParams(
        uint256 marketId,
        uint256 utilizationWeight,
        uint256 insuranceWeight,
        uint256 minLeverageRatio,
        uint256 oiToTvlRatio,
        uint256 oiToInsuranceRatio
    ) external onlyOwner {
        dynamicParams[marketId] = DynamicParams({
            utilizationWeight: utilizationWeight,
            insuranceWeight: insuranceWeight,
            minLeverageRatio: minLeverageRatio,
            oiToTvlRatio: oiToTvlRatio,
            oiToInsuranceRatio: oiToInsuranceRatio
        });
        
        emit DynamicParamsSet(marketId);
    }
    
    // ============ Core Functions ============
    
    /**
     * @notice Get effective (dynamically adjusted) parameters for a market
     */
    function getEffectiveParams(uint256 marketId) public view returns (EffectiveParams memory params) {
        BaseRiskParams storage base = baseParams[marketId];
        DynamicParams storage dynamic = dynamicParams[marketId];
        
        // Start with base values
        params.initialMarginBps = base.initialMarginBps;
        params.maintenanceMarginBps = base.maintenanceMarginBps;
        params.maxLeverage = base.maxLeverage;
        
        // Calculate effective max leverage
        params.maxLeverage = _calculateEffectiveMaxLeverage(marketId);
        
        // Calculate effective max OI
        params.maxOI = _calculateEffectiveMaxOI(marketId);
        
        // Calculate current borrow rate
        params.currentBorrowRate = _calculateBorrowRate(marketId);
        
        // Adjust margins if insurance is critical
        if (address(insuranceFund) != address(0)) {
            uint8 healthStatus = insuranceFund.getHealthStatus();
            if (healthStatus == 0) {
                // Critical: increase margins by 50%
                params.initialMarginBps = (base.initialMarginBps * 150) / 100;
                params.maintenanceMarginBps = (base.maintenanceMarginBps * 150) / 100;
            } else if (healthStatus == 1) {
                // Warning: increase margins by 25%
                params.initialMarginBps = (base.initialMarginBps * 125) / 100;
                params.maintenanceMarginBps = (base.maintenanceMarginBps * 125) / 100;
            }
        }
    }
    
    /**
     * @notice Check if a position meets margin requirements with dynamic params
     */
    function checkInitialMargin(
        uint256 marketId,
        uint256 size,
        uint256 collateral,
        uint256 price
    ) external view returns (bool) {
        EffectiveParams memory params = getEffectiveParams(marketId);
        
        // Notional = size * price
        uint256 notional = (size * price) / PRECISION;
        
        // Required margin
        uint256 requiredMargin = (notional * params.initialMarginBps) / BASIS_POINTS;
        
        // Check leverage
        if (collateral == 0) return false;
        uint256 leverage = (notional * PRECISION) / collateral;
        if (leverage > params.maxLeverage * PRECISION) return false;
        
        return collateral >= requiredMargin;
    }
    
    /**
     * @notice Check if a position is liquidatable with dynamic params
     */
    function isLiquidatable(
        address trader,
        uint256 marketId,
        uint256 currentPrice
    ) external view returns (bool liquidatable, uint256 shortfall) {
        IPositionLedger.Position memory pos = ledger.getPosition(trader, marketId);
        if (pos.size == 0) return (false, 0);
        
        EffectiveParams memory params = getEffectiveParams(marketId);
        
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
    
    /**
     * @notice Check if opening a position would exceed OI limits
     */
    function checkOILimit(
        uint256 marketId,
        int256 sizeDelta
    ) external view returns (bool withinLimit) {
        EffectiveParams memory params = getEffectiveParams(marketId);
        IPositionLedger.Market memory market = ledger.getMarket(marketId);
        
        uint256 absSize = sizeDelta >= 0 ? uint256(sizeDelta) : uint256(-sizeDelta);
        
        if (sizeDelta > 0) {
            // Adding to longs
            return market.totalLongOI + absSize <= params.maxOI;
        } else {
            // Adding to shorts
            return market.totalShortOI + absSize <= params.maxOI;
        }
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get current utilization across all markets
     */
    function getGlobalUtilization() public view returns (uint256) {
        if (address(lpPool) == address(0)) return 0;
        return lpPool.utilization();
    }
    
    /**
     * @notice Get insurance fund health factor
     */
    function getInsuranceHealthFactor() public view returns (uint256) {
        if (address(insuranceFund) == address(0)) return PRECISION;
        return insuranceFund.getRiskAdjustmentFactor();
    }
    
    /**
     * @notice Get detailed risk metrics for a market
     */
    function getRiskMetrics(uint256 marketId) external view returns (
        uint256 effectiveMaxLeverage,
        uint256 effectiveMaxOI,
        uint256 currentUtilization,
        uint256 insuranceHealth,
        uint256 currentBorrowRate,
        bool isHighRisk
    ) {
        EffectiveParams memory params = getEffectiveParams(marketId);
        
        effectiveMaxLeverage = params.maxLeverage;
        effectiveMaxOI = params.maxOI;
        currentUtilization = getGlobalUtilization();
        insuranceHealth = getInsuranceHealthFactor();
        currentBorrowRate = params.currentBorrowRate;
        
        // High risk if utilization > 90% or insurance < 50%
        isHighRisk = currentUtilization > (90 * PRECISION / 100) || 
                     insuranceHealth < (50 * PRECISION / 100);
    }
    
    // ============ IRiskEngine Interface Functions ============
    
    /**
     * @notice Get utilization data for a market (IRiskEngine interface)
     */
    function getUtilization(uint256 marketId) external view returns (
        uint256 totalOI,
        uint256 totalLPCapital,
        uint256 utilization,
        uint256 currentBorrowRate
    ) {
        IPositionLedger.Market memory market = ledger.getMarket(marketId);
        totalOI = market.totalLongOI + market.totalShortOI;
        totalLPCapital = address(lpPool) != address(0) ? lpPool.totalAssets() : 0;
        utilization = getGlobalUtilization();
        currentBorrowRate = _calculateBorrowRate(marketId);
    }
    
    /**
     * @notice Get required collateral for a position size (IRiskEngine interface)
     */
    function getRequiredCollateral(
        uint256 marketId,
        uint256 size,
        uint256 price
    ) external view returns (uint256 initial, uint256 maintenance) {
        EffectiveParams memory params = getEffectiveParams(marketId);
        uint256 notional = (size * price) / PRECISION;
        initial = (notional * params.initialMarginBps) / BASIS_POINTS;
        maintenance = (notional * params.maintenanceMarginBps) / BASIS_POINTS;
    }
    
    /**
     * @notice Get pending borrow fee for a position (IRiskEngine interface)
     */
    function getPendingBorrowFee(
        address trader,
        uint256 marketId
    ) external view returns (uint256) {
        IPositionLedger.Position memory pos = ledger.getPosition(trader, marketId);
        if (pos.size == 0) return 0;
        
        // Calculate accrued index since position opened
        uint256 currentIndex = borrowIndex[marketId];
        if (pos.lastBorrowIndex == 0 || pos.lastBorrowIndex >= currentIndex) return 0;
        
        uint256 absSize = pos.size >= 0 ? uint256(pos.size) : uint256(-pos.size);
        uint256 notional = (absSize * pos.entryPrice) / PRECISION;
        
        // Fee = notional * (currentIndex / positionIndex - 1)
        uint256 indexRatio = (currentIndex * PRECISION) / pos.lastBorrowIndex;
        return (notional * (indexRatio - PRECISION)) / PRECISION;
    }
    
    /**
     * @notice Get liquidation penalty amount (IRiskEngine interface)
     */
    function getLiquidationPenalty(
        uint256 marketId,
        uint256 collateral
    ) external view returns (uint256) {
        BaseRiskParams storage base = baseParams[marketId];
        return (collateral * base.liquidationPenaltyBps) / BASIS_POINTS;
    }
    
    /**
     * @notice Get max position size for given collateral (IRiskEngine interface)
     */
    function getMaxPositionSize(
        uint256 marketId,
        uint256 collateral,
        uint256 price
    ) external view returns (uint256) {
        EffectiveParams memory params = getEffectiveParams(marketId);
        if (price == 0) return 0;
        // maxSize = collateral * maxLeverage * PRECISION / price
        return (collateral * params.maxLeverage * PRECISION) / price;
    }
    
    /**
     * @notice Accrue interest for a market (IRiskEngine interface)
     */
    function accrueInterest(uint256 marketId) external {
        uint256 lastUpdate = lastBorrowUpdate[marketId];
        if (lastUpdate == 0 || block.timestamp <= lastUpdate) return;
        
        uint256 elapsed = block.timestamp - lastUpdate;
        uint256 rate = _calculateBorrowRate(marketId);
        
        // Index growth = elapsed * rate / SECONDS_PER_YEAR
        uint256 growth = (elapsed * rate) / SECONDS_PER_YEAR;
        borrowIndex[marketId] = borrowIndex[marketId] + (borrowIndex[marketId] * growth) / PRECISION;
        lastBorrowUpdate[marketId] = block.timestamp;
    }
    
    // ============ Internal Functions ============
    
    function _calculateEffectiveMaxLeverage(uint256 marketId) internal view returns (uint256) {
        BaseRiskParams storage base = baseParams[marketId];
        DynamicParams storage dynamic = dynamicParams[marketId];
        
        uint256 baseLeverage = base.maxLeverage * PRECISION;
        uint256 adjustmentFactor = PRECISION;  // Start at 100%
        
        // Utilization adjustment
        if (address(lpPool) != address(0) && dynamic.utilizationWeight > 0) {
            uint256 utilization = lpPool.utilization();
            // At 100% utilization, reduce by utilizationWeight%
            uint256 utilizationPenalty = (utilization * dynamic.utilizationWeight) / 100;
            if (utilizationPenalty < adjustmentFactor) {
                adjustmentFactor -= utilizationPenalty;
            }
        }
        
        // Insurance adjustment
        if (address(insuranceFund) != address(0) && dynamic.insuranceWeight > 0) {
            uint256 insuranceFactor = insuranceFund.getRiskAdjustmentFactor();
            // Insurance factor is already 0-100%, weight it
            uint256 insuranceAdjustment = PRECISION - ((PRECISION - insuranceFactor) * dynamic.insuranceWeight / 100);
            adjustmentFactor = (adjustmentFactor * insuranceAdjustment) / PRECISION;
        }
        
        // Apply minimum leverage ratio
        uint256 minLeverage = (baseLeverage * dynamic.minLeverageRatio) / 100;
        uint256 effectiveLeverage = (baseLeverage * adjustmentFactor) / PRECISION;
        
        return effectiveLeverage < minLeverage ? minLeverage / PRECISION : effectiveLeverage / PRECISION;
    }
    
    function _calculateEffectiveMaxOI(uint256 marketId) internal view returns (uint256) {
        DynamicParams storage dynamic = dynamicParams[marketId];
        IPositionLedger.Market memory market = ledger.getMarket(marketId);
        
        uint256 maxOI = market.maxOI;  // Start with static cap
        
        // Cap by TVL ratio
        if (address(lpPool) != address(0) && dynamic.oiToTvlRatio > 0) {
            uint256 tvlCap = (lpPool.totalAssets() * dynamic.oiToTvlRatio) / 100;
            if (tvlCap < maxOI) maxOI = tvlCap;
        }
        
        // Cap by insurance ratio
        if (address(insuranceFund) != address(0) && dynamic.oiToInsuranceRatio > 0) {
            uint256 insuranceCap = (insuranceFund.totalFunds() * dynamic.oiToInsuranceRatio) / 100;
            if (insuranceCap < maxOI) maxOI = insuranceCap;
        }
        
        return maxOI;
    }
    
    function _calculateBorrowRate(uint256 marketId) internal view returns (uint256) {
        BaseRiskParams storage base = baseParams[marketId];
        
        uint256 utilization = getGlobalUtilization();
        
        if (utilization <= base.optimalUtilization) {
            uint256 optimalRate = (base.baseBorrowRate + base.maxBorrowRate) / 2;
            return base.baseBorrowRate + 
                   (optimalRate - base.baseBorrowRate) * utilization / base.optimalUtilization;
        } else {
            uint256 optimalRate = (base.baseBorrowRate + base.maxBorrowRate) / 2;
            uint256 excessUtilization = utilization - base.optimalUtilization;
            uint256 maxExcess = PRECISION - base.optimalUtilization;
            return optimalRate + 
                   (base.maxBorrowRate - optimalRate) * excessUtilization / maxExcess;
        }
    }
}
