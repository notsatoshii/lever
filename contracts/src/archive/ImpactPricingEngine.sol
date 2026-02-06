// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ImpactPricingEngine
 * @notice Imbalance-Adjusted Linear Impact pricing for LEVER
 * 
 * execution_price = oracle_price × (1 ± impact)
 * 
 * Where:
 *   base_impact = trade_size / (market_depth × 2)
 *   imbalance_delta = |imbalance_after| - |imbalance_before|
 *   impact = base_impact × (1 + imbalance_delta × IMBALANCE_MULTIPLIER)
 * 
 * Trades that balance the book get discounts (can go negative = rebate)
 * Trades that imbalance the book pay more
 */
contract ImpactPricingEngine {
    // ============ Constants ============
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_IMPACT = 5e16;          // 5% max impact
    uint256 public constant IMBALANCE_MULTIPLIER = 2;   // How much imbalance affects impact
    uint256 public constant MIN_DEPTH = 1000e18;        // Minimum $1000 depth
    
    // ============ State ============
    address public owner;
    address public priceEngine;     // PriceEngineV2 for oracle prices
    address public positionLedger;  // For OI data
    address public router;          // Authorized caller
    
    // Per-market depth configuration (defaults to % of TVL)
    mapping(uint256 => uint256) public marketDepth;
    uint256 public defaultDepthBps = 1500;  // 15% of TVL default
    uint256 public totalTVL;
    
    // ============ Events ============
    event ExecutionPriceCalculated(
        uint256 indexed marketId,
        bool isBuy,
        uint256 tradeSize,
        uint256 oraclePrice,
        uint256 executionPrice,
        int256 impactBps
    );
    event MarketDepthSet(uint256 indexed marketId, uint256 depth);
    event ConfigUpdated(address priceEngine, address positionLedger, address router);
    
    // ============ Errors ============
    error Unauthorized();
    error ZeroAddress();
    error InvalidTradeSize();
    
    // ============ Modifiers ============
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyRouter() {
        if (msg.sender != router && msg.sender != owner) revert Unauthorized();
        _;
    }
    
    // ============ Constructor ============
    constructor(address _priceEngine, address _positionLedger) {
        if (_priceEngine == address(0) || _positionLedger == address(0)) revert ZeroAddress();
        owner = msg.sender;
        priceEngine = _priceEngine;
        positionLedger = _positionLedger;
    }
    
    // ============ Admin ============
    function setConfig(
        address _priceEngine,
        address _positionLedger,
        address _router
    ) external onlyOwner {
        priceEngine = _priceEngine;
        positionLedger = _positionLedger;
        router = _router;
        emit ConfigUpdated(_priceEngine, _positionLedger, _router);
    }
    
    function setMarketDepth(uint256 marketId, uint256 depth) external onlyOwner {
        marketDepth[marketId] = depth;
        emit MarketDepthSet(marketId, depth);
    }
    
    function setDefaultDepthBps(uint256 bps) external onlyOwner {
        defaultDepthBps = bps;
    }
    
    function setTotalTVL(uint256 _tvl) external onlyOwner {
        totalTVL = _tvl;
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
    
    // ============ Core Pricing ============
    
    /**
     * @notice Calculate execution price with imbalance-adjusted linear impact
     * @param marketId Market ID
     * @param isBuy True for long, false for short
     * @param tradeSize Notional size of trade (in USD, 18 decimals)
     * @return executionPrice The execution price (18 decimals, 0-1 range for binary)
     * @return impactBps Signed impact in basis points (negative = rebate)
     */
    function getExecutionPrice(
        uint256 marketId,
        bool isBuy,
        uint256 tradeSize
    ) external view returns (uint256 executionPrice, int256 impactBps) {
        if (tradeSize == 0) revert InvalidTradeSize();
        
        // Get oracle price
        uint256 oraclePrice = _getOraclePrice(marketId);
        
        // Get current OI
        (uint256 longOI, uint256 shortOI) = _getOI(marketId);
        
        // Get market depth
        uint256 depth = _getMarketDepth(marketId);
        
        // Calculate impact
        (executionPrice, impactBps) = _calculateImpact(
            oraclePrice,
            longOI,
            shortOI,
            tradeSize,
            depth,
            isBuy
        );
    }
    
    /**
     * @notice Execute pricing (called by router, emits event)
     */
    function calculateExecutionPrice(
        uint256 marketId,
        bool isBuy,
        uint256 tradeSize
    ) external onlyRouter returns (uint256 executionPrice, int256 impactBps) {
        if (tradeSize == 0) revert InvalidTradeSize();
        
        uint256 oraclePrice = _getOraclePrice(marketId);
        (uint256 longOI, uint256 shortOI) = _getOI(marketId);
        uint256 depth = _getMarketDepth(marketId);
        
        (executionPrice, impactBps) = _calculateImpact(
            oraclePrice,
            longOI,
            shortOI,
            tradeSize,
            depth,
            isBuy
        );
        
        emit ExecutionPriceCalculated(marketId, isBuy, tradeSize, oraclePrice, executionPrice, impactBps);
    }
    
    // ============ Internal ============
    
    function _calculateImpact(
        uint256 oraclePrice,
        uint256 longOI,
        uint256 shortOI,
        uint256 tradeSize,
        uint256 depth,
        bool isBuy
    ) internal pure returns (uint256 executionPrice, int256 impactBps) {
        // Base impact = trade_size / (depth × 2)
        uint256 baseImpact = tradeSize * PRECISION / (depth * 2);
        
        // Calculate imbalance before
        uint256 totalOI = longOI + shortOI;
        int256 imbalanceBefore = 0;
        if (totalOI > 0) {
            // imbalance = (longOI - shortOI) / totalOI, scaled to PRECISION
            imbalanceBefore = int256(longOI * PRECISION / totalOI) - int256(PRECISION / 2);
            imbalanceBefore = imbalanceBefore * 2; // Scale to -1 to +1 range
        }
        
        // Calculate imbalance after trade
        uint256 newLongOI = isBuy ? longOI + tradeSize : longOI;
        uint256 newShortOI = isBuy ? shortOI : shortOI + tradeSize;
        uint256 newTotalOI = newLongOI + newShortOI;
        
        int256 imbalanceAfter = 0;
        if (newTotalOI > 0) {
            imbalanceAfter = int256(newLongOI * PRECISION / newTotalOI) - int256(PRECISION / 2);
            imbalanceAfter = imbalanceAfter * 2;
        }
        
        // Imbalance delta = |after| - |before|
        // Positive delta = trade worsens balance
        // Negative delta = trade improves balance
        int256 imbalanceDelta = _abs(imbalanceAfter) - _abs(imbalanceBefore);
        
        // Adjusted impact = base_impact × (1 + delta × IMBALANCE_MULTIPLIER)
        // Note: delta is in PRECISION scale, so we need to scale properly
        int256 multiplier = int256(PRECISION) + (imbalanceDelta * int256(IMBALANCE_MULTIPLIER));
        int256 adjustedImpact = int256(baseImpact) * multiplier / int256(PRECISION);
        
        // Cap at MAX_IMPACT (but allow negative for rebates, capped at -MAX_IMPACT)
        if (adjustedImpact > int256(MAX_IMPACT)) {
            adjustedImpact = int256(MAX_IMPACT);
        } else if (adjustedImpact < -int256(MAX_IMPACT)) {
            adjustedImpact = -int256(MAX_IMPACT);
        }
        
        // Convert to basis points for return value
        impactBps = adjustedImpact * 10000 / int256(PRECISION);
        
        // Calculate execution price
        // For buys: price goes up (positive impact)
        // For sells (shorts): price goes down (negative impact from buyer's perspective)
        if (isBuy) {
            // execution_price = oracle_price × (1 + impact)
            if (adjustedImpact >= 0) {
                executionPrice = oraclePrice * (PRECISION + uint256(adjustedImpact)) / PRECISION;
            } else {
                executionPrice = oraclePrice * (PRECISION - uint256(-adjustedImpact)) / PRECISION;
            }
        } else {
            // For shorts, negative impact is favorable (lower entry price)
            if (adjustedImpact >= 0) {
                executionPrice = oraclePrice * (PRECISION - uint256(adjustedImpact)) / PRECISION;
            } else {
                executionPrice = oraclePrice * (PRECISION + uint256(-adjustedImpact)) / PRECISION;
            }
        }
        
        // Ensure price stays in valid range for binary outcomes
        if (executionPrice > PRECISION) executionPrice = PRECISION;
        if (executionPrice < 1e14) executionPrice = 1e14; // Min 0.01%
    }
    
    function _getOraclePrice(uint256 marketId) internal view returns (uint256) {
        (bool success, bytes memory data) = priceEngine.staticcall(
            abi.encodeWithSignature("getMarkPrice(uint256)", marketId)
        );
        require(success && data.length >= 32, "Oracle price failed");
        return abi.decode(data, (uint256));
    }
    
    function _getOI(uint256 marketId) internal view returns (uint256 longOI, uint256 shortOI) {
        (bool success, bytes memory data) = positionLedger.staticcall(
            abi.encodeWithSignature("getMarket(uint256)", marketId)
        );
        if (success && data.length >= 96) {
            // Market struct: oracle, totalLongOI, totalShortOI, ...
            assembly {
                longOI := mload(add(data, 64))   // offset 32 (skip oracle address)
                shortOI := mload(add(data, 96))  // offset 64
            }
        }
    }
    
    function _getMarketDepth(uint256 marketId) internal view returns (uint256) {
        uint256 depth = marketDepth[marketId];
        if (depth == 0) {
            // Default: 15% of TVL
            depth = totalTVL * defaultDepthBps / 10000;
        }
        if (depth < MIN_DEPTH) {
            depth = MIN_DEPTH;
        }
        return depth;
    }
    
    function _abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }
    
    // ============ View Helpers ============
    
    /**
     * @notice Preview impact for a trade without executing
     */
    function previewImpact(
        uint256 marketId,
        bool isBuy,
        uint256 tradeSize
    ) external view returns (
        uint256 oraclePrice,
        uint256 executionPrice,
        int256 impactBps,
        uint256 longOI,
        uint256 shortOI,
        int256 imbalanceBps
    ) {
        oraclePrice = _getOraclePrice(marketId);
        (longOI, shortOI) = _getOI(marketId);
        uint256 depth = _getMarketDepth(marketId);
        
        (executionPrice, impactBps) = _calculateImpact(
            oraclePrice,
            longOI,
            shortOI,
            tradeSize,
            depth,
            isBuy
        );
        
        // Current imbalance in bps
        uint256 totalOI = longOI + shortOI;
        if (totalOI > 0) {
            imbalanceBps = int256(longOI * 10000 / totalOI) - 5000; // -5000 to +5000 range
        }
    }
}
