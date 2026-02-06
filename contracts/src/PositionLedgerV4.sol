// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC20.sol";

/**
 * @title PositionLedgerV4
 * @author LEVER Protocol
 * @notice Position tracking with Position IDs - each position is independent
 * @dev V4 Changes:
 *      - Position ID model: each open is a unique position
 *      - Users can have multiple positions per market (long AND short)
 *      - Explicit close by position ID (no auto-netting)
 */
contract PositionLedgerV4 {
    
    // ============ Enums ============
    
    enum Side { Long, Short }
    
    // ============ Structs ============
    
    struct Position {
        uint256 id;                 // Unique position ID
        address owner;              // Position owner
        uint256 marketId;           // Prediction market identifier
        Side side;                  // Long or Short
        uint256 size;               // Position size (always positive, side determines direction)
        uint256 entryPrice;         // Entry probability (18 decimals, 0-1e18)
        uint256 collateral;         // Deposited collateral (USDC, 18 decimals)
        uint256 openTimestamp;      // When position was opened
        bool isOpen;                // Whether position is still open
        
        // Lazy fee accrual fields
        uint256 lastFeeUpdate;      // Timestamp of last fee settlement
        uint256 settledFees;        // Fees already locked in from previous settlements
        uint256 lastBorrowIndex;    // Global borrow index at last settlement
        int256 lastFundingIndex;    // Global funding index at last settlement (signed)
    }
    
    struct Market {
        address oracle;             // Price/probability oracle (PriceEngineV2)
        uint256 totalLongOI;        // Total long open interest
        uint256 totalShortOI;       // Total short open interest
        uint256 maxOI;              // Maximum allowed OI per side
        
        // Indices for lazy calculation
        uint256 borrowIndex;        // Global borrow index (grows over time)
        int256 fundingIndex;        // Global funding index (can be positive or negative)
        
        // Time-based parameters
        uint256 resolutionTime;     // When market resolves (for M_ttR calculation)
        uint256 liveStartTime;      // 0 if not live, timestamp when event goes live
        bool isLive;                // Whether underlying event is currently live
        bool active;                // Trading enabled
    }
    
    struct LPPosition {
        uint256 shares;             // LP's share of the pool
        uint256 claimedFees;        // Lifetime fees claimed
        uint256 depositTimestamp;   // When LP deposited
    }
    
    // ============ State ============
    
    address public owner;
    
    // Position ID tracking
    uint256 public nextPositionId;
    mapping(uint256 => Position) public positions;           // positionId => Position
    mapping(address => uint256[]) public userPositionIds;    // user => array of position IDs
    mapping(address => mapping(uint256 => uint256[])) public userMarketPositionIds; // user => marketId => position IDs
    
    // Market tracking
    mapping(uint256 => Market) public markets;
    mapping(address => bool) public authorizedEngines;
    
    // LP tracking
    mapping(address => LPPosition) public lpPositions;
    
    // Global state
    address public immutable collateralToken;
    uint256 public totalTVL;              // Total value locked by LPs
    uint256 public totalGlobalOI;         // Total OI across all markets
    uint256 public totalLPShares;         // Total LP shares outstanding
    uint256 public settledFeePool;        // Collected fees available for LP distribution
    
    // Protocol addresses
    address public protocolTreasury;
    address public insuranceFund;
    
    // Fee distribution (basis points, total = 10000)
    uint256 public constant LP_FEE_SHARE = 5000;        // 50%
    uint256 public constant PROTOCOL_FEE_SHARE = 3000;  // 30%
    uint256 public constant INSURANCE_FEE_SHARE = 2000; // 20%
    
    // Borrow rate bounds (per hour, 18 decimals)
    uint256 public constant MIN_BORROW_RATE = 2e14;     // 0.02% = 0.0002
    uint256 public constant MAX_BORROW_RATE = 2e15;     // 0.20% = 0.002
    uint256 public constant BASE_BORROW_RATE = 2e14;    // 0.02% = 0.0002
    
    // Global OI cap percentages (basis points)
    uint256 public constant PHASE_A_CAP = 8000;  // 80% TVL when T >= 48h
    uint256 public constant PHASE_B_CAP = 6500;  // 65% TVL when 12h < T < 48h
    uint256 public constant PHASE_C_CAP = 5000;  // 50% TVL when live
    uint256 public constant PHASE_D_CAP = 3500;  // 35% TVL post-event
    
    uint256 public nextMarketId;
    
    // Reentrancy guard
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status;
    
    // ============ Events ============
    
    event MarketCreated(uint256 indexed marketId, address oracle, uint256 maxOI, uint256 resolutionTime);
    event MarketLiveStatusChanged(uint256 indexed marketId, bool isLive, uint256 liveStartTime);
    event PositionOpened(uint256 indexed positionId, address indexed trader, uint256 indexed marketId, Side side, uint256 size, uint256 entryPrice, uint256 collateral);
    event PositionIncreased(uint256 indexed positionId, uint256 sizeDelta, uint256 collateralDelta, uint256 newAvgEntry);
    event PositionDecreased(uint256 indexed positionId, uint256 sizeDelta, uint256 exitPrice, int256 realizedPnL);
    event PositionClosed(uint256 indexed positionId, address indexed trader, uint256 indexed marketId, int256 realizedPnL, uint256 feesPaid);
    event PositionLiquidated(uint256 indexed positionId, address indexed trader, uint256 indexed marketId, address liquidator, uint256 penalty, uint256 feesPaid);
    event CollateralModified(uint256 indexed positionId, int256 delta, uint256 newCollateral);
    event FeesSettled(uint256 indexed positionId, uint256 borrowFees, int256 fundingPayment, uint256 newCollateral);
    event LPDeposit(address indexed lp, uint256 amount, uint256 shares);
    event LPWithdraw(address indexed lp, uint256 amount, uint256 shares);
    event LPFeesClaimed(address indexed lp, uint256 amount);
    event FeeDistributed(uint256 lpAmount, uint256 protocolAmount, uint256 insuranceAmount);
    event EngineAuthorized(address indexed engine, bool authorized);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    // ============ Errors ============
    
    error Unauthorized();
    error MarketNotActive();
    error MarketNotFound();
    error PositionNotFound();
    error PositionNotOpen();
    error NotPositionOwner();
    error ExceedsMaxOI();
    error ExceedsGlobalOICap();
    error InsufficientCollateral();
    error InvalidSize();
    error InvalidPrice();
    error ReentrantCall();
    error ZeroAddress();
    error NoFeesToClaim();
    error InsufficientLPShares();
    error SizeTooLarge();
    
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
    
    modifier positionExists(uint256 positionId) {
        if (positions[positionId].owner == address(0)) revert PositionNotFound();
        _;
    }
    
    modifier positionOpen(uint256 positionId) {
        if (!positions[positionId].isOpen) revert PositionNotOpen();
        _;
    }
    
    modifier nonReentrant() {
        if (_status == ENTERED) revert ReentrantCall();
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
    
    // ============ Constructor ============
    
    constructor(
        address _collateralToken,
        address _protocolTreasury,
        address _insuranceFund
    ) {
        if (_collateralToken == address(0)) revert ZeroAddress();
        if (_protocolTreasury == address(0)) revert ZeroAddress();
        if (_insuranceFund == address(0)) revert ZeroAddress();
        
        owner = msg.sender;
        collateralToken = _collateralToken;
        protocolTreasury = _protocolTreasury;
        insuranceFund = _insuranceFund;
        _status = NOT_ENTERED;
        nextPositionId = 1; // Start at 1 so 0 is invalid
    }
    
    // ============ Admin Functions ============
    
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    function setEngineAuthorization(address engine, bool authorized) external onlyOwner {
        authorizedEngines[engine] = authorized;
        emit EngineAuthorized(engine, authorized);
    }
    
    function createMarket(
        address oracle,
        uint256 maxOI,
        uint256 resolutionTime
    ) external onlyOwner returns (uint256 marketId) {
        if (oracle == address(0)) revert ZeroAddress();
        
        marketId = nextMarketId++;
        markets[marketId] = Market({
            oracle: oracle,
            totalLongOI: 0,
            totalShortOI: 0,
            maxOI: maxOI,
            borrowIndex: 1e18,      // Start at 1
            fundingIndex: 0,        // Start at 0
            resolutionTime: resolutionTime,
            liveStartTime: 0,
            isLive: false,
            active: true
        });
        emit MarketCreated(marketId, oracle, maxOI, resolutionTime);
    }
    
    function setMarketActive(uint256 marketId, bool active) external onlyOwner marketExists(marketId) {
        markets[marketId].active = active;
    }
    
    function setMarketLive(uint256 marketId, bool isLive) external onlyOwner marketExists(marketId) {
        Market storage market = markets[marketId];
        market.isLive = isLive;
        market.liveStartTime = isLive ? block.timestamp : 0;
        emit MarketLiveStatusChanged(marketId, isLive, market.liveStartTime);
    }
    
    function setTotalTVL(uint256 _tvl) external onlyOwner {
        totalTVL = _tvl;
    }
    
    // ============ Core Position Functions ============
    
    /**
     * @notice Open a NEW position (always creates new position ID)
     * @param trader The trader opening the position
     * @param marketId The market to trade
     * @param side Long or Short
     * @param size Position size (notional)
     * @param price Entry price
     * @param collateral Collateral amount
     * @return positionId The new position's ID
     */
    function openPosition(
        address trader,
        uint256 marketId,
        Side side,
        uint256 size,
        uint256 price,
        uint256 collateral
    ) external onlyEngine marketActive(marketId) nonReentrant returns (uint256 positionId) {
        if (size == 0) revert InvalidSize();
        if (price == 0 || price > 1e18) revert InvalidPrice();
        
        Market storage market = markets[marketId];
        
        // Check OI limits
        if (side == Side.Long) {
            if (market.totalLongOI + size > market.maxOI) revert ExceedsMaxOI();
            market.totalLongOI += size;
        } else {
            if (market.totalShortOI + size > market.maxOI) revert ExceedsMaxOI();
            market.totalShortOI += size;
        }
        totalGlobalOI += size;
        
        // Check global OI cap
        uint256 globalCap = _getGlobalOICap(marketId);
        if (totalGlobalOI > globalCap) revert ExceedsGlobalOICap();
        
        // Create new position
        positionId = nextPositionId++;
        positions[positionId] = Position({
            id: positionId,
            owner: trader,
            marketId: marketId,
            side: side,
            size: size,
            entryPrice: price,
            collateral: collateral,
            openTimestamp: block.timestamp,
            isOpen: true,
            lastFeeUpdate: block.timestamp,
            settledFees: 0,
            lastBorrowIndex: market.borrowIndex,
            lastFundingIndex: market.fundingIndex
        });
        
        // Track position for user
        userPositionIds[trader].push(positionId);
        userMarketPositionIds[trader][marketId].push(positionId);
        
        emit PositionOpened(positionId, trader, marketId, side, size, price, collateral);
    }
    
    /**
     * @notice Increase an existing position (add size, average entry)
     * @param positionId The position to increase
     * @param sizeDelta Additional size
     * @param price Current price (for averaging)
     * @param collateralDelta Additional collateral
     */
    function increasePosition(
        uint256 positionId,
        uint256 sizeDelta,
        uint256 price,
        uint256 collateralDelta
    ) external onlyEngine positionExists(positionId) positionOpen(positionId) nonReentrant {
        if (sizeDelta == 0 && collateralDelta == 0) revert InvalidSize();
        
        Position storage pos = positions[positionId];
        Market storage market = markets[pos.marketId];
        
        // Settle fees first
        _settleFees(positionId);
        
        if (sizeDelta > 0) {
            // Check OI limits
            if (pos.side == Side.Long) {
                if (market.totalLongOI + sizeDelta > market.maxOI) revert ExceedsMaxOI();
                market.totalLongOI += sizeDelta;
            } else {
                if (market.totalShortOI + sizeDelta > market.maxOI) revert ExceedsMaxOI();
                market.totalShortOI += sizeDelta;
            }
            totalGlobalOI += sizeDelta;
            
            // Check global cap
            uint256 globalCap = _getGlobalOICap(pos.marketId);
            if (totalGlobalOI > globalCap) revert ExceedsGlobalOICap();
            
            // Average entry price
            uint256 oldNotional = pos.size * pos.entryPrice;
            uint256 deltaNotional = sizeDelta * price;
            uint256 newSize = pos.size + sizeDelta;
            pos.entryPrice = (oldNotional + deltaNotional) / newSize;
            pos.size = newSize;
        }
        
        if (collateralDelta > 0) {
            pos.collateral += collateralDelta;
        }
        
        emit PositionIncreased(positionId, sizeDelta, collateralDelta, pos.entryPrice);
    }
    
    /**
     * @notice Decrease an existing position (partial close)
     * @param positionId The position to decrease
     * @param sizeDelta Size to remove
     * @param price Exit price
     * @return realizedPnL The realized P&L from the partial close
     */
    function decreasePosition(
        uint256 positionId,
        uint256 sizeDelta,
        uint256 price
    ) external onlyEngine positionExists(positionId) positionOpen(positionId) nonReentrant returns (int256 realizedPnL) {
        Position storage pos = positions[positionId];
        if (sizeDelta > pos.size) revert SizeTooLarge();
        
        // Settle fees first
        _settleFees(positionId);
        
        Market storage market = markets[pos.marketId];
        
        // Calculate realized PnL for the closed portion
        if (pos.side == Side.Long) {
            realizedPnL = int256(sizeDelta) * (int256(price) - int256(pos.entryPrice)) / 1e18;
            market.totalLongOI -= sizeDelta;
        } else {
            realizedPnL = int256(sizeDelta) * (int256(pos.entryPrice) - int256(price)) / 1e18;
            market.totalShortOI -= sizeDelta;
        }
        totalGlobalOI -= sizeDelta;
        
        pos.size -= sizeDelta;
        
        // If fully closed, mark as closed
        if (pos.size == 0) {
            pos.isOpen = false;
            emit PositionClosed(positionId, pos.owner, pos.marketId, realizedPnL, pos.settledFees);
        } else {
            emit PositionDecreased(positionId, sizeDelta, price, realizedPnL);
        }
    }
    
    /**
     * @notice Close a position entirely
     * @param positionId The position to close
     * @param price Exit price
     * @return realizedPnL The realized P&L
     */
    function closePosition(
        uint256 positionId,
        uint256 price
    ) external onlyEngine positionExists(positionId) positionOpen(positionId) nonReentrant returns (int256 realizedPnL) {
        Position storage pos = positions[positionId];
        
        // Settle fees first
        uint256 feesPaid = _settleFees(positionId);
        
        Market storage market = markets[pos.marketId];
        
        // Calculate realized PnL
        if (pos.side == Side.Long) {
            realizedPnL = int256(pos.size) * (int256(price) - int256(pos.entryPrice)) / 1e18;
            market.totalLongOI -= pos.size;
        } else {
            realizedPnL = int256(pos.size) * (int256(pos.entryPrice) - int256(price)) / 1e18;
            market.totalShortOI -= pos.size;
        }
        totalGlobalOI -= pos.size;
        
        pos.size = 0;
        pos.isOpen = false;
        
        emit PositionClosed(positionId, pos.owner, pos.marketId, realizedPnL, feesPaid);
    }
    
    /**
     * @notice Add or remove collateral from a position
     */
    function modifyCollateral(
        uint256 positionId,
        int256 collateralDelta
    ) external onlyEngine positionExists(positionId) positionOpen(positionId) nonReentrant {
        Position storage pos = positions[positionId];
        
        // Settle fees first
        _settleFees(positionId);
        
        if (collateralDelta > 0) {
            pos.collateral += uint256(collateralDelta);
        } else {
            uint256 reduction = uint256(-collateralDelta);
            if (reduction > pos.collateral) revert InsufficientCollateral();
            pos.collateral -= reduction;
        }
        
        emit CollateralModified(positionId, collateralDelta, pos.collateral);
    }
    
    /**
     * @notice Liquidate an unsafe position
     */
    function liquidatePosition(
        uint256 positionId,
        address liquidator,
        uint256 penalty
    ) external onlyEngine positionExists(positionId) positionOpen(positionId) nonReentrant {
        Position storage pos = positions[positionId];
        
        // Settle fees
        uint256 feesPaid = _settleFees(positionId);
        
        Market storage market = markets[pos.marketId];
        
        // Update OI
        if (pos.side == Side.Long) {
            market.totalLongOI -= pos.size;
        } else {
            market.totalShortOI -= pos.size;
        }
        totalGlobalOI -= pos.size;
        
        pos.size = 0;
        pos.isOpen = false;
        
        emit PositionLiquidated(positionId, pos.owner, pos.marketId, liquidator, penalty, feesPaid);
    }
    
    // ============ Index Updates ============
    
    function updateBorrowIndex(uint256 marketId, uint256 newIndex) external onlyEngine marketExists(marketId) {
        markets[marketId].borrowIndex = newIndex;
    }
    
    function updateFundingIndex(uint256 marketId, int256 newIndex) external onlyEngine marketExists(marketId) {
        markets[marketId].fundingIndex = newIndex;
    }
    
    // ============ View Functions ============
    
    function getPosition(uint256 positionId) external view returns (Position memory) {
        return positions[positionId];
    }
    
    function getMarket(uint256 marketId) external view returns (Market memory) {
        return markets[marketId];
    }
    
    /**
     * @notice Get all position IDs for a user
     */
    function getUserPositionIds(address user) external view returns (uint256[] memory) {
        return userPositionIds[user];
    }
    
    /**
     * @notice Get all position IDs for a user in a specific market
     */
    function getUserMarketPositionIds(address user, uint256 marketId) external view returns (uint256[] memory) {
        return userMarketPositionIds[user][marketId];
    }
    
    /**
     * @notice Get all OPEN positions for a user
     */
    function getUserOpenPositions(address user) external view returns (Position[] memory) {
        uint256[] memory ids = userPositionIds[user];
        
        // Count open positions
        uint256 openCount = 0;
        for (uint256 i = 0; i < ids.length; i++) {
            if (positions[ids[i]].isOpen) openCount++;
        }
        
        // Collect open positions
        Position[] memory openPositions = new Position[](openCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < ids.length; i++) {
            if (positions[ids[i]].isOpen) {
                openPositions[idx++] = positions[ids[i]];
            }
        }
        
        return openPositions;
    }
    
    /**
     * @notice Calculate pending fees for a position
     */
    function getPendingFees(uint256 positionId) external view returns (uint256 totalFees) {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) return 0;
        
        Market storage market = markets[pos.marketId];
        
        uint256 borrowFees = _calculateBorrowFees(pos, market);
        totalFees = pos.settledFees + borrowFees;
    }
    
    /**
     * @notice Calculate unrealized PnL for a position
     */
    function getUnrealizedPnL(uint256 positionId, uint256 currentPrice) external view returns (int256 pnl) {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) return 0;
        
        if (pos.side == Side.Long) {
            pnl = int256(pos.size) * (int256(currentPrice) - int256(pos.entryPrice)) / 1e18;
        } else {
            pnl = int256(pos.size) * (int256(pos.entryPrice) - int256(currentPrice)) / 1e18;
        }
    }
    
    /**
     * @notice Get effective equity (collateral - pending fees + unrealized PnL)
     */
    function getEquity(uint256 positionId, uint256 currentPrice) external view returns (int256 equity) {
        Position storage pos = positions[positionId];
        if (!pos.isOpen) return 0;
        
        int256 pnl;
        if (pos.side == Side.Long) {
            pnl = int256(pos.size) * (int256(currentPrice) - int256(pos.entryPrice)) / 1e18;
        } else {
            pnl = int256(pos.size) * (int256(pos.entryPrice) - int256(currentPrice)) / 1e18;
        }
        
        uint256 pendingFees = this.getPendingFees(positionId);
        equity = int256(pos.collateral) + pnl - int256(pendingFees);
    }
    
    function getGlobalOICap(uint256 marketId) external view returns (uint256) {
        return _getGlobalOICap(marketId);
    }
    
    // ============ Internal Functions ============
    
    function _settleFees(uint256 positionId) internal returns (uint256 feesPaid) {
        Position storage pos = positions[positionId];
        Market storage market = markets[pos.marketId];
        
        uint256 borrowFees = _calculateBorrowFees(pos, market);
        int256 fundingPayment = _calculateFundingPayment(pos, market);
        
        feesPaid = pos.settledFees + borrowFees;
        if (fundingPayment > 0) {
            feesPaid += uint256(fundingPayment);
        }
        
        if (feesPaid > pos.collateral) {
            feesPaid = pos.collateral;
        }
        pos.collateral -= feesPaid;
        
        if (fundingPayment < 0) {
            pos.collateral += uint256(-fundingPayment);
        }
        
        _distributeFees(feesPaid);
        
        pos.settledFees = 0;
        pos.lastFeeUpdate = block.timestamp;
        pos.lastBorrowIndex = market.borrowIndex;
        pos.lastFundingIndex = market.fundingIndex;
        
        emit FeesSettled(positionId, borrowFees, fundingPayment, pos.collateral);
    }
    
    function _calculateBorrowFees(Position storage pos, Market storage market) internal view returns (uint256) {
        if (pos.lastBorrowIndex == 0) return 0;
        
        uint256 notional = pos.size * pos.entryPrice / 1e18;
        uint256 indexRatio = (market.borrowIndex * 1e18) / pos.lastBorrowIndex;
        if (indexRatio <= 1e18) return 0;
        
        return (notional * (indexRatio - 1e18)) / 1e18;
    }
    
    function _calculateFundingPayment(Position storage pos, Market storage market) internal view returns (int256) {
        int256 fundingDelta = market.fundingIndex - pos.lastFundingIndex;
        int256 signedSize = pos.side == Side.Long ? int256(pos.size) : -int256(pos.size);
        return (signedSize * fundingDelta) / 1e18;
    }
    
    function _distributeFees(uint256 totalFees) internal {
        if (totalFees == 0) return;
        
        uint256 lpAmount = (totalFees * LP_FEE_SHARE) / 10000;
        uint256 protocolAmount = (totalFees * PROTOCOL_FEE_SHARE) / 10000;
        uint256 insuranceAmount = totalFees - lpAmount - protocolAmount;
        
        settledFeePool += lpAmount;
        
        if (protocolAmount > 0) {
            IERC20(collateralToken).transfer(protocolTreasury, protocolAmount);
        }
        if (insuranceAmount > 0) {
            IERC20(collateralToken).transfer(insuranceFund, insuranceAmount);
        }
        
        emit FeeDistributed(lpAmount, protocolAmount, insuranceAmount);
    }
    
    function _getGlobalOICap(uint256 marketId) internal view returns (uint256) {
        Market storage market = markets[marketId];
        
        if (totalTVL == 0) return 0;
        
        uint256 T = market.resolutionTime > block.timestamp 
            ? (market.resolutionTime - block.timestamp) / 1 hours
            : 0;
        
        uint256 capBps;
        
        if (T >= 48) {
            capBps = PHASE_A_CAP;
        } else if (T > 12) {
            capBps = PHASE_B_CAP;
        } else if (market.isLive) {
            capBps = PHASE_C_CAP;
        } else {
            capBps = PHASE_D_CAP;
        }
        
        return (totalTVL * capBps) / 10000;
    }
    
    // ============ Migration Helper ============
    
    /**
     * @notice Migrate position from V3 (owner only, one-time)
     */
    function migratePosition(
        address trader,
        uint256 marketId,
        Side side,
        uint256 size,
        uint256 entryPrice,
        uint256 collateral
    ) external onlyOwner marketExists(marketId) returns (uint256 positionId) {
        Market storage market = markets[marketId];
        
        positionId = nextPositionId++;
        positions[positionId] = Position({
            id: positionId,
            owner: trader,
            marketId: marketId,
            side: side,
            size: size,
            entryPrice: entryPrice,
            collateral: collateral,
            openTimestamp: block.timestamp,
            isOpen: true,
            lastFeeUpdate: block.timestamp,
            settledFees: 0,
            lastBorrowIndex: market.borrowIndex,
            lastFundingIndex: market.fundingIndex
        });
        
        userPositionIds[trader].push(positionId);
        userMarketPositionIds[trader][marketId].push(positionId);
        
        // Update OI
        if (side == Side.Long) {
            market.totalLongOI += size;
        } else {
            market.totalShortOI += size;
        }
        totalGlobalOI += size;
        
        emit PositionOpened(positionId, trader, marketId, side, size, entryPrice, collateral);
    }
}
