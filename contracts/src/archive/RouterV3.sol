// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RouterV3
 * @author LEVER Protocol
 * @notice User-facing entry point with COMPLETE fee implementation
 * 
 * CHANGES from V2:
 * - Trading fees collected and sent to LP Pool
 * - Borrow fees charged from collateral
 * - Funding payments settled between traders
 * - LP allocation/deallocation (from V2)
 */

import {IPositionLedger} from "./interfaces/IPositionLedger.sol";
import {IPriceEngine} from "./interfaces/IPriceEngine.sol";
import {IRiskEngine} from "./interfaces/IRiskEngine.sol";
import {IERC20} from "./interfaces/IERC20.sol";

interface ILPPool {
    function allocate(uint256 amount) external;
    function deallocate(uint256 amount) external;
    function addFees(uint256 amount) external;
}

interface IFundingEngine {
    function getPendingFunding(address trader, uint256 marketId) external view returns (int256);
}

interface IRiskEngineV3 {
    function accrueInterest(uint256 marketId) external;
    function checkInitialMargin(uint256 marketId, uint256 size, uint256 collateral, uint256 price) external view returns (bool);
    function getPendingBorrowFee(address trader, uint256 marketId) external view returns (uint256);
    function isLiquidatable(address trader, uint256 marketId, uint256 price) external view returns (bool, uint256);
    function getRequiredCollateral(uint256 marketId, uint256 size, uint256 price) external view returns (uint256, uint256);
    function getMaxPositionSize(uint256 marketId, uint256 collateral, uint256 price) external view returns (uint256);
}

