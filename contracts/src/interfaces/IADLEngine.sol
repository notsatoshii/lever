// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IADLEngine {
    struct ADLCandidate {
        address trader;
        int256 size;
        int256 unrealizedPnL;
        uint256 leverage;
        uint256 adlScore;
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
    
    function processBadDebt(
        uint256 marketId,
        uint256 badDebtAmount,
        bool liquidatedSide,
        address[] calldata candidates
    ) external returns (uint256 coveredByInsurance, uint256 coveredByADL);
    
    function calculateADLScore(address trader, uint256 marketId, uint256 currentPrice) external view returns (uint256);
    function getADLCandidates(uint256 marketId, bool side, address[] calldata traders, uint256 maxResults) external view returns (ADLCandidate[] memory);
    function wouldTriggerADL(uint256 badDebtAmount) external view returns (bool);
}
