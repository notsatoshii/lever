// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PriceEngine
 * @author LEVER Protocol
 * @notice Oracle integration and mark price calculation for prediction markets
 * @dev Answers: "What is the fair price/probability right now?"
 * 
 * Components:
 * - External probability index (aggregates Polymarket, UMA, etc.)
 * - EMA smoothing to prevent manipulation
 * - vAMM pricing curve for slippage
 * - Mark price for PnL calculations
 * 
 * Price Flow:
 * 1. ProbabilityIndex aggregates prices from multiple sources
 * 2. PriceEngine pulls from index OR receives direct keeper updates
 * 3. EMA smoothing applied to prevent manipulation
 * 4. vAMM adjustment based on OI imbalance
 * 5. Final mark price used for PnL and liquidations
 */

import {IPositionLedger} from "./interfaces/IPositionLedger.sol";

interface IProbabilityIndex {
    function getIndexPrice(uint256 marketId) external view returns (uint256);
    function calculateIndex(uint256 marketId) external returns (uint256);
    function previewIndex(uint256 marketId) external view returns (
        uint256 calculatedIndex,
        uint256 sourcesUsed,
        uint256[] memory usedSourceIds,
        uint256[] memory usedPrices
    );
}

contract PriceEngine {
    
    // ============ Structs ============
    
    struct PriceConfig {
        address oracle;              // External oracle address
        uint256 emaPeriod;           // EMA smoothing period (seconds)
        uint256 maxDeviation;        // Max deviation from oracle (basis points)
        uint256 vammDepth;           // Virtual AMM depth for slippage
        uint256 lastUpdate;          // Last price update timestamp
        uint256 oraclePrice;         // Latest oracle price
        uint256 emaPrice;            // EMA-smoothed price
        uint256 markPrice;           // Final mark price for PnL
    }
    
    // ============ State ============
    
    address public owner;
    IPositionLedger public immutable ledger;
    IProbabilityIndex public probabilityIndex;
    
    // marketId => PriceConfig
    mapping(uint256 => PriceConfig) public priceConfigs;
    
    // marketId => use probability index (vs direct keeper updates)
    mapping(uint256 => bool) public useIndex;
    
    // Authorized price updaters (keepers)
    mapping(address => bool) public authorizedKeepers;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant PRICE_PRECISION = 1e18;
    
    // ============ Events ============
    
    event PriceConfigSet(uint256 indexed marketId, address oracle, uint256 emaPeriod, uint256 vammDepth);
    event PriceUpdated(uint256 indexed marketId, uint256 oraclePrice, uint256 emaPrice, uint256 markPrice);
    event KeeperAuthorized(address indexed keeper, bool authorized);
    
    // ============ Errors ============
    
    error Unauthorized();
    error InvalidPrice();
    error StalePrice();
    error PriceDeviationTooHigh();
    error MarketNotConfigured();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyKeeper() {
        if (!authorizedKeepers[msg.sender]) revert Unauthorized();
        _;
    }
    
    modifier marketConfigured(uint256 marketId) {
        if (priceConfigs[marketId].oracle == address(0)) revert MarketNotConfigured();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _ledger) {
        owner = msg.sender;
        ledger = IPositionLedger(_ledger);
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
     * @notice Set the probability index contract
     */
    function setProbabilityIndex(address _index) external onlyOwner {
        probabilityIndex = IProbabilityIndex(_index);
    }
    
    /**
     * @notice Enable/disable probability index for a market
     * @dev When enabled, updatePriceFromIndex() should be used instead of updatePrice()
     */
    function setUseIndex(uint256 marketId, bool _useIndex) external onlyOwner {
        useIndex[marketId] = _useIndex;
    }
    
    function configurePricing(
        uint256 marketId,
        address oracle,
        uint256 emaPeriod,
        uint256 maxDeviation,
        uint256 vammDepth
    ) external onlyOwner {
        priceConfigs[marketId] = PriceConfig({
            oracle: oracle,
            emaPeriod: emaPeriod,
            maxDeviation: maxDeviation,
            vammDepth: vammDepth,
            lastUpdate: 0,
            oraclePrice: 0,
            emaPrice: 0,
            markPrice: 0
        });
        emit PriceConfigSet(marketId, oracle, emaPeriod, vammDepth);
    }
    
    /**
     * @notice Force update price (admin bypass for stale/deviated prices)
     * @dev Skips deviation check, resets EMA to new price
     * @param marketId Market to update
     * @param newPrice New price to set (0-1e18)
     */
    function forceUpdatePrice(
        uint256 marketId,
        uint256 newPrice
    ) external onlyOwner marketConfigured(marketId) {
        if (newPrice == 0 || newPrice > PRICE_PRECISION) revert InvalidPrice();
        
        PriceConfig storage config = priceConfigs[marketId];
        uint256 markPrice = _calculateMarkPrice(marketId, newPrice, config.vammDepth);
        
        config.oraclePrice = newPrice;
        config.emaPrice = newPrice;  // Reset EMA to new price
        config.markPrice = markPrice;
        config.lastUpdate = block.timestamp;
        
        emit PriceUpdated(marketId, newPrice, newPrice, markPrice);
    }
    
    /**
     * @notice Update maxDeviation for a market
     */
    function setMaxDeviation(uint256 marketId, uint256 newMaxDeviation) external onlyOwner {
        priceConfigs[marketId].maxDeviation = newMaxDeviation;
    }
    
    // ============ Keeper Functions ============
    
    /**
     * @notice Update price from oracle
     * @param marketId Market to update
     * @param newOraclePrice Fresh price from oracle (0-1e18)
     */
    function updatePrice(
        uint256 marketId,
        uint256 newOraclePrice
    ) external onlyKeeper marketConfigured(marketId) {
        _updatePriceInternal(marketId, newOraclePrice);
    }
    
    /**
     * @notice Internal price update logic
     */
    function _updatePriceInternal(
        uint256 marketId,
        uint256 newOraclePrice
    ) internal {
        if (newOraclePrice == 0 || newOraclePrice > PRICE_PRECISION) revert InvalidPrice();
        
        PriceConfig storage config = priceConfigs[marketId];
        
        // Calculate new EMA
        uint256 newEmaPrice;
        if (config.lastUpdate == 0) {
            // First update - use oracle price directly
            newEmaPrice = newOraclePrice;
        } else {
            // EMA = alpha * newPrice + (1 - alpha) * oldEMA
            // alpha = 2 / (period + 1), but we use time-weighted version
            uint256 elapsed = block.timestamp - config.lastUpdate;
            uint256 alpha = _calculateAlpha(elapsed, config.emaPeriod);
            newEmaPrice = (alpha * newOraclePrice + (PRICE_PRECISION - alpha) * config.emaPrice) / PRICE_PRECISION;
        }
        
        // Check deviation
        uint256 deviation = _calculateDeviation(newOraclePrice, newEmaPrice);
        if (deviation > config.maxDeviation) revert PriceDeviationTooHigh();
        
        // Calculate mark price (EMA + vAMM adjustment based on OI imbalance)
        uint256 markPrice = _calculateMarkPrice(marketId, newEmaPrice, config.vammDepth);
        
        // Update state
        config.oraclePrice = newOraclePrice;
        config.emaPrice = newEmaPrice;
        config.markPrice = markPrice;
        config.lastUpdate = block.timestamp;
        
        emit PriceUpdated(marketId, newOraclePrice, newEmaPrice, markPrice);
    }
    
    /**
     * @notice Update price by pulling from ProbabilityIndex
     * @dev Triggers index calculation, then applies EMA smoothing
     * @param marketId Market to update
     */
    function updatePriceFromIndex(uint256 marketId) external onlyKeeper marketConfigured(marketId) {
        require(address(probabilityIndex) != address(0), "Index not set");
        require(useIndex[marketId], "Index not enabled for market");
        
        // Calculate and fetch index price
        uint256 newOraclePrice = probabilityIndex.calculateIndex(marketId);
        if (newOraclePrice == 0 || newOraclePrice > PRICE_PRECISION) revert InvalidPrice();
        
        PriceConfig storage config = priceConfigs[marketId];
        
        // Calculate new EMA
        uint256 newEmaPrice;
        if (config.lastUpdate == 0) {
            newEmaPrice = newOraclePrice;
        } else {
            uint256 elapsed = block.timestamp - config.lastUpdate;
            uint256 alpha = _calculateAlpha(elapsed, config.emaPeriod);
            newEmaPrice = (alpha * newOraclePrice + (PRICE_PRECISION - alpha) * config.emaPrice) / PRICE_PRECISION;
        }
        
        // Check deviation
        uint256 deviation = _calculateDeviation(newOraclePrice, newEmaPrice);
        if (deviation > config.maxDeviation) revert PriceDeviationTooHigh();
        
        // Calculate mark price
        uint256 markPrice = _calculateMarkPrice(marketId, newEmaPrice, config.vammDepth);
        
        // Update state
        config.oraclePrice = newOraclePrice;
        config.emaPrice = newEmaPrice;
        config.markPrice = markPrice;
        config.lastUpdate = block.timestamp;
        
        emit PriceUpdated(marketId, newOraclePrice, newEmaPrice, markPrice);
    }
    
    /**
     * @notice Preview what the price would be if updated from index
     */
    function previewPriceFromIndex(uint256 marketId) external view returns (
        uint256 indexPrice,
        uint256 sourcesUsed,
        uint256 projectedEma,
        uint256 projectedMark
    ) {
        require(address(probabilityIndex) != address(0), "Index not set");
        
        (indexPrice, sourcesUsed,,) = probabilityIndex.previewIndex(marketId);
        
        PriceConfig storage config = priceConfigs[marketId];
        
        if (config.lastUpdate == 0) {
            projectedEma = indexPrice;
        } else {
            uint256 elapsed = block.timestamp - config.lastUpdate;
            uint256 alpha = _calculateAlpha(elapsed, config.emaPeriod);
            projectedEma = (alpha * indexPrice + (PRICE_PRECISION - alpha) * config.emaPrice) / PRICE_PRECISION;
        }
        
        projectedMark = _calculateMarkPrice(marketId, projectedEma, config.vammDepth);
    }
    
    /**
     * @notice Batch update multiple markets
     */
    function batchUpdatePrices(
        uint256[] calldata marketIds,
        uint256[] calldata prices
    ) external onlyKeeper {
        require(marketIds.length == prices.length, "Length mismatch");
        for (uint256 i = 0; i < marketIds.length; i++) {
            _updatePriceInternal(marketIds[i], prices[i]);
        }
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get current mark price for a market
     */
    function getMarkPrice(uint256 marketId) external view returns (uint256) {
        return priceConfigs[marketId].markPrice;
    }
    
    /**
     * @notice Get all price data for a market
     */
    function getPriceData(uint256 marketId) external view returns (
        uint256 oraclePrice,
        uint256 emaPrice,
        uint256 markPrice,
        uint256 lastUpdate
    ) {
        PriceConfig storage config = priceConfigs[marketId];
        return (config.oraclePrice, config.emaPrice, config.markPrice, config.lastUpdate);
    }
    
    /**
     * @notice Calculate execution price with slippage for a trade
     * @param marketId Market ID
     * @param sizeDelta Size of trade (positive = buy/long, negative = sell/short)
     * @return executionPrice Price after slippage
     */
    function getExecutionPrice(
        uint256 marketId,
        int256 sizeDelta
    ) external view marketConfigured(marketId) returns (uint256 executionPrice) {
        PriceConfig storage config = priceConfigs[marketId];
        
        // Get current OI
        IPositionLedger.Market memory market = ledger.getMarket(marketId);
        
        // Calculate price impact using constant product formula
        // impact = size / (2 * vammDepth)
        uint256 absSize = sizeDelta >= 0 ? uint256(sizeDelta) : uint256(-sizeDelta);
        uint256 impact = (absSize * PRICE_PRECISION) / (2 * config.vammDepth);
        
        if (sizeDelta > 0) {
            // Buying pushes price up
            executionPrice = config.markPrice + (config.markPrice * impact / PRICE_PRECISION);
            // Cap at 100%
            if (executionPrice > PRICE_PRECISION) executionPrice = PRICE_PRECISION;
        } else {
            // Selling pushes price down
            uint256 decrease = config.markPrice * impact / PRICE_PRECISION;
            executionPrice = decrease >= config.markPrice ? 1 : config.markPrice - decrease;
        }
    }
    
    /**
     * @notice Check if price is stale
     */
    function isPriceStale(uint256 marketId, uint256 maxAge) external view returns (bool) {
        return block.timestamp - priceConfigs[marketId].lastUpdate > maxAge;
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Calculate EMA alpha based on elapsed time
     */
    function _calculateAlpha(uint256 elapsed, uint256 period) internal pure returns (uint256) {
        if (elapsed >= period) return PRICE_PRECISION; // Full weight to new price
        // Linear interpolation: alpha = elapsed / period
        return (elapsed * PRICE_PRECISION) / period;
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
     * @notice Calculate mark price with OI imbalance adjustment
     */
    function _calculateMarkPrice(
        uint256 marketId,
        uint256 basePrice,
        uint256 vammDepth
    ) internal view returns (uint256) {
        // Get OI imbalance from ledger
        int256 imbalance = ledger.getOIImbalance(marketId);
        
        if (imbalance == 0 || vammDepth == 0) return basePrice;
        
        // Adjustment = imbalance / vammDepth (capped)
        // Positive imbalance (more longs) -> higher mark price
        // Negative imbalance (more shorts) -> lower mark price
        
        uint256 absImbalance = imbalance >= 0 ? uint256(imbalance) : uint256(-imbalance);
        uint256 adjustment = (absImbalance * PRICE_PRECISION) / vammDepth;
        
        // Cap adjustment at 10%
        uint256 maxAdjustment = PRICE_PRECISION / 10;
        if (adjustment > maxAdjustment) adjustment = maxAdjustment;
        
        uint256 markPrice;
        if (imbalance > 0) {
            markPrice = basePrice + (basePrice * adjustment / PRICE_PRECISION);
            if (markPrice > PRICE_PRECISION) markPrice = PRICE_PRECISION;
        } else {
            uint256 decrease = basePrice * adjustment / PRICE_PRECISION;
            markPrice = decrease >= basePrice ? 1 : basePrice - decrease;
        }
        
        return markPrice;
    }
}
