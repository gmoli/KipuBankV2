// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract KipuBankV2 is Ownable(msg.sender), ReentrancyGuard {

    mapping(address => mapping(address => uint256)) public balances;
    AggregatorV3Interface public ethUsdFeed;
    uint256 public immutable bankCapUSD;
    uint256 public totalValueUSD;
    IERC20 public immutable usdc;

    event Deposited(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event FeedUpdated(address indexed newFeed);

    error InvalidAddress();
    error BankCapExceeded(uint256 attempted, uint256 cap);
    error TransferFailed();

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

    function depositETH() external payable nonReentrant {
        _depositETH(msg.sender, msg.value);
    }

    function _depositETH(address user, uint256 amount) internal {
        uint256 usdValue = _convertETHtoUSD(amount);
        uint256 newTotal = totalValueUSD + usdValue;
        if (newTotal > bankCapUSD) revert BankCapExceeded(newTotal, bankCapUSD);
        balances[user][address(0)] += amount;
        totalValueUSD = newTotal;
        emit Deposited(user, address(0), amount, usdValue);
    }

    function depositToken(IERC20 token, uint256 amount) external nonReentrant {
        token.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender][address(token)] += amount;
        emit Deposited(msg.sender, address(token), amount, amount);
    }

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

    function setFeed(address _newFeed) external onlyOwner {
        ethUsdFeed = AggregatorV3Interface(_newFeed);
        emit FeedUpdated(_newFeed);
    }

    function _convertETHtoUSD(uint256 ethAmount) internal view returns (uint256) {
        (, int256 price,,,) = ethUsdFeed.latestRoundData();
        return (ethAmount * uint256(price)) / 1e20;
    }

    receive() external payable {
        _depositETH(msg.sender, msg.value);
    }
}
