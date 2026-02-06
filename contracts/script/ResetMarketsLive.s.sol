// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

/**
 * @title ResetMarketsLive
 * @notice Resets all markets to Top 10 LIVE Polymarket markets by volume
 * @dev Generated on 2026-02-06 with 5-min average prices from Polymarket
 *
 * Top 10 Live Markets (sorted by volume):
 *   1. Indiana Pacers NBA Finals - $30.3M - 0.15%
 *   2. Patriots Super Bowl - $15.7M - 31.8%
 *   3. Seahawks Super Bowl - $11.8M - 68.23%
 *   4. Jesus returns before GTA VI - $9.1M - 48.5%
 *   5. Celtics NBA Finals - $3.4M - 6.65%
 *   6. Thunder NBA Finals - $3.4M - 36.5%
 *   7. BTC $1M before GTA VI - $3.0M - 48.5%
 *   8. Caroline van der Plas PM - $3.0M - 0.1%
 *   9. GTA 6 $100+ - $2.9M - 0.95%
 *   10. Timberwolves NBA Finals - $2.6M - 3.63%
 */

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
    function forceSetPrice(uint256 marketId, uint256 price) external;
    function deactivateMarket(uint256 marketId) external;
    function priceStates(uint256) external view returns (uint256,uint256,uint256,uint256);
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

contract ResetMarketsLive is Script {
    address constant PRICE_ENGINE_V2 = 0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC;
    address constant LEDGER_V2 = 0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3;
    address constant RISK_ENGINE_V2 = 0x5f696d1E0011C8cde0060C721335d2dF43198383;
    
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        
        IPriceEngineV2 priceEngine = IPriceEngineV2(PRICE_ENGINE_V2);
        IPositionLedgerV2 ledger = IPositionLedgerV2(LEDGER_V2);
        IRiskEngineV2 riskEngine = IRiskEngineV2(RISK_ENGINE_V2);
        
        // ========== Market prices from Polymarket 5-min average (2026-02-06) ==========
        // Prices are in 18 decimals (1e18 = 100%)
        uint256[10] memory prices = [
            uint256(15e14),    // 1. Indiana Pacers - 0.15%
            uint256(318e15),   // 2. Patriots SB - 31.8%
            uint256(6823e14),  // 3. Seahawks SB - 68.23%
            uint256(485e15),   // 4. Jesus/GTA VI - 48.5%
            uint256(665e14),   // 5. Celtics - 6.65%
            uint256(365e15),   // 6. Thunder - 36.5%
            uint256(485e15),   // 7. BTC $1M/GTA VI - 48.5%
            uint256(1e15),     // 8. van der Plas - 0.1%
            uint256(95e14),    // 9. GTA 6 $100 - 0.95%
            uint256(363e14)    // 10. Timberwolves - 3.63%
        ];
        
        // ========== Expiry timestamps (Unix) ==========
        uint256[10] memory expiries = [
            uint256(1782864000), // 1. 2026-07-01 NBA Finals
            uint256(1770552000), // 2. 2026-02-08 Super Bowl
            uint256(1770552000), // 3. 2026-02-08 Super Bowl
            uint256(1785499200), // 4. 2026-07-31 GTA VI
            uint256(1782864000), // 5. 2026-07-01 NBA Finals
            uint256(1782864000), // 6. 2026-07-01 NBA Finals
            uint256(1785499200), // 7. 2026-07-31 GTA VI
            uint256(1798675200), // 8. 2026-12-31 Netherlands PM
            uint256(1772280000), // 9. 2026-02-28 GTA 6 price
            uint256(1782864000)  // 10. 2026-07-01 NBA Finals
        ];
        
        console.log("=== Deactivating old markets 1-12 ===");
        for (uint256 i = 1; i <= 12; i++) {
            try priceEngine.deactivateMarket(i) {
                console.log("  Deactivated market", i);
            } catch {
                console.log("  Market", i, "already deactivated or not found");
            }
        }
        
        console.log("");
        console.log("=== Configuring 10 NEW LIVE markets ===");
        console.log("(Top 10 by volume from Polymarket)");
        console.log("");
        
        for (uint256 i = 1; i <= 10; i++) {
            uint256 price = prices[i - 1];
            uint256 expiry = expiries[i - 1];
            
            console.log("Market", i);
            console.log("  Target price (5min avg):", price);
            console.log("  Expiry:", expiry);
            
            // Configure with 100% tick movement allowed (testnet flexibility)
            priceEngine.configureMarket(
                i,
                expiry,
                500,          // 5% max spread
                10000,        // 100% max tick - allow any price change
                0,            // no min liquidity for testnet
                1e17,         // 0.1 alpha (smoothing factor)
                3600          // 1 hour volatility window
            );
            console.log("  Configured in PriceEngine");
            
            // Set initial price from 5-min Polymarket average (bypass validation for initial setup)
            priceEngine.forceSetPrice(i, price);
            console.log("  Initial price set (force)");
            
            // Create in Ledger if not exists
            try ledger.createMarket(i, PRICE_ENGINE_V2, 1_000_000e18) {
                console.log("  Created in Ledger");
            } catch {
                console.log("  Ledger market exists");
            }
            
            // Configure RiskEngine
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
                console.log("  RiskEngine exists");
            }
            
            console.log("");
        }
        
        console.log("==============================================");
        console.log("  10 LIVE MARKETS DEPLOYED (by volume)");
        console.log("==============================================");
        console.log("");
        console.log("1. Indiana Pacers NBA Finals - 0.15%");
        console.log("2. Patriots Super Bowl - 31.8%");
        console.log("3. Seahawks Super Bowl - 68.23%");
        console.log("4. Jesus returns before GTA VI - 48.5%");
        console.log("5. Celtics NBA Finals - 6.65%");
        console.log("6. Thunder NBA Finals - 36.5%");
        console.log("7. BTC $1M before GTA VI - 48.5%");
        console.log("8. Caroline van der Plas PM - 0.1%");
        console.log("9. GTA 6 $100+ - 0.95%");
        console.log("10. Timberwolves NBA Finals - 3.63%");
        console.log("==============================================");
        
        vm.stopBroadcast();
    }
}
