// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

interface IPriceEngineV2 {
    function configureMarket(
        uint256 marketId,
        uint256 expiryTimestamp,
        uint256 maxSpread,
        uint256 maxTickMovement,
        uint256 minLiquidityDepth,
        uint256 alpha,
        uint256 volatilityWindow
    ) external;
    function updatePriceSimple(uint256 marketId, uint256 rawPrice) external;
    function priceStates(uint256) external view returns (uint256 rawPrice, uint256 smoothedPrice, uint256 lastUpdate, uint256 volatility);
    function marketConfigs(uint256) external view returns (uint256,uint256,uint256,uint256,uint256,uint256,bool);
}

interface IPositionLedgerV2 {
    function createMarket(uint256 marketId, address oracle, uint256 maxOI) external;
}

interface IRiskEngineV2 {
    function configureMarket(
        uint256 marketId,
        uint256 maintenanceMargin,
        uint256 maxLeverage,
        uint256 maxPositionSize,
        uint256 liquidationFee,
        uint256 minCollateral
    ) external;
}

contract DeployNewMarkets is Script {
    address constant PRICE_ENGINE_V2 = 0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC;
    address constant LEDGER_V2 = 0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3;
    address constant RISK_ENGINE_V2 = 0x5f696d1E0011C8cde0060C721335d2dF43198383;
    
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        
        IPriceEngineV2 priceEngine = IPriceEngineV2(PRICE_ENGINE_V2);
        IPositionLedgerV2 ledger = IPositionLedgerV2(LEDGER_V2);
        IRiskEngineV2 riskEngine = IRiskEngineV2(RISK_ENGINE_V2);
        
        // Market prices from Polymarket (2026-02-06)
        uint256[10] memory prices = [
            uint256(865e15),   // 1. Fed No Change - 86.5%
            uint256(947e15),   // 2. Kevin Warsh - 94.7%
            uint256(145e15),   // 3. BTC $85K - 14.5%
            uint256(264e15),   // 4. BTC dip $55K - 26.4%
            uint256(75e15),    // 5. Russia ceasefire - 7.5%
            uint256(685e15),   // 6. Seahawks - 68.5%
            uint256(315e15),   // 7. Trump Kamala - 31.5%
            uint256(582e15),   // 8. BTC up/down - 58.2%
            uint256(75e14),    // 9. Hillary 2028 - 0.75%
            uint256(65e14)     // 10. Abbott 2028 - 0.65%
        ];
        
        uint256[10] memory expiries = [
            uint256(1742256000), // 2026-03-18
            uint256(1798761600), // 2026-12-31
            uint256(1740787200), // 2026-03-01
            uint256(1740787200), // 2026-03-01
            uint256(1743379200), // 2026-03-31
            uint256(1739052000), // 2026-02-08
            uint256(1739052000), // 2026-02-08
            uint256(1738882800), // 2026-02-06
            uint256(1857254400), // 2028-11-07
            uint256(1857254400)  // 2028-11-07
        ];
        
        for (uint256 i = 1; i <= 10; i++) {
            uint256 price = prices[i - 1];
            uint256 expiry = expiries[i - 1];
            
            console.log("=== Market", i, "===");
            
            // Check if market already configured
            (,,,,,, bool active) = priceEngine.marketConfigs(i);
            
            if (!active) {
                // Configure in PriceEngineV2 (7 params)
                priceEngine.configureMarket(
                    i,
                    expiry,
                    500,          // 5% max spread (in basis points)
                    1000,         // 10% max tick (in basis points) - generous for initial setup
                    0,            // no min liquidity for testnet
                    1e17,         // 0.1 alpha
                    3600          // 1 hour volatility window
                );
                console.log("  Configured PriceEngine");
            } else {
                console.log("  PriceEngine already active");
            }
            
            // Check current price state
            (uint256 rawPrice, uint256 smoothedPrice,,) = priceEngine.priceStates(i);
            console.log("  Current raw:", rawPrice);
            console.log("  Target price:", price);
            
            // Update price if needed (might need multiple updates if big change)
            if (smoothedPrice == 0) {
                // First price update
                priceEngine.updatePriceSimple(i, price);
                console.log("  Set initial price");
            } else {
                // Gradual update to avoid tick limit
                uint256 current = smoothedPrice;
                uint256 target = price;
                uint256 maxMove = current / 10; // 10% max move
                
                if (target > current + maxMove) {
                    priceEngine.updatePriceSimple(i, current + maxMove);
                    console.log("  Moved price up toward target");
                } else if (target < current && current - target > maxMove) {
                    priceEngine.updatePriceSimple(i, current - maxMove);
                    console.log("  Moved price down toward target");
                } else {
                    priceEngine.updatePriceSimple(i, target);
                    console.log("  Set target price");
                }
            }
            
            // Create in Ledger if not exists (try-catch)
            try ledger.createMarket(i, PRICE_ENGINE_V2, 1_000_000e18) {
                console.log("  Created in Ledger");
            } catch {
                console.log("  Ledger market exists");
            }
            
            // Configure RiskEngine (try-catch)
            try riskEngine.configureMarket(
                i,
                5e16,       // 5% maintenance margin
                5e18,       // 5x max leverage
                100_000e18, // max position size
                1e16,       // 1% liquidation fee
                10e18       // 10 USDT min collateral
            ) {
                console.log("  Configured RiskEngine");
            } catch {
                console.log("  RiskEngine exists/failed");
            }
        }
        
        console.log("=== Done ===");
        
        vm.stopBroadcast();
    }
}