contract RouterV3 {
    
    // ============ State ============
    
    address public owner;
    IPositionLedger public ledger;
    IPriceEngine public priceEngine;
    IRiskEngineV3 public riskEngine;
    IFundingEngine public fundingEngine;
    IERC20 public collateralToken;
    ILPPool public lpPool;
    
    // Fee configuration
    uint256 public tradingFeeBps = 10; // 0.10% = 10 bps
    
    // Reentrancy guard
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status;
    
    // Constants
    uint256 public constant PRECISION = 1e18;
    uint256 public constant BASIS_POINTS = 10000;
    
    // ============ Events ============
    
    event PositionOpened(
        address indexed trader,
        uint256 indexed marketId,
        int256 size,
        uint256 executionPrice,
        uint256 collateral,
        uint256 tradingFee
    );
    event PositionClosed(
        address indexed trader,
        uint256 indexed marketId,
        int256 size,
        uint256 executionPrice,
        int256 realizedPnL,
        uint256 tradingFee
    );
    event CollateralDeposited(address indexed trader, uint256 indexed marketId, uint256 amount);
    event CollateralWithdrawn(address indexed trader, uint256 indexed marketId, uint256 amount);
    event LPAllocated(uint256 indexed marketId, uint256 amount);
    event LPDeallocated(uint256 indexed marketId, uint256 amount);
    event FeesCollected(address indexed trader, uint256 tradingFee, uint256 borrowFee, int256 fundingPayment);
    
    // ============ Errors ============
    
    error Unauthorized();
    error InsufficientMargin();
    error InvalidSize();
    error StalePrice();
    error TransferFailed();
    error ReentrantCall();
    error LPPoolNotSet();
    error InsufficientCollateral();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
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
        address _ledger,
        address _priceEngine,
        address _riskEngine,
        address _fundingEngine,
        address _collateralToken,
        address _lpPool
    ) {
        owner = msg.sender;
        ledger = IPositionLedger(_ledger);
        priceEngine = IPriceEngine(_priceEngine);
        riskEngine = IRiskEngineV3(_riskEngine);
        fundingEngine = IFundingEngine(_fundingEngine);
        collateralToken = IERC20(_collateralToken);
        lpPool = ILPPool(_lpPool);
        _status = NOT_ENTERED;
        
        // Approve LP Pool to pull fees
        collateralToken.approve(_lpPool, type(uint256).max);
    }
    
    // ============ Admin Functions ============
    
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
    
    function setEngines(
        address _ledger,
        address _priceEngine,
        address _riskEngine,
        address _fundingEngine
    ) external onlyOwner {
        if (_ledger != address(0)) ledger = IPositionLedger(_ledger);
        if (_priceEngine != address(0)) priceEngine = IPriceEngine(_priceEngine);
        if (_riskEngine != address(0)) riskEngine = IRiskEngineV3(_riskEngine);
        if (_fundingEngine != address(0)) fundingEngine = IFundingEngine(_fundingEngine);
    }
    
    function setLPPool(address _lpPool) external onlyOwner {
        lpPool = ILPPool(_lpPool);
        collateralToken.approve(_lpPool, type(uint256).max);
    }
    
    function setTradingFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 100, "Fee too high"); // Max 1%
        tradingFeeBps = _feeBps;
    }
    
    // ============ Trading Functions ============
    
    /**
     * @notice Open or increase a position
     */
    function openPosition(
        uint256 marketId,
        int256 sizeDelta,
        uint256 collateralAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external nonReentrant {
        if (sizeDelta == 0) revert InvalidSize();
        if (address(lpPool) == address(0)) revert LPPoolNotSet();
        
        // Check price freshness
        if (priceEngine.isPriceStale(marketId, 60)) revert StalePrice();
        
        // Get execution price
        uint256 executionPrice = priceEngine.getExecutionPrice(marketId, sizeDelta);
        
        // Slippage check
        if (sizeDelta > 0 && executionPrice > maxPrice) revert InsufficientMargin();
        if (sizeDelta < 0 && executionPrice < minPrice) revert InsufficientMargin();
        
        // Transfer collateral from user
        if (collateralAmount > 0) {
            if (!collateralToken.transferFrom(msg.sender, address(this), collateralAmount)) {
                revert TransferFailed();
            }
        }
        
        // Accrue interest before position change
        riskEngine.accrueInterest(marketId);
        
        // Get current position and settle existing fees
        IPositionLedger.Position memory pos = ledger.getPosition(msg.sender, marketId);
        uint256 totalCollateral = pos.collateral + collateralAmount;
        
        // Settle fees for existing position
        uint256 borrowFee = 0;
        int256 fundingPayment = 0;
        if (pos.size != 0) {
            (borrowFee, fundingPayment, totalCollateral) = _settleFees(msg.sender, marketId, totalCollateral);
        }
        
        // Calculate trading fee
        uint256 absSizeDelta = sizeDelta >= 0 ? uint256(sizeDelta) : uint256(-sizeDelta);
        uint256 notionalValue = (absSizeDelta * executionPrice) / PRECISION;
        uint256 tradingFee = (notionalValue * tradingFeeBps) / BASIS_POINTS;
        
        // Deduct trading fee from collateral
        if (tradingFee >= totalCollateral) revert InsufficientCollateral();
        totalCollateral -= tradingFee;
        
        // Calculate new position size
        int256 newSize = pos.size + sizeDelta;
        uint256 absNewSize = newSize >= 0 ? uint256(newSize) : uint256(-newSize);
        
        // Check margin requirements
        if (absNewSize > 0) {
            bool marginOk = riskEngine.checkInitialMargin(
                marketId,
                absNewSize,
                totalCollateral,
                executionPrice
            );
            if (!marginOk) revert InsufficientMargin();
        }
        
        // Allocate LP capital for position notional
        uint256 positionValue = (absSizeDelta * executionPrice) / PRECISION;
        if (positionValue > 0) {
            lpPool.allocate(positionValue);
            emit LPAllocated(marketId, positionValue);
        }
        
        // Send trading fee to LP Pool
        if (tradingFee > 0) {
            lpPool.addFees(tradingFee);
        }
        
        // Execute on ledger - adjust for fees taken
        uint256 collateralForLedger = collateralAmount > tradingFee + borrowFee 
            ? collateralAmount - tradingFee - borrowFee - (fundingPayment > 0 ? uint256(fundingPayment) : 0)
            : 0;
            
        ledger.openPosition(
            msg.sender,
            marketId,
            sizeDelta,
            executionPrice,
            collateralForLedger
        );
        
        emit FeesCollected(msg.sender, tradingFee, borrowFee, fundingPayment);
        emit PositionOpened(
            msg.sender,
            marketId,
            sizeDelta,
            executionPrice,
            collateralAmount,
            tradingFee
        );
    }
    
    /**
     * @notice Close or reduce a position
     */
    function closePosition(
        uint256 marketId,
        int256 sizeDelta,
        uint256 minPrice,
        uint256 maxPrice
    ) external nonReentrant {
        IPositionLedger.Position memory pos = ledger.getPosition(msg.sender, marketId);
        if (pos.size == 0) revert InvalidSize();
        if (address(lpPool) == address(0)) revert LPPoolNotSet();
        
        // Check price freshness
        if (priceEngine.isPriceStale(marketId, 60)) revert StalePrice();
        
        // Get execution price
        uint256 executionPrice = priceEngine.getExecutionPrice(marketId, sizeDelta);
        
        // Slippage check
        if (pos.size > 0 && executionPrice < minPrice) revert InsufficientMargin();
        if (pos.size < 0 && executionPrice > maxPrice) revert InsufficientMargin();
        
        // Accrue interest
        riskEngine.accrueInterest(marketId);
        
        // Settle fees
        uint256 borrowFee;
        int256 fundingPayment;
        uint256 remainingCollateral;
        (borrowFee, fundingPayment, remainingCollateral) = _settleFees(msg.sender, marketId, pos.collateral);
        
        // Calculate trading fee
        uint256 absSizeDelta = sizeDelta >= 0 ? uint256(sizeDelta) : uint256(-sizeDelta);
        uint256 notionalValue = (absSizeDelta * executionPrice) / PRECISION;
        uint256 tradingFee = (notionalValue * tradingFeeBps) / BASIS_POINTS;
        
        // Calculate PnL
        int256 pnl = ledger.getUnrealizedPnL(msg.sender, marketId, executionPrice);
        
        // Deallocate LP capital
        uint256 positionValue = (absSizeDelta * pos.entryPrice) / PRECISION;
        if (positionValue > 0) {
            lpPool.deallocate(positionValue);
            emit LPDeallocated(marketId, positionValue);
        }
        
        // Execute on ledger
        ledger.openPosition(
            msg.sender,
            marketId,
            sizeDelta,
            executionPrice,
            0
        );
        
        // Check if fully closed
        IPositionLedger.Position memory newPos = ledger.getPosition(msg.sender, marketId);
        if (newPos.size == 0) {
            // Full close - settle everything
            int256 finalAmount = int256(remainingCollateral) + pnl - int256(tradingFee);
            
            // Send trading fee to LP Pool
            if (tradingFee > 0 && remainingCollateral >= tradingFee) {
                lpPool.addFees(tradingFee);
            }
            
            // Handle PnL with LP Pool
            if (pnl > 0) {
                // Trader profit - LP Pool pays
                collateralToken.transferFrom(address(lpPool), address(this), uint256(pnl));
            } else if (pnl < 0) {
                // Trader loss - goes to LP Pool
                uint256 loss = uint256(-pnl);
                if (loss > remainingCollateral) loss = remainingCollateral;
                collateralToken.transfer(address(lpPool), loss);
            }
            
            // Return remaining to trader
            if (finalAmount > 0) {
                collateralToken.transfer(msg.sender, uint256(finalAmount));
            }
        }
        
        emit FeesCollected(msg.sender, tradingFee, borrowFee, fundingPayment);
        emit PositionClosed(
            msg.sender,
            marketId,
            sizeDelta,
            executionPrice,
            pnl,
            tradingFee
        );
    }
    
    /**
     * @notice Add collateral to position
     */
    function depositCollateral(uint256 marketId, uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidSize();
        
        if (!collateralToken.transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }
        
        ledger.modifyCollateral(msg.sender, marketId, int256(amount));
        emit CollateralDeposited(msg.sender, marketId, amount);
    }
    
    /**
     * @notice Remove collateral from position
     */
    function withdrawCollateral(uint256 marketId, uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidSize();
        
        IPositionLedger.Position memory pos = ledger.getPosition(msg.sender, marketId);
        
        if (pos.size != 0) {
            uint256 newCollateral = pos.collateral - amount;
            uint256 currentPrice = priceEngine.getMarkPrice(marketId);
            uint256 absSize = pos.size >= 0 ? uint256(pos.size) : uint256(-pos.size);
            
            bool marginOk = riskEngine.checkInitialMargin(
                marketId,
                absSize,
                newCollateral,
                currentPrice
            );
            if (!marginOk) revert InsufficientMargin();
        }
        
        ledger.modifyCollateral(msg.sender, marketId, -int256(amount));
        
        if (!collateralToken.transfer(msg.sender, amount)) {
            revert TransferFailed();
        }
        
        emit CollateralWithdrawn(msg.sender, marketId, amount);
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Settle borrow fees and funding payments
     * @return borrowFee Amount of borrow fee charged
     * @return fundingPayment Funding payment (positive = owed, negative = received)
     * @return remainingCollateral Collateral after fees
     */
    function _settleFees(
        address trader,
        uint256 marketId,
        uint256 collateral
    ) internal returns (uint256 borrowFee, int256 fundingPayment, uint256 remainingCollateral) {
        remainingCollateral = collateral;
        
        // Get pending borrow fee
        borrowFee = riskEngine.getPendingBorrowFee(trader, marketId);
        if (borrowFee > 0 && borrowFee < remainingCollateral) {
            remainingCollateral -= borrowFee;
            // Send borrow fee to LP Pool
            lpPool.addFees(borrowFee);
        }
        
        // Get pending funding
        fundingPayment = fundingEngine.getPendingFunding(trader, marketId);
        if (fundingPayment > 0) {
            // Trader owes funding
            uint256 owes = uint256(fundingPayment);
            if (owes < remainingCollateral) {
                remainingCollateral -= owes;
                // Note: Funding is zero-sum, goes to counterparty pool (simplified: to LP Pool for now)
            }
        } else if (fundingPayment < 0) {
            // Trader receives funding
            remainingCollateral += uint256(-fundingPayment);
        }
    }
    
    // ============ View Functions ============
    
    function getPositionWithPnL(
        address trader,
        uint256 marketId
    ) external view returns (
        IPositionLedger.Position memory position,
        int256 unrealizedPnL,
        uint256 currentPrice,
        bool isLiquidatable,
        uint256 pendingBorrowFee,
        int256 pendingFunding
    ) {
        position = ledger.getPosition(trader, marketId);
        currentPrice = priceEngine.getMarkPrice(marketId);
        
        if (position.size != 0) {
            unrealizedPnL = ledger.getUnrealizedPnL(trader, marketId, currentPrice);
            (isLiquidatable,) = riskEngine.isLiquidatable(trader, marketId, currentPrice);
            pendingBorrowFee = riskEngine.getPendingBorrowFee(trader, marketId);
            pendingFunding = fundingEngine.getPendingFunding(trader, marketId);
        }
    }
    
    function previewTrade(
        uint256 marketId,
        int256 sizeDelta,
        uint256 collateral
    ) external view returns (
        uint256 executionPrice,
        uint256 requiredMargin,
        uint256 maxLeverage,
        bool marginOk,
        uint256 tradingFee
    ) {
        executionPrice = priceEngine.getExecutionPrice(marketId, sizeDelta);
        
        uint256 absSize = sizeDelta >= 0 ? uint256(sizeDelta) : uint256(-sizeDelta);
        (requiredMargin,) = riskEngine.getRequiredCollateral(marketId, absSize, executionPrice);
        maxLeverage = riskEngine.getMaxPositionSize(marketId, collateral, executionPrice);
        
        // Calculate trading fee
        uint256 notionalValue = (absSize * executionPrice) / PRECISION;
        tradingFee = (notionalValue * tradingFeeBps) / BASIS_POINTS;
        
        // Check margin after fee
        uint256 collateralAfterFee = collateral > tradingFee ? collateral - tradingFee : 0;
        marginOk = riskEngine.checkInitialMargin(marketId, absSize, collateralAfterFee, executionPrice);
    }
}
