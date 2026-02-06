// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FundingEngine
 * @author LEVER Protocol
 * @notice Funding rate calculations and redistribution between longs and shorts
 * @dev Answers: "Which side is crowded, and how do we rebalance?"
 * 
 * Key principles:
 * - Funding is ZERO-SUM between traders (protocol takes no cut)
 * - LPs are NOT the counterparty for funding
 * - Positive imbalance (more longs) -> longs pay shorts
 * - Negative imbalance (more shorts) -> shorts pay longs
 */

import {IPositionLedger} from "./interfaces/IPositionLedger.sol";

contract FundingEngine {
    
    // ============ Structs ============
    
    struct FundingConfig {
        uint256 maxFundingRate;      // Max rate per period (18 decimals)
        uint256 fundingPeriod;       // Funding period in seconds (e.g., 8 hours)
        uint256 imbalanceThreshold;  // Imbalance threshold for max rate
        uint256 lastFundingTime;     // Last funding update
        int256 cumulativeFunding;    // Cumulative funding index (can be negative)
    }
    
    // ============ State ============
    
    address public owner;
    IPositionLedger public immutable ledger;
    
    // marketId => FundingConfig
    mapping(uint256 => FundingConfig) public fundingConfigs;
    
    // Authorized keepers
    mapping(address => bool) public authorizedKeepers;
    
    // Constants
    uint256 public constant PRECISION = 1e18;
    
    // ============ Events ============
    
    event FundingConfigSet(uint256 indexed marketId, uint256 maxRate, uint256 period, uint256 threshold);
    event FundingUpdated(uint256 indexed marketId, int256 fundingRate, int256 cumulativeFunding);
    event KeeperAuthorized(address indexed keeper, bool authorized);
    
    // ============ Errors ============
    
    error Unauthorized();
    error MarketNotConfigured();
    error FundingTooEarly();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyKeeper() {
        if (!authorizedKeepers[msg.sender]) revert Unauthorized();
        _;
    }
    
    modifier marketConfigured(uint256 marketId) {
        if (fundingConfigs[marketId].fundingPeriod == 0) revert MarketNotConfigured();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _ledger) {
        owner = msg.sender;
        ledger = IPositionLedger(_ledger);
        authorizedKeepers[msg.sender] = true;
    }
    
    // ============ Admin Functions ============
    
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
    
    function setKeeperAuthorization(address keeper, bool authorized) external onlyOwner {
        authorizedKeepers[keeper] = authorized;
        emit KeeperAuthorized(keeper, authorized);
    }
    
    function configureFunding(
        uint256 marketId,
        uint256 maxFundingRate,
        uint256 fundingPeriod,
        uint256 imbalanceThreshold
    ) external onlyOwner {
        fundingConfigs[marketId] = FundingConfig({
            maxFundingRate: maxFundingRate,
            fundingPeriod: fundingPeriod,
            imbalanceThreshold: imbalanceThreshold,
            lastFundingTime: block.timestamp,
            cumulativeFunding: 0
        });
        emit FundingConfigSet(marketId, maxFundingRate, fundingPeriod, imbalanceThreshold);
    }
    
    // ============ Keeper Functions ============
    
    /**
     * @notice Update funding for a market
     * @param marketId Market to update
     */
    function updateFunding(uint256 marketId) external onlyKeeper marketConfigured(marketId) {
        FundingConfig storage config = fundingConfigs[marketId];
        
        uint256 elapsed = block.timestamp - config.lastFundingTime;
        if (elapsed == 0) revert FundingTooEarly();
        
        // Get OI data
        IPositionLedger.Market memory market = ledger.getMarket(marketId);
        int256 imbalance = int256(market.totalLongOI) - int256(market.totalShortOI);
        uint256 totalOI = market.totalLongOI + market.totalShortOI;
        
        // Calculate funding rate
        int256 fundingRate = _calculateFundingRate(
            imbalance,
            totalOI,
            config.maxFundingRate,
            config.imbalanceThreshold,
            elapsed,
            config.fundingPeriod
        );
        
        // Update cumulative funding
        config.cumulativeFunding += fundingRate;
        config.lastFundingTime = block.timestamp;
        
        // Update ledger's funding index
        // Note: Ledger stores unsigned index, we encode sign in the rate
        uint256 newFundingIndex = fundingRate >= 0 
            ? PRECISION + uint256(fundingRate) 
            : PRECISION - uint256(-fundingRate);
        
        ledger.updateIndices(marketId, newFundingIndex, PRECISION); // Keep borrow index unchanged
        
        emit FundingUpdated(marketId, fundingRate, config.cumulativeFunding);
    }
    
    /**
     * @notice Batch update funding for multiple markets
     */
    function batchUpdateFunding(uint256[] calldata marketIds) external onlyKeeper {
        for (uint256 i = 0; i < marketIds.length; i++) {
            try this.updateFunding(marketIds[i]) {} catch {}
        }
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get current funding rate for a market (annualized)
     */
    function getCurrentFundingRate(uint256 marketId) external view returns (int256) {
        FundingConfig storage config = fundingConfigs[marketId];
        if (config.fundingPeriod == 0) return 0;
        
        IPositionLedger.Market memory market = ledger.getMarket(marketId);
        int256 imbalance = int256(market.totalLongOI) - int256(market.totalShortOI);
        uint256 totalOI = market.totalLongOI + market.totalShortOI;
        
        return _calculateFundingRate(
            imbalance,
            totalOI,
            config.maxFundingRate,
            config.imbalanceThreshold,
            config.fundingPeriod,  // Full period rate
            config.fundingPeriod
        );
    }
    
    /**
     * @notice Calculate pending funding payment for a position
     * @param trader Position owner
     * @param marketId Market ID
     * @return payment Funding payment (positive = owes, negative = receives)
     */
    function getPendingFunding(
        address trader,
        uint256 marketId
    ) external view returns (int256 payment) {
        IPositionLedger.Position memory pos = ledger.getPosition(trader, marketId);
        if (pos.size == 0) return 0;
        
        FundingConfig storage config = fundingConfigs[marketId];
        
        // Calculate funding since position opened
        // Simplified: rate * size * time_held / period
        uint256 elapsed = block.timestamp - pos.openTimestamp;
        int256 fundingOwed = (config.cumulativeFunding * pos.size) / int256(PRECISION);
        
        return fundingOwed;
    }
    
    /**
     * @notice Get funding config for a market
     */
    function getFundingConfig(uint256 marketId) external view returns (FundingConfig memory) {
        return fundingConfigs[marketId];
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Calculate funding rate based on OI imbalance
     * @dev Rate scales linearly with imbalance up to threshold, then capped
     */
    function _calculateFundingRate(
        int256 imbalance,
        uint256 totalOI,
        uint256 maxRate,
        uint256 threshold,
        uint256 elapsed,
        uint256 period
    ) internal pure returns (int256) {
        if (totalOI == 0 || threshold == 0) return 0;
        
        // Calculate imbalance ratio
        uint256 absImbalance = imbalance >= 0 ? uint256(imbalance) : uint256(-imbalance);
        
        // Rate = maxRate * (imbalance / threshold), capped at maxRate
        uint256 rate;
        if (absImbalance >= threshold) {
            rate = maxRate;
        } else {
            rate = (maxRate * absImbalance) / threshold;
        }
        
        // Pro-rate by elapsed time
        rate = (rate * elapsed) / period;
        
        // Sign: positive imbalance -> positive rate (longs pay)
        return imbalance >= 0 ? int256(rate) : -int256(rate);
    }
}
