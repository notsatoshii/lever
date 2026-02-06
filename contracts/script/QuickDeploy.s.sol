// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/vAMM.sol";
import "../src/RiskEngineV2.sol";
import "../src/RouterV4.sol";

contract QuickDeploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        
        // Deploy vAMM
        vAMM amm = new vAMM(0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC);
        console.log("vAMM:", address(amm));
        
        // Deploy RiskEngineV2
        RiskEngineV2 risk = new RiskEngineV2(
            0x32Fe76322105f7990aACF5C6E2E103Aba68d0CbC,
            0xE865bD88ccf2f42D6cf9cC6deA04c702EF2585a3,
            0xc68e5b17f286624E31c468147360D36eA672BD35
        );
        console.log("RiskEngineV2:", address(risk));
        
        // Deploy RouterV4
        RouterV4 router = new RouterV4(0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58);
        console.log("RouterV4:", address(router));
        
        vm.stopBroadcast();
    }
}
