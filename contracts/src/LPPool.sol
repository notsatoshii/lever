// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LPPool
 * @author LEVER Protocol
 * @notice Liquidity provider pool for LEVER protocol
 * @dev LPs deposit USDC, receive LP tokens, earn fees from:
 *      - Trading fees
 *      - Borrow fees
 *      - Liquidation recoveries
 *      
 * LPs are NOT the counterparty to trades (funding is zero-sum between traders).
 * LPs provide capital that backs leveraged positions.
 */

import {IERC20} from "./interfaces/IERC20.sol";

contract LPPool {
    
    // ============ State ============
    
    string public constant name = "LEVER LP Token";
    string public constant symbol = "lvUSDT";
    uint8 public constant decimals = 18;
    
    address public owner;
    IERC20 public immutable asset; // USDC
    
    // LP token state
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    // Pool accounting
    uint256 public totalAssets;           // Total USDC in pool
    uint256 public totalAllocated;        // USDC allocated to positions
    uint256 public pendingFees;           // Fees waiting to be distributed
    
    // Fee tracking
    uint256 public cumulativeFeePerShare; // Cumulative fees per LP share
    mapping(address => uint256) public userFeeCheckpoint;
    mapping(address => uint256) public unclaimedFees;
    
    // Withdrawal queue (for large withdrawals)
    struct WithdrawalRequest {
        uint256 shares;
        uint256 requestTime;
        bool processed;
    }
    mapping(address => WithdrawalRequest) public withdrawalRequests;
    uint256 public withdrawalDelay = 1 days;
    
    // Caps and limits
    uint256 public maxPoolSize = type(uint256).max;
    uint256 public minDeposit = 100e18; // 100 USDT minimum
    
    // Authorized contracts that can allocate/deallocate
    mapping(address => bool) public authorizedAllocators;
    
    // Constants
    uint256 public constant PRECISION = 1e18;
    
    // ============ Events ============
    
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event WithdrawalRequested(address indexed owner, uint256 shares);
    event FeesAccrued(uint256 amount, uint256 newCumulativeFeePerShare);
    event FeesClaimed(address indexed user, uint256 amount);
    event Allocated(uint256 amount, uint256 newTotalAllocated);
    event Deallocated(uint256 amount, uint256 newTotalAllocated);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    // ============ Errors ============
    
    error Unauthorized();
    error InsufficientBalance();
    error InsufficientAllowance();
    error BelowMinDeposit();
    error ExceedsMaxPoolSize();
    error InsufficientLiquidity();
    error WithdrawalPending();
    error WithdrawalNotReady();
    error NoWithdrawalPending();
    error ZeroAmount();
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    modifier onlyAllocator() {
        if (!authorizedAllocators[msg.sender]) revert Unauthorized();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _asset) {
        owner = msg.sender;
        asset = IERC20(_asset);
    }
    
    // ============ Admin Functions ============
    
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
    
    function setAllocatorAuthorization(address allocator, bool authorized) external onlyOwner {
        authorizedAllocators[allocator] = authorized;
    }
    
    function setMaxPoolSize(uint256 _maxPoolSize) external onlyOwner {
        maxPoolSize = _maxPoolSize;
    }
    
    function setMinDeposit(uint256 _minDeposit) external onlyOwner {
        minDeposit = _minDeposit;
    }
    
    function setWithdrawalDelay(uint256 _delay) external onlyOwner {
        withdrawalDelay = _delay;
    }
    
    // ============ Deposit Functions ============
    
    /**
     * @notice Deposit USDC and receive LP tokens
     * @param assets Amount of USDC to deposit
     * @param receiver Address to receive LP tokens
     * @return shares Amount of LP tokens minted
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        if (assets < minDeposit) revert BelowMinDeposit();
        if (totalAssets + assets > maxPoolSize) revert ExceedsMaxPoolSize();
        
        // Calculate shares
        shares = convertToShares(assets);
        if (shares == 0) revert ZeroAmount();
        
        // Update fee checkpoint before changing balance
        _updateFeeCheckpoint(receiver);
        
        // Transfer USDC from sender
        asset.transferFrom(msg.sender, address(this), assets);
        
        // Mint LP tokens
        _mint(receiver, shares);
        totalAssets += assets;
        
        emit Deposit(msg.sender, receiver, assets, shares);
    }
    
    /**
     * @notice Request withdrawal (for amounts > instant threshold)
     * @param shares Amount of LP tokens to withdraw
     */
    function requestWithdrawal(uint256 shares) external {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < shares) revert InsufficientBalance();
        if (withdrawalRequests[msg.sender].shares > 0 && !withdrawalRequests[msg.sender].processed) {
            revert WithdrawalPending();
        }
        
        withdrawalRequests[msg.sender] = WithdrawalRequest({
            shares: shares,
            requestTime: block.timestamp,
            processed: false
        });
        
        emit WithdrawalRequested(msg.sender, shares);
    }
    
    /**
     * @notice Process a pending withdrawal
     * @param receiver Address to receive USDC
     */
    function processWithdrawal(address receiver) external returns (uint256 assets) {
        WithdrawalRequest storage request = withdrawalRequests[msg.sender];
        
        if (request.shares == 0 || request.processed) revert NoWithdrawalPending();
        if (block.timestamp < request.requestTime + withdrawalDelay) revert WithdrawalNotReady();
        
        uint256 shares = request.shares;
        assets = convertToAssets(shares);
        
        // Check liquidity
        uint256 availableLiquidity = totalAssets - totalAllocated;
        if (assets > availableLiquidity) revert InsufficientLiquidity();
        
        // Update fee checkpoint
        _updateFeeCheckpoint(msg.sender);
        
        // Mark as processed
        request.processed = true;
        
        // Burn LP tokens and transfer USDC
        _burn(msg.sender, shares);
        totalAssets -= assets;
        asset.transfer(receiver, assets);
        
        emit Withdraw(msg.sender, receiver, msg.sender, assets, shares);
    }
    
    /**
     * @notice Instant withdrawal for small amounts (if liquidity available)
     * @param shares Amount of LP tokens to redeem
     * @param receiver Address to receive USDC
     */
    function withdraw(uint256 shares, address receiver) external returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < shares) revert InsufficientBalance();
        
        assets = convertToAssets(shares);
        
        // Check instant liquidity
        uint256 availableLiquidity = totalAssets - totalAllocated;
        if (assets > availableLiquidity) revert InsufficientLiquidity();
        
        // Update fee checkpoint
        _updateFeeCheckpoint(msg.sender);
        
        // Burn and transfer
        _burn(msg.sender, shares);
        totalAssets -= assets;
        asset.transfer(receiver, assets);
        
        emit Withdraw(msg.sender, receiver, msg.sender, assets, shares);
    }
    
    // ============ Allocator Functions ============
    
    /**
     * @notice Allocate capital for position backing
     * @param amount USDC amount to allocate
     */
    function allocate(uint256 amount) external onlyAllocator {
        if (amount > totalAssets - totalAllocated) revert InsufficientLiquidity();
        
        totalAllocated += amount;
        emit Allocated(amount, totalAllocated);
    }
    
    /**
     * @notice Deallocate capital when position closes
     * @param amount USDC amount to deallocate
     */
    function deallocate(uint256 amount) external onlyAllocator {
        if (amount > totalAllocated) amount = totalAllocated;
        
        totalAllocated -= amount;
        emit Deallocated(amount, totalAllocated);
    }
    
    /**
     * @notice Add fees to the pool (from trading, borrow, liquidations)
     * @param amount Fee amount in USDC
     */
    function addFees(uint256 amount) external onlyAllocator {
        if (amount == 0) return;
        
        // Transfer fees to pool
        asset.transferFrom(msg.sender, address(this), amount);
        
        // Update cumulative fee per share
        if (totalSupply > 0) {
            cumulativeFeePerShare += (amount * PRECISION) / totalSupply;
        }
        
        totalAssets += amount;
        
        emit FeesAccrued(amount, cumulativeFeePerShare);
    }
    
    /**
     * @notice Record a loss (e.g., from bad debt)
     * @param amount Loss amount in USDC
     */
    function recordLoss(uint256 amount) external onlyAllocator {
        if (amount > totalAssets) amount = totalAssets;
        totalAssets -= amount;
        // Loss is socialized across all LPs via share price decrease
    }
    
    // ============ Fee Claiming ============
    
    /**
     * @notice Claim accrued fees
     */
    function claimFees() external returns (uint256 fees) {
        _updateFeeCheckpoint(msg.sender);
        
        fees = unclaimedFees[msg.sender];
        if (fees == 0) return 0;
        
        unclaimedFees[msg.sender] = 0;
        asset.transfer(msg.sender, fees);
        
        emit FeesClaimed(msg.sender, fees);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Convert USDC amount to LP shares
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalSupply == 0) return assets;
        return (assets * totalSupply) / totalAssets;
    }
    
    /**
     * @notice Convert LP shares to USDC amount
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (totalSupply == 0) return shares;
        return (shares * totalAssets) / totalSupply;
    }
    
    /**
     * @notice Get current share price (assets per share)
     */
    function sharePrice() external view returns (uint256) {
        if (totalSupply == 0) return PRECISION;
        return (totalAssets * PRECISION) / totalSupply;
    }
    
    /**
     * @notice Get available liquidity for withdrawals/allocations
     */
    function availableLiquidity() external view returns (uint256) {
        return totalAssets - totalAllocated;
    }
    
    /**
     * @notice Get utilization rate
     */
    function utilization() external view returns (uint256) {
        if (totalAssets == 0) return 0;
        return (totalAllocated * PRECISION) / totalAssets;
    }
    
    /**
     * @notice Get pending fees for a user
     */
    function pendingFeesOf(address user) external view returns (uint256) {
        uint256 checkpoint = userFeeCheckpoint[user];
        uint256 delta = cumulativeFeePerShare - checkpoint;
        return unclaimedFees[user] + (balanceOf[user] * delta) / PRECISION;
    }
    
    /**
     * @notice Preview deposit
     */
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }
    
    /**
     * @notice Preview withdrawal
     */
    function previewWithdraw(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }
    
    // ============ ERC20 Functions ============
    
    function transfer(address to, uint256 amount) external returns (bool) {
        _updateFeeCheckpoint(msg.sender);
        _updateFeeCheckpoint(to);
        
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        
        _updateFeeCheckpoint(from);
        _updateFeeCheckpoint(to);
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    // ============ Internal Functions ============
    
    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
    
    function _updateFeeCheckpoint(address user) internal {
        uint256 checkpoint = userFeeCheckpoint[user];
        uint256 delta = cumulativeFeePerShare - checkpoint;
        
        if (delta > 0 && balanceOf[user] > 0) {
            unclaimedFees[user] += (balanceOf[user] * delta) / PRECISION;
        }
        
        userFeeCheckpoint[user] = cumulativeFeePerShare;
    }
}
