// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title KipuBankV2
/// @notice Multi-asset vault supporting ETH and ERC20 deposits with Chainlink oracle for USD conversion
/// @dev USDC is used as canonical USD token (6 decimals). AccessControl is used for admin operations.
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract KipuBankV2 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Admin role for managing feeds and rescue
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Native token placeholder (ETH)
    address public constant NATIVE = address(0);

    /// @notice Canonical decimals for USD accounting (USDC uses 6)
    uint8 public constant USD_DECIMALS = 6;

    /// @notice Mapping user => token => balance (token units)
    mapping(address => mapping(address => uint256)) public balances;

    /// @notice Chainlink feed per ERC20 token (token => feed)
    mapping(IERC20 => AggregatorV3Interface) public tokenFeeds;

    /// @notice Chainlink ETH/USD feed
    AggregatorV3Interface public ethUsdFeed;

    /// @notice USDC token used as reference for USD accounting (immutable)
    IERC20 public immutable usdc;

    /// @notice Bank cap expressed in USD with USD_DECIMALS
    uint256 public immutable bankCapUSD;

    /// @notice Total value stored in the bank in USD with USD_DECIMALS
    uint256 public totalValueUSD;

    /* --------------------- Events --------------------- */
    event Deposited(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event Withdrawn(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event FeedUpdated(address indexed newFeed);
    event TokenFeedAdded(address indexed token, address indexed feed);
    event RescueTokens(address indexed token, address indexed to, uint256 amount);
    event RescueETH(address indexed to, uint256 amount);

    /* --------------------- Errors --------------------- */
    error InvalidAddress();
    error InvalidFeed();
    error BankCapExceeded(uint256 attempted, uint256 cap);
    error TransferFailed();
    error InsufficientBalance(uint256 available, uint256 required);

    /// @notice Construct the vault
    /// @param _usdc Address of the USDC token (canonical USD)
    /// @param _ethUsdFeed Chainlink ETH/USD feed
    /// @param _bankCapUSD Bank cap in USD using USD_DECIMALS
   constructor(
    IERC20 _usdc,
    AggregatorV3Interface _ethUsdFeed,
    uint256 _bankCapUSD
) {
    if (address(_usdc) == address(0) || address(_ethUsdFeed) == address(0)) revert InvalidAddress();
    usdc = _usdc;
    ethUsdFeed = _ethUsdFeed;
    bankCapUSD = _bankCapUSD;

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
}

    /* --------------------- Admin / Feeds --------------------- */

    /// @notice Register a Chainlink feed for an ERC20 token (only ADMIN)
    /// @param token ERC20 token address
    /// @param feed Chainlink aggregator address for token/USD
    function addTokenFeed(IERC20 token, AggregatorV3Interface feed) external onlyRole(ADMIN_ROLE) {
        if (address(token) == address(0) || address(feed) == address(0)) revert InvalidFeed();
        tokenFeeds[token] = feed;
        emit TokenFeedAdded(address(token), address(feed));
    }

    /// @notice Update ETH/USD feed (only ADMIN)
    /// @param _newFeed New Chainlink ETH/USD feed address
    function setETHFeed(address _newFeed) external onlyRole(ADMIN_ROLE) {
        if (_newFeed == address(0)) revert InvalidFeed();
        ethUsdFeed = AggregatorV3Interface(_newFeed);
        emit FeedUpdated(_newFeed);
    }

    /// @notice Rescue ERC20 tokens accidentally sent (only ADMIN)
    /// @param token Token to rescue
    /// @param to Recipient
    /// @param amount Amount to rescue
    function rescueTokens(IERC20 token, address to, uint256 amount) external onlyRole(ADMIN_ROLE) {
        if (to == address(0)) revert InvalidAddress();
        token.safeTransfer(to, amount);
        emit RescueTokens(address(token), to, amount);
    }

    /// @notice Rescue ETH accidentally sent to contract (only ADMIN)
    /// @param to Recipient
    /// @param amount Wei amount
    function rescueETH(address to, uint256 amount) external onlyRole(ADMIN_ROLE) {
        if (to == address(0)) revert InvalidAddress();
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
        emit RescueETH(to, amount);
    }

    /* --------------------- Deposits --------------------- */

    /// @notice Deposit native ETH into the vault
    function depositETH() external payable nonReentrant {
        _depositETH(msg.sender, msg.value);
    }

    /// @dev internal ETH deposit handler
    function _depositETH(address user, uint256 amount) internal {
        uint256 usdValue = _convertETHtoUSD(amount);
        uint256 newTotal = totalValueUSD + usdValue;
        if (newTotal > bankCapUSD) revert BankCapExceeded(newTotal, bankCapUSD);

        balances[user][NATIVE] += amount;
        totalValueUSD = newTotal;

        emit Deposited(user, NATIVE, amount, usdValue);
    }

    /// @notice Deposit ERC20 token into the vault
    /// @param token Token address
    /// @param amount Amount of tokens to deposit (in token's smallest unit)
    function depositToken(IERC20 token, uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAddress();

        // pull tokens in
        token.safeTransferFrom(msg.sender, address(this), amount);

        // compute USD value (special-case USDC)
        uint256 usdValue = _convertTokenToUSD(token, amount);
        uint256 newTotal = totalValueUSD + usdValue;
        if (newTotal > bankCapUSD) revert BankCapExceeded(newTotal, bankCapUSD);

        balances[msg.sender][address(token)] += amount;
        totalValueUSD = newTotal;

        emit Deposited(msg.sender, address(token), amount, usdValue);
    }

    /* --------------------- Withdrawals --------------------- */

    /// @notice Withdraw ETH or ERC20 token from the vault
    /// @param token Token address (NATIVE / address(0) for ETH)
    /// @param amount Amount to withdraw (in token smallest unit)
    function withdraw(address token, uint256 amount) external nonReentrant {
        uint256 userBalance = balances[msg.sender][token];
        if (userBalance < amount) revert InsufficientBalance(userBalance, amount);

        // EFFECTS
        balances[msg.sender][token] = userBalance - amount;

        uint256 usdValue = _convertTokenToUSD(IERC20(token), amount);
        if (totalValueUSD >= usdValue) {
            totalValueUSD -= usdValue;
        } else {
            // in case of rounding/edge cases, avoid underflow
            totalValueUSD = 0;
        }

        // INTERACTIONS
        if (token == NATIVE) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit Withdrawn(msg.sender, token, amount, usdValue);
    }

    /* --------------------- Conversion Helpers --------------------- */

    /// @notice Convert ETH (wei) to USD using Chainlink feed, result in USD_DECIMALS
    /// @param ethAmount Amount in wei
    /// @return usdValue Value in USD with USD_DECIMALS
    function _convertETHtoUSD(uint256 ethAmount) internal view returns (uint256) {
        (, int256 price, , , ) = ethUsdFeed.latestRoundData(); // price with feed decimals (usually 8)
        uint8 feedDecimals = ethUsdFeed.decimals();

        // exponent = 18 (wei) + feedDecimals - USD_DECIMALS
        uint256 denomExp = uint256(18 + feedDecimals - USD_DECIMALS);
        return (ethAmount * uint256(price)) / (10 ** denomExp);
    }

    /// @notice Convert ERC20 token amount to USD (USD_DECIMALS)
    /// @dev - If token == usdc, returns amount (USDC assumed to have USD_DECIMALS)
    ///      - Requires token feed for non-USDC tokens
    /// @param token Token address (can be NATIVE)
    /// @param amount Amount in token smallest units
    /// @return usdValue Value in USD with USD_DECIMALS
    function _convertTokenToUSD(IERC20 token, uint256 amount) internal view returns (uint256) {
        // ETH path
        if (address(token) == NATIVE) return _convertETHtoUSD(amount);

        // USDC path: token is canonical USD
        if (address(token) == address(usdc)) {
            // assume usdc.decimals() == USD_DECIMALS; return amount directly
            return amount;
        }

        // Non-USDC tokens must have a registered feed
        AggregatorV3Interface feed = tokenFeeds[token];
        if (address(feed) == address(0)) revert InvalidFeed();

        (, int256 price, , , ) = feed.latestRoundData();
        uint8 feedDecimals = feed.decimals();
        uint8 tokenDecimals = IERC20Metadata(address(token)).decimals();

        // exponent = tokenDecimals + feedDecimals - USD_DECIMALS
        uint256 denomExp = uint256(tokenDecimals + feedDecimals - USD_DECIMALS);
        return (amount * uint256(price)) / (10 ** denomExp);
    }

    /* --------------------- View Helpers --------------------- */

    /// @notice Compute USD balance for a given user across an array of tokens (tokens must be provided)
    /// @dev Because mappings can't be iterated on-chain, caller must pass the token list to sum.
    /// @param user User address
    /// @param tokens Array of token addresses to include (use address(0) for ETH)
    /// @return totalUsd Total USD value (USD_DECIMALS)
    function balanceUSD(address user, IERC20[] calldata tokens) external view returns (uint256 totalUsd) {
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; ++i) {
            IERC20 t = tokens[i];
            uint256 bal = balances[user][address(t)];
            if (bal == 0) continue;
            uint256 usd = _convertTokenToUSD(t, bal);
            totalUsd += usd;
        }
    }

    /* --------------------- Receive --------------------- */

    receive() external payable {
        _depositETH(msg.sender, msg.value);
    }
}
