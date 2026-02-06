// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPriceEngine.sol";

/**
 * @title RiskEngineV2
 * @author LEVER Protocol
 * @notice Risk and margin calculations with PI-only liquidations
 * @dev Implements Module 4 from LEVER Architecture:
 * 
 * THE GOLDEN RULE: ALWAYS liquidate against PI (Mark Price), NEVER against vAMM (Entry Price)
 * 
 * Key formulas:
 * - Equity = Collateral + (PI - Entry) × Size - PendingFees
 * - Initial Margin (IM) = (Notional / Leverage) × (1 + α × σ)
 * - Maintenance Margin (MM) = m × Notional
 * - Liquidation: If Equity ≤ MM → Liquidate
 * 
 * Features:
 * - 2% liquidation buffer to prevent micro-liquidations
 * - Partial liquidation (25-50%) before full liquidation
 * - Volatility-adjusted initial margin
 */
contract RiskEngineV2 {
    
    // ============ Constants ============
    
    uint256 public constant SCALE = 1e18;
    
    // Margin parameters
    uint256 public constant MAINTENANCE_MARGIN_RATIO = 5e16;  // 5% = 0.05
    uint256 public constant LIQUIDATION_BUFFER = 2e16;        // 2% buffer
    uint256 public constant VOLATILITY_SCALING = 1e18;        // α = 1.0
    
    // Partial liquidation
    uint256 public constant PARTIAL_LIQUIDATION_RATIO = 5e17; // 50%
    uint256 public constant MIN_PARTIAL_RATIO = 25e16;        // 25% minimum
    
    // Liquidation penalty
    uint256 public constant LIQUIDATION_PENALTY = 25e15;      // 2.5%
    
    // ============ State ============
    
    address public owner;
    address public priceEngine;        // PriceEngineV2 for Mark Price (PI)
    address public positionLedger;     // PositionLedgerV2
    address public borrowFeeEngine;    // BorrowFeeEngineV2 for pending fees
    address public liquidationEngine;  // Receives liquidation calls
    
    // Per-market config
    mapping(uint256 => MarketRiskConfig) public marketConfigs;
    
    struct MarketRiskConfig {
        uint256 maxLeverage;           // e.g., 5e18 = 5x
        uint256 volatility;            // Current volatility estimate
        bool active;
    }
    
    // ============ Events ============
    
    event PositionHealthChecked(
        address indexed trader,
        uint256 indexed marketId,
        int256 equity,
        uint256 maintenanceMargin,
        bool isHealthy
    );
    event LiquidationTriggered(
        address indexed trader,
        uint256 indexed marketId,
        bool isPartial,
        uint256 liquidationAmount
    );
    event MarketConfigUpdated(uint256 indexed marketId, uint256 maxLeverage, uint256 volatility);
    
    // ============ Errors ============
    
    error Unauthorized();
    error ZeroAddress();
    error MarketNotActive();
    error PositionHealthy();
    error ExceedsMaxLeverage();
    error InsufficientMargin();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyAuthorized() {
        if (msg.sender != owner && 
            msg.sender != liquidationEngine && 
            msg.sender != positionLedger) revert Unauthorized();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(
        address _priceEngine,
        address _positionLedger,
        address _borrowFeeEngine
    ) {
        if (_priceEngine == address(0)) revert ZeroAddress();
        if (_positionLedger == address(0)) revert ZeroAddress();
        if (_borrowFeeEngine == address(0)) revert ZeroAddress();
        
        owner = msg.sender;
        priceEngine = _priceEngine;
        positionLedger = _positionLedger;
        borrowFeeEngine = _borrowFeeEngine;
    }
    
    // ============ Admin Functions ============
    
    function setLiquidationEngine(address _liquidationEngine) external onlyOwner {
        if (_liquidationEngine == address(0)) revert ZeroAddress();
        liquidationEngine = _liquidationEngine;
    }
    
    function setMarketConfig(
        uint256 marketId,
        uint256 maxLeverage,
        uint256 volatility
    ) external onlyOwner {
        marketConfigs[marketId] = MarketRiskConfig({
            maxLeverage: maxLeverage,
            volatility: volatility,
            active: true
        });
        emit MarketConfigUpdated(marketId, maxLeverage, volatility);
    }
    
    function updateVolatility(uint256 marketId, uint256 newVolatility) external onlyAuthorized {
        marketConfigs[marketId].volatility = newVolatility;
    }
    
    // ============ Core Risk Functions ============
    
    /**
     * @notice Check if a position can be opened with given parameters
     * @dev Validates leverage and initial margin requirements
     */
    function validatePositionOpen(
        uint256 marketId,
        uint256 notional,
        uint256 collateral,
        uint256 leverage
    ) external view returns (bool valid) {
        MarketRiskConfig storage config = marketConfigs[marketId];
        if (!config.active) revert MarketNotActive();
        
        // Check leverage limit
        if (leverage > config.maxLeverage) revert ExceedsMaxLeverage();
        
        // Calculate required initial margin with volatility adjustment
        uint256 requiredIM = calculateInitialMargin(notional, leverage, config.volatility);
        
        // Collateral must cover initial margin
        if (collateral < requiredIM) revert InsufficientMargin();
        
        return true;
    }
    
    /**
     * @notice Check position health and determine if liquidation is needed
     * @dev THE GOLDEN RULE: Uses Mark Price (PI) from PriceEngineV2, NEVER vAMM
     * @return isHealthy True if position is healthy
     * @return equity Current equity
     * @return maintenanceMargin Required MM
     */
    function checkPositionHealth(
        address trader,
        uint256 marketId,
        int256 positionSize,
        uint256 entryPrice,
        uint256 collateral,
        uint256 pendingFees
    ) external returns (bool isHealthy, int256 equity, uint256 maintenanceMargin) {
        // ⚠️ CRITICAL: Get Mark Price from PriceEngineV2 (smoothed PI)
        // NEVER use vAMM price for liquidation checks
        uint256 markPrice = _getMarkPrice(marketId);
        
        // Calculate equity: Collateral + UnrealizedPnL - PendingFees
        equity = _calculateEquity(
            collateral,
            positionSize,
            entryPrice,
            markPrice,
            pendingFees
        );
        
        // Calculate maintenance margin: m × Notional
        uint256 notional = _abs(positionSize) * markPrice / SCALE;
        maintenanceMargin = notional * MAINTENANCE_MARGIN_RATIO / SCALE;
        
        // Add liquidation buffer (2%) to prevent micro-liquidations
        uint256 bufferedMM = maintenanceMargin + (maintenanceMargin * LIQUIDATION_BUFFER / SCALE);
        
        isHealthy = equity > int256(bufferedMM);
        
        emit PositionHealthChecked(trader, marketId, equity, maintenanceMargin, isHealthy);
    }
    
    /**
     * @notice Determine liquidation type and amount
     * @dev Prefers partial liquidation (50%) if it can restore health
     * @return liquidationType 0=none, 1=partial, 2=full
     * @return liquidationAmount Amount to liquidate (notional)
     */
    function determineLiquidation(
        address trader,
        uint256 marketId,
        int256 positionSize,
        uint256 entryPrice,
        uint256 collateral,
        uint256 pendingFees
    ) external returns (uint8 liquidationType, uint256 liquidationAmount) {
        uint256 markPrice = _getMarkPrice(marketId);
        
        int256 equity = _calculateEquity(
            collateral,
            positionSize,
            entryPrice,
            markPrice,
            pendingFees
        );
        
        uint256 notional = _abs(positionSize) * markPrice / SCALE;
        uint256 maintenanceMargin = notional * MAINTENANCE_MARGIN_RATIO / SCALE;
        uint256 bufferedMM = maintenanceMargin + (maintenanceMargin * LIQUIDATION_BUFFER / SCALE);
        
        // If healthy, no liquidation needed
        if (equity > int256(bufferedMM)) {
            return (0, 0);
        }
        
        // Try partial liquidation first (50%)
        uint256 partialAmount = notional * PARTIAL_LIQUIDATION_RATIO / SCALE;
        
        // Simulate equity after partial liquidation
        // Closing 50% releases collateral proportionally and realizes partial PnL
        int256 equityAfterPartial = equity + int256(partialAmount * MAINTENANCE_MARGIN_RATIO / SCALE);
        
        // New MM after partial
        uint256 remainingNotional = notional - partialAmount;
        uint256 newMM = remainingNotional * MAINTENANCE_MARGIN_RATIO / SCALE;
        uint256 newBufferedMM = newMM + (newMM * LIQUIDATION_BUFFER / SCALE);
        
        if (equityAfterPartial > int256(newBufferedMM)) {
            // Partial liquidation sufficient
            liquidationType = 1;
            liquidationAmount = partialAmount;
            emit LiquidationTriggered(trader, marketId, true, partialAmount);
        } else {
            // Full liquidation required
            liquidationType = 2;
            liquidationAmount = notional;
            emit LiquidationTriggered(trader, marketId, false, notional);
        }
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Calculate Initial Margin with volatility adjustment
     * @dev IM = (Notional / Leverage) × (1 + α × σ)
     */
    function calculateInitialMargin(
        uint256 notional,
        uint256 leverage,
        uint256 volatility
    ) public pure returns (uint256 im) {
        // Base margin = Notional / Leverage
        uint256 baseMargin = notional * SCALE / leverage;
        
        // Volatility adjustment = 1 + α × σ
        // α = 1.0, so adjustment = 1 + σ
        uint256 volAdjustment = SCALE + volatility;
        
        im = baseMargin * volAdjustment / SCALE;
    }
    
    /**
     * @notice Calculate Maintenance Margin
     * @dev MM = m × Notional (m = 5%)
     */
    function calculateMaintenanceMargin(uint256 notional) public pure returns (uint256) {
        return notional * MAINTENANCE_MARGIN_RATIO / SCALE;
    }
    
    /**
     * @notice Calculate liquidation price for a position
     * @dev Price at which Equity = Maintenance Margin
     */
    function calculateLiquidationPrice(
        int256 positionSize,
        uint256 entryPrice,
        uint256 collateral,
        uint256 pendingFees
    ) external pure returns (uint256 liquidationPrice) {
        if (positionSize == 0) return 0;
        
        uint256 absSize = _abs(positionSize);
        
        // For longs: liqPrice = entry - (collateral - fees - MM) / size
        // For shorts: liqPrice = entry + (collateral - fees - MM) / size
        // Simplified: solve for price where equity = MM
        
        // MM = m × size × price → need to solve iteratively or approximate
        // Approximation: use entry price for MM calculation
        uint256 approxNotional = absSize * entryPrice / SCALE;
        uint256 mm = approxNotional * MAINTENANCE_MARGIN_RATIO / SCALE;
        
        // Net margin available for loss
        int256 netMargin = int256(collateral) - int256(pendingFees) - int256(mm);
        if (netMargin < 0) {
            // Already underwater
            return positionSize > 0 ? entryPrice : entryPrice;
        }
        
        // Price movement to reach liquidation
        uint256 priceMove = uint256(netMargin) * SCALE / absSize;
        
        if (positionSize > 0) {
            // Long: liquidate when price drops
            liquidationPrice = entryPrice > priceMove ? entryPrice - priceMove : 0;
        } else {
            // Short: liquidate when price rises
            liquidationPrice = entryPrice + priceMove;
            if (liquidationPrice > SCALE) liquidationPrice = SCALE; // Cap at 1.0 for probabilities
        }
    }
    
    /**
     * @notice Get effective leverage of a position
     */
    function getEffectiveLeverage(
        int256 positionSize,
        uint256 markPrice,
        uint256 collateral,
        uint256 pendingFees
    ) external pure returns (uint256 leverage) {
        if (collateral <= pendingFees) return type(uint256).max; // Infinite leverage (underwater)
        
        uint256 notional = _abs(positionSize) * markPrice / SCALE;
        uint256 effectiveCollateral = collateral - pendingFees;
        
        leverage = notional * SCALE / effectiveCollateral;
    }
    
    /**
     * @notice Get margin ratio (equity / notional)
     */
    function getMarginRatio(
        int256 positionSize,
        uint256 entryPrice,
        uint256 markPrice,
        uint256 collateral,
        uint256 pendingFees
    ) external pure returns (int256 marginRatio) {
        int256 equity = _calculateEquity(collateral, positionSize, entryPrice, markPrice, pendingFees);
        uint256 notional = _abs(positionSize) * markPrice / SCALE;
        
        if (notional == 0) return 0;
        
        marginRatio = equity * int256(SCALE) / int256(notional);
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Get Mark Price from PriceEngineV2
     * @dev This is THE smoothed PI - manipulation resistant
     */
    function _getMarkPrice(uint256 marketId) internal view returns (uint256) {
        // Call PriceEngineV2.getMarkPrice(marketId)
        // In production, this would be: IPriceEngine(priceEngine).getMarkPrice(marketId)
        // For now, using a simplified interface
        (bool success, bytes memory data) = priceEngine.staticcall(
            abi.encodeWithSignature("getMarkPrice(uint256)", marketId)
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        
        // Fallback: try getSmoothedPrice
        (success, data) = priceEngine.staticcall(
            abi.encodeWithSignature("getSmoothedPrice(uint256)", marketId)
        );
        
        require(success && data.length >= 32, "Failed to get mark price");
        return abi.decode(data, (uint256));
    }
    
    /**
     * @notice Calculate position equity
     * @dev Equity = Collateral + UnrealizedPnL - PendingFees
     *      UnrealizedPnL = Size × (MarkPrice - EntryPrice)
     */
    function _calculateEquity(
        uint256 collateral,
        int256 positionSize,
        uint256 entryPrice,
        uint256 markPrice,
        uint256 pendingFees
    ) internal pure returns (int256 equity) {
        // Calculate unrealized PnL
        // For longs (positive size): profit when price goes up
        // For shorts (negative size): profit when price goes down
        int256 pnl = positionSize * (int256(markPrice) - int256(entryPrice)) / int256(SCALE);
        
        // Equity = Collateral + PnL - Fees
        equity = int256(collateral) + pnl - int256(pendingFees);
    }
    
    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
}
