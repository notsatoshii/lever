// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PriceEngineV2
 * @author LEVER Protocol
 * @notice Manipulation-resistant price engine implementing the North Star architecture
 * 
 * Core Principle: Entry Price ≠ Mark Price
 * - Entry Price: Determined by vAMM (separate contract), includes slippage
 * - Mark Price: Determined by Probability Index (PI), used for PnL/Margin/Liquidations
 * 
 * This contract ONLY handles Mark Price (the PI). vAMM is separate.
 * 
 * Anti-Manipulation Features:
 * 1. Input Validation Layer - Rejects suspicious price updates
 * 2. Volatility Dampening - w_vol = 1/(1+σ), stickier when volatile
 * 3. Time-Weighted Smoothing - w_time = √(τ/τ_max), locks near expiry
 * 4. Combined Smoothing Formula: P_smooth(t) = P_smooth(t-1) + α × w_vol × (P_raw - P_smooth(t-1))
 */

contract PriceEngineV2 {
    
    // ============ Structs ============
    
    struct MarketConfig {
        uint256 expiryTimestamp;      // When market resolves (0 = perpetual)
        uint256 maxSpread;            // Max bid-ask spread to accept (basis points)
        uint256 maxTickMovement;      // Max price change per update (basis points)
        uint256 minLiquidityDepth;    // Minimum liquidity to accept update
        uint256 alpha;                // Base smoothing factor (0-1e18)
        uint256 volatilityWindow;     // Seconds to calculate volatility over
        bool active;                  // Is market active
    }
    
    struct PriceState {
        uint256 rawPrice;             // Latest raw price from oracle (P_raw)
        uint256 smoothedPrice;        // Smoothed probability index (P_smooth / PI)
        uint256 lastUpdate;           // Last update timestamp
        uint256 volatility;           // Current volatility estimate (σ, scaled 1e18)
    }
    
    struct PriceHistory {
        uint256 price;
        uint256 timestamp;
    }
    
    // ============ Constants ============
    
    uint256 public constant PRECISION = 1e18;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_HISTORY = 20;  // Rolling window for volatility
    
    // ============ State ============
    
    address public owner;
    
    mapping(uint256 => MarketConfig) public marketConfigs;
    mapping(uint256 => PriceState) public priceStates;
    mapping(uint256 => PriceHistory[]) public priceHistories;  // For volatility calc
    
    mapping(address => bool) public authorizedKeepers;
    
    // ============ Events ============
    
    event MarketConfigured(
        uint256 indexed marketId,
        uint256 expiryTimestamp,
        uint256 alpha
    );
    event PriceUpdated(
        uint256 indexed marketId,
        uint256 rawPrice,
        uint256 smoothedPrice,
        uint256 volatility,
        uint256 volWeight,
        uint256 timeWeight
    );
    event PriceRejected(
        uint256 indexed marketId,
        uint256 rawPrice,
        string reason
    );
    event KeeperAuthorized(address indexed keeper, bool authorized);
    event MarketSettled(uint256 indexed marketId, uint256 finalPrice);
    
    // ============ Errors ============
    
    error Unauthorized();
    error MarketNotConfigured();
    error MarketExpired();
    error MarketNotExpired();
    error InvalidPrice();
    error SpreadTooWide();
    error TickMovementTooLarge();
    error LiquidityTooLow();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyKeeper() {
        if (!authorizedKeepers[msg.sender]) revert Unauthorized();
        _;
    }
    
    modifier marketActive(uint256 marketId) {
        if (!marketConfigs[marketId].active) revert MarketNotConfigured();
        if (marketConfigs[marketId].expiryTimestamp != 0 && 
            block.timestamp >= marketConfigs[marketId].expiryTimestamp) {
            revert MarketExpired();
        }
        _;
    }
    
    // ============ Constructor ============
    
    constructor() {
        owner = msg.sender;
        authorizedKeepers[msg.sender] = true;
    }
    
    // ============ Admin Functions ============
    
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
    
    function setKeeperAuthorization(address keeper, bool authorized) external onlyOwner {
        authorizedKeepers[keeper] = authorized;
        emit KeeperAuthorized(keeper, authorized);
    }
    
    /**
     * @notice Configure a new market
     * @param marketId Unique market identifier
     * @param expiryTimestamp When market resolves (0 for perpetual)
     * @param maxSpread Max bid-ask spread in basis points
     * @param maxTickMovement Max single-update price change in basis points
     * @param minLiquidityDepth Minimum liquidity required
     * @param alpha Base smoothing factor (suggested: 0.1e18 = 10%)
     * @param volatilityWindow Seconds for volatility calculation (suggested: 3600)
     */
    function configureMarket(
        uint256 marketId,
        uint256 expiryTimestamp,
        uint256 maxSpread,
        uint256 maxTickMovement,
        uint256 minLiquidityDepth,
        uint256 alpha,
        uint256 volatilityWindow
    ) external onlyOwner {
        require(alpha <= PRECISION, "Alpha > 1");
        require(expiryTimestamp == 0 || expiryTimestamp > block.timestamp, "Invalid expiry");
        
        marketConfigs[marketId] = MarketConfig({
            expiryTimestamp: expiryTimestamp,
            maxSpread: maxSpread,
            maxTickMovement: maxTickMovement,
            minLiquidityDepth: minLiquidityDepth,
            alpha: alpha,
            volatilityWindow: volatilityWindow,
            active: true
        });
        
        emit MarketConfigured(marketId, expiryTimestamp, alpha);
    }
    
    /**
     * @notice Update market expiry (e.g., if event date changes)
     */
    function setMarketExpiry(uint256 marketId, uint256 newExpiry) external onlyOwner {
        require(marketConfigs[marketId].active, "Market not configured");
        marketConfigs[marketId].expiryTimestamp = newExpiry;
    }
    
    /**
     * @notice Deactivate a market
     */
    function deactivateMarket(uint256 marketId) external onlyOwner {
        marketConfigs[marketId].active = false;
    }
    
    /**
     * @notice Force set price (admin emergency override)
     */
    function forceSetPrice(uint256 marketId, uint256 price) external onlyOwner {
        require(price > 0 && price <= PRECISION, "Invalid price");
        
        priceStates[marketId].rawPrice = price;
        priceStates[marketId].smoothedPrice = price;
        priceStates[marketId].lastUpdate = block.timestamp;
        
        emit PriceUpdated(marketId, price, price, 0, PRECISION, PRECISION);
    }
    
    // ============ Keeper Functions ============
    
    /**
     * @notice Update price with full validation
     * @param marketId Market to update
     * @param rawPrice New raw price from oracle (0-1e18, representing 0-100%)
     * @param spread Current bid-ask spread (basis points)
     * @param liquidityDepth Current orderbook depth
     */
    function updatePrice(
        uint256 marketId,
        uint256 rawPrice,
        uint256 spread,
        uint256 liquidityDepth
    ) external onlyKeeper marketActive(marketId) {
        // Validate price range
        if (rawPrice == 0 || rawPrice > PRECISION) revert InvalidPrice();
        
        MarketConfig storage config = marketConfigs[marketId];
        PriceState storage state = priceStates[marketId];
        
        // === INPUT VALIDATION LAYER ===
        
        // 1. Check spread
        if (spread > config.maxSpread) {
            emit PriceRejected(marketId, rawPrice, "Spread too wide");
            revert SpreadTooWide();
        }
        
        // 2. Check tick movement (if not first update)
        if (state.lastUpdate != 0) {
            uint256 tickMovement = _calculateDeviation(rawPrice, state.rawPrice);
            if (tickMovement > config.maxTickMovement) {
                emit PriceRejected(marketId, rawPrice, "Tick movement too large");
                revert TickMovementTooLarge();
            }
        }
        
        // 3. Check liquidity depth
        if (liquidityDepth < config.minLiquidityDepth) {
            emit PriceRejected(marketId, rawPrice, "Liquidity too low");
            revert LiquidityTooLow();
        }
        
        // === SMOOTHING ENGINE ===
        
        uint256 newSmoothedPrice;
        uint256 volWeight;
        uint256 timeWeight;
        
        if (state.lastUpdate == 0) {
            // First update - use raw price directly
            newSmoothedPrice = rawPrice;
            volWeight = PRECISION;
            timeWeight = PRECISION;
            state.volatility = 0;
        } else {
            // Calculate volatility from history
            uint256 volatility = _calculateVolatility(marketId);
            state.volatility = volatility;
            
            // Formula 1: Volatility Dampening
            // w_vol = 1 / (1 + σ)
            volWeight = PRECISION * PRECISION / (PRECISION + volatility);
            
            // Formula 2: Time-Weighted Smoothing
            // w_time = √(τ / τ_max)
            timeWeight = _calculateTimeWeight(marketId);
            
            // Formula 3: Combined Update
            // P_smooth(t) = P_smooth(t-1) + α × w_vol × w_time × (P_raw - P_smooth(t-1))
            uint256 effectiveAlpha = config.alpha * volWeight / PRECISION;
            effectiveAlpha = effectiveAlpha * timeWeight / PRECISION;
            
            int256 priceDelta = int256(rawPrice) - int256(state.smoothedPrice);
            int256 adjustment = int256(effectiveAlpha) * priceDelta / int256(PRECISION);
            
            newSmoothedPrice = uint256(int256(state.smoothedPrice) + adjustment);
            
            // Clamp to valid range
            if (newSmoothedPrice > PRECISION) newSmoothedPrice = PRECISION;
            if (newSmoothedPrice == 0) newSmoothedPrice = 1;
        }
        
        // Update state
        state.rawPrice = rawPrice;
        state.smoothedPrice = newSmoothedPrice;
        state.lastUpdate = block.timestamp;
        
        // Add to history for volatility calculation
        _addToHistory(marketId, rawPrice);
        
        emit PriceUpdated(marketId, rawPrice, newSmoothedPrice, state.volatility, volWeight, timeWeight);
    }
    
    /**
     * @notice Simplified update (for trusted sources with pre-validated data)
     */
    function updatePriceSimple(
        uint256 marketId,
        uint256 rawPrice
    ) external onlyKeeper marketActive(marketId) {
        if (rawPrice == 0 || rawPrice > PRECISION) revert InvalidPrice();
        
        MarketConfig storage config = marketConfigs[marketId];
        PriceState storage state = priceStates[marketId];
        
        // Check tick movement
        if (state.lastUpdate != 0) {
            uint256 tickMovement = _calculateDeviation(rawPrice, state.rawPrice);
            if (tickMovement > config.maxTickMovement) {
                revert TickMovementTooLarge();
            }
        }
        
        uint256 newSmoothedPrice;
        uint256 volWeight = PRECISION;
        uint256 timeWeight = PRECISION;
        
        if (state.lastUpdate == 0) {
            newSmoothedPrice = rawPrice;
        } else {
            uint256 volatility = _calculateVolatility(marketId);
            state.volatility = volatility;
            
            volWeight = PRECISION * PRECISION / (PRECISION + volatility);
            timeWeight = _calculateTimeWeight(marketId);
            
            uint256 effectiveAlpha = config.alpha * volWeight / PRECISION;
            effectiveAlpha = effectiveAlpha * timeWeight / PRECISION;
            
            int256 priceDelta = int256(rawPrice) - int256(state.smoothedPrice);
            int256 adjustment = int256(effectiveAlpha) * priceDelta / int256(PRECISION);
            
            newSmoothedPrice = uint256(int256(state.smoothedPrice) + adjustment);
            if (newSmoothedPrice > PRECISION) newSmoothedPrice = PRECISION;
            if (newSmoothedPrice == 0) newSmoothedPrice = 1;
        }
        
        state.rawPrice = rawPrice;
        state.smoothedPrice = newSmoothedPrice;
        state.lastUpdate = block.timestamp;
        
        _addToHistory(marketId, rawPrice);
        
        emit PriceUpdated(marketId, rawPrice, newSmoothedPrice, state.volatility, volWeight, timeWeight);
    }
    
    /**
     * @notice Batch update multiple markets
     */
    function batchUpdatePrices(
        uint256[] calldata marketIds,
        uint256[] calldata rawPrices
    ) external onlyKeeper {
        require(marketIds.length == rawPrices.length, "Length mismatch");
        
        for (uint256 i = 0; i < marketIds.length; i++) {
            uint256 marketId = marketIds[i];
            uint256 rawPrice = rawPrices[i];
            
            if (!marketConfigs[marketId].active) continue;
            if (marketConfigs[marketId].expiryTimestamp != 0 && 
                block.timestamp >= marketConfigs[marketId].expiryTimestamp) continue;
            if (rawPrice == 0 || rawPrice > PRECISION) continue;
            
            MarketConfig storage config = marketConfigs[marketId];
            PriceState storage state = priceStates[marketId];
            
            // Skip if tick movement too large
            if (state.lastUpdate != 0) {
                uint256 tickMovement = _calculateDeviation(rawPrice, state.rawPrice);
                if (tickMovement > config.maxTickMovement) continue;
            }
            
            uint256 newSmoothedPrice;
            
            if (state.lastUpdate == 0) {
                newSmoothedPrice = rawPrice;
                state.volatility = 0;
            } else {
                uint256 volatility = _calculateVolatility(marketId);
                state.volatility = volatility;
                
                uint256 volWeight = PRECISION * PRECISION / (PRECISION + volatility);
                uint256 timeWeight = _calculateTimeWeight(marketId);
                
                uint256 effectiveAlpha = config.alpha * volWeight / PRECISION;
                effectiveAlpha = effectiveAlpha * timeWeight / PRECISION;
                
                int256 priceDelta = int256(rawPrice) - int256(state.smoothedPrice);
                int256 adjustment = int256(effectiveAlpha) * priceDelta / int256(PRECISION);
                
                newSmoothedPrice = uint256(int256(state.smoothedPrice) + adjustment);
                if (newSmoothedPrice > PRECISION) newSmoothedPrice = PRECISION;
                if (newSmoothedPrice == 0) newSmoothedPrice = 1;
            }
            
            state.rawPrice = rawPrice;
            state.smoothedPrice = newSmoothedPrice;
            state.lastUpdate = block.timestamp;
            
            _addToHistory(marketId, rawPrice);
        }
    }
    
    /**
     * @notice Settle market at expiry with final price
     */
    function settleMarket(uint256 marketId, uint256 finalPrice) external onlyOwner {
        MarketConfig storage config = marketConfigs[marketId];
        require(config.active, "Market not active");
        require(config.expiryTimestamp != 0, "Perpetual market");
        require(block.timestamp >= config.expiryTimestamp, "Not expired yet");
        require(finalPrice == 0 || finalPrice == PRECISION, "Final price must be 0 or 1e18");
        
        priceStates[marketId].smoothedPrice = finalPrice;
        priceStates[marketId].rawPrice = finalPrice;
        config.active = false;
        
        emit MarketSettled(marketId, finalPrice);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get the Mark Price (PI) for PnL/Margin/Liquidation calculations
     * @dev This is THE price to use for solvency checks - manipulation resistant
     */
    function getMarkPrice(uint256 marketId) external view returns (uint256) {
        return priceStates[marketId].smoothedPrice;
    }
    
    /**
     * @notice Get raw oracle price (for reference only, NOT for liquidations)
     */
    function getRawPrice(uint256 marketId) external view returns (uint256) {
        return priceStates[marketId].rawPrice;
    }
    
    /**
     * @notice Get full price state
     */
    function getPriceState(uint256 marketId) external view returns (
        uint256 rawPrice,
        uint256 smoothedPrice,
        uint256 lastUpdate,
        uint256 volatility
    ) {
        PriceState storage state = priceStates[marketId];
        return (state.rawPrice, state.smoothedPrice, state.lastUpdate, state.volatility);
    }
    
    /**
     * @notice Get market config
     */
    function getMarketConfig(uint256 marketId) external view returns (
        uint256 expiryTimestamp,
        uint256 maxSpread,
        uint256 maxTickMovement,
        uint256 minLiquidityDepth,
        uint256 alpha,
        bool active
    ) {
        MarketConfig storage config = marketConfigs[marketId];
        return (
            config.expiryTimestamp,
            config.maxSpread,
            config.maxTickMovement,
            config.minLiquidityDepth,
            config.alpha,
            config.active
        );
    }
    
    /**
     * @notice Get time until market expiry
     */
    function getTimeToExpiry(uint256 marketId) external view returns (uint256) {
        uint256 expiry = marketConfigs[marketId].expiryTimestamp;
        if (expiry == 0) return type(uint256).max; // Perpetual
        if (block.timestamp >= expiry) return 0;
        return expiry - block.timestamp;
    }
    
    /**
     * @notice Check if market is expired
     */
    function isExpired(uint256 marketId) external view returns (bool) {
        uint256 expiry = marketConfigs[marketId].expiryTimestamp;
        if (expiry == 0) return false;
        return block.timestamp >= expiry;
    }
    
    /**
     * @notice Check if price is stale
     */
    function isPriceStale(uint256 marketId, uint256 maxAge) external view returns (bool) {
        return block.timestamp - priceStates[marketId].lastUpdate > maxAge;
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Calculate volatility from price history
     * @dev Uses standard deviation of returns
     */
    function _calculateVolatility(uint256 marketId) internal view returns (uint256) {
        PriceHistory[] storage history = priceHistories[marketId];
        uint256 len = history.length;
        
        if (len < 2) return 0;
        
        MarketConfig storage config = marketConfigs[marketId];
        uint256 cutoff = block.timestamp > config.volatilityWindow 
            ? block.timestamp - config.volatilityWindow 
            : 0;
        
        // Calculate returns and their variance
        uint256 sumSquaredReturns = 0;
        uint256 count = 0;
        
        for (uint256 i = 1; i < len; i++) {
            if (history[i].timestamp < cutoff) continue;
            
            uint256 prevPrice = history[i-1].price;
            uint256 currPrice = history[i].price;
            
            if (prevPrice == 0) continue;
            
            // Return = |curr - prev| / prev
            uint256 absDiff = currPrice > prevPrice 
                ? currPrice - prevPrice 
                : prevPrice - currPrice;
            uint256 returnVal = absDiff * PRECISION / prevPrice;
            
            sumSquaredReturns += returnVal * returnVal / PRECISION;
            count++;
        }
        
        if (count == 0) return 0;
        
        // Volatility = sqrt(variance) ≈ sqrt(sumSquaredReturns / count)
        uint256 variance = sumSquaredReturns / count;
        return _sqrt(variance * PRECISION);
    }
    
    /**
     * @notice Calculate time weight for smoothing near expiry
     * @dev w_time = √(τ / τ_max) where τ = time to expiry
     * Near expiry: w_time → 0, making price very sticky
     * Far from expiry: w_time → 1, normal responsiveness
     */
    function _calculateTimeWeight(uint256 marketId) internal view returns (uint256) {
        uint256 expiry = marketConfigs[marketId].expiryTimestamp;
        
        // Perpetual markets have full time weight
        if (expiry == 0) return PRECISION;
        
        // Expired markets have zero weight (fully locked)
        if (block.timestamp >= expiry) return 0;
        
        uint256 timeToExpiry = expiry - block.timestamp;
        
        // τ_max = 30 days (in seconds) - configurable baseline
        uint256 tauMax = 30 days;
        
        // Cap at tauMax (so distant expiries don't get > 1 weight)
        if (timeToExpiry >= tauMax) return PRECISION;
        
        // w_time = √(τ / τ_max)
        uint256 ratio = timeToExpiry * PRECISION / tauMax;
        return _sqrt(ratio * PRECISION);
    }
    
    /**
     * @notice Add price to history (rolling window)
     */
    function _addToHistory(uint256 marketId, uint256 price) internal {
        PriceHistory[] storage history = priceHistories[marketId];
        
        history.push(PriceHistory({
            price: price,
            timestamp: block.timestamp
        }));
        
        // Trim old entries if over max
        if (history.length > MAX_HISTORY) {
            // Shift array (expensive but bounded by MAX_HISTORY)
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history.pop();
        }
    }
    
    /**
     * @notice Calculate deviation between two prices (in basis points)
     */
    function _calculateDeviation(uint256 price1, uint256 price2) internal pure returns (uint256) {
        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        uint256 avg = (price1 + price2) / 2;
        if (avg == 0) return 0;
        return (diff * BASIS_POINTS) / avg;
    }
    
    /**
     * @notice Integer square root (Babylonian method)
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        
        return y;
    }
}
