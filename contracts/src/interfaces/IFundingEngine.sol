// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFundingEngine {
    struct FundingConfig {
        uint256 maxFundingRate;
        uint256 fundingPeriod;
        uint256 imbalanceThreshold;
        uint256 lastFundingTime;
        int256 cumulativeFunding;
    }
    
    function getCurrentFundingRate(uint256 marketId) external view returns (int256);
    function getPendingFunding(address trader, uint256 marketId) external view returns (int256);
    function getFundingConfig(uint256 marketId) external view returns (FundingConfig memory);
    function updateFunding(uint256 marketId) external;
}
