// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PriceEngineV2.sol";

interface IPositionLedgerV2 {
    function setMarketOracle(uint256 marketId, address oracle) external;
}

interface IRiskEngineV2 {
    function setPriceEngine(address _priceEngine) external;
}

contract RedeployPriceEngine is Script {
    address constant LEDGER_V2 = 0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3;
    address constant RISK_ENGINE_V2 = 0x5f696d1E0011C8cde0060C721335d2dF43198383;
    
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        
        // Deploy new PriceEngineV2 with forceSetPrice function
        PriceEngineV2 priceEngine = new PriceEngineV2();
        console.log("New PriceEngineV2:", address(priceEngine));
        
        // Authorize deployer as keeper
        priceEngine.setKeeperAuthorization(msg.sender, true);
        console.log("Keeper authorized");
        
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
            uint256(1773792000), // 2026-03-18
            uint256(1798761600), // 2026-12-31
            uint256(1772323200), // 2026-03-01
            uint256(1772323200), // 2026-03-01
            uint256(1774915200), // 2026-03-31
            uint256(1770508800), // 2026-02-08
            uint256(1770508800), // 2026-02-08
            uint256(1770480000), // 2026-02-07
            uint256(1857254400), // 2028-11-07
            uint256(1857254400)  // 2028-11-07
        ];
        
        // Configure all 10 markets
        for (uint256 i = 1; i <= 10; i++) {
            console.log("Configuring market", i);
            
            // Configure market
            priceEngine.configureMarket(
                i,
                expiries[i - 1],
                500,      // 5% max spread
                1000,     // 10% max tick
                0,        // no min liquidity
                1e17,     // 0.1 alpha
                3600      // 1 hour volatility window
            );
            
            // Force set the correct price (bypasses validation)
            priceEngine.forceSetPrice(i, prices[i - 1]);
            console.log("  Price set:", prices[i - 1] / 1e16, "%");
        }
        
        // Update Ledger to use new PriceEngine for all markets
        IPositionLedgerV2 ledger = IPositionLedgerV2(LEDGER_V2);
        for (uint256 i = 1; i <= 10; i++) {
            try ledger.setMarketOracle(i, address(priceEngine)) {
                console.log("  Ledger market", i, "oracle updated");
            } catch {
                console.log("  Ledger market", i, "update failed (need to check)");
            }
        }
        
        // Try to update RiskEngine (may not have this function)
        try IRiskEngineV2(RISK_ENGINE_V2).setPriceEngine(address(priceEngine)) {
            console.log("RiskEngine updated");
        } catch {
            console.log("RiskEngine update not available");
        }
        
        console.log("=== Done ===");
        console.log("UPDATE frontend/src/config/contracts.ts:");
        console.log("  PRICE_ENGINE:", address(priceEngine));
        
        vm.stopBroadcast();
    }
}
