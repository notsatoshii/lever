// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PositionLedger
 * @author LEVER Protocol
 * @notice Core position tracking for synthetic perpetuals on prediction markets
 * @dev Single source of truth for all position data. Other engines read but never own exposure.
 * 
 * Positions represent leveraged exposure to prediction market outcomes.
 * - Long: Betting outcome resolves YES (probability increases = profit)
 * - Short: Betting outcome resolves NO (probability decreases = profit)
 */

contract PositionLedger {
    
    // ============ Structs ============
    
    struct Position {
        uint256 marketId;           // Prediction market identifier
        int256 size;                // Position size (positive = long, negative = short)
        uint256 entryPrice;         // Entry probability (18 decimals, 0-1e18)
        uint256 collateral;         // Deposited collateral (USDT, 18 decimals)
        uint256 openTimestamp;      // When position was opened
        uint256 lastFundingIndex;   // For funding rate calculations
        uint256 lastBorrowIndex;    // For borrow fee calculations
    }
    
    struct Market {
        address oracle;             // Price/probability oracle
        uint256 totalLongOI;        // Total long open interest
        uint256 totalShortOI;       // Total short open interest
        uint256 maxOI;              // Maximum allowed OI per side
        uint256 fundingIndex;       // Cumulative funding
        uint256 borrowIndex;        // Cumulative borrow fees
        bool active;                // Trading enabled
    }
    
    // ============ State ============
    
    address public owner;
    
    // marketId => Market
    mapping(uint256 => Market) public markets;
    
    // trader => marketId => Position
    mapping(address => mapping(uint256 => Position)) public positions;
    
    // Authorized engines that can modify positions
    mapping(address => bool) public authorizedEngines;
    
    // Collateral token (USDC)
    address public immutable collateralToken;
    
    // Next market ID
    uint256 public nextMarketId;
    
    // Reentrancy guard
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status;
    
    // ============ Events ============
    
    event MarketCreated(uint256 indexed marketId, address oracle, uint256 maxOI);
    event PositionOpened(address indexed trader, uint256 indexed marketId, int256 size, uint256 entryPrice, uint256 collateral);
    event PositionModified(address indexed trader, uint256 indexed marketId, int256 sizeDelta, uint256 newCollateral);
    event PositionClosed(address indexed trader, uint256 indexed marketId, int256 realizedPnL);
    event PositionLiquidated(address indexed trader, uint256 indexed marketId, address liquidator, uint256 penalty);
    event EngineAuthorized(address indexed engine, bool authorized);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    // ============ Errors ============
    
    error Unauthorized();
    error MarketNotActive();
    error MarketNotFound();
    error PositionNotFound();
    error ExceedsMaxOI();
    error InsufficientCollateral();
    error InvalidSize();
    error InvalidPrice();
    error ReentrantCall();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyEngine() {
        if (!authorizedEngines[msg.sender]) revert Unauthorized();
        _;
    }
    
    modifier marketExists(uint256 marketId) {
        if (markets[marketId].oracle == address(0)) revert MarketNotFound();
        _;
    }
    
    modifier marketActive(uint256 marketId) {
        if (!markets[marketId].active) revert MarketNotActive();
        _;
    }
    
    modifier nonReentrant() {
        if (_status == ENTERED) revert ReentrantCall();
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
    
    // ============ Constructor ============
    
    constructor(address _collateralToken) {
        owner = msg.sender;
        collateralToken = _collateralToken;
        _status = NOT_ENTERED;
    }
    
    // ============ Admin Functions ============
    
    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    function setEngineAuthorization(address engine, bool authorized) external onlyOwner {
        authorizedEngines[engine] = authorized;
        emit EngineAuthorized(engine, authorized);
    }
    
    function createMarket(address oracle, uint256 maxOI) external onlyOwner returns (uint256 marketId) {
        marketId = nextMarketId++;
        markets[marketId] = Market({
            oracle: oracle,
            totalLongOI: 0,
            totalShortOI: 0,
            maxOI: maxOI,
            fundingIndex: 1e18,  // Start at 1
            borrowIndex: 1e18,   // Start at 1
            active: true
        });
        emit MarketCreated(marketId, oracle, maxOI);
    }
    
    function setMarketActive(uint256 marketId, bool active) external onlyOwner marketExists(marketId) {
        markets[marketId].active = active;
    }
    
    // ============ Engine Functions ============
    
    /**
     * @notice Open a new position or add to existing
     * @param trader The position owner
     * @param marketId The market to trade
     * @param sizeDelta Change in position size (positive = add long/reduce short)
     * @param price Current mark price
     * @param collateralDelta Collateral to add
     */
    function openPosition(
        address trader,
        uint256 marketId,
        int256 sizeDelta,
        uint256 price,
        uint256 collateralDelta
    ) external onlyEngine marketActive(marketId) nonReentrant {
        if (sizeDelta == 0) revert InvalidSize();
        if (price == 0 || price > 1e18) revert InvalidPrice();
        
        Position storage pos = positions[trader][marketId];
        Market storage market = markets[marketId];
        
        // Update OI
        _updateOI(market, pos.size, sizeDelta);
        
        // Update position
        if (pos.size == 0) {
            // New position
            pos.marketId = marketId;
            pos.size = sizeDelta;
            pos.entryPrice = price;
            pos.collateral = collateralDelta;
            pos.openTimestamp = block.timestamp;
            pos.lastFundingIndex = market.fundingIndex;
            pos.lastBorrowIndex = market.borrowIndex;
            
            emit PositionOpened(trader, marketId, sizeDelta, price, collateralDelta);
        } else {
            // Modify existing
            int256 newSize = pos.size + sizeDelta;
            
            if (newSize == 0) {
                // Position fully closed
                _closePosition(trader, marketId, price);
            } else if ((pos.size > 0) == (newSize > 0)) {
                // Same direction - average entry
                uint256 oldNotional = _abs(pos.size) * pos.entryPrice;
                uint256 deltaNotional = _abs(sizeDelta) * price;
                pos.entryPrice = (oldNotional + deltaNotional) / _abs(newSize);
                pos.size = newSize;
                pos.collateral += collateralDelta;
                
                emit PositionModified(trader, marketId, sizeDelta, pos.collateral);
            } else {
                // Direction flip - close old, open new
                _closePosition(trader, marketId, price);
                
                pos.size = newSize;
                pos.entryPrice = price;
                pos.collateral = collateralDelta;
                pos.openTimestamp = block.timestamp;
                pos.lastFundingIndex = market.fundingIndex;
                pos.lastBorrowIndex = market.borrowIndex;
                
                emit PositionOpened(trader, marketId, newSize, price, collateralDelta);
            }
        }
    }
    
    /**
     * @notice Add or remove collateral from position
     */
    function modifyCollateral(
        address trader,
        uint256 marketId,
        int256 collateralDelta
    ) external onlyEngine marketExists(marketId) nonReentrant {
        Position storage pos = positions[trader][marketId];
        if (pos.size == 0) revert PositionNotFound();
        
        if (collateralDelta > 0) {
            pos.collateral += uint256(collateralDelta);
        } else {
            uint256 reduction = uint256(-collateralDelta);
            if (reduction > pos.collateral) revert InsufficientCollateral();
            pos.collateral -= reduction;
        }
        
        emit PositionModified(trader, marketId, 0, pos.collateral);
    }
    
    /**
     * @notice Liquidate an unsafe position
     */
    function liquidatePosition(
        address trader,
        uint256 marketId,
        address liquidator,
        uint256 penalty
    ) external onlyEngine marketExists(marketId) nonReentrant {
        Position storage pos = positions[trader][marketId];
        if (pos.size == 0) revert PositionNotFound();
        
        Market storage market = markets[marketId];
        
        // Update OI
        if (pos.size > 0) {
            market.totalLongOI -= _abs(pos.size);
        } else {
            market.totalShortOI -= _abs(pos.size);
        }
        
        emit PositionLiquidated(trader, marketId, liquidator, penalty);
        
        // Clear position
        delete positions[trader][marketId];
    }
    
    /**
     * @notice Update funding and borrow indices (called by Risk Engine)
     */
    function updateIndices(
        uint256 marketId,
        uint256 newFundingIndex,
        uint256 newBorrowIndex
    ) external onlyEngine marketExists(marketId) {
        Market storage market = markets[marketId];
        market.fundingIndex = newFundingIndex;
        market.borrowIndex = newBorrowIndex;
    }
    
    // ============ View Functions ============
    
    function getPosition(address trader, uint256 marketId) external view returns (Position memory) {
        return positions[trader][marketId];
    }
    
    function getMarket(uint256 marketId) external view returns (Market memory) {
        return markets[marketId];
    }
    
    function getOIImbalance(uint256 marketId) external view returns (int256) {
        Market storage market = markets[marketId];
        return int256(market.totalLongOI) - int256(market.totalShortOI);
    }
    
    /**
     * @notice Calculate unrealized PnL for a position
     * @param trader Position owner
     * @param marketId Market ID
     * @param currentPrice Current mark price
     * @return pnl Unrealized PnL (can be negative)
     */
    function getUnrealizedPnL(
        address trader,
        uint256 marketId,
        uint256 currentPrice
    ) external view returns (int256 pnl) {
        Position storage pos = positions[trader][marketId];
        if (pos.size == 0) return 0;
        
        // PnL = size * (currentPrice - entryPrice)
        // For longs: price up = profit
        // For shorts: price down = profit (size is negative)
        pnl = pos.size * (int256(currentPrice) - int256(pos.entryPrice)) / 1e18;
    }
    
    // ============ Internal Functions ============
    
    function _closePosition(address trader, uint256 marketId, uint256 exitPrice) internal {
        Position storage pos = positions[trader][marketId];
        
        int256 pnl = pos.size * (int256(exitPrice) - int256(pos.entryPrice)) / 1e18;
        
        emit PositionClosed(trader, marketId, pnl);
        
        delete positions[trader][marketId];
    }
    
    function _updateOI(Market storage market, int256 oldSize, int256 sizeDelta) internal {
        // Remove old OI
        if (oldSize > 0) {
            market.totalLongOI -= _abs(oldSize);
        } else if (oldSize < 0) {
            market.totalShortOI -= _abs(oldSize);
        }
        
        // Add new OI
        int256 newSize = oldSize + sizeDelta;
        if (newSize > 0) {
            uint256 newLongOI = market.totalLongOI + _abs(newSize);
            if (newLongOI > market.maxOI) revert ExceedsMaxOI();
            market.totalLongOI = newLongOI;
        } else if (newSize < 0) {
            uint256 newShortOI = market.totalShortOI + _abs(newSize);
            if (newShortOI > market.maxOI) revert ExceedsMaxOI();
            market.totalShortOI = newShortOI;
        }
    }
    
    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
}
