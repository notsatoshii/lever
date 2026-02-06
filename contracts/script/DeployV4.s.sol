// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PositionLedgerV4.sol";
import "../src/RouterV6.sol";

contract DeployV4 is Script {
    function run() external {
        // BSC Testnet addresses
        address usdt = 0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58;
        address treasury = 0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc;
        address insurance = 0xB8CA10ADbE4c0666eF701e0D0aeB27cFC5b81932;
        
        // Existing contracts to link
        address vamm = 0xAb015aE92092996ad3dc95a8874183c0Fb5f9938;
        address priceEngine = 0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC;
        address riskEngine = 0x543ccaD81A2EDEd2dc785272fCba899512a161B4;
        address borrowFeeEngine = 0xc68e5b17f286624E31c468147360D36eA672BD35;
        address lpPool = 0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1;
        
        vm.startBroadcast();
        
        // 1. Deploy PositionLedgerV4
        PositionLedgerV4 ledger = new PositionLedgerV4(usdt, treasury, insurance);
        console.log("PositionLedgerV4 deployed at:", address(ledger));
        
        // 2. Deploy RouterV6
        RouterV6 router = new RouterV6(usdt);
        console.log("RouterV6 deployed at:", address(router));
        
        // 3. Configure RouterV6
        router.setContracts(
            vamm,
            priceEngine,
            address(ledger),
            riskEngine,
            borrowFeeEngine,
            lpPool
        );
        console.log("RouterV6 configured");
        
        // 4. Set fee recipients
        router.setFeeRecipients(insurance, treasury);
        console.log("Fee recipients set");
        
        // 5. Authorize router on ledger
        ledger.setEngineAuthorization(address(router), true);
        console.log("Router authorized on ledger");
        
        // 6. Enable trading
        router.setTradingEnabled(true);
        console.log("Trading enabled");
        
        // 7. Create markets (0-9)
        for (uint256 i = 0; i < 10; i++) {
            ledger.createMarket(
                priceEngine,
                1000000 * 1e18, // maxOI per side
                block.timestamp + 180 days // resolution time placeholder
            );
        }
        console.log("10 markets created");
        
        // 8. Set TVL for OI caps
        ledger.setTotalTVL(1000000 * 1e18); // 1M TVL
        console.log("TVL set");
        
        vm.stopBroadcast();
        
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("PositionLedgerV4:", address(ledger));
        console.log("RouterV6:", address(router));
    }
}
