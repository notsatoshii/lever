// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC20.sol";

/**
 * @title PositionLedgerV2
 * @author LEVER Protocol
 * @notice Core position tracking with lazy fee accrual for synthetic perpetuals
 * @dev Implements Eric's Lazy Fee Accrual System (2026-02-06):
 *      - Fees are CALCULATED, not STORED
 *      - On-chain holds static inputs
 *      - Frontend calculates live values
 *      - Settlement happens only on user interaction
 */
contract PositionLedgerV2 {
    
    // ============ Structs ============
    
    struct Position {
        uint256 marketId;           // Prediction market identifier
        int256 size;                // Position size (positive = long, negative = short)
        uint256 entryPrice;         // Entry probability (18 decimals, 0-1e18)
        uint256 collateral;         // Deposited collateral (USDC, 18 decimals)
        uint256 openTimestamp;      // When position was opened
        
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
    
    // Core mappings
    mapping(uint256 => Market) public markets;
    mapping(address => mapping(uint256 => Position)) public positions;
    mapping(address => LPPosition) public lpPositions;
    mapping(address => bool) public authorizedEngines;
    
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
    event PositionOpened(address indexed trader, uint256 indexed marketId, int256 size, uint256 entryPrice, uint256 collateral);
    event PositionModified(address indexed trader, uint256 indexed marketId, int256 sizeDelta, uint256 newCollateral);
    event PositionClosed(address indexed trader, uint256 indexed marketId, int256 realizedPnL, uint256 feesPaid);
    event PositionLiquidated(address indexed trader, uint256 indexed marketId, address liquidator, uint256 penalty, uint256 feesPaid);
    event FeesSettled(address indexed trader, uint256 indexed marketId, uint256 borrowFees, int256 fundingPayment, uint256 newCollateral);
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
    error ExceedsMaxOI();
    error ExceedsGlobalOICap();
    error InsufficientCollateral();
    error InvalidSize();
    error InvalidPrice();
    error ReentrantCall();
    error ZeroAddress();
    error NoFeesToClaim();
    error InsufficientLPShares();
    
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
    
    // ============ Core Position Functions ============
    
    /**
     * @notice Open a new position or add to existing (settlement triggered)
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
        
        // LAZY SETTLEMENT: Settle any accrued fees first
        if (pos.size != 0) {
            _settleFees(trader, marketId);
        }
        
        // Check global OI cap
        uint256 globalCap = _getGlobalOICap(marketId);
        uint256 newGlobalOI = totalGlobalOI + _abs(sizeDelta);
        if (newGlobalOI > globalCap) revert ExceedsGlobalOICap();
        
        // Update OI
        _updateOI(market, pos.size, sizeDelta);
        totalGlobalOI = newGlobalOI;
        
        // Update position
        if (pos.size == 0) {
            // New position
            pos.marketId = marketId;
            pos.size = sizeDelta;
            pos.entryPrice = price;
            pos.collateral = collateralDelta;
            pos.openTimestamp = block.timestamp;
            pos.lastFeeUpdate = block.timestamp;
            pos.settledFees = 0;
            pos.lastBorrowIndex = market.borrowIndex;
            pos.lastFundingIndex = market.fundingIndex;
            
            emit PositionOpened(trader, marketId, sizeDelta, price, collateralDelta);
        } else {
            // Modify existing
            int256 newSize = pos.size + sizeDelta;
            
            if (newSize == 0) {
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
                // Direction flip
                _closePosition(trader, marketId, price);
                
                pos.size = newSize;
                pos.entryPrice = price;
                pos.collateral = collateralDelta;
                pos.openTimestamp = block.timestamp;
                pos.lastFeeUpdate = block.timestamp;
                pos.settledFees = 0;
                pos.lastBorrowIndex = market.borrowIndex;
                pos.lastFundingIndex = market.fundingIndex;
                
                emit PositionOpened(trader, marketId, newSize, price, collateralDelta);
            }
        }
    }
    
    /**
     * @notice Add or remove collateral (settlement triggered)
     */
    function modifyCollateral(
        address trader,
        uint256 marketId,
        int256 collateralDelta
    ) external onlyEngine marketExists(marketId) nonReentrant {
        Position storage pos = positions[trader][marketId];
        if (pos.size == 0) revert PositionNotFound();
        
        // LAZY SETTLEMENT: Settle fees before modifying collateral
        _settleFees(trader, marketId);
        
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
     * @notice Liquidate an unsafe position (settlement triggered)
     */
    function liquidatePosition(
        address trader,
        uint256 marketId,
        address liquidator,
        uint256 penalty
    ) external onlyEngine marketExists(marketId) nonReentrant {
        Position storage pos = positions[trader][marketId];
        if (pos.size == 0) revert PositionNotFound();
        
        // LAZY SETTLEMENT: Settle fees before liquidation
        uint256 feesPaid = _settleFees(trader, marketId);
        
        Market storage market = markets[marketId];
        
        // Update OI
        uint256 positionSize = _abs(pos.size);
        if (pos.size > 0) {
            market.totalLongOI -= positionSize;
        } else {
            market.totalShortOI -= positionSize;
        }
        totalGlobalOI -= positionSize;
        
        emit PositionLiquidated(trader, marketId, liquidator, penalty, feesPaid);
        
        delete positions[trader][marketId];
    }
    
    // ============ Index Updates (Called by Keeper/Engine) ============
    
    /**
     * @notice Update global borrow index
     * @dev Called periodically by keeper. Index grows based on current rate.
     */
    function updateBorrowIndex(uint256 marketId, uint256 newIndex) external onlyEngine marketExists(marketId) {
        markets[marketId].borrowIndex = newIndex;
    }
    
    /**
     * @notice Update global funding index
     */
    function updateFundingIndex(uint256 marketId, int256 newIndex) external onlyEngine marketExists(marketId) {
        markets[marketId].fundingIndex = newIndex;
    }
    
    // ============ LP Functions ============
    
    /**
     * @notice LP claims their share of settled fees
     * @dev Triggers settlement of all pending fees to pool
     */
    function claimLPFees(address lp) external nonReentrant {
        LPPosition storage lpPos = lpPositions[lp];
        if (lpPos.shares == 0) revert InsufficientLPShares();
        
        // Calculate claimable: (pool share) - already claimed
        uint256 totalEntitlement = (settledFeePool * lpPos.shares) / totalLPShares;
        uint256 claimable = totalEntitlement > lpPos.claimedFees 
            ? totalEntitlement - lpPos.claimedFees 
            : 0;
        
        if (claimable == 0) revert NoFeesToClaim();
        
        lpPos.claimedFees += claimable;
        
        // Transfer fees to LP
        IERC20(collateralToken).transfer(lp, claimable);
        
        emit LPFeesClaimed(lp, claimable);
    }
    
    // ============ View Functions ============
    
    function getPosition(address trader, uint256 marketId) external view returns (Position memory) {
        return positions[trader][marketId];
    }
    
    function getMarket(uint256 marketId) external view returns (Market memory) {
        return markets[marketId];
    }
    
    /**
     * @notice Calculate current pending fees for a position (view only, for frontend)
     * @dev This is what the frontend displays as "ticking" fees
     */
    function getPendingFees(address trader, uint256 marketId) external view returns (uint256 totalFees) {
        Position storage pos = positions[trader][marketId];
        if (pos.size == 0) return 0;
        
        Market storage market = markets[marketId];
        
        // Calculate borrow fees since last update
        uint256 borrowFees = _calculateBorrowFees(pos, market);
        
        // Add already settled fees
        totalFees = pos.settledFees + borrowFees;
    }
    
    /**
     * @notice Get global OI cap based on current phase
     */
    function getGlobalOICap(uint256 marketId) external view returns (uint256) {
        return _getGlobalOICap(marketId);
    }
    
    /**
     * @notice Get LP's pending claimable fees
     */
    function getLPClaimable(address lp) external view returns (uint256) {
        LPPosition storage lpPos = lpPositions[lp];
        if (lpPos.shares == 0 || totalLPShares == 0) return 0;
        
        uint256 totalEntitlement = (settledFeePool * lpPos.shares) / totalLPShares;
        return totalEntitlement > lpPos.claimedFees 
            ? totalEntitlement - lpPos.claimedFees 
            : 0;
    }
    
    /**
     * @notice Calculate unrealized PnL for a position
     */
    function getUnrealizedPnL(
        address trader,
        uint256 marketId,
        uint256 currentPrice
    ) external view returns (int256 pnl) {
        Position storage pos = positions[trader][marketId];
        if (pos.size == 0) return 0;
        
        pnl = pos.size * (int256(currentPrice) - int256(pos.entryPrice)) / 1e18;
    }
    
    /**
     * @notice Get effective equity (collateral - pending fees + unrealized PnL)
     */
    function getEquity(
        address trader,
        uint256 marketId,
        uint256 currentPrice
    ) external view returns (int256 equity) {
        Position storage pos = positions[trader][marketId];
        if (pos.size == 0) return 0;
        
        int256 pnl = pos.size * (int256(currentPrice) - int256(pos.entryPrice)) / 1e18;
        uint256 pendingFees = this.getPendingFees(trader, marketId);
        
        equity = int256(pos.collateral) + pnl - int256(pendingFees);
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Settle all accrued fees for a position
     * @dev Called on: close, modify, liquidate, collateral change
     * @return feesPaid Total fees settled
     */
    function _settleFees(address trader, uint256 marketId) internal returns (uint256 feesPaid) {
        Position storage pos = positions[trader][marketId];
        Market storage market = markets[marketId];
        
        // Calculate fees since last settlement
        uint256 borrowFees = _calculateBorrowFees(pos, market);
        int256 fundingPayment = _calculateFundingPayment(pos, market);
        
        // Total fees (borrow + funding if paying)
        feesPaid = pos.settledFees + borrowFees;
        if (fundingPayment > 0) {
            feesPaid += uint256(fundingPayment);
        }
        
        // Deduct from collateral
        if (feesPaid > pos.collateral) {
            feesPaid = pos.collateral; // Cap at available collateral
        }
        pos.collateral -= feesPaid;
        
        // If receiving funding, add to collateral
        if (fundingPayment < 0) {
            pos.collateral += uint256(-fundingPayment);
        }
        
        // Distribute fees (50% LP, 30% protocol, 20% insurance)
        _distributeFees(feesPaid);
        
        // Reset fee tracking
        pos.settledFees = 0;
        pos.lastFeeUpdate = block.timestamp;
        pos.lastBorrowIndex = market.borrowIndex;
        pos.lastFundingIndex = market.fundingIndex;
        
        emit FeesSettled(trader, marketId, borrowFees, fundingPayment, pos.collateral);
    }
    
    /**
     * @notice Calculate borrow fees using global index method
     */
    function _calculateBorrowFees(Position storage pos, Market storage market) internal view returns (uint256) {
        if (pos.lastBorrowIndex == 0) return 0;
        
        uint256 notional = _abs(pos.size) * pos.entryPrice / 1e18;
        
        // Fees = notional × (currentIndex / entryIndex - 1)
        uint256 indexRatio = (market.borrowIndex * 1e18) / pos.lastBorrowIndex;
        if (indexRatio <= 1e18) return 0;
        
        return (notional * (indexRatio - 1e18)) / 1e18;
    }
    
    /**
     * @notice Calculate funding payment (positive = pay, negative = receive)
     */
    function _calculateFundingPayment(Position storage pos, Market storage market) internal view returns (int256) {
        int256 fundingDelta = market.fundingIndex - pos.lastFundingIndex;
        
        // Longs pay positive funding, shorts receive (and vice versa)
        return (pos.size * fundingDelta) / 1e18;
    }
    
    /**
     * @notice Distribute fees to LP pool, protocol, and insurance
     */
    function _distributeFees(uint256 totalFees) internal {
        if (totalFees == 0) return;
        
        uint256 lpAmount = (totalFees * LP_FEE_SHARE) / 10000;
        uint256 protocolAmount = (totalFees * PROTOCOL_FEE_SHARE) / 10000;
        uint256 insuranceAmount = totalFees - lpAmount - protocolAmount;
        
        // LP fees go to settled pool (claimed lazily by LPs)
        settledFeePool += lpAmount;
        
        // Protocol and insurance get transferred immediately
        if (protocolAmount > 0) {
            IERC20(collateralToken).transfer(protocolTreasury, protocolAmount);
        }
        if (insuranceAmount > 0) {
            IERC20(collateralToken).transfer(insuranceFund, insuranceAmount);
        }
        
        emit FeeDistributed(lpAmount, protocolAmount, insuranceAmount);
    }
    
    /**
     * @notice Get global OI cap based on time to resolution and live status
     */
    function _getGlobalOICap(uint256 marketId) internal view returns (uint256) {
        Market storage market = markets[marketId];
        
        if (totalTVL == 0) return 0;
        
        uint256 T = market.resolutionTime > block.timestamp 
            ? (market.resolutionTime - block.timestamp) / 1 hours
            : 0;
        
        uint256 capBps;
        
        if (T >= 48) {
            capBps = PHASE_A_CAP;  // 80%
        } else if (T > 12) {
            capBps = PHASE_B_CAP;  // 65%
        } else if (market.isLive) {
            capBps = PHASE_C_CAP;  // 50%
        } else {
            capBps = PHASE_D_CAP;  // 35%
        }
        
        return (totalTVL * capBps) / 10000;
    }
    
    function _closePosition(address trader, uint256 marketId, uint256 exitPrice) internal {
        Position storage pos = positions[trader][marketId];
        Market storage market = markets[marketId];
        
        // Settle final fees
        uint256 feesPaid = _settleFees(trader, marketId);
        
        // Calculate PnL
        int256 pnl = pos.size * (int256(exitPrice) - int256(pos.entryPrice)) / 1e18;
        
        // Update OI
        uint256 positionSize = _abs(pos.size);
        if (pos.size > 0) {
            market.totalLongOI -= positionSize;
        } else {
            market.totalShortOI -= positionSize;
        }
        totalGlobalOI -= positionSize;
        
        emit PositionClosed(trader, marketId, pnl, feesPaid);
        
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
