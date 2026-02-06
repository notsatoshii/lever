// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract TestStaticCall {
    address public priceEngine;
    
    constructor(address _priceEngine) {
        priceEngine = _priceEngine;
    }
    
    function testGetMarkPrice(uint256 marketId) external view returns (bool success, uint256 price, uint256 dataLen) {
        bytes memory data;
        (success, data) = priceEngine.staticcall(
            abi.encodeWithSignature("getMarkPrice(uint256)", marketId)
        );
        dataLen = data.length;
        if (success && data.length >= 32) {
            price = abi.decode(data, (uint256));
        }
    }
}
