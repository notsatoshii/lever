// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ProbabilityIndex
 * @author LEVER Protocol
 * @notice Aggregates probability from multiple sources into a single consensus price
 * 
 * Sources can include:
 * - Polymarket CLOB (via keeper)
 * - UMA optimistic oracle
 * - Chainlink (if available)
 * - Protocol's own vAMM
 * 
 * The index applies:
 * - Per-source staleness thresholds
 * - Per-source weight multipliers
 * - Outlier rejection (prices too far from median)
 * - Final weighted average = probability index
 */
contract ProbabilityIndex {
    
    // ============ Structs ============
    
    struct Source {
        string name;              // Human-readable name
        uint256 weight;           // Weight in basis points (10000 = 100%)
        uint256 maxStaleness;     // Max age in seconds before considered stale
        uint256 maxDeviation;     // Max deviation from median (basis points)
        bool active;              // Whether source is currently active
        uint256 lastPrice;        // Last reported price (0-1e18)
        uint256 lastUpdate;       // Timestamp of last update
    }
    
    struct IndexConfig {
        uint256 minSources;       // Minimum active sources required
        uint256 outlierThreshold; // Deviation threshold for outlier rejection (bps)
        uint256 updateCooldown;   // Min time between index recalculations
    }
    
    // ============ State ============
    
    address public owner;
    
    // marketId => sourceId => Source
    mapping(uint256 => mapping(uint256 => Source)) public sources;
    
    // marketId => number of sources
    mapping(uint256 => uint256) public sourceCount;
    
    // marketId => IndexConfig
    mapping(uint256 => IndexConfig) public indexConfigs;
    
    // marketId => consensus index price
    mapping(uint256 => uint256) public indexPrice;
    
    // marketId => last index calculation time
    mapping(uint256 => uint256) public lastIndexUpdate;
    
    // Authorized keepers who can submit prices
    mapping(address => bool) public authorizedKeepers;
    
    // ============ Constants ============
    
    uint256 public constant PRECISION = 1e18;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_SOURCES = 10;
    
    // ============ Events ============
    
    event SourceAdded(uint256 indexed marketId, uint256 sourceId, string name, uint256 weight);
    event SourceUpdated(uint256 indexed marketId, uint256 sourceId, uint256 price, uint256 timestamp);
    event SourceDeactivated(uint256 indexed marketId, uint256 sourceId);
    event IndexCalculated(uint256 indexed marketId, uint256 indexPrice, uint256 sourcesUsed);
    event KeeperAuthorized(address keeper, bool authorized);
    
    // ============ Errors ============
    
    error Unauthorized();
    error InvalidSource();
    error TooManySources();
    error InsufficientSources();
    error PriceOutOfRange();
    error UpdateTooFrequent();
    error SourceStale();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyKeeper() {
        if (!authorizedKeepers[msg.sender] && msg.sender != owner) revert Unauthorized();
        _;
    }
    
    // ============ Constructor ============
    
    constructor() {
        owner = msg.sender;
        authorizedKeepers[msg.sender] = true;
    }
    
    // ============ Admin Functions ============
    
    function setKeeperAuthorization(address keeper, bool authorized) external onlyOwner {
        authorizedKeepers[keeper] = authorized;
        emit KeeperAuthorized(keeper, authorized);
    }
    
    function configureIndex(
        uint256 marketId,
        uint256 minSources,
        uint256 outlierThreshold,
        uint256 updateCooldown
    ) external onlyOwner {
        indexConfigs[marketId] = IndexConfig({
            minSources: minSources,
            outlierThreshold: outlierThreshold,
            updateCooldown: updateCooldown
        });
    }
    
    /**
     * @notice Add a new price source for a market
     */
    function addSource(
        uint256 marketId,
        string calldata name,
        uint256 weight,
        uint256 maxStaleness,
        uint256 maxDeviation
    ) external onlyOwner returns (uint256 sourceId) {
        if (sourceCount[marketId] >= MAX_SOURCES) revert TooManySources();
        
        sourceId = sourceCount[marketId]++;
        
        sources[marketId][sourceId] = Source({
            name: name,
            weight: weight,
            maxStaleness: maxStaleness,
            maxDeviation: maxDeviation,
            active: true,
            lastPrice: 0,
            lastUpdate: 0
        });
        
        emit SourceAdded(marketId, sourceId, name, weight);
    }
    
    function updateSourceConfig(
        uint256 marketId,
        uint256 sourceId,
        uint256 weight,
        uint256 maxStaleness,
        uint256 maxDeviation
    ) external onlyOwner {
        Source storage source = sources[marketId][sourceId];
        source.weight = weight;
        source.maxStaleness = maxStaleness;
        source.maxDeviation = maxDeviation;
    }
    
    function deactivateSource(uint256 marketId, uint256 sourceId) external onlyOwner {
        sources[marketId][sourceId].active = false;
        emit SourceDeactivated(marketId, sourceId);
    }
    
    function activateSource(uint256 marketId, uint256 sourceId) external onlyOwner {
        sources[marketId][sourceId].active = true;
    }
    
    // ============ Keeper Functions ============
    
    /**
     * @notice Submit a price update for a specific source
     */
    function submitPrice(
        uint256 marketId,
        uint256 sourceId,
        uint256 price
    ) external onlyKeeper {
        if (sourceId >= sourceCount[marketId]) revert InvalidSource();
        if (price > PRECISION) revert PriceOutOfRange();
        
        Source storage source = sources[marketId][sourceId];
        if (!source.active) revert InvalidSource();
        
        source.lastPrice = price;
        source.lastUpdate = block.timestamp;
        
        emit SourceUpdated(marketId, sourceId, price, block.timestamp);
    }
    
    /**
     * @notice Submit prices for multiple sources at once
     */
    function submitPricesBatch(
        uint256 marketId,
        uint256[] calldata sourceIds,
        uint256[] calldata prices
    ) external onlyKeeper {
        require(sourceIds.length == prices.length, "Length mismatch");
        
        for (uint256 i = 0; i < sourceIds.length; i++) {
            uint256 sourceId = sourceIds[i];
            uint256 price = prices[i];
            
            if (sourceId >= sourceCount[marketId]) continue;
            if (price > PRECISION) continue;
            
            Source storage source = sources[marketId][sourceId];
            if (!source.active) continue;
            
            source.lastPrice = price;
            source.lastUpdate = block.timestamp;
            
            emit SourceUpdated(marketId, sourceId, price, block.timestamp);
        }
    }
    
    /**
     * @notice Calculate and store the consensus index price
     */
    function calculateIndex(uint256 marketId) external returns (uint256) {
        IndexConfig storage config = indexConfigs[marketId];
        
        // Check cooldown
        if (block.timestamp < lastIndexUpdate[marketId] + config.updateCooldown) {
            revert UpdateTooFrequent();
        }
        
        (uint256 newIndex, uint256 sourcesUsed) = _calculateIndexInternal(marketId);
        
        // Check minimum sources
        if (sourcesUsed < config.minSources) revert InsufficientSources();
        
        indexPrice[marketId] = newIndex;
        lastIndexUpdate[marketId] = block.timestamp;
        
        emit IndexCalculated(marketId, newIndex, sourcesUsed);
        
        return newIndex;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get the current index price (cached)
     */
    function getIndexPrice(uint256 marketId) external view returns (uint256) {
        return indexPrice[marketId];
    }
    
    /**
     * @notice Calculate index without storing (for preview)
     */
    function previewIndex(uint256 marketId) external view returns (
        uint256 calculatedIndex,
        uint256 sourcesUsed,
        uint256[] memory usedSourceIds,
        uint256[] memory usedPrices
    ) {
        return _calculateIndexWithDetails(marketId);
    }
    
    /**
     * @notice Get all source data for a market
     */
    function getSources(uint256 marketId) external view returns (
        string[] memory names,
        uint256[] memory weights,
        uint256[] memory prices,
        uint256[] memory timestamps,
        bool[] memory isStale
    ) {
        uint256 count = sourceCount[marketId];
        names = new string[](count);
        weights = new uint256[](count);
        prices = new uint256[](count);
        timestamps = new uint256[](count);
        isStale = new bool[](count);
        
        for (uint256 i = 0; i < count; i++) {
            Source storage source = sources[marketId][i];
            names[i] = source.name;
            weights[i] = source.weight;
            prices[i] = source.lastPrice;
            timestamps[i] = source.lastUpdate;
            isStale[i] = _isStale(source);
        }
    }
    
    /**
     * @notice Check if a specific source is stale
     */
    function isSourceStale(uint256 marketId, uint256 sourceId) external view returns (bool) {
        return _isStale(sources[marketId][sourceId]);
    }
    
    // ============ Internal Functions ============
    
    function _isStale(Source storage source) internal view returns (bool) {
        if (!source.active) return true;
        if (source.lastUpdate == 0) return true;
        return block.timestamp > source.lastUpdate + source.maxStaleness;
    }
    
    function _calculateIndexInternal(uint256 marketId) internal view returns (
        uint256 weightedPrice,
        uint256 sourcesUsed
    ) {
        uint256 count = sourceCount[marketId];
        if (count == 0) return (0, 0);
        
        // First pass: collect valid prices and calculate median
        uint256[] memory validPrices = new uint256[](count);
        uint256[] memory validWeights = new uint256[](count);
        uint256 validCount = 0;
        
        for (uint256 i = 0; i < count; i++) {
            Source storage source = sources[marketId][i];
            if (!_isStale(source) && source.lastPrice > 0) {
                validPrices[validCount] = source.lastPrice;
                validWeights[validCount] = source.weight;
                validCount++;
            }
        }
        
        if (validCount == 0) return (0, 0);
        
        // Calculate median for outlier detection
        uint256 median = _calculateMedian(validPrices, validCount);
        
        // Second pass: weighted average excluding outliers
        IndexConfig storage config = indexConfigs[marketId];
        uint256 totalWeight = 0;
        uint256 weightedSum = 0;
        
        for (uint256 i = 0; i < validCount; i++) {
            uint256 price = validPrices[i];
            uint256 weight = validWeights[i];
            
            // Check if price is an outlier
            uint256 deviation = price > median 
                ? ((price - median) * BASIS_POINTS) / median
                : ((median - price) * BASIS_POINTS) / median;
            
            if (deviation <= config.outlierThreshold) {
                weightedSum += price * weight;
                totalWeight += weight;
                sourcesUsed++;
            }
        }
        
        if (totalWeight == 0) return (0, 0);
        
        weightedPrice = weightedSum / totalWeight;
    }
    
    function _calculateIndexWithDetails(uint256 marketId) internal view returns (
        uint256 calculatedIndex,
        uint256 sourcesUsed,
        uint256[] memory usedSourceIds,
        uint256[] memory usedPrices
    ) {
        uint256 count = sourceCount[marketId];
        usedSourceIds = new uint256[](count);
        usedPrices = new uint256[](count);
        
        (calculatedIndex, sourcesUsed) = _calculateIndexInternal(marketId);
        
        // Collect used sources for return
        uint256 idx = 0;
        for (uint256 i = 0; i < count && idx < sourcesUsed; i++) {
            Source storage source = sources[marketId][i];
            if (!_isStale(source) && source.lastPrice > 0) {
                usedSourceIds[idx] = i;
                usedPrices[idx] = source.lastPrice;
                idx++;
            }
        }
    }
    
    function _calculateMedian(uint256[] memory arr, uint256 len) internal pure returns (uint256) {
        if (len == 0) return 0;
        if (len == 1) return arr[0];
        
        // Simple sort for small arrays (bubble sort - OK for max 10 elements)
        for (uint256 i = 0; i < len - 1; i++) {
            for (uint256 j = 0; j < len - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    (arr[j], arr[j + 1]) = (arr[j + 1], arr[j]);
                }
            }
        }
        
        if (len % 2 == 0) {
            return (arr[len / 2 - 1] + arr[len / 2]) / 2;
        } else {
            return arr[len / 2];
        }
    }
}
