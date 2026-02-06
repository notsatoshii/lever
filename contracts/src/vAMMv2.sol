// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title vAMMv2 - Virtual AMM with Imbalance-Adjusted Linear Impact
 * @notice Replaces x*y=k with linear impact scaled by OI imbalance
 * 
 * execution_price = oracle_price × (1 ± impact)
 * impact = base_impact × (1 + imbalance_delta × 2)
 * 
 * Trades that balance the book get discounts (rebates)
 * Trades that imbalance the book pay more
 */
contract vAMMv2 {
    // ============ Constants ============
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_IMPACT = 5e16;          // 5% max impact
    uint256 public constant IMBALANCE_MULTIPLIER = 2;   // How much imbalance affects impact
    uint256 public constant DEFAULT_DEPTH_BPS = 1500;   // 15% of TVL default depth
    
    // ============ State ============
    address public owner;
    address public router;
    address public keeper;
    address public priceEngine;
    address public positionLedger;
    
    uint256 public totalTVL;
    mapping(uint256 => uint256) public marketDepth;  // Custom depth per market
    mapping(uint256 => bool) public marketInitialized;
    
    // ============ Events ============
    event SwapExecuted(
        uint256 indexed marketId,
        address indexed trader,
        bool isBuy,
        uint256 amountIn,
        uint256 amountOut,
        uint256 executionPrice,
        int256 impactBps
    );
    event MarketInitialized(uint256 indexed marketId, uint256 depth);
    event ConfigUpdated(address priceEngine, address positionLedger);
    
    // ============ Errors ============
    error Unauthorized();
    error ZeroAddress();
    error InvalidAmount();
    error MarketNotInitialized();
    
    // ============ Modifiers ============
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyRouter() {
        if (msg.sender != router) revert Unauthorized();
        _;
    }
    
    modifier onlyKeeper() {
        if (msg.sender != keeper && msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier marketExists(uint256 marketId) {
        if (!marketInitialized[marketId]) revert MarketNotInitialized();
        _;
    }
    
    // ============ Constructor ============
    constructor(address _priceEngine) {
        if (_priceEngine == address(0)) revert ZeroAddress();
        owner = msg.sender;
        priceEngine = _priceEngine;
    }
    
    // ============ Admin ============
    function setRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert ZeroAddress();
        router = _router;
    }
    
    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) revert ZeroAddress();
        keeper = _keeper;
    }
    
    function setPositionLedger(address _ledger) external onlyOwner {
        if (_ledger == address(0)) revert ZeroAddress();
        positionLedger = _ledger;
    }
    
    function setTotalTVL(uint256 _tvl) external onlyOwner {
        totalTVL = _tvl;
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
    
    // ============ Market Setup ============
    
    /**
     * @notice Initialize a market for trading
     * @param marketId Market ID
     * @param depth Custom market depth (0 = use default)
     */
    function initializeMarket(uint256 marketId, uint256 depth) external onlyOwner {
        marketInitialized[marketId] = true;
        if (depth > 0) {
            marketDepth[marketId] = depth;
        }
        emit MarketInitialized(marketId, depth);
    }
    
    /**
     * @notice Set custom depth for a market
     */
    function setMarketDepth(uint256 marketId, uint256 depth) external onlyOwner {
        marketDepth[marketId] = depth;
    }
    
    // ============ Core Trading (Router Interface) ============
    
    /**
     * @notice Execute a swap - called by Router
     * @param marketId Market ID
     * @param trader Trader address (for event)
     * @param isBuy True for long, false for short
     * @param amountIn Notional trade size
     * @param minAmountOut Minimum output (slippage protection) - not used in this model
     * @return amountOut Same as amountIn (no token swap, just pricing)
     * @return executionPrice The execution price with impact
     */
    function swap(
        uint256 marketId,
        address trader,
        bool isBuy,
        uint256 amountIn,
        uint256 minAmountOut
    ) external onlyRouter marketExists(marketId) returns (
        uint256 amountOut,
        uint256 executionPrice
    ) {
        if (amountIn == 0) revert InvalidAmount();
        
        int256 impactBps;
        (executionPrice, impactBps) = _calculateExecutionPrice(marketId, isBuy, amountIn);
        
        // In this model, amountOut = amountIn (notional sizing, not token swap)
        amountOut = amountIn;
        
        emit SwapExecuted(marketId, trader, isBuy, amountIn, amountOut, executionPrice, impactBps);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get execution price for a trade (quote)
     * @return amountOut Same as input (notional)
     * @return executionPrice Price with impact applied
     * @return priceImpact Impact in basis points (can be negative for rebates)
     */
    function getExecutionPrice(
        uint256 marketId,
        bool isBuy,
        uint256 amountIn
    ) external view marketExists(marketId) returns (
        uint256 amountOut,
        uint256 executionPrice,
        uint256 priceImpact
    ) {
        int256 impactBps;
        (executionPrice, impactBps) = _calculateExecutionPrice(marketId, isBuy, amountIn);
        amountOut = amountIn;
        priceImpact = impactBps >= 0 ? uint256(impactBps) : uint256(-impactBps);
    }
    
    /**
     * @notice Get current spot price (oracle price)
     */
    function getSpotPrice(uint256 marketId) external view returns (uint256) {
        return _getOraclePrice(marketId);
    }
    
    /**
     * @notice Preview full impact details
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
        int256 currentImbalanceBps
    ) {
        oraclePrice = _getOraclePrice(marketId);
        (longOI, shortOI) = _getOI(marketId);
        (executionPrice, impactBps) = _calculateExecutionPrice(marketId, isBuy, tradeSize);
        
        uint256 totalOI = longOI + shortOI;
        if (totalOI > 0) {
            currentImbalanceBps = int256(longOI * 10000 / totalOI) - 5000;
        }
    }
    
    // ============ Internal ============
    
    function _calculateExecutionPrice(
        uint256 marketId,
        bool isBuy,
        uint256 tradeSize
    ) internal view returns (uint256 executionPrice, int256 impactBps) {
        uint256 oraclePrice = _getOraclePrice(marketId);
        (uint256 longOI, uint256 shortOI) = _getOI(marketId);
        uint256 depth = _getMarketDepth(marketId);
        
        // Base impact = trade_size / (depth × 2)
        uint256 baseImpact = tradeSize * PRECISION / (depth * 2);
        
        // Calculate imbalance before and after
        uint256 totalOI = longOI + shortOI;
        int256 imbalanceBefore = _calculateImbalance(longOI, shortOI, totalOI);
        
        uint256 newLongOI = isBuy ? longOI + tradeSize : longOI;
        uint256 newShortOI = isBuy ? shortOI : shortOI + tradeSize;
        uint256 newTotalOI = newLongOI + newShortOI;
        int256 imbalanceAfter = _calculateImbalance(newLongOI, newShortOI, newTotalOI);
        
        // Delta = |after| - |before| (positive = worsens, negative = improves)
        int256 imbalanceDelta = _abs(imbalanceAfter) - _abs(imbalanceBefore);
        
        // Adjusted impact = base × (1 + delta × multiplier)
        int256 multiplier = int256(PRECISION) + (imbalanceDelta * int256(IMBALANCE_MULTIPLIER));
        int256 adjustedImpact = int256(baseImpact) * multiplier / int256(PRECISION);
        
        // Cap impact
        if (adjustedImpact > int256(MAX_IMPACT)) adjustedImpact = int256(MAX_IMPACT);
        if (adjustedImpact < -int256(MAX_IMPACT)) adjustedImpact = -int256(MAX_IMPACT);
        
        impactBps = adjustedImpact * 10000 / int256(PRECISION);
        
        // Apply impact to price
        if (isBuy) {
            // Buys push price up
            if (adjustedImpact >= 0) {
                executionPrice = oraclePrice * (PRECISION + uint256(adjustedImpact)) / PRECISION;
            } else {
                executionPrice = oraclePrice * (PRECISION - uint256(-adjustedImpact)) / PRECISION;
            }
        } else {
            // Shorts get inverse (lower = better for shorts)
            if (adjustedImpact >= 0) {
                executionPrice = oraclePrice * (PRECISION - uint256(adjustedImpact)) / PRECISION;
            } else {
                executionPrice = oraclePrice * (PRECISION + uint256(-adjustedImpact)) / PRECISION;
            }
        }
        
        // Clamp to valid range
        if (executionPrice > PRECISION) executionPrice = PRECISION;
        if (executionPrice < 1e14) executionPrice = 1e14;
    }
    
    function _calculateImbalance(uint256 longOI, uint256 shortOI, uint256 totalOI) internal pure returns (int256) {
        if (totalOI == 0) return 0;
        // Returns -1 to +1 scaled by PRECISION
        // +1 = 100% long, -1 = 100% short, 0 = balanced
        return (int256(longOI * PRECISION / totalOI) - int256(PRECISION / 2)) * 2;
    }
    
    function _getOraclePrice(uint256 marketId) internal view returns (uint256) {
        (bool success, bytes memory data) = priceEngine.staticcall(
            abi.encodeWithSignature("getMarkPrice(uint256)", marketId)
        );
        require(success && data.length >= 32, "Oracle failed");
        return abi.decode(data, (uint256));
    }
    
    function _getOI(uint256 marketId) internal view returns (uint256 longOI, uint256 shortOI) {
        if (positionLedger == address(0)) return (0, 0);
        
        (bool success, bytes memory data) = positionLedger.staticcall(
            abi.encodeWithSignature("getMarket(uint256)", marketId)
        );
        if (success && data.length >= 96) {
            assembly {
                longOI := mload(add(data, 64))
                shortOI := mload(add(data, 96))
            }
        }
    }
    
    function _getMarketDepth(uint256 marketId) internal view returns (uint256) {
        uint256 depth = marketDepth[marketId];
        if (depth == 0 && totalTVL > 0) {
            depth = totalTVL * DEFAULT_DEPTH_BPS / 10000;
        }
        if (depth < 1000e18) depth = 1000e18; // Min $1000
        return depth;
    }
    
    function _abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }
    
    // ============ Legacy Compatibility ============
    
    /**
     * @notice No-op for compatibility - no pools to recenter
     */
    function recenter(uint256) external onlyKeeper {
        // No-op - stateless pricing doesn't need recentering
    }
    
    /**
     * @notice Legacy pool getter - returns dummy values
     */
    function getPool(uint256 marketId) external view returns (
        uint256 vQ, uint256 vB, uint256 k, uint256 lastPI, uint256 lastUpdate, bool initialized
    ) {
        uint256 price = _getOraclePrice(marketId);
        uint256 depth = _getMarketDepth(marketId);
        vQ = depth * price / PRECISION;
        vB = depth - vQ;
        k = vQ * vB;
        lastPI = price;
        lastUpdate = block.timestamp;
        initialized = marketInitialized[marketId];
    }
}
