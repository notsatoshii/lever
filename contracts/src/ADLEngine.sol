// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ADLEngine (Auto-Deleveraging)
 * @author LEVER Protocol
 * @notice Automatically deleverages profitable positions when insurance can't cover bad debt
 * @dev ADL is the last resort when:
 *      1. A position is liquidated with negative equity (bad debt)
 *      2. Insurance fund cannot cover the bad debt
 *      3. Most profitable opposing positions are reduced to cover the loss
 * 
 * This ensures the protocol remains solvent without socializing losses to LPs.
 */

import {IPositionLedger} from "./interfaces/IPositionLedger.sol";

interface IInsuranceFund {
    function coverBadDebt(uint256 amount) external returns (uint256 covered);
    function totalFunds() external view returns (uint256);
}

interface IPriceEngine {
    function getMarkPrice(uint256 marketId) external view returns (uint256);
}

contract ADLEngine {
    
    // ============ Structs ============
    
    struct ADLCandidate {
        address trader;
        int256 size;
        int256 unrealizedPnL;
        uint256 leverage;
        uint256 adlScore;  // Higher = more likely to be ADL'd
    }
    
    struct ADLEvent {
        address liquidatedTrader;
        address adlTrader;
        uint256 marketId;
        int256 sizeReduced;
        int256 pnlTaken;
        uint256 badDebtCovered;
        uint256 timestamp;
    }
    
    // ============ State ============
    
    address public owner;
    IPositionLedger public immutable ledger;
    IInsuranceFund public insuranceFund;
    IPriceEngine public priceEngine;
    
    // ADL history
    ADLEvent[] public adlHistory;
    
    // Authorized callers (liquidation engine)
    mapping(address => bool) public authorizedCallers;
    
    // ADL thresholds
    uint256 public minProfitForADL = 0;  // Minimum profit to be ADL candidate (0 = any profit)
    
    // Constants
    uint256 public constant PRECISION = 1e18;
    uint256 public constant BASIS_POINTS = 10000;
    
    // ============ Events ============
    
    event AutoDeleveraged(
        address indexed liquidatedTrader,
        address indexed adlTrader,
        uint256 indexed marketId,
        int256 sizeReduced,
        int256 pnlTaken,
        uint256 badDebtCovered
    );
    event ADLTriggered(uint256 indexed marketId, uint256 badDebtAmount, uint256 insuranceCovered);
    
    // ============ Errors ============
    
    error Unauthorized();
    error NoADLCandidates();
    error NoBadDebt();
    error InsuranceCoveredDebt();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender] && msg.sender != owner) revert Unauthorized();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _ledger) {
        owner = msg.sender;
        ledger = IPositionLedger(_ledger);
    }
    
    // ============ Admin Functions ============
    
    function setInsuranceFund(address _insuranceFund) external onlyOwner {
        insuranceFund = IInsuranceFund(_insuranceFund);
    }
    
    function setPriceEngine(address _priceEngine) external onlyOwner {
        priceEngine = IPriceEngine(_priceEngine);
    }
    
    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
    }
    
    function setMinProfitForADL(uint256 _minProfit) external onlyOwner {
        minProfitForADL = _minProfit;
    }
    
    // ============ Core ADL Functions ============
    
    /**
     * @notice Process bad debt through insurance + ADL
     * @param marketId Market where bad debt occurred
     * @param badDebtAmount Amount of bad debt to cover
     * @param liquidatedSide true = long was liquidated, false = short was liquidated
     * @param candidates Array of traders on opposing side sorted by ADL score (desc)
     * @return coveredByInsurance Amount covered by insurance
     * @return coveredByADL Amount covered by ADL
     */
    function processBadDebt(
        uint256 marketId,
        uint256 badDebtAmount,
        bool liquidatedSide,
        address[] calldata candidates
    ) external onlyAuthorized returns (uint256 coveredByInsurance, uint256 coveredByADL) {
        if (badDebtAmount == 0) revert NoBadDebt();
        
        uint256 currentPrice = priceEngine.getMarkPrice(marketId);
        uint256 remainingDebt = badDebtAmount;
        
        // Step 1: Try insurance fund first
        if (address(insuranceFund) != address(0) && insuranceFund.totalFunds() > 0) {
            coveredByInsurance = insuranceFund.coverBadDebt(remainingDebt);
            remainingDebt -= coveredByInsurance;
        }
        
        emit ADLTriggered(marketId, badDebtAmount, coveredByInsurance);
        
        // Step 2: If insurance didn't cover everything, ADL profitable traders
        if (remainingDebt > 0 && candidates.length > 0) {
            coveredByADL = _executeADL(
                marketId,
                remainingDebt,
                liquidatedSide,
                candidates,
                currentPrice
            );
        }
        
        // Note: If there's still remaining debt after ADL, it would be socialized to LPs
        // This should be extremely rare with proper risk parameters
    }
    
    /**
     * @notice Execute ADL on profitable opposing positions
     */
    function _executeADL(
        uint256 marketId,
        uint256 debtTocover,
        bool liquidatedSide,
        address[] calldata candidates,
        uint256 currentPrice
    ) internal returns (uint256 totalCovered) {
        uint256 remainingDebt = debtTocover;
        
        for (uint256 i = 0; i < candidates.length && remainingDebt > 0; i++) {
            address trader = candidates[i];
            IPositionLedger.Position memory pos = ledger.getPosition(trader, marketId);
            
            // Skip if no position or same side as liquidated
            if (pos.size == 0) continue;
            bool isLong = pos.size > 0;
            if (isLong == liquidatedSide) continue;  // Same side, skip
            
            // Calculate unrealized PnL
            int256 pnl = ledger.getUnrealizedPnL(trader, marketId, currentPrice);
            
            // Only ADL profitable positions
            if (pnl <= int256(minProfitForADL)) continue;
            
            // Calculate how much of their profit we need
            uint256 profitAvailable = uint256(pnl);
            uint256 profitToTake = profitAvailable > remainingDebt ? remainingDebt : profitAvailable;
            
            // Calculate position size to close proportionally
            uint256 absSize = pos.size > 0 ? uint256(pos.size) : uint256(-pos.size);
            uint256 sizeToClose = (absSize * profitToTake) / profitAvailable;
            
            if (sizeToClose == 0) continue;
            
            // Execute ADL: close their position at current price
            int256 sizeDelta = pos.size > 0 ? -int256(sizeToClose) : int256(sizeToClose);
            
            // Reduce their position (this realizes their PnL at current price, minus the taken profit)
            ledger.openPosition(
                trader,
                marketId,
                sizeDelta,
                currentPrice,
                0  // No additional collateral
            );
            
            // Record ADL event
            ADLEvent memory adlEvent = ADLEvent({
                liquidatedTrader: address(0),  // Set by caller
                adlTrader: trader,
                marketId: marketId,
                sizeReduced: sizeDelta,
                pnlTaken: int256(profitToTake),
                badDebtCovered: profitToTake,
                timestamp: block.timestamp
            });
            adlHistory.push(adlEvent);
            
            emit AutoDeleveraged(
                address(0),
                trader,
                marketId,
                sizeDelta,
                int256(profitToTake),
                profitToTake
            );
            
            remainingDebt -= profitToTake;
            totalCovered += profitToTake;
        }
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Calculate ADL score for a position
     * @dev Score = PnL% * Leverage. Higher = more likely to be ADL'd
     * This prioritizes high-leverage, high-profit positions
     */
    function calculateADLScore(
        address trader,
        uint256 marketId,
        uint256 currentPrice
    ) public view returns (uint256 score) {
        IPositionLedger.Position memory pos = ledger.getPosition(trader, marketId);
        if (pos.size == 0 || pos.collateral == 0) return 0;
        
        int256 pnl = ledger.getUnrealizedPnL(trader, marketId, currentPrice);
        if (pnl <= 0) return 0;  // Only profitable positions
        
        // PnL percentage (scaled by PRECISION)
        uint256 pnlPercent = (uint256(pnl) * PRECISION) / pos.collateral;
        
        // Leverage (scaled by PRECISION)
        uint256 absSize = pos.size > 0 ? uint256(pos.size) : uint256(-pos.size);
        uint256 notional = (absSize * currentPrice) / PRECISION;
        uint256 leverage = (notional * PRECISION) / pos.collateral;
        
        // Score = PnL% * Leverage
        score = (pnlPercent * leverage) / PRECISION;
    }
    
    /**
     * @notice Get ADL candidates for a market (sorted by score)
     * @dev This is gas-intensive, meant for off-chain use
     * @param marketId Market ID
     * @param side true = get longs, false = get shorts
     * @param traders List of traders to check
     * @param maxResults Maximum results to return
     */
    function getADLCandidates(
        uint256 marketId,
        bool side,
        address[] calldata traders,
        uint256 maxResults
    ) external view returns (ADLCandidate[] memory candidates) {
        uint256 currentPrice = priceEngine.getMarkPrice(marketId);
        
        // First pass: count valid candidates
        uint256 count = 0;
        for (uint256 i = 0; i < traders.length && count < maxResults; i++) {
            IPositionLedger.Position memory pos = ledger.getPosition(traders[i], marketId);
            bool isLong = pos.size > 0;
            if (pos.size != 0 && isLong == side) {
                int256 pnl = ledger.getUnrealizedPnL(traders[i], marketId, currentPrice);
                if (pnl > int256(minProfitForADL)) {
                    count++;
                }
            }
        }
        
        // Second pass: build array
        candidates = new ADLCandidate[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < traders.length && idx < count; i++) {
            IPositionLedger.Position memory pos = ledger.getPosition(traders[i], marketId);
            bool isLong = pos.size > 0;
            if (pos.size != 0 && isLong == side) {
                int256 pnl = ledger.getUnrealizedPnL(traders[i], marketId, currentPrice);
                if (pnl > int256(minProfitForADL)) {
                    uint256 absSize = pos.size > 0 ? uint256(pos.size) : uint256(-pos.size);
                    uint256 notional = (absSize * currentPrice) / PRECISION;
                    uint256 leverage = pos.collateral > 0 ? (notional * PRECISION) / pos.collateral : 0;
                    
                    candidates[idx] = ADLCandidate({
                        trader: traders[i],
                        size: pos.size,
                        unrealizedPnL: pnl,
                        leverage: leverage,
                        adlScore: calculateADLScore(traders[i], marketId, currentPrice)
                    });
                    idx++;
                }
            }
        }
        
        // Note: Sorting should be done off-chain for gas efficiency
    }
    
    /**
     * @notice Check if ADL would be triggered for a given bad debt amount
     */
    function wouldTriggerADL(uint256 badDebtAmount) external view returns (bool) {
        if (address(insuranceFund) == address(0)) return badDebtAmount > 0;
        return badDebtAmount > insuranceFund.totalFunds();
    }
    
    /**
     * @notice Get ADL history length
     */
    function getADLHistoryLength() external view returns (uint256) {
        return adlHistory.length;
    }
    
    /**
     * @notice Get recent ADL events
     */
    function getRecentADLEvents(uint256 count) external view returns (ADLEvent[] memory events) {
        uint256 len = adlHistory.length;
        uint256 start = len > count ? len - count : 0;
        uint256 resultCount = len - start;
        
        events = new ADLEvent[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            events[i] = adlHistory[start + i];
        }
    }
}
