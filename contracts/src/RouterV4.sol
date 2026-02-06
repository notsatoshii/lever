// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC20.sol";

/**
 * @title RouterV4
 * @author LEVER Protocol
 * @notice Main entry point integrating all V2 contracts
 * @dev Coordinates:
 *      - vAMM for Entry Price (slippage)
 *      - PriceEngineV2 for Mark Price (PI)
 *      - PositionLedgerV2 for position state (lazy fees)
 *      - RiskEngineV2 for margin checks
 *      - BorrowFeeEngineV2 for fee calculations
 * 
 * KEY ARCHITECTURE:
 * Entry Price ≠ Mark Price
 * - Entry: from vAMM (includes slippage)
 * - Mark: from PriceEngineV2 (smoothed PI)
 */
contract RouterV4 {
    
    // ============ Constants ============
    
    uint256 public constant SCALE = 1e18;
    uint256 public constant MAX_SLIPPAGE = 5e16;  // 5% max slippage
    
    // ============ State ============
    
    address public owner;
    address public collateralToken;     // USDC
    
    // V2 Contract addresses
    address public vAMM;                // Entry price calculator
    address public priceEngine;         // Mark price (PriceEngineV2)
    address public positionLedger;      // Position state (PositionLedgerV2)
    address public riskEngine;          // Margin checks (RiskEngineV2)
    address public borrowFeeEngine;     // Fee calculations (BorrowFeeEngineV2)
    address public lpPool;              // Liquidity pool
    
    // Trading enabled
    bool public tradingEnabled;
    
    // ============ Events ============
    
    event PositionOpened(
        address indexed trader,
        uint256 indexed marketId,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 entryPrice,
        uint256 markPrice
    );
    event PositionClosed(
        address indexed trader,
        uint256 indexed marketId,
        uint256 size,
        uint256 exitPrice,
        int256 pnl
    );
    event PositionIncreased(
        address indexed trader,
        uint256 indexed marketId,
        uint256 sizeDelta,
        uint256 collateralDelta,
        uint256 newEntryPrice
    );
    event CollateralModified(
        address indexed trader,
        uint256 indexed marketId,
        int256 collateralDelta,
        uint256 newCollateral
    );
    event ContractsUpdated(
        address vAMM,
        address priceEngine,
        address positionLedger,
        address riskEngine,
        address borrowFeeEngine
    );
    
    // ============ Errors ============
    
    error Unauthorized();
    error ZeroAddress();
    error TradingDisabled();
    error InvalidSize();
    error InvalidCollateral();
    error SlippageExceeded();
    error InsufficientMargin();
    error PositionNotFound();
    error TransferFailed();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier whenTradingEnabled() {
        if (!tradingEnabled) revert TradingDisabled();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _collateralToken) {
        if (_collateralToken == address(0)) revert ZeroAddress();
        owner = msg.sender;
        collateralToken = _collateralToken;
    }
    
    // ============ Admin Functions ============
    
    function setContracts(
        address _vAMM,
        address _priceEngine,
        address _positionLedger,
        address _riskEngine,
        address _borrowFeeEngine,
        address _lpPool
    ) external onlyOwner {
        vAMM = _vAMM;
        priceEngine = _priceEngine;
        positionLedger = _positionLedger;
        riskEngine = _riskEngine;
        borrowFeeEngine = _borrowFeeEngine;
        lpPool = _lpPool;
        
        emit ContractsUpdated(_vAMM, _priceEngine, _positionLedger, _riskEngine, _borrowFeeEngine);
    }
    
    function setTradingEnabled(bool enabled) external onlyOwner {
        tradingEnabled = enabled;
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
    
    // ============ Trading Functions ============
    
    /**
     * @notice Open a new leveraged position
     * @param marketId Market to trade
     * @param isLong True for long (YES), false for short (NO)
     * @param collateralAmount Collateral to deposit
     * @param leverage Desired leverage (e.g., 5e18 = 5x)
     * @param maxSlippage Max acceptable slippage (e.g., 1e16 = 1%)
     */
    function openPosition(
        uint256 marketId,
        bool isLong,
        uint256 collateralAmount,
        uint256 leverage,
        uint256 maxSlippage
    ) external whenTradingEnabled returns (uint256 positionSize, uint256 entryPrice) {
        if (collateralAmount == 0) revert InvalidCollateral();
        if (maxSlippage > MAX_SLIPPAGE) maxSlippage = MAX_SLIPPAGE;
        
        // Transfer collateral from trader
        _transferIn(msg.sender, collateralAmount);
        
        // Calculate position size (notional)
        positionSize = collateralAmount * leverage / SCALE;
        
        // Get Mark Price (PI) from PriceEngineV2 for risk checks
        uint256 markPrice = _getMarkPrice(marketId);
        
        // Validate margin requirements
        _validateMargin(marketId, positionSize, collateralAmount, leverage);
        
        // Get Entry Price from vAMM (with slippage)
        entryPrice = _getEntryPrice(marketId, isLong, positionSize, markPrice, maxSlippage);
        
        // Open position in ledger
        int256 sizeSigned = isLong ? int256(positionSize) : -int256(positionSize);
        _openPositionInLedger(msg.sender, marketId, sizeSigned, entryPrice, collateralAmount);
        
        emit PositionOpened(
            msg.sender,
            marketId,
            isLong,
            positionSize,
            collateralAmount,
            entryPrice,
            markPrice
        );
    }
    
    /**
     * @notice Close an existing position
     * @param marketId Market ID
     * @param closePercent Percentage to close (1e18 = 100%)
     * @param minAmountOut Minimum collateral to receive back
     */
    function closePosition(
        uint256 marketId,
        uint256 closePercent,
        uint256 minAmountOut
    ) external returns (int256 pnl, uint256 amountOut) {
        // Get current position from ledger
        (
            int256 size,
            uint256 entryPrice,
            uint256 collateral,
            uint256 pendingFees
        ) = _getPosition(msg.sender, marketId);
        
        if (size == 0) revert PositionNotFound();
        
        // Calculate close amount
        uint256 closeSize = _abs(size) * closePercent / SCALE;
        if (closeSize == 0) revert InvalidSize();
        
        // Get exit price from vAMM (opposite direction)
        bool isBuy = size < 0; // If short, buying to close
        uint256 exitPrice = _getExitPrice(marketId, isBuy, closeSize);
        
        // Calculate PnL
        // For longs: PnL = size × (exitPrice - entryPrice)
        // For shorts: PnL = |size| × (entryPrice - exitPrice)
        if (size > 0) {
            pnl = int256(closeSize) * (int256(exitPrice) - int256(entryPrice)) / int256(SCALE);
        } else {
            pnl = int256(closeSize) * (int256(entryPrice) - int256(exitPrice)) / int256(SCALE);
        }
        
        // Calculate amount to return
        uint256 collateralToReturn = collateral * closePercent / SCALE;
        uint256 feesToDeduct = pendingFees * closePercent / SCALE;
        
        if (pnl >= 0) {
            amountOut = collateralToReturn + uint256(pnl) - feesToDeduct;
        } else {
            uint256 loss = uint256(-pnl);
            if (loss + feesToDeduct >= collateralToReturn) {
                amountOut = 0;
            } else {
                amountOut = collateralToReturn - loss - feesToDeduct;
            }
        }
        
        if (amountOut < minAmountOut) revert SlippageExceeded();
        
        // Update position in ledger
        int256 sizeDelta = size > 0 ? -int256(closeSize) : int256(closeSize);
        _modifyPositionInLedger(msg.sender, marketId, sizeDelta, exitPrice);
        
        // Transfer collateral back to trader
        if (amountOut > 0) {
            _transferOut(msg.sender, amountOut);
        }
        
        emit PositionClosed(msg.sender, marketId, closeSize, exitPrice, pnl);
    }
    
    /**
     * @notice Add collateral to an existing position
     */
    function addCollateral(uint256 marketId, uint256 amount) external {
        if (amount == 0) revert InvalidCollateral();
        
        // Transfer collateral from trader
        _transferIn(msg.sender, amount);
        
        // Update position in ledger
        _modifyCollateralInLedger(msg.sender, marketId, int256(amount));
        
        emit CollateralModified(msg.sender, marketId, int256(amount), 0);
    }
    
    /**
     * @notice Remove collateral from an existing position (if margin allows)
     */
    function removeCollateral(uint256 marketId, uint256 amount) external {
        if (amount == 0) revert InvalidCollateral();
        
        // Get current position
        (int256 size, , uint256 collateral, uint256 pendingFees) = _getPosition(msg.sender, marketId);
        if (size == 0) revert PositionNotFound();
        
        // Check if removal maintains margin requirements
        uint256 newCollateral = collateral - amount;
        uint256 notional = _abs(size) * _getMarkPrice(marketId) / SCALE;
        uint256 effectiveLeverage = notional * SCALE / (newCollateral - pendingFees);
        
        // Get max leverage for market
        uint256 maxLeverage = _getMaxLeverage(marketId);
        if (effectiveLeverage > maxLeverage) revert InsufficientMargin();
        
        // Update position in ledger
        _modifyCollateralInLedger(msg.sender, marketId, -int256(amount));
        
        // Transfer collateral to trader
        _transferOut(msg.sender, amount);
        
        emit CollateralModified(msg.sender, marketId, -int256(amount), newCollateral);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get position details with current values
     */
    function getPositionDetails(
        address trader,
        uint256 marketId
    ) external view returns (
        int256 size,
        uint256 entryPrice,
        uint256 collateral,
        uint256 markPrice,
        int256 unrealizedPnl,
        uint256 pendingFees,
        int256 equity,
        uint256 liquidationPrice
    ) {
        (size, entryPrice, collateral, pendingFees) = _getPosition(trader, marketId);
        markPrice = _getMarkPrice(marketId);
        
        // Calculate unrealized PnL using Mark Price
        unrealizedPnl = size * (int256(markPrice) - int256(entryPrice)) / int256(SCALE);
        
        // Calculate equity
        equity = int256(collateral) + unrealizedPnl - int256(pendingFees);
        
        // Get liquidation price from RiskEngine
        liquidationPrice = _getLiquidationPrice(size, entryPrice, collateral, pendingFees);
    }
    
    /**
     * @notice Preview a trade (get expected entry price and fees)
     */
    function previewTrade(
        uint256 marketId,
        bool isLong,
        uint256 collateral,
        uint256 leverage
    ) external view returns (
        uint256 positionSize,
        uint256 expectedEntryPrice,
        uint256 markPrice,
        uint256 priceImpact,
        uint256 estimatedDailyFee
    ) {
        positionSize = collateral * leverage / SCALE;
        markPrice = _getMarkPrice(marketId);
        
        // Get expected entry price from vAMM
        (expectedEntryPrice, priceImpact) = _previewEntryPrice(marketId, isLong, positionSize);
        
        // Estimate daily borrow fee
        uint256 hourlyRate = _getCurrentBorrowRate(marketId);
        estimatedDailyFee = positionSize * hourlyRate * 24 / SCALE;
    }
    
    // ============ Internal Functions ============
    
    function _transferIn(address from, uint256 amount) internal {
        bool success = IERC20(collateralToken).transferFrom(from, address(this), amount);
        if (!success) revert TransferFailed();
    }
    
    function _transferOut(address to, uint256 amount) internal {
        bool success = IERC20(collateralToken).transfer(to, amount);
        if (!success) revert TransferFailed();
    }
    
    function _getMarkPrice(uint256 marketId) internal view returns (uint256) {
        (bool success, bytes memory data) = priceEngine.staticcall(
            abi.encodeWithSignature("getMarkPrice(uint256)", marketId)
        );
        require(success && data.length >= 32, "Mark price failed");
        return abi.decode(data, (uint256));
    }
    
    function _getEntryPrice(
        uint256 marketId,
        bool isBuy,
        uint256 amount,
        uint256 markPrice,
        uint256 maxSlippage
    ) internal returns (uint256 entryPrice) {
        // Get execution price from vAMM
        (bool success, bytes memory data) = vAMM.call(
            abi.encodeWithSignature(
                "swap(uint256,address,bool,uint256,uint256)",
                marketId,
                msg.sender,
                isBuy,
                amount,
                0  // minAmountOut handled separately
            )
        );
        require(success, "vAMM swap failed");
        
        (, entryPrice) = abi.decode(data, (uint256, uint256));
        
        // Check slippage vs mark price
        uint256 slippage;
        if (isBuy) {
            slippage = entryPrice > markPrice 
                ? (entryPrice - markPrice) * SCALE / markPrice 
                : 0;
        } else {
            slippage = markPrice > entryPrice 
                ? (markPrice - entryPrice) * SCALE / markPrice 
                : 0;
        }
        
        if (slippage > maxSlippage) revert SlippageExceeded();
    }
    
    function _getExitPrice(
        uint256 marketId,
        bool isBuy,
        uint256 amount
    ) internal returns (uint256 exitPrice) {
        (bool success, bytes memory data) = vAMM.call(
            abi.encodeWithSignature(
                "swap(uint256,address,bool,uint256,uint256)",
                marketId,
                msg.sender,
                isBuy,
                amount,
                0
            )
        );
        require(success, "vAMM swap failed");
        
        (, exitPrice) = abi.decode(data, (uint256, uint256));
    }
    
    function _previewEntryPrice(
        uint256 marketId,
        bool isBuy,
        uint256 amount
    ) internal view returns (uint256 entryPrice, uint256 priceImpact) {
        (bool success, bytes memory data) = vAMM.staticcall(
            abi.encodeWithSignature(
                "getExecutionPrice(uint256,bool,uint256)",
                marketId,
                isBuy,
                amount
            )
        );
        require(success, "Preview failed");
        
        (, entryPrice, priceImpact) = abi.decode(data, (uint256, uint256, uint256));
    }
    
    function _validateMargin(
        uint256 marketId,
        uint256 notional,
        uint256 collateral,
        uint256 leverage
    ) internal view {
        (bool success, bytes memory data) = riskEngine.staticcall(
            abi.encodeWithSignature(
                "validatePositionOpen(uint256,uint256,uint256,uint256)",
                marketId,
                notional,
                collateral,
                leverage
            )
        );
        
        if (!success) revert InsufficientMargin();
        
        bool valid = abi.decode(data, (bool));
        if (!valid) revert InsufficientMargin();
    }
    
    function _openPositionInLedger(
        address trader,
        uint256 marketId,
        int256 size,
        uint256 price,
        uint256 collateral
    ) internal {
        (bool success, ) = positionLedger.call(
            abi.encodeWithSignature(
                "openPosition(address,uint256,int256,uint256,uint256)",
                trader,
                marketId,
                size,
                price,
                collateral
            )
        );
        require(success, "Ledger open failed");
    }
    
    function _modifyPositionInLedger(
        address trader,
        uint256 marketId,
        int256 sizeDelta,
        uint256 price
    ) internal {
        (bool success, ) = positionLedger.call(
            abi.encodeWithSignature(
                "openPosition(address,uint256,int256,uint256,uint256)",
                trader,
                marketId,
                sizeDelta,
                price,
                0  // No additional collateral on close
            )
        );
        require(success, "Ledger modify failed");
    }
    
    function _modifyCollateralInLedger(
        address trader,
        uint256 marketId,
        int256 collateralDelta
    ) internal {
        (bool success, ) = positionLedger.call(
            abi.encodeWithSignature(
                "modifyCollateral(address,uint256,int256)",
                trader,
                marketId,
                collateralDelta
            )
        );
        require(success, "Ledger collateral modify failed");
    }
    
    function _getPosition(
        address trader,
        uint256 marketId
    ) internal view returns (
        int256 size,
        uint256 entryPrice,
        uint256 collateral,
        uint256 pendingFees
    ) {
        (bool success, bytes memory data) = positionLedger.staticcall(
            abi.encodeWithSignature("getPosition(address,uint256)", trader, marketId)
        );
        require(success, "Get position failed");
        
        // Decode position struct
        // Position: marketId, size, entryPrice, collateral, openTimestamp, lastFeeUpdate, settledFees, lastBorrowIndex, lastFundingIndex
        (
            ,  // marketId
            size,
            entryPrice,
            collateral,
            ,  // openTimestamp
            ,  // lastFeeUpdate
            ,  // settledFees
            ,  // lastBorrowIndex
               // lastFundingIndex
        ) = abi.decode(data, (uint256, int256, uint256, uint256, uint256, uint256, uint256, uint256, int256));
        
        // Get pending fees
        (success, data) = positionLedger.staticcall(
            abi.encodeWithSignature("getPendingFees(address,uint256)", trader, marketId)
        );
        if (success && data.length >= 32) {
            pendingFees = abi.decode(data, (uint256));
        }
    }
    
    function _getLiquidationPrice(
        int256 size,
        uint256 entryPrice,
        uint256 collateral,
        uint256 pendingFees
    ) internal view returns (uint256) {
        (bool success, bytes memory data) = riskEngine.staticcall(
            abi.encodeWithSignature(
                "calculateLiquidationPrice(int256,uint256,uint256,uint256)",
                size,
                entryPrice,
                collateral,
                pendingFees
            )
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }
    
    function _getMaxLeverage(uint256 marketId) internal view returns (uint256) {
        (bool success, bytes memory data) = riskEngine.staticcall(
            abi.encodeWithSignature("marketConfigs(uint256)", marketId)
        );
        
        if (success && data.length >= 32) {
            (uint256 maxLev, , ) = abi.decode(data, (uint256, uint256, bool));
            return maxLev;
        }
        return 5e18; // Default 5x
    }
    
    function _getCurrentBorrowRate(uint256 marketId) internal view returns (uint256) {
        (bool success, bytes memory data) = borrowFeeEngine.staticcall(
            abi.encodeWithSignature("getCurrentRate(uint256)", marketId)
        );
        
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 2e14; // Default 0.02%
    }
    
    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
}
