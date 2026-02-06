// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title vAMM
 * @author LEVER Protocol
 * @notice Virtual AMM for Entry Price calculation with slippage
 * @dev Implements Module 3 from LEVER Architecture:
 * 
 * KEY CONCEPT: Entry Price ≠ Mark Price
 * - Entry Price: Determined by vAMM (includes slippage) - used for trade execution
 * - Mark Price: From PriceEngineV2 (smoothed PI) - used for PnL/liquidations
 * 
 * The vAMM uses constant product formula: x · y = k
 * - Holds ZERO real capital (purely a calculator)
 * - Virtual reserves determine slippage
 * - JIT keepers re-center to PI before each block
 * - Volatility Spread Guard widens spread during uncertainty
 */
contract vAMM {
    
    // ============ Constants ============
    
    uint256 public constant SCALE = 1e18;
    uint256 public constant MIN_LIQUIDITY = 1e15;    // Minimum virtual liquidity
    
    // Spread guard thresholds
    uint256 public constant SPREAD_THRESHOLD = 5e16;    // 5% deviation triggers spread
    uint256 public constant MAX_SPREAD = 2e16;          // 2% max spread addition
    uint256 public constant BASE_SPREAD = 1e15;         // 0.1% base spread
    
    // ============ Structs ============
    
    struct Pool {
        uint256 vQ;              // Virtual Quote (e.g., virtual USDC)
        uint256 vB;              // Virtual Base (e.g., virtual YES tokens)
        uint256 k;               // Constant product k = vQ × vB
        uint256 lastPI;          // Last oracle PI (for spread guard)
        uint256 lastUpdate;      // Last recenter timestamp
        bool initialized;
    }
    
    // ============ State ============
    
    address public owner;
    address public priceEngine;      // PriceEngineV2 for PI
    address public router;           // Router authorized to execute swaps
    address public keeper;           // JIT keeper for recentering
    
    // marketId => Pool
    mapping(uint256 => Pool) public pools;
    
    // Virtual liquidity depth (controls slippage sensitivity)
    uint256 public defaultVirtualLiquidity = 1_000_000e18;  // $1M default
    
    // ============ Events ============
    
    event PoolInitialized(uint256 indexed marketId, uint256 vQ, uint256 vB, uint256 k);
    event PoolRecentered(uint256 indexed marketId, uint256 newPI, uint256 newVQ, uint256 newVB);
    event SwapExecuted(
        uint256 indexed marketId,
        address indexed trader,
        bool isBuy,
        uint256 amountIn,
        uint256 amountOut,
        uint256 executionPrice
    );
    event SpreadGuardTriggered(uint256 indexed marketId, uint256 deviation, uint256 spreadAdded);
    
    // ============ Errors ============
    
    error Unauthorized();
    error ZeroAddress();
    error PoolNotInitialized();
    error PoolAlreadyInitialized();
    error InsufficientLiquidity();
    error SlippageExceeded();
    error InvalidAmount();
    
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
    
    modifier poolExists(uint256 marketId) {
        if (!pools[marketId].initialized) revert PoolNotInitialized();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _priceEngine) {
        if (_priceEngine == address(0)) revert ZeroAddress();
        owner = msg.sender;
        priceEngine = _priceEngine;
    }
    
    // ============ Admin Functions ============
    
    function setRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert ZeroAddress();
        router = _router;
    }
    
    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) revert ZeroAddress();
        keeper = _keeper;
    }
    
    function setDefaultVirtualLiquidity(uint256 _liquidity) external onlyOwner {
        defaultVirtualLiquidity = _liquidity;
    }
    
    /**
     * @notice Initialize a pool for a market
     * @param marketId Market identifier
     * @param initialPI Initial probability index (from oracle)
     * @param virtualLiquidity Virtual liquidity depth (controls slippage)
     */
    function initializePool(
        uint256 marketId,
        uint256 initialPI,
        uint256 virtualLiquidity
    ) external onlyOwner {
        if (pools[marketId].initialized) revert PoolAlreadyInitialized();
        if (virtualLiquidity < MIN_LIQUIDITY) virtualLiquidity = defaultVirtualLiquidity;
        
        // Set reserves such that vQ/vB = initialPI
        // With constraint that vQ × vB = k (constant)
        // vQ = sqrt(k × PI), vB = sqrt(k / PI)
        // For simplicity: vQ = virtualLiquidity × PI, vB = virtualLiquidity
        // This gives price = vQ/vB = PI as desired
        
        uint256 vQ = virtualLiquidity * initialPI / SCALE;
        uint256 vB = virtualLiquidity * (SCALE - initialPI) / SCALE;
        
        // Ensure minimum reserves
        if (vQ < MIN_LIQUIDITY) vQ = MIN_LIQUIDITY;
        if (vB < MIN_LIQUIDITY) vB = MIN_LIQUIDITY;
        
        uint256 k = vQ * vB;
        
        pools[marketId] = Pool({
            vQ: vQ,
            vB: vB,
            k: k,
            lastPI: initialPI,
            lastUpdate: block.timestamp,
            initialized: true
        });
        
        emit PoolInitialized(marketId, vQ, vB, k);
    }
    
    // ============ JIT Keeper Functions ============
    
    /**
     * @notice Re-center pool to current oracle PI
     * @dev Called by JIT keeper before each block/trade
     *      This ensures traders enter at fair prices
     */
    function recenter(uint256 marketId) external onlyKeeper poolExists(marketId) {
        Pool storage pool = pools[marketId];
        
        // Get current PI from PriceEngineV2
        uint256 currentPI = _getOraclePI(marketId);
        
        // Maintain k but adjust reserves to match PI
        // New vQ/vB should equal currentPI
        // vQ × vB = k (constant)
        // vQ = sqrt(k × PI), vB = sqrt(k / PI)
        
        uint256 sqrtK = _sqrt(pool.k);
        uint256 sqrtPI = _sqrt(currentPI * SCALE); // sqrt(PI × SCALE) to maintain precision
        uint256 sqrtInvPI = _sqrt(SCALE * SCALE / currentPI);
        
        pool.vQ = sqrtK * sqrtPI / SCALE;
        pool.vB = sqrtK * sqrtInvPI / SCALE;
        
        // Ensure minimum reserves
        if (pool.vQ < MIN_LIQUIDITY) pool.vQ = MIN_LIQUIDITY;
        if (pool.vB < MIN_LIQUIDITY) pool.vB = MIN_LIQUIDITY;
        
        pool.lastPI = currentPI;
        pool.lastUpdate = block.timestamp;
        
        emit PoolRecentered(marketId, currentPI, pool.vQ, pool.vB);
    }
    
    // ============ Core Trading Functions ============
    
    /**
     * @notice Get execution price for a trade (quote)
     * @param marketId Market ID
     * @param isBuy True for buying YES (going long), false for selling
     * @param amountIn Amount of quote currency (USDC) for buy, or base for sell
     * @return amountOut Amount received
     * @return executionPrice Average execution price
     * @return priceImpact Price impact in basis points
     */
    function getExecutionPrice(
        uint256 marketId,
        bool isBuy,
        uint256 amountIn
    ) external view poolExists(marketId) returns (
        uint256 amountOut,
        uint256 executionPrice,
        uint256 priceImpact
    ) {
        Pool storage pool = pools[marketId];
        
        // Get current spot price before trade
        uint256 spotPrice = pool.vQ * SCALE / pool.vB;
        
        // Apply volatility spread guard
        uint256 spread = _calculateSpread(marketId);
        
        if (isBuy) {
            // Buying YES: trader sends Quote, receives Base
            // x · y = k → (vQ + Δin) · (vB - Δout) = k
            // Δout = vB - k / (vQ + Δin)
            uint256 newVQ = pool.vQ + amountIn;
            uint256 newVB = pool.k / newVQ;
            amountOut = pool.vB - newVB;
            
            // Apply spread (reduces amount out)
            amountOut = amountOut * (SCALE - spread) / SCALE;
            
            executionPrice = amountIn * SCALE / amountOut;
        } else {
            // Selling YES: trader sends Base, receives Quote  
            // (vQ - Δout) · (vB + Δin) = k
            // Δout = vQ - k / (vB + Δin)
            uint256 newVB = pool.vB + amountIn;
            uint256 newVQ = pool.k / newVB;
            amountOut = pool.vQ - newVQ;
            
            // Apply spread (reduces amount out)
            amountOut = amountOut * (SCALE - spread) / SCALE;
            
            executionPrice = amountOut * SCALE / amountIn;
        }
        
        // Calculate price impact
        if (isBuy) {
            priceImpact = executionPrice > spotPrice 
                ? (executionPrice - spotPrice) * 10000 / spotPrice 
                : 0;
        } else {
            priceImpact = spotPrice > executionPrice 
                ? (spotPrice - executionPrice) * 10000 / spotPrice 
                : 0;
        }
    }
    
    /**
     * @notice Execute a swap (called by Router only)
     * @param marketId Market ID
     * @param trader Trader address
     * @param isBuy True for buying YES (long), false for selling (short entry or long exit)
     * @param amountIn Amount in
     * @param minAmountOut Minimum amount out (slippage protection)
     * @return amountOut Actual amount received
     * @return executionPrice Execution price
     */
    function swap(
        uint256 marketId,
        address trader,
        bool isBuy,
        uint256 amountIn,
        uint256 minAmountOut
    ) external onlyRouter poolExists(marketId) returns (
        uint256 amountOut,
        uint256 executionPrice
    ) {
        if (amountIn == 0) revert InvalidAmount();
        
        Pool storage pool = pools[marketId];
        
        // Calculate spread
        uint256 spread = _calculateSpread(marketId);
        
        if (isBuy) {
            // Buying YES
            uint256 newVQ = pool.vQ + amountIn;
            uint256 newVB = pool.k / newVQ;
            amountOut = pool.vB - newVB;
            
            // Apply spread
            amountOut = amountOut * (SCALE - spread) / SCALE;
            
            if (amountOut < minAmountOut) revert SlippageExceeded();
            
            // Update reserves
            pool.vQ = newVQ;
            pool.vB = newVB;
            
            executionPrice = amountIn * SCALE / amountOut;
        } else {
            // Selling YES
            uint256 newVB = pool.vB + amountIn;
            uint256 newVQ = pool.k / newVB;
            amountOut = pool.vQ - newVQ;
            
            // Apply spread
            amountOut = amountOut * (SCALE - spread) / SCALE;
            
            if (amountOut < minAmountOut) revert SlippageExceeded();
            
            // Update reserves
            pool.vQ = newVQ;
            pool.vB = newVB;
            
            executionPrice = amountOut * SCALE / amountIn;
        }
        
        emit SwapExecuted(marketId, trader, isBuy, amountIn, amountOut, executionPrice);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get current spot price (vQ/vB ratio)
     */
    function getSpotPrice(uint256 marketId) external view poolExists(marketId) returns (uint256) {
        Pool storage pool = pools[marketId];
        return pool.vQ * SCALE / pool.vB;
    }
    
    /**
     * @notice Get pool state
     */
    function getPool(uint256 marketId) external view returns (Pool memory) {
        return pools[marketId];
    }
    
    /**
     * @notice Get current spread (for frontend display)
     */
    function getCurrentSpread(uint256 marketId) external view returns (uint256) {
        return _calculateSpread(marketId);
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Calculate dynamic spread based on oracle deviation
     * @dev Volatility Spread Guard: widen spread when PI deviates from vAMM price
     */
    function _calculateSpread(uint256 marketId) internal view returns (uint256 spread) {
        Pool storage pool = pools[marketId];
        
        // Current vAMM price
        uint256 vammPrice = pool.vQ * SCALE / pool.vB;
        
        // Get raw oracle price
        uint256 rawPI = _getRawOraclePI(marketId);
        
        // Calculate deviation
        uint256 deviation = rawPI > vammPrice 
            ? rawPI - vammPrice 
            : vammPrice - rawPI;
        
        // Base spread always applies
        spread = BASE_SPREAD;
        
        // Add dynamic spread if deviation exceeds threshold
        if (deviation > SPREAD_THRESHOLD) {
            // Linear scaling: more deviation = wider spread
            uint256 excessDeviation = deviation - SPREAD_THRESHOLD;
            uint256 additionalSpread = excessDeviation * MAX_SPREAD / SCALE;
            
            // Cap additional spread
            if (additionalSpread > MAX_SPREAD) additionalSpread = MAX_SPREAD;
            
            spread += additionalSpread;
            
            // Note: Can't emit in view function - spread guard triggered
            // emit SpreadGuardTriggered(marketId, deviation, additionalSpread);
        }
    }
    
    /**
     * @notice Get smoothed PI from PriceEngineV2 (for recentering)
     */
    function _getOraclePI(uint256 marketId) internal view returns (uint256) {
        (bool success, bytes memory data) = priceEngine.staticcall(
            abi.encodeWithSignature("getSmoothedPrice(uint256)", marketId)
        );
        require(success && data.length >= 32, "Failed to get PI");
        return abi.decode(data, (uint256));
    }
    
    /**
     * @notice Get raw PI from PriceEngineV2 (for spread guard)
     */
    function _getRawOraclePI(uint256 marketId) internal view returns (uint256) {
        (bool success, bytes memory data) = priceEngine.staticcall(
            abi.encodeWithSignature("getRawPrice(uint256)", marketId)
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        
        // Fallback to smoothed if raw not available
        return _getOraclePI(marketId);
    }
    
    /**
     * @notice Integer square root (Babylonian method)
     */
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
