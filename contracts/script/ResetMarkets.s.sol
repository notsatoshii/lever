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

contract ResetMarkets is Script {
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
            uint256(1773792000), // 2026-03-18 Fed March
            uint256(1798761600), // 2026-12-31 Fed Chair
            uint256(1772323200), // 2026-03-01 BTC Feb
            uint256(1772323200), // 2026-03-01 BTC Feb dip
            uint256(1774915200), // 2026-03-31 Ceasefire
            uint256(1770508800), // 2026-02-08 NFL
            uint256(1770508800), // 2026-02-08 Trump Kamala
            uint256(1770480000), // 2026-02-07 BTC daily (tomorrow)
            uint256(1857254400), // 2028-11-07 Hillary
            uint256(1857254400)  // 2028-11-07 Abbott
        ];
        
        console.log("=== Deactivating old markets 1-12 ===");
        for (uint256 i = 1; i <= 12; i++) {
            try priceEngine.deactivateMarket(i) {
                console.log("  Deactivated market", i);
            } catch {
                console.log("  Market", i, "not found or failed");
            }
        }
        
        console.log("=== Configuring 10 new markets with 100% tick allowed ===");
        for (uint256 i = 1; i <= 10; i++) {
            uint256 price = prices[i - 1];
            uint256 expiry = expiries[i - 1];
            
            console.log("Market", i, "target price:", price);
            
            // Reconfigure with 100% tick movement allowed (10000 basis points)
            priceEngine.configureMarket(
                i,
                expiry,
                500,          // 5% max spread
                10000,        // 100% max tick - allow any price change
                0,            // no min liquidity for testnet
                1e17,         // 0.1 alpha
                3600          // 1 hour volatility window
            );
            console.log("  Configured with high tick limit");
            
            // Now set the price (should work with 100% tick limit)
            priceEngine.updatePriceSimple(i, price);
            console.log("  Price set");
            
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
        }
        
        console.log("=== All 10 markets reset with correct prices ===");
        
        vm.stopBroadcast();
    }
}
