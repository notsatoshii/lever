// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

interface IRiskEngine {
    function setRiskParams(
        uint256 marketId,
        uint256 initialMarginBps,
        uint256 maintenanceMarginBps,
        uint256 maxLeverage,
        uint256 baseBorrowRate,
        uint256 maxBorrowRate,
        uint256 optimalUtilization,
        uint256 liquidationPenaltyBps
    ) external;
    
    function riskParams(uint256 marketId) external view returns (
        uint256 initialMarginBps,
        uint256 maintenanceMarginBps,
        uint256 maxLeverage,
        uint256 baseBorrowRate
    );
}

/**
 * @title FixLeverage
 * @notice Fixes max leverage from 10x to 5x on all markets
 */
contract FixLeverage is Script {
    // Deployed RiskEngine address
    address constant RISK_ENGINE = 0x833D02521a41f175c389ec2A8c86F22E3de524DB;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console2.log("Fixing leverage on RiskEngine:", RISK_ENGINE);
        
        vm.startBroadcast(deployerPrivateKey);
        
        IRiskEngine engine = IRiskEngine(RISK_ENGINE);
        
        // Fix markets 1-12
        for (uint256 marketId = 1; marketId <= 12; marketId++) {
            try engine.riskParams(marketId) returns (
                uint256,
                uint256,
                uint256 currentMaxLeverage,
                uint256
            ) {
                if (currentMaxLeverage > 0) {
                    console2.log("Market", marketId);
                    console2.log("  Current max leverage:", currentMaxLeverage);
                    
                    if (currentMaxLeverage > 5) {
                        console2.log("  Fixing to 5x...");
                        
                        // 5x leverage means 20% initial margin
                        engine.setRiskParams(
                            marketId,
                            2000,                   // 20% initial margin = 5x max
                            1000,                   // 10% maintenance margin
                            5,                      // 5x max leverage
                            0.05e18,                // 5% base borrow rate
                            0.50e18,                // 50% max borrow rate
                            0.8e18,                 // 80% optimal utilization
                            500                     // 5% liquidation penalty
                        );
                        console2.log("  Done!");
                    }
                }
            } catch {
                // Market not configured, skip
            }
        }
        
        vm.stopBroadcast();
        
        console2.log("\nLeverage fix complete!");
    }
}
