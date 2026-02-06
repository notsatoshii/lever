// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract SimpleRiskEngine {
    function validatePositionOpen(
        uint256 marketId,
        uint256 notional,
        uint256 collateral,
        uint256 leverage
    ) external pure returns (bool) {
        // Always allow positions up to 5x leverage
        return leverage <= 5e18;
    }
    
    function getBorrowFee(uint256, uint256, uint256) external pure returns (uint256) {
        return 0;
    }
}
