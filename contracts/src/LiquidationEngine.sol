// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LiquidationEngine
 * @author LEVER Protocol
 * @notice Executes liquidations and distributes penalties
 * @dev The liquidation engine ACTS but does not choose when rules change
 * 
 * Responsibilities:
 * - Execute forced position closures
 * - Transfer collateral appropriately
 * - Apply liquidation penalties
 * - Protect LP capital
 * - Reward liquidators
 */

import {IPositionLedger} from "./interfaces/IPositionLedger.sol";
import {IERC20} from "./interfaces/IERC20.sol";

interface IRiskEngine {
    function isLiquidatable(address trader, uint256 marketId, uint256 currentPrice) 
        external view returns (bool liquidatable, uint256 shortfall);
    function getLiquidationPenalty(uint256 marketId, uint256 collateral) 
        external view returns (uint256);
    function riskParams(uint256 marketId) external view returns (
        uint256 initialMarginBps,
        uint256 maintenanceMarginBps,
        uint256 maxLeverage,
        uint256 baseBorrowRate,
        uint256 maxBorrowRate,
        uint256 optimalUtilization,
        uint256 liquidationPenaltyBps
    );
}

interface IPriceEngine {
    function getMarkPrice(uint256 marketId) external view returns (uint256);
}

contract LiquidationEngine {
    
    // ============ Structs ============
    
    struct LiquidationResult {
        address trader;
        uint256 marketId;
        int256 positionSize;
        uint256 collateral;
        int256 pnl;
        uint256 penalty;
        uint256 liquidatorReward;
        uint256 protocolFee;
        uint256 lpRecovery;
    }
    
    // ============ State ============
    
    address public owner;
    IPositionLedger public immutable ledger;
    IRiskEngine public riskEngine;
    IPriceEngine public priceEngine;
    IERC20 public immutable collateralToken;
    
    // Fee distribution (basis points, total = 10000)
    uint256 public liquidatorRewardBps = 5000;  // 50% to liquidator
    uint256 public protocolFeeBps = 1000;       // 10% to protocol
    // Remaining 40% to LP pool
    
    // Protocol fee recipient
    address public protocolFeeRecipient;
    
    // LP pool address (receives recovered collateral)
    address public lpPool;
    
    // Stats
    uint256 public totalLiquidations;
    uint256 public totalPenaltiesCollected;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant PRECISION = 1e18;
    
    // ============ Events ============
    
    event Liquidation(
        address indexed trader,
        uint256 indexed marketId,
        address indexed liquidator,
        int256 positionSize,
        uint256 collateralSeized,
        uint256 penalty,
        uint256 liquidatorReward
    );
    event PartialLiquidation(
        address indexed trader,
        uint256 indexed marketId,
        int256 sizeLiquidated,
        uint256 collateralSeized
    );
    event EnginesUpdated(address riskEngine, address priceEngine);
    event FeeDistributionUpdated(uint256 liquidatorBps, uint256 protocolBps);
    
    // ============ Errors ============
    
    error Unauthorized();
    error NotLiquidatable();
    error InvalidConfiguration();
    error TransferFailed();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(
        address _ledger,
        address _collateralToken,
        address _protocolFeeRecipient,
        address _lpPool
    ) {
        owner = msg.sender;
        ledger = IPositionLedger(_ledger);
        collateralToken = IERC20(_collateralToken);
        protocolFeeRecipient = _protocolFeeRecipient;
        lpPool = _lpPool;
    }
    
    // ============ Admin Functions ============
    
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
    
    function setEngines(address _riskEngine, address _priceEngine) external onlyOwner {
        riskEngine = IRiskEngine(_riskEngine);
        priceEngine = IPriceEngine(_priceEngine);
        emit EnginesUpdated(_riskEngine, _priceEngine);
    }
    
    function setFeeDistribution(uint256 _liquidatorBps, uint256 _protocolBps) external onlyOwner {
        if (_liquidatorBps + _protocolBps > BASIS_POINTS) revert InvalidConfiguration();
        liquidatorRewardBps = _liquidatorBps;
        protocolFeeBps = _protocolBps;
        emit FeeDistributionUpdated(_liquidatorBps, _protocolBps);
    }
    
    function setProtocolFeeRecipient(address _recipient) external onlyOwner {
        protocolFeeRecipient = _recipient;
    }
    
    function setLPPool(address _lpPool) external onlyOwner {
        lpPool = _lpPool;
    }
    
    // ============ Liquidation Functions ============
    
    /**
     * @notice Liquidate an underwater position
     * @param trader Address of position owner
     * @param marketId Market ID
     * @return result Liquidation details
     */
    function liquidate(
        address trader,
        uint256 marketId
    ) external returns (LiquidationResult memory result) {
        uint256 currentPrice = priceEngine.getMarkPrice(marketId);
        
        // Check if liquidatable
        (bool liquidatable, uint256 shortfall) = riskEngine.isLiquidatable(trader, marketId, currentPrice);
        if (!liquidatable) revert NotLiquidatable();
        
        // Get position details
        IPositionLedger.Position memory pos = ledger.getPosition(trader, marketId);
        
        // Calculate PnL
        int256 pnl = ledger.getUnrealizedPnL(trader, marketId, currentPrice);
        
        // Calculate penalty
        uint256 penalty = riskEngine.getLiquidationPenalty(marketId, pos.collateral);
        
        // Calculate distributions
        uint256 liquidatorReward = (penalty * liquidatorRewardBps) / BASIS_POINTS;
        uint256 protocolFee = (penalty * protocolFeeBps) / BASIS_POINTS;
        uint256 lpRecovery = penalty - liquidatorReward - protocolFee;
        
        // Calculate remaining collateral after PnL
        int256 remainingCollateral = int256(pos.collateral) + pnl;
        
        // Execute liquidation on ledger
        ledger.liquidatePosition(trader, marketId, msg.sender, penalty);
        
        // Distribute funds (simplified - actual implementation would transfer tokens)
        // In production, this would interact with actual token transfers
        
        // Build result
        result = LiquidationResult({
            trader: trader,
            marketId: marketId,
            positionSize: pos.size,
            collateral: pos.collateral,
            pnl: pnl,
            penalty: penalty,
            liquidatorReward: liquidatorReward,
            protocolFee: protocolFee,
            lpRecovery: lpRecovery
        });
        
        // Update stats
        totalLiquidations++;
        totalPenaltiesCollected += penalty;
        
        emit Liquidation(
            trader,
            marketId,
            msg.sender,
            pos.size,
            pos.collateral,
            penalty,
            liquidatorReward
        );
    }
    
    /**
     * @notice Batch liquidate multiple positions
     * @param traders Array of trader addresses
     * @param marketIds Array of market IDs
     */
    function batchLiquidate(
        address[] calldata traders,
        uint256[] calldata marketIds
    ) external returns (uint256 liquidated) {
        require(traders.length == marketIds.length, "Length mismatch");
        
        for (uint256 i = 0; i < traders.length; i++) {
            try this.liquidate(traders[i], marketIds[i]) {
                liquidated++;
            } catch {
                // Skip failed liquidations
            }
        }
    }
    
    /**
     * @notice Partial liquidation - reduce position to safe level
     * @param trader Position owner
     * @param marketId Market ID
     * @param targetSize New position size (absolute value)
     */
    function partialLiquidate(
        address trader,
        uint256 marketId,
        uint256 targetSize
    ) external returns (uint256 collateralSeized) {
        uint256 currentPrice = priceEngine.getMarkPrice(marketId);
        
        // Check if liquidatable
        (bool liquidatable,) = riskEngine.isLiquidatable(trader, marketId, currentPrice);
        if (!liquidatable) revert NotLiquidatable();
        
        // Get position
        IPositionLedger.Position memory pos = ledger.getPosition(trader, marketId);
        uint256 currentSize = pos.size >= 0 ? uint256(pos.size) : uint256(-pos.size);
        
        require(targetSize < currentSize, "Target must be smaller");
        
        // Calculate how much to liquidate
        uint256 sizeToLiquidate = currentSize - targetSize;
        uint256 ratio = (sizeToLiquidate * PRECISION) / currentSize;
        
        // Seize proportional collateral + penalty
        collateralSeized = (pos.collateral * ratio) / PRECISION;
        uint256 penalty = riskEngine.getLiquidationPenalty(marketId, collateralSeized);
        collateralSeized += penalty;
        
        // Execute partial liquidation
        int256 sizeDelta = pos.size > 0 ? -int256(sizeToLiquidate) : int256(sizeToLiquidate);
        ledger.openPosition(trader, marketId, sizeDelta, currentPrice, 0);
        ledger.modifyCollateral(trader, marketId, -int256(collateralSeized));
        
        emit PartialLiquidation(trader, marketId, sizeDelta, collateralSeized);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Check if a position can be liquidated
     */
    function canLiquidate(address trader, uint256 marketId) external view returns (bool) {
        uint256 currentPrice = priceEngine.getMarkPrice(marketId);
        (bool liquidatable,) = riskEngine.isLiquidatable(trader, marketId, currentPrice);
        return liquidatable;
    }
    
    /**
     * @notice Preview liquidation result
     */
    function previewLiquidation(
        address trader,
        uint256 marketId
    ) external view returns (LiquidationResult memory result) {
        uint256 currentPrice = priceEngine.getMarkPrice(marketId);
        
        (bool liquidatable,) = riskEngine.isLiquidatable(trader, marketId, currentPrice);
        if (!liquidatable) revert NotLiquidatable();
        
        IPositionLedger.Position memory pos = ledger.getPosition(trader, marketId);
        int256 pnl = ledger.getUnrealizedPnL(trader, marketId, currentPrice);
        uint256 penalty = riskEngine.getLiquidationPenalty(marketId, pos.collateral);
        
        uint256 liquidatorReward = (penalty * liquidatorRewardBps) / BASIS_POINTS;
        uint256 protocolFee = (penalty * protocolFeeBps) / BASIS_POINTS;
        uint256 lpRecovery = penalty - liquidatorReward - protocolFee;
        
        result = LiquidationResult({
            trader: trader,
            marketId: marketId,
            positionSize: pos.size,
            collateral: pos.collateral,
            pnl: pnl,
            penalty: penalty,
            liquidatorReward: liquidatorReward,
            protocolFee: protocolFee,
            lpRecovery: lpRecovery
        });
    }
    
    /**
     * @notice Get all liquidatable positions for a market (off-chain helper)
     * @dev This is gas-intensive, meant for off-chain use
     */
    function getLiquidatablePositions(
        uint256 marketId,
        address[] calldata traders
    ) external view returns (address[] memory liquidatable) {
        uint256 count = 0;
        uint256 currentPrice = priceEngine.getMarkPrice(marketId);
        
        // First pass: count liquidatable
        for (uint256 i = 0; i < traders.length; i++) {
            (bool isLiq,) = riskEngine.isLiquidatable(traders[i], marketId, currentPrice);
            if (isLiq) count++;
        }
        
        // Second pass: collect addresses
        liquidatable = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < traders.length; i++) {
            (bool isLiq,) = riskEngine.isLiquidatable(traders[i], marketId, currentPrice);
            if (isLiq) {
                liquidatable[idx++] = traders[i];
            }
        }
    }
}
