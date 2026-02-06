// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PriceEngineV2.sol";

/**
 * @title DeployPriceEngineV2
 * @notice Deploys new manipulation-resistant PriceEngineV2
 * 
 * Run: forge script script/DeployPriceEngineV2.s.sol --rpc-url $BSC_TESTNET_RPC --broadcast
 */
contract DeployPriceEngineV2 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy PriceEngineV2
        PriceEngineV2 priceEngine = new PriceEngineV2();
        console.log("PriceEngineV2 deployed:", address(priceEngine));
        
        // Configure example markets with expiry dates
        // Market 1: Trump Wins 2028 - expires Nov 5, 2028
        priceEngine.configureMarket(
            1,                          // marketId
            1793923200,                 // expiryTimestamp (Nov 5, 2028 00:00 UTC)
            500,                        // maxSpread (5%)
            1000,                       // maxTickMovement (10% per update)
            0,                          // minLiquidityDepth (0 for now)
            0.1e18,                     // alpha (10% base smoothing)
            3600                        // volatilityWindow (1 hour)
        );
        console.log("Market 1 configured: Trump Wins 2028");
        
        // Market 2: Trump Deportations 250-500k
        priceEngine.configureMarket(
            2,
            1798761600,                 // Jan 1, 2027
            500,
            1000,
            0,
            0.1e18,
            3600
        );
        console.log("Market 2 configured: Trump Deportations");
        
        // Market 3: GTA 6 $100+
        priceEngine.configureMarket(
            3,
            1798761600,                 // Jan 1, 2027
            500,
            1000,
            0,
            0.1e18,
            3600
        );
        console.log("Market 3 configured: GTA 6 $100+");
        
        // Market 4: US Revenue
        priceEngine.configureMarket(
            4,
            1798761600,                 // Jan 1, 2027
            500,
            1000,
            0,
            0.1e18,
            3600
        );
        console.log("Market 4 configured: US Revenue");
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("PriceEngineV2:", address(priceEngine));
        console.log("");
        console.log("Next steps:");
        console.log("1. Update keeper to use PriceEngineV2");
        console.log("2. Update RiskEngine to read from PriceEngineV2");
        console.log("3. Configure real expiry dates for all markets");
    }
}
