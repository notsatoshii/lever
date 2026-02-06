// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/EmergencyClose.sol";

interface IOldLedgerAdmin {
    function setEngineAuthorization(address engine, bool authorized) external;
    function owner() external view returns (address);
}

contract EmergencyCloseScript is Script {
    // Old ledger with positions
    address constant OLD_LEDGER = 0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c;
    address constant USDT = 0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58;
    address constant TRADER = 0x7928251fE2D52CBECDCe0Fe9551aD9BF798347bc;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy EmergencyClose
        EmergencyClose emergencyClose = new EmergencyClose(OLD_LEDGER, USDT);
        console.log("EmergencyClose deployed:", address(emergencyClose));
        
        // 2. Authorize EmergencyClose on old ledger
        IOldLedgerAdmin(OLD_LEDGER).setEngineAuthorization(address(emergencyClose), true);
        console.log("EmergencyClose authorized on ledger");
        
        // 3. Close positions on markets 2 and 9
        console.log("Closing market 2...");
        try emergencyClose.closePosition(TRADER, 2) {
            console.log("  Market 2 closed");
        } catch Error(string memory reason) {
            console.log("  Market 2 failed:", reason);
        } catch {
            console.log("  Market 2 failed (no reason)");
        }
        
        console.log("Closing market 9...");
        try emergencyClose.closePosition(TRADER, 9) {
            console.log("  Market 9 closed");
        } catch Error(string memory reason) {
            console.log("  Market 9 failed:", reason);
        } catch {
            console.log("  Market 9 failed (no reason)");
        }
        
        // 4. Try to withdraw collateral
        console.log("Withdrawing collateral market 2...");
        try emergencyClose.withdrawCollateral(TRADER, 2) {
            console.log("  Collateral 2 withdrawn");
        } catch {
            console.log("  Collateral 2 withdrawal failed");
        }
        
        console.log("Withdrawing collateral market 9...");
        try emergencyClose.withdrawCollateral(TRADER, 9) {
            console.log("  Collateral 9 withdrawn");
        } catch {
            console.log("  Collateral 9 withdrawal failed");
        }
        
        // 5. Deauthorize for cleanliness
        IOldLedgerAdmin(OLD_LEDGER).setEngineAuthorization(address(emergencyClose), false);
        console.log("EmergencyClose deauthorized");
        
        vm.stopBroadcast();
        
        console.log("\n=== Done ===");
    }
}
