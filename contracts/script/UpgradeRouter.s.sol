// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Router.sol";
import "../src/interfaces/IPositionLedger.sol";

interface ILedger {
    function setAuthorizedEngine(address engine, bool authorized) external;
}

interface IPool {
    function approve(address spender, uint256 amount) external returns (bool);
}

contract UpgradeRouter is Script {
    // Existing contracts
    address constant USDT = 0x0Fbe7F2C870636b1f3cFc6AD9d5767eb26A48F58;
    address constant LEDGER = 0x6738828760E8d2Eb8cD892c5a15Ad5d994d7995c;
    address constant PRICE_ENGINE = 0x74F964E2bda482Ae78834fF4F4FBC892E1b6Aa33;
    address constant RISK_ENGINE = 0x833D02521a41f175c389ec2A8c86F22E3de524DB;
    address constant LP_POOL = 0x187d9CA1A112323a966C2BB1Ed05Fe436Aadd5C1;
    address constant OLD_ROUTER = 0x34A73a10a953A69d9Ee8453BFef0d6fB12c105a7;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new Router
        Router newRouter = new Router(LEDGER, PRICE_ENGINE, RISK_ENGINE, USDT);
        console.log("New Router deployed at:", address(newRouter));
        
        // Configure LP Pool
        newRouter.setLPPool(LP_POOL);
        
        // Authorize new Router on Ledger
        ILedger(LEDGER).setAuthorizedEngine(address(newRouter), true);
        
        // Deauthorize old Router
        ILedger(LEDGER).setAuthorizedEngine(OLD_ROUTER, false);
        
        // LP Pool needs to approve new Router to pull profits
        // (LP Pool owner needs to do this separately if not deployer)
        // IPool(LP_POOL).approve(address(newRouter), type(uint256).max);
        
        vm.stopBroadcast();
        
        console.log("=== Router Upgrade Complete ===");
        console.log("New Router:", address(newRouter));
        console.log("IMPORTANT: LP Pool must approve new Router!");
    }
}
