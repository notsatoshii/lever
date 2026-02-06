// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC20.sol";

/**
 * @title RouterV6
 * @author LEVER Protocol
 * @notice Main entry point with Position ID model
 * @dev Changes from V5:
 *      - Uses PositionLedgerV4 with Position IDs
 *      - openPosition returns positionId
 *      - closePosition takes positionId (not marketId)
 *      - Supports multiple positions per market (long + short)
 */

interface ILPPool {
    function allocate(uint256 amount) external;
    function deallocate(uint256 amount) external;
    function addFees(uint256 amount) external;
}

interface IPositionLedgerV4 {
    enum Side { Long, Short }
    
    struct Position {
        uint256 id;
        address owner;
        uint256 marketId;
        Side side;
        uint256 size;
        uint256 entryPrice;
        uint256 collateral;
        uint256 openTimestamp;
        bool isOpen;
        uint256 lastFeeUpdate;
        uint256 settledFees;
        uint256 lastBorrowIndex;
        int256 lastFundingIndex;
    }
    
    function openPosition(address trader, uint256 marketId, Side side, uint256 size, uint256 price, uint256 collateral) external returns (uint256 positionId);
    function increasePosition(uint256 positionId, uint256 sizeDelta, uint256 price, uint256 collateralDelta) external;
    function decreasePosition(uint256 positionId, uint256 sizeDelta, uint256 price) external returns (int256 realizedPnL);
    function closePosition(uint256 positionId, uint256 price) external returns (int256 realizedPnL);
    function modifyCollateral(uint256 positionId, int256 collateralDelta) external;
    function liquidatePosition(uint256 positionId, address liquidator, uint256 penalty) external;
    function getPosition(uint256 positionId) external view returns (Position memory);
    function getUserOpenPositions(address user) external view returns (Position[] memory);
    function getUserMarketPositionIds(address user, uint256 marketId) external view returns (uint256[] memory);
    function getPendingFees(uint256 positionId) external view returns (uint256);
    function getUnrealizedPnL(uint256 positionId, uint256 currentPrice) external view returns (int256);
    function getEquity(uint256 positionId, uint256 currentPrice) external view returns (int256);
}

