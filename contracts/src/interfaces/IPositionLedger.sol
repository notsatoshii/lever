// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPositionLedger
 * @notice Interface for the Position Ledger - used by other LEVER engines
 */
interface IPositionLedger {
    
    struct Position {
        uint256 marketId;
        int256 size;
        uint256 entryPrice;
        uint256 collateral;
        uint256 openTimestamp;
        uint256 lastFundingIndex;
        uint256 lastBorrowIndex;
    }
    
    struct Market {
        address oracle;
        uint256 totalLongOI;
        uint256 totalShortOI;
        uint256 maxOI;
        uint256 fundingIndex;
        uint256 borrowIndex;
        bool active;
    }
    
    // View functions for other engines
    function getPosition(address trader, uint256 marketId) external view returns (Position memory);
    function getMarket(uint256 marketId) external view returns (Market memory);
    function getOIImbalance(uint256 marketId) external view returns (int256);
    function getUnrealizedPnL(address trader, uint256 marketId, uint256 currentPrice) external view returns (int256);
    
    // Engine functions (authorized callers only)
    function openPosition(address trader, uint256 marketId, int256 sizeDelta, uint256 price, uint256 collateralDelta) external;
    function modifyCollateral(address trader, uint256 marketId, int256 collateralDelta) external;
    function liquidatePosition(address trader, uint256 marketId, address liquidator, uint256 penalty) external;
    function updateIndices(uint256 marketId, uint256 newFundingIndex, uint256 newBorrowIndex) external;
}
