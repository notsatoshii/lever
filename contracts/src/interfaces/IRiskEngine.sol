// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRiskEngine {
    struct RiskParams {
        uint256 initialMarginBps;
        uint256 maintenanceMarginBps;
        uint256 maxLeverage;
        uint256 baseBorrowRate;
        uint256 maxBorrowRate;
        uint256 optimalUtilization;
        uint256 liquidationPenaltyBps;
    }
    
    struct UtilizationData {
        uint256 totalOI;
        uint256 totalLPCapital;
        uint256 utilization;
        uint256 currentBorrowRate;
    }
    
    function checkInitialMargin(uint256 marketId, uint256 size, uint256 collateral, uint256 price) external view returns (bool);
    function isLiquidatable(address trader, uint256 marketId, uint256 currentPrice) external view returns (bool liquidatable, uint256 shortfall);
    function getUtilization(uint256 marketId) external view returns (UtilizationData memory);
    function getRequiredCollateral(uint256 marketId, uint256 size, uint256 price) external view returns (uint256 initial, uint256 maintenance);
    function getPendingBorrowFee(address trader, uint256 marketId) external view returns (uint256);
    function getLiquidationPenalty(uint256 marketId, uint256 collateral) external view returns (uint256);
    function getMaxPositionSize(uint256 marketId, uint256 collateral, uint256 price) external view returns (uint256);
    function accrueInterest(uint256 marketId) external;
}