contract RouterV6 {
    
    // ============ Constants ============
    
    uint256 public constant SCALE = 1e18;
    uint256 public constant MAX_SLIPPAGE = 5e16;  // 5% max slippage
    
    // ============ State ============
    
    address public owner;
    address public collateralToken;
    
    // Contract addresses
    address public vAMM;
    address public priceEngine;
    address public positionLedger;      // PositionLedgerV4
    address public riskEngine;
    address public borrowFeeEngine;
    address public lpPool;
    address public insuranceFund;
    address public protocolTreasury;
    
    // Fee splits (basis points)
    uint256 public constant FEE_LP_BPS = 5000;       // 50%
    uint256 public constant FEE_PROTOCOL_BPS = 3000; // 30%
    uint256 public constant FEE_INSURANCE_BPS = 2000; // 20%
    
    bool public tradingEnabled;
    
    // ============ Events ============
    
    event PositionOpened(
        uint256 indexed positionId,
        address indexed trader,
        uint256 indexed marketId,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 entryPrice,
        uint256 markPrice
    );
    
    event PositionIncreased(
        uint256 indexed positionId,
        uint256 sizeDelta,
        uint256 collateralDelta,
        uint256 newAvgEntry
    );
    
    event PositionDecreased(
        uint256 indexed positionId,
        uint256 sizeDelta,
        uint256 exitPrice,
        int256 realizedPnL
    );
    
    event PositionClosed(
        uint256 indexed positionId,
        address indexed trader,
        uint256 indexed marketId,
        uint256 exitPrice,
        int256 pnl,
        uint256 feesCollected
    );
    
    event CollateralModified(
        uint256 indexed positionId,
        int256 collateralDelta,
        uint256 newCollateral
    );
    
    event FeesRouted(uint256 amount, address indexed recipient);
    event LPAllocated(uint256 amount);
    event LPDeallocated(uint256 amount);
    
    // ============ Errors ============
    
    error Unauthorized();
    error ZeroAddress();
    error TradingDisabled();
    error InvalidSize();
    error InvalidCollateral();
    error SlippageExceeded();
    error InsufficientMargin();
    error PositionNotFound();
    error NotPositionOwner();
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
    }
    
    function setFeeRecipients(address _insuranceFund, address _protocolTreasury) external onlyOwner {
        insuranceFund = _insuranceFund;
        protocolTreasury = _protocolTreasury;
    }
    
    function setTradingEnabled(bool enabled) external onlyOwner {
        tradingEnabled = enabled;
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
    
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }
    
    // ============ Trading Functions ============
    
    /**
     * @notice Open a NEW position (always creates new position ID)
     * @param marketId Market to trade
     * @param isLong True for long (YES), false for short (NO)
     * @param collateralAmount Collateral to deposit
     * @param leverage Desired leverage (e.g., 5e18 = 5x)
     * @param maxSlippage Max acceptable slippage
     * @return positionId The new position's unique ID
     * @return positionSize The notional size
     * @return entryPrice The execution price
     */
    function openPosition(
        uint256 marketId,
        bool isLong,
        uint256 collateralAmount,
        uint256 leverage,
        uint256 maxSlippage
    ) external whenTradingEnabled returns (uint256 positionId, uint256 positionSize, uint256 entryPrice) {
        if (collateralAmount == 0) revert InvalidCollateral();
        if (maxSlippage > MAX_SLIPPAGE) maxSlippage = MAX_SLIPPAGE;
        
        // Transfer collateral
        _transferIn(msg.sender, collateralAmount);
        
        // Calculate position size
        positionSize = collateralAmount * leverage / SCALE;
        
        // Get Mark Price for risk checks
        uint256 markPrice = _getMarkPrice(marketId);
        
        // Validate margin
        _validateMargin(marketId, positionSize, collateralAmount, leverage);
        
        // Get Entry Price from vAMM
        entryPrice = _getEntryPrice(marketId, isLong, positionSize, markPrice, maxSlippage);
        
        // Open position in ledger (returns position ID)
        IPositionLedgerV4.Side side = isLong ? IPositionLedgerV4.Side.Long : IPositionLedgerV4.Side.Short;
        positionId = IPositionLedgerV4(positionLedger).openPosition(
            msg.sender,
            marketId,
            side,
            positionSize,
            entryPrice,
            collateralAmount
        );
        
        // LP allocation
        _allocateToLP(positionSize);
        
        emit PositionOpened(
            positionId,
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
     * @notice Increase an existing position
     * @param positionId The position to increase
     * @param additionalCollateral Extra collateral to add
     * @param additionalLeverage Leverage for the new portion
     * @param maxSlippage Max slippage for new entry
     */
    function increasePosition(
        uint256 positionId,
        uint256 additionalCollateral,
        uint256 additionalLeverage,
        uint256 maxSlippage
    ) external whenTradingEnabled {
        IPositionLedgerV4.Position memory pos = IPositionLedgerV4(positionLedger).getPosition(positionId);
        if (pos.owner != msg.sender) revert NotPositionOwner();
        if (!pos.isOpen) revert PositionNotFound();
        
        // Transfer collateral
        _transferIn(msg.sender, additionalCollateral);
        
        // Calculate additional size
        uint256 sizeDelta = additionalCollateral * additionalLeverage / SCALE;
        
        // Get entry price for new portion
        bool isLong = pos.side == IPositionLedgerV4.Side.Long;
        uint256 markPrice = _getMarkPrice(pos.marketId);
        uint256 price = _getEntryPrice(pos.marketId, isLong, sizeDelta, markPrice, maxSlippage);
        
        // Increase in ledger
        IPositionLedgerV4(positionLedger).increasePosition(positionId, sizeDelta, price, additionalCollateral);
        
        // LP allocation
        _allocateToLP(sizeDelta);
        
        emit PositionIncreased(positionId, sizeDelta, additionalCollateral, price);
    }
    
    /**
     * @notice Partially close a position
     * @param positionId The position to decrease
     * @param closePercent Percentage to close (1e18 = 100%)
     * @param minAmountOut Minimum to receive
     */
    function decreasePosition(
        uint256 positionId,
        uint256 closePercent,
        uint256 minAmountOut
    ) external returns (int256 pnl, uint256 amountOut) {
        IPositionLedgerV4.Position memory pos = IPositionLedgerV4(positionLedger).getPosition(positionId);
        if (pos.owner != msg.sender) revert NotPositionOwner();
        if (!pos.isOpen) revert PositionNotFound();
        
        uint256 closeSize = pos.size * closePercent / SCALE;
        if (closeSize == 0) revert InvalidSize();
        
        // Get exit price
        bool isBuy = pos.side == IPositionLedgerV4.Side.Short; // Shorts buy to close
        uint256 exitPrice = _getExitPrice(pos.marketId, isBuy, closeSize);
        
        // Get pending fees (proportional)
        uint256 pendingFees = IPositionLedgerV4(positionLedger).getPendingFees(positionId);
        uint256 feesToCollect = pendingFees * closePercent / SCALE;
        
        // Close in ledger
        pnl = IPositionLedgerV4(positionLedger).decreasePosition(positionId, closeSize, exitPrice);
        
        // Calculate amount out
        uint256 collateralToReturn = pos.collateral * closePercent / SCALE;
        if (pnl >= 0) {
            amountOut = collateralToReturn + uint256(pnl) - feesToCollect;
        } else {
            uint256 loss = uint256(-pnl);
            amountOut = (loss + feesToCollect >= collateralToReturn) ? 0 : collateralToReturn - loss - feesToCollect;
        }
        
        if (amountOut < minAmountOut) revert SlippageExceeded();
        
        // LP deallocation
        _deallocateFromLP(closeSize);
        
        // Route fees
        if (feesToCollect > 0) {
            _routeFeesToLP(feesToCollect);
        }
        
        // Transfer out
        if (amountOut > 0) {
            _transferOut(msg.sender, amountOut);
        }
        
        emit PositionDecreased(positionId, closeSize, exitPrice, pnl);
    }
    
    /**
     * @notice Close a position entirely
     * @param positionId The position to close
     * @param minAmountOut Minimum to receive
     */
    function closePosition(
        uint256 positionId,
        uint256 minAmountOut
    ) external returns (int256 pnl, uint256 amountOut) {
        IPositionLedgerV4.Position memory pos = IPositionLedgerV4(positionLedger).getPosition(positionId);
        if (pos.owner != msg.sender) revert NotPositionOwner();
        if (!pos.isOpen) revert PositionNotFound();
        
        // Get exit price
        bool isBuy = pos.side == IPositionLedgerV4.Side.Short;
        uint256 exitPrice = _getExitPrice(pos.marketId, isBuy, pos.size);
        
        // Get pending fees
        uint256 feesToCollect = IPositionLedgerV4(positionLedger).getPendingFees(positionId);
        
        // Close in ledger
        pnl = IPositionLedgerV4(positionLedger).closePosition(positionId, exitPrice);
        
        // Calculate amount out
        if (pnl >= 0) {
            amountOut = pos.collateral + uint256(pnl) - feesToCollect;
        } else {
            uint256 loss = uint256(-pnl);
            amountOut = (loss + feesToCollect >= pos.collateral) ? 0 : pos.collateral - loss - feesToCollect;
        }
        
        if (amountOut < minAmountOut) revert SlippageExceeded();
        
        // LP deallocation
        _deallocateFromLP(pos.size);
        
        // Route fees
        if (feesToCollect > 0) {
            _routeFeesToLP(feesToCollect);
        }
        
        // Transfer out
        if (amountOut > 0) {
            _transferOut(msg.sender, amountOut);
        }
        
        emit PositionClosed(positionId, msg.sender, pos.marketId, exitPrice, pnl, feesToCollect);
    }
    
    /**
     * @notice Add collateral to a position
     */
    function addCollateral(uint256 positionId, uint256 amount) external {
        if (amount == 0) revert InvalidCollateral();
        
        IPositionLedgerV4.Position memory pos = IPositionLedgerV4(positionLedger).getPosition(positionId);
        if (pos.owner != msg.sender) revert NotPositionOwner();
        if (!pos.isOpen) revert PositionNotFound();
        
        _transferIn(msg.sender, amount);
        IPositionLedgerV4(positionLedger).modifyCollateral(positionId, int256(amount));
        
        emit CollateralModified(positionId, int256(amount), pos.collateral + amount);
    }
    
    /**
     * @notice Remove collateral from a position
     */
    function removeCollateral(uint256 positionId, uint256 amount) external {
        if (amount == 0) revert InvalidCollateral();
        
        IPositionLedgerV4.Position memory pos = IPositionLedgerV4(positionLedger).getPosition(positionId);
        if (pos.owner != msg.sender) revert NotPositionOwner();
        if (!pos.isOpen) revert PositionNotFound();
        
        // Check margin requirements
        uint256 newCollateral = pos.collateral - amount;
        uint256 markPrice = _getMarkPrice(pos.marketId);
        uint256 notional = pos.size * markPrice / SCALE;
        uint256 pendingFees = IPositionLedgerV4(positionLedger).getPendingFees(positionId);
        uint256 effectiveLeverage = notional * SCALE / (newCollateral - pendingFees);
        
        uint256 maxLeverage = _getMaxLeverage(pos.marketId);
        if (effectiveLeverage > maxLeverage) revert InsufficientMargin();
        
        IPositionLedgerV4(positionLedger).modifyCollateral(positionId, -int256(amount));
        _transferOut(msg.sender, amount);
        
        emit CollateralModified(positionId, -int256(amount), newCollateral);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get all open positions for a user
     */
    function getUserOpenPositions(address user) external view returns (IPositionLedgerV4.Position[] memory) {
        return IPositionLedgerV4(positionLedger).getUserOpenPositions(user);
    }
    
    /**
     * @notice Get position IDs for a user in a specific market
     */
    function getUserMarketPositionIds(address user, uint256 marketId) external view returns (uint256[] memory) {
        return IPositionLedgerV4(positionLedger).getUserMarketPositionIds(user, marketId);
    }
    
    /**
     * @notice Get detailed position info
     */
    function getPositionDetails(uint256 positionId) external view returns (
        IPositionLedgerV4.Position memory position,
        uint256 markPrice,
        int256 unrealizedPnL,
        uint256 pendingFees,
        int256 equity,
        uint256 liquidationPrice
    ) {
        position = IPositionLedgerV4(positionLedger).getPosition(positionId);
        if (!position.isOpen) return (position, 0, 0, 0, 0, 0);
        
        markPrice = _getMarkPrice(position.marketId);
        unrealizedPnL = IPositionLedgerV4(positionLedger).getUnrealizedPnL(positionId, markPrice);
        pendingFees = IPositionLedgerV4(positionLedger).getPendingFees(positionId);
        equity = IPositionLedgerV4(positionLedger).getEquity(positionId, markPrice);
        liquidationPrice = _getLiquidationPrice(position, pendingFees);
    }
    
    /**
     * @notice Preview opening a new position
     */
    function previewOpenPosition(
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
        (expectedEntryPrice, priceImpact) = _previewEntryPrice(marketId, isLong, positionSize);
        
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
    
    function _allocateToLP(uint256 amount) internal {
        if (lpPool == address(0)) return;
        try ILPPool(lpPool).allocate(amount) {} catch {}
    }
    
    function _deallocateFromLP(uint256 amount) internal {
        if (lpPool == address(0)) return;
        try ILPPool(lpPool).deallocate(amount) {} catch {}
    }
    
    function _routeFeesToLP(uint256 amount) internal {
        if (amount == 0) return;
        
        uint256 lpAmount = (amount * FEE_LP_BPS) / 10000;
        uint256 protocolAmount = (amount * FEE_PROTOCOL_BPS) / 10000;
        uint256 insuranceAmount = amount - lpAmount - protocolAmount;
        
        if (lpPool != address(0) && lpAmount > 0) {
            IERC20(collateralToken).transfer(lpPool, lpAmount);
            try ILPPool(lpPool).addFees(lpAmount) {} catch {}
        }
        
        if (protocolTreasury != address(0) && protocolAmount > 0) {
            IERC20(collateralToken).transfer(protocolTreasury, protocolAmount);
        }
        
        if (insuranceFund != address(0) && insuranceAmount > 0) {
            IERC20(collateralToken).transfer(insuranceFund, insuranceAmount);
        }
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
        (bool success, bytes memory data) = vAMM.call(
            abi.encodeWithSignature("swap(uint256,address,bool,uint256,uint256)", marketId, msg.sender, isBuy, amount, 0)
        );
        require(success, "vAMM swap failed");
        (, entryPrice) = abi.decode(data, (uint256, uint256));
        
        uint256 slippage;
        if (isBuy) {
            slippage = entryPrice > markPrice ? (entryPrice - markPrice) * SCALE / markPrice : 0;
        } else {
            slippage = markPrice > entryPrice ? (markPrice - entryPrice) * SCALE / markPrice : 0;
        }
        if (slippage > maxSlippage) revert SlippageExceeded();
    }
    
    function _getExitPrice(uint256 marketId, bool isBuy, uint256 amount) internal returns (uint256 exitPrice) {
        (bool success, bytes memory data) = vAMM.call(
            abi.encodeWithSignature("swap(uint256,address,bool,uint256,uint256)", marketId, msg.sender, isBuy, amount, 0)
        );
        require(success, "vAMM swap failed");
        (, exitPrice) = abi.decode(data, (uint256, uint256));
    }
    
    function _previewEntryPrice(uint256 marketId, bool isBuy, uint256 amount) internal view returns (uint256 entryPrice, uint256 priceImpact) {
        (bool success, bytes memory data) = vAMM.staticcall(
            abi.encodeWithSignature("getExecutionPrice(uint256,bool,uint256)", marketId, isBuy, amount)
        );
        require(success, "Preview failed");
        (, entryPrice, priceImpact) = abi.decode(data, (uint256, uint256, uint256));
    }
    
    function _validateMargin(uint256 marketId, uint256 notional, uint256 collateral, uint256 leverage) internal view {
        (bool success, bytes memory data) = riskEngine.staticcall(
            abi.encodeWithSignature("validatePositionOpen(uint256,uint256,uint256,uint256)", marketId, notional, collateral, leverage)
        );
        if (!success) revert InsufficientMargin();
        bool valid = abi.decode(data, (bool));
        if (!valid) revert InsufficientMargin();
    }
    
    function _getLiquidationPrice(IPositionLedgerV4.Position memory pos, uint256 pendingFees) internal view returns (uint256) {
        int256 size = pos.side == IPositionLedgerV4.Side.Long ? int256(pos.size) : -int256(pos.size);
        (bool success, bytes memory data) = riskEngine.staticcall(
            abi.encodeWithSignature("calculateLiquidationPrice(int256,uint256,uint256,uint256)", size, pos.entryPrice, pos.collateral, pendingFees)
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
        return 5e18;
    }
    
    function _getCurrentBorrowRate(uint256 marketId) internal view returns (uint256) {
        (bool success, bytes memory data) = borrowFeeEngine.staticcall(
            abi.encodeWithSignature("getCurrentRate(uint256)", marketId)
        );
        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }
        return 2e14;
    }
}
