// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Router
 * @author LEVER Protocol
 * @notice User-facing entry point for all trading operations
 * @dev Coordinates between all engines for atomic operations
 * 
 * Users interact with Router, Router coordinates:
 * - PositionLedger (position storage)
 * - PriceEngine (execution prices)
 * - RiskEngine (margin checks)
 * - FundingEngine (funding settlement)
 */

import {IPositionLedger} from "./interfaces/IPositionLedger.sol";
import {IPriceEngine} from "./interfaces/IPriceEngine.sol";
import {IRiskEngine} from "./interfaces/IRiskEngine.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract Router {
    
    // ============ State ============
    
    address public owner;
    IPositionLedger public ledger;
    IPriceEngine public priceEngine;
    IRiskEngine public riskEngine;
    IERC20 public collateralToken;
    
    // Reentrancy guard
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status;
    
    // Constants
    uint256 public constant PRECISION = 1e18;
    
    // ============ Events ============
    
    event PositionOpened(
        address indexed trader,
        uint256 indexed marketId,
        int256 size,
        uint256 executionPrice,
        uint256 collateral,
        uint256 fee
    );
    event PositionClosed(
        address indexed trader,
        uint256 indexed marketId,
        int256 size,
        uint256 executionPrice,
        int256 realizedPnL
    );
    event CollateralDeposited(address indexed trader, uint256 indexed marketId, uint256 amount);
    event CollateralWithdrawn(address indexed trader, uint256 indexed marketId, uint256 amount);
    
    // ============ Errors ============
    
    error Unauthorized();
    error InsufficientMargin();
    error InvalidSize();
    error StalePrice();
    error TransferFailed();
    error ReentrantCall();
    
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
        address _collateralToken
    ) {
        owner = msg.sender;
        ledger = IPositionLedger(_ledger);
        priceEngine = IPriceEngine(_priceEngine);
        riskEngine = IRiskEngine(_riskEngine);
        collateralToken = IERC20(_collateralToken);
        _status = NOT_ENTERED;
    }
    
    // ============ Admin Functions ============
    
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
    
    function setEngines(
        address _ledger,
        address _priceEngine,
        address _riskEngine
    ) external onlyOwner {
        if (_ledger != address(0)) ledger = IPositionLedger(_ledger);
        if (_priceEngine != address(0)) priceEngine = IPriceEngine(_priceEngine);
        if (_riskEngine != address(0)) riskEngine = IRiskEngine(_riskEngine);
    }
    
    // ============ Trading Functions ============
    
    /**
     * @notice Open or increase a position
     * @param marketId Market to trade
     * @param sizeDelta Position size change (positive = long, negative = short)
     * @param collateralAmount Collateral to deposit (in USDC)
     * @param maxPrice Maximum execution price (slippage protection for longs)
     * @param minPrice Minimum execution price (slippage protection for shorts)
     */
    function openPosition(
        uint256 marketId,
        int256 sizeDelta,
        uint256 collateralAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external nonReentrant {
        if (sizeDelta == 0) revert InvalidSize();
        
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
        
        // Get current position
        IPositionLedger.Position memory pos = ledger.getPosition(msg.sender, marketId);
        uint256 totalCollateral = pos.collateral + collateralAmount;
        
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
        
        // Accrue interest before position change
        riskEngine.accrueInterest(marketId);
        
        // Execute on ledger
        ledger.openPosition(
            msg.sender,
            marketId,
            sizeDelta,
            executionPrice,
            collateralAmount
        );
        
        emit PositionOpened(
            msg.sender,
            marketId,
            sizeDelta,
            executionPrice,
            collateralAmount,
            0 // TODO: calculate trading fee
        );
    }
    
    /**
     * @notice Close or reduce a position
     * @param marketId Market ID
     * @param sizeDelta Size to close (opposite sign of position)
     * @param minPrice Minimum price for closing longs
     * @param maxPrice Maximum price for closing shorts
     */
    function closePosition(
        uint256 marketId,
        int256 sizeDelta,
        uint256 minPrice,
        uint256 maxPrice
    ) external nonReentrant {
        IPositionLedger.Position memory pos = ledger.getPosition(msg.sender, marketId);
        if (pos.size == 0) revert InvalidSize();
        
        // Check price freshness
        if (priceEngine.isPriceStale(marketId, 60)) revert StalePrice();
        
        // Get execution price
        uint256 executionPrice = priceEngine.getExecutionPrice(marketId, sizeDelta);
        
        // Slippage check (closing long = selling, closing short = buying)
        if (pos.size > 0 && executionPrice < minPrice) revert InsufficientMargin();
        if (pos.size < 0 && executionPrice > maxPrice) revert InsufficientMargin();
        
        // Calculate PnL
        int256 pnl = ledger.getUnrealizedPnL(msg.sender, marketId, executionPrice);
        
        // Accrue interest
        riskEngine.accrueInterest(marketId);
        
        // Execute on ledger
        ledger.openPosition(
            msg.sender,
            marketId,
            sizeDelta,
            executionPrice,
            0
        );
        
        // If fully closed, return collateral
        IPositionLedger.Position memory newPos = ledger.getPosition(msg.sender, marketId);
        if (newPos.size == 0 && pos.collateral > 0) {
            // Calculate final amount (collateral + PnL)
            int256 finalAmount = int256(pos.collateral) + pnl;
            if (finalAmount > 0) {
                if (!collateralToken.transfer(msg.sender, uint256(finalAmount))) {
                    revert TransferFailed();
                }
            }
        }
        
        emit PositionClosed(
            msg.sender,
            marketId,
            sizeDelta,
            executionPrice,
            pnl
        );
    }
    
    /**
     * @notice Add collateral to an existing position
     * @param marketId Market ID
     * @param amount Amount to add
     */
    function depositCollateral(uint256 marketId, uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidSize();
        
        // Transfer from user
        if (!collateralToken.transferFrom(msg.sender, address(this), amount)) {
            revert TransferFailed();
        }
        
        // Update position
        ledger.modifyCollateral(msg.sender, marketId, int256(amount));
        
        emit CollateralDeposited(msg.sender, marketId, amount);
    }
    
    /**
     * @notice Remove collateral from a position
     * @param marketId Market ID
     * @param amount Amount to withdraw
     */
    function withdrawCollateral(uint256 marketId, uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidSize();
        
        IPositionLedger.Position memory pos = ledger.getPosition(msg.sender, marketId);
        
        // Check we maintain margin after withdrawal
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
        
        // Update position
        ledger.modifyCollateral(msg.sender, marketId, -int256(amount));
        
        // Transfer to user
        if (!collateralToken.transfer(msg.sender, amount)) {
            revert TransferFailed();
        }
        
        emit CollateralWithdrawn(msg.sender, marketId, amount);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get position details with current PnL
     */
    function getPositionWithPnL(
        address trader,
        uint256 marketId
    ) external view returns (
        IPositionLedger.Position memory position,
        int256 unrealizedPnL,
        uint256 currentPrice,
        bool isLiquidatable
    ) {
        position = ledger.getPosition(trader, marketId);
        currentPrice = priceEngine.getMarkPrice(marketId);
        
        if (position.size != 0) {
            unrealizedPnL = ledger.getUnrealizedPnL(trader, marketId, currentPrice);
            (isLiquidatable,) = riskEngine.isLiquidatable(trader, marketId, currentPrice);
        }
    }
    
    /**
     * @notice Preview a trade execution
     */
    function previewTrade(
        uint256 marketId,
        int256 sizeDelta,
        uint256 collateral
    ) external view returns (
        uint256 executionPrice,
        uint256 requiredMargin,
        uint256 maxLeverage,
        bool marginOk
    ) {
        executionPrice = priceEngine.getExecutionPrice(marketId, sizeDelta);
        
        uint256 absSize = sizeDelta >= 0 ? uint256(sizeDelta) : uint256(-sizeDelta);
        (requiredMargin,) = riskEngine.getRequiredCollateral(marketId, absSize, executionPrice);
        maxLeverage = riskEngine.getMaxPositionSize(marketId, collateral, executionPrice);
        marginOk = riskEngine.checkInitialMargin(marketId, absSize, collateral, executionPrice);
    }
}
