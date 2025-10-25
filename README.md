# KipuBankV2 

## Overview

KipuBankV2 improves over the previous version by enabling deposits and withdrawals of both ETH and ERC-20 tokens while using Chainlink price feeds for real-time USD valuation. The contract now includes:

- AccessControl for secure management roles
- A Chainlink oracle instance for ETH/USD conversion
- Support for additional ERC-20 tokens through a price feed registry
- Standardized USD accounting using USDC decimal format
- Nested mappings to track balances per user per token
- Bank value limit expressed in USD for financial security
- Security protections including SafeERC20 and ReentrancyGuard

These upgrades make the vault more scalable, secure, and suitable for handling multiple digital assets.


---

## Deployment & Interaction Instructions

### Deployment Parameters Required
When deploying, the following arguments must be provided:

| Parameter | Description |
|----------|-------------|
| `_usdc` | USDC token contract address |
| `_ethUsdFeed` | Chainlink ETH/USD price feed address |
| `_bankCapUSD` | Maximum value (in USD) allowed in the bank |

---

### User Interaction

Users can interact with the KipuBankV2 contract in the following ways:

1. **Deposit ETH**  
   - Call `depositETH()` and send ETH.  
   - The contract converts the ETH amount to USD using the Chainlink ETH/USD feed and updates the user's balance and the total bank value.

2. **Deposit ERC20 Tokens**  
   - Call `depositToken(tokenAddress, amount)` with an ERC20 token address and the amount to deposit.  
   - If the token is USDC, the value is taken directly. For other tokens, the contract uses the registered Chainlink feed to convert to USD.

3. **Withdraw Funds**  
   - Call `withdraw(tokenAddress, amount)` to withdraw ETH or ERC20 tokens.  
   - The contract verifies the user balance, deducts the amount, and sends the funds to the user.

4. **Admin Operations** (only users with `ADMIN_ROLE`)  
   - `addTokenFeed(token, feed)`: Register a Chainlink feed for a new token.  
   - `setETHFeed(newFeed)`: Update the ETH/USD feed.  
   - `rescueTokens(token, to, amount)`: Recover tokens sent accidentally.  
   - `rescueETH(to, amount)`: Recover ETH sent accidentally.

---

## Design Decisions

- **Chainlink dependency:**  
  Provides security and real pricing, but requires oracle availability and incurs oracle-based gas usage.

- **Admin-only configurations:**  
  Protects global settings but adds centralization.
- **Nested mappings instead of struct arrays:**  
  Improves performance for lookups per user & asset but makes iteration more complex.

- **Decimals normalization:**  
  Introduced for financial accuracy, but adds slight gas cost per conversion.


---



