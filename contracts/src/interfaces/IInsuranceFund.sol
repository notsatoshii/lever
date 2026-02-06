// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IInsuranceFund {
    // Deposits
    function depositFromLiquidation(uint256 totalPenalty) external;
    function depositFromTradingFees(uint256 totalFees) external;
    function depositFromBorrowFees(uint256 totalFees) external;
    function deposit(uint256 amount) external;
    
    // Withdrawals
    function coverBadDebt(uint256 amount) external returns (uint256 covered);
    
    // Views
    function totalFunds() external view returns (uint256);
    function getHealthStatus() external view returns (uint8);
    function getRiskAdjustmentFactor() external view returns (uint256);
    function getAdjustedMaxOI(uint256 baseMaxOI) external view returns (uint256);
    function getAdjustedMaxLeverage(uint256 baseMaxLeverage) external view returns (uint256);
    function canCoverLoss(uint256 potentialLoss) external view returns (bool);
}
