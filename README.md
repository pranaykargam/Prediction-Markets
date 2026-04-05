# Prediction Markets 📈📉

A simple Solidity prediction market built with Foundry for the Speedrun Ethereum prediction markets challenge.

<img src = "./images/img-1.png">

This project lets a market owner create a yes/no market, seed initial ETH liquidity, let traders buy and sell outcome tokens, and let an oracle report the final result. After resolution, holders of the winning token can redeem ETH and the liquidity provider can withdraw remaining collateral plus trading revenue.

## Contracts

### `PredictionMarket.sol`

Main market contract.

Features:
- Creates one `YES` token and one `NO` token for a single question
- Accepts initial ETH liquidity during deployment
- Allows the owner to add or remove liquidity before the market is reported
- Lets users buy outcome tokens with ETH
- Lets users sell outcome tokens back before resolution
- Lets the oracle report the winning outcome
- Lets winning token holders redeem ETH after resolution
- Lets the owner resolve the market and withdraw remaining value

### `PredictionMarketToken.sol`

ERC20 token used for outcome shares.

Features:
- Minted and burned only by the market contract
- Separate token contract for `YES` and `NO`

## How It Works

1. The owner deploys a market with:
- a question
- an oracle address
- initial ETH liquidity
- an initial token value
- an initial `YES` probability
- a percentage of tokens to lock for the liquidity provider

2. The market deploys two ERC20 tokens:
- `YES`
- `NO`

3. Traders buy and sell these tokens before the result is known.

4. The contract estimates price using market activity:
- if more `YES` tokens are bought, `YES` becomes more expensive
- if more `NO` tokens are bought, `NO` becomes more expensive

5. When the event ends, the oracle reports the winner:
- `YES`
- `NO`

6. After reporting:
- users redeem winning tokens for ETH
- the owner can withdraw remaining collateral and trading revenue

## Probability and Pricing

The oracle does not calculate probability.

In this implementation, the oracle only reports the final outcome by calling `report(Outcome.YES)` or `report(Outcome.NO)`.

The pricing logic is market-based. The contract calculates an implied probability from token demand:

```solidity
probability = tokensSold / totalTokensSold
```

That probability is then used to estimate the ETH cost to buy or sell tokens.



## Project Structure
├── src
│   ├── PredictionMarket.sol
│   └── PredictionMarketToken.sol
├── script
│   └── DeployPredictionMarket.s.sol
├── test
│   └── PredictionMarket.t.sol
└── foundry.toml

## Current Test Coverage

The test suite currently covers:
- oracle-only reporting
- owner liquidity withdrawal
- resolving only after reporting
- redeeming winning tokens
- owner withdrawal on market resolution



Challenge link:
- https://speedrunethereum.com/challenge/prediction-markets
