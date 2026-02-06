// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EmergencyClose
 * @notice One-time use contract to close positions on old ledger
 */

interface IOldLedger {
    struct Position {
        uint256 marketId;
        int256 size;
        uint256 entryPrice;
        uint256 collateral;
        uint256 openTimestamp;
        uint256 lastFundingIndex;
        uint256 lastBorrowIndex;
    }
    
    function getPosition(address trader, uint256 marketId) external view returns (Position memory);
    function positions(address trader, uint256 marketId) external view returns (
        uint256 marketId_,
        int256 size,
        uint256 entryPrice,
        uint256 collateral,
        uint256 openTimestamp,
        uint256 lastFundingIndex,
        uint256 lastBorrowIndex
    );
    
    // This is what the router would call
    function openPosition(
        address trader,
        uint256 marketId,
        int256 sizeDelta,
        uint256 price,
        uint256 collateralDelta
    ) external;
    
    function modifyCollateral(
        address trader,
        uint256 marketId,
        int256 collateralDelta,
        uint256 price
    ) external;
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract EmergencyClose {
    address public owner;
    IOldLedger public ledger;
    IERC20 public usdt;
    
    constructor(address _ledger, address _usdt) {
        owner = msg.sender;
        ledger = IOldLedger(_ledger);
        usdt = IERC20(_usdt);
    }
    
    function closePosition(address trader, uint256 marketId) external {
        require(msg.sender == owner, "Not owner");
        
        IOldLedger.Position memory pos = ledger.getPosition(trader, marketId);
        require(pos.size != 0, "No position");
        
        // Close by opening opposite position (sizeDelta = -size)
        // Use entry price as exit price (we're just clearing, not settling PnL properly)
        ledger.openPosition(
            trader,
            marketId,
            -pos.size,          // Opposite direction
            pos.entryPrice,     // Use entry price to avoid PnL
            0                   // No additional collateral
        );
    }
    
    function withdrawCollateral(address trader, uint256 marketId) external {
        require(msg.sender == owner, "Not owner");
        
        IOldLedger.Position memory pos = ledger.getPosition(trader, marketId);
        
        // Withdraw all collateral
        if (pos.collateral > 0) {
            ledger.modifyCollateral(
                trader,
                marketId,
                -int256(pos.collateral),
                pos.entryPrice
            );
        }
    }
    
    function rescueTokens(address token) external {
        require(msg.sender == owner, "Not owner");
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) {
            IERC20(token).transfer(owner, bal);
        }
    }
}
