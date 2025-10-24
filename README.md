# KipuBankV2

## Overview
This is an upgraded version of KipuBank, introducing access control, multi-token support, and Chainlink oracle integration for ETH/USD conversion.

## Improvements
- Role-based access control using OpenZeppelin's `AccessControl`
- Multi-token accounting (native ETH + ERC20)
- Chainlink price feed for USD conversion
- Decimal conversion utility
- Custom errors and events for observability
- Security patterns (checks-effects-interactions)
- Optimized gas usage with `immutable` and `constant` variables

## Deployment
1. Compile with Solidity 0.8.24
2. Deploy to Sepolia via Remix using Metamask
3. Verify contract at [Etherscan](https://sepolia.etherscan.io)


## Example Interaction
- Deposit ETH with `deposit()` (send value)
- Withdraw with `withdraw(uint amount)`
- Check balance with `getBalance(address)`
