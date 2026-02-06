// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPriceEngine {
    function getMarkPrice(uint256 marketId) external view returns (uint256);
    function getExecutionPrice(uint256 marketId, int256 sizeDelta) external view returns (uint256);
    function getPriceData(uint256 marketId) external view returns (
        uint256 oraclePrice,
        uint256 emaPrice,
        uint256 markPrice,
        uint256 lastUpdate
    );
    function isPriceStale(uint256 marketId, uint256 maxAge) external view returns (bool);
    function updatePrice(uint256 marketId, uint256 newOraclePrice) external;
}
