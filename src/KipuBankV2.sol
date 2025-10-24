// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title KipuBankV2
/// @notice Multi-asset vault supporting ETH and ERC20 with Chainlink oracle integration.

contract KipuBankV2 is Ownable, ReentrancyGuard {
     //STATE VARIABLES

    /// @notice Mapping of user => token => balance
    mapping(address => mapping(address => uint256)) public balances;

    /// @notice Chainlink price feed for ETH/USD
    AggregatorV3Interface public ethUsdFeed;

    /// @notice Bank cap in USD (e.g. 10,000 USDC)
    uint256 public immutable bankCapUSD;

    /// @notice Total value locked in USD (approx.)
    uint256 public totalValueUSD;

    /// @notice USDC token used for accounting
    IERC20 public immutable usdc;

    // EVENTS

    event Deposited(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event FeedUpdated(address indexed newFeed);

    // ERRORS

    error InvalidAddress();
    error BankCapExceeded(uint256 attempted, uint256 cap);
    error TransferFailed();

    // CONSTRUCTOR

    constructor(
        IERC20 _usdc,
        AggregatorV3Interface _ethUsdFeed,
        uint256 _bankCapUSD
    ) {
        if (address(_usdc) == address(0) || address(_ethUsdFeed) == address(0)) revert InvalidAddress();
        usdc = _usdc;
        ethUsdFeed = _ethUsdFeed;
        bankCapUSD = _bankCapUSD;
    }

    // CORE FUNCTIONS

    /// @notice Deposit native ETH
    function depositETH() external payable nonReentrant {
        uint256 usdValue = _convertETHtoUSD(msg.value);
        uint256 newTotal = totalValueUSD + usdValue;
        if (newTotal > bankCapUSD) revert BankCapExceeded(newTotal, bankCapUSD);

        balances[msg.sender][address(0)] += msg.value;
        totalValueUSD = newTotal;
        emit Deposited(msg.sender, address(0), msg.value, usdValue);
    }

    /// @notice Deposit ERC20 tokens (e.g., USDC)
    function depositToken(IERC20 token, uint256 amount) external nonReentrant {
        token.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender][address(token)] += amount;
        emit Deposited(msg.sender, address(token), amount, amount); // 1 USDC = 1 USD approx.
    }

    /// @notice Withdraw tokens or ETH
    function withdraw(address token, uint256 amount) external nonReentrant {
        uint256 userBalance = balances[msg.sender][token];
        require(userBalance >= amount, "Insufficient balance");
        balances[msg.sender][token] -= amount;

        if (token == address(0)) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }

        emit Withdrawn(msg.sender, token, amount);
    }

    //  ADMIN FUNCTIONS

    function setFeed(address _newFeed) external onlyOwner {
        ethUsdFeed = AggregatorV3Interface(_newFeed);
        emit FeedUpdated(_newFeed);
    }

    //   INTERNAL HELPERS

    
    function _convertETHtoUSD(uint256 ethAmount) internal view returns (uint256) {
        (, int256 price,,,) = ethUsdFeed.latestRoundData();
        // price tiene 8 decimales, ETH tiene 18 → ajustar a 6 (USDC)
        return (ethAmount * uint256(price)) / 1e20;
    }

    receive() external payable {
        depositETH();
    }
}
