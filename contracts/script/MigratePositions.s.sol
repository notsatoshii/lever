// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PositionLedgerV4.sol";

contract MigratePositions is Script {
    function run() external {
        address ledgerV4 = 0x63477383dcA29747790b46dD5052fCA333D6A985;
        address trader = 0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc;
        
        PositionLedgerV4 ledger = PositionLedgerV4(ledgerV4);
        
        vm.startBroadcast();
        
        // Market 1: SHORT -9000, entry 0.3086, collateral 3000
        ledger.migratePosition(
            trader,
            1,
            PositionLedgerV4.Side.Short,
            9000000000000000000000,
            308644213217353990,
            3000000000000000000000
        );
        console.log("Migrated market 1");
        
        // Market 2: LONG 44000, entry 0.7034, collateral 10000
        ledger.migratePosition(
            trader,
            2,
            PositionLedgerV4.Side.Long,
            44000000000000000000000,
            703401230937071572,
            10000000000000000000000
        );
        console.log("Migrated market 2");
        
        // Market 3: SHORT -9000, entry 0.4772, collateral 3000
        ledger.migratePosition(
            trader,
            3,
            PositionLedgerV4.Side.Short,
            9000000000000000000000,
            477212744161461358,
            3000000000000000000000
        );
        console.log("Migrated market 3");
        
        // Market 5: SHORT -25000, entry 0.3492, collateral 5000
        ledger.migratePosition(
            trader,
            5,
            PositionLedgerV4.Side.Short,
            25000000000000000000000,
            349225920786692041,
            5000000000000000000000
        );
        console.log("Migrated market 5");
        
        // Market 6: LONG 9370, entry 0.4890, collateral 3335
        ledger.migratePosition(
            trader,
            6,
            PositionLedgerV4.Side.Long,
            9370000000000000000000,
            489053778561191794,
            3335000000000000000000
        );
        console.log("Migrated market 6");
        
        // Market 7: SHORT -9625, entry 0.0357, collateral 3275
        ledger.migratePosition(
            trader,
            7,
            PositionLedgerV4.Side.Short,
            9625000000000000000000,
            35758252195081419,
            3275000000000000000000
        );
        console.log("Migrated market 7");
        
        // Market 9: SHORT -8320, entry 0.0354, collateral 3000
        ledger.migratePosition(
            trader,
            9,
            PositionLedgerV4.Side.Short,
            8320000000000000000000,
            35475582077740103,
            3000000000000000000000
        );
        console.log("Migrated market 9");
        
        vm.stopBroadcast();
        
        console.log("=== MIGRATION COMPLETE ===");
        console.log("7 positions migrated to V4");
    }
}
