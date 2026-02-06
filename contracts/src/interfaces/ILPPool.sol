// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILPPool {
    // Deposit/Withdraw
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 shares, address receiver) external returns (uint256 assets);
    function requestWithdrawal(uint256 shares) external;
    function processWithdrawal(address receiver) external returns (uint256 assets);
    
    // Allocator functions
    function allocate(uint256 amount) external;
    function deallocate(uint256 amount) external;
    function addFees(uint256 amount) external;
    function recordLoss(uint256 amount) external;
    
    // View functions
    function totalAssets() external view returns (uint256);
    function totalAllocated() external view returns (uint256);
    function availableLiquidity() external view returns (uint256);
    function utilization() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function sharePrice() external view returns (uint256);
    function pendingFeesOf(address user) external view returns (uint256);
    
    // ERC20
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
