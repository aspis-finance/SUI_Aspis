# SUI Aspis Treasury

A Sui Move implementation of a decentralized treasury system with proportional voting power through LP tokens. The system enables fair governance and automated fund management based on token holder voting.

## Core Concepts

### Treasury Management

The treasury acts as a pool for SUI tokens, where:

- Users can deposit SUI and receive LP tokens
- # of issued lp_tokens = (deposit_amount \* total_lp_supply) / current_balance
- Withdrawals can be made either through:
  - Direct withdrawal (burning LP tokens)
  - Community-voted proposals

### LP Token Economics

LP tokens represent a user's share in the treasury. The number of LP tokens minted is calculated using:

## Features

- **Treasury Management**: Create and manage a treasury that holds SUI tokens
- **LP Tokens**: Users receive LP tokens proportional to their deposits
- **Voting System**: LP token holders can vote on withdrawal proposals
- **Threshold-based Voting**: Proposals require a percentage of total LP tokens to vote (e.g., 40%)
- **Withdrawal Mechanism**:
  - Via proposals: Users can create and vote on withdrawal proposals
  - Direct withdrawal: LP token holders can withdraw their share of the treasury

## Project Structure

```
.
├── Move.toml          # Project configuration
└── sources/           # Source files
    └── hello.move     # Sample module
```

## Prerequisites

- Move CLI tool installed
- Sui CLI (if you're planning to deploy on Sui)

## Getting Started

1. Update the `my_addr` in `Move.toml` with your address
2. Build the project:
   ```bash
   move build
   ```
3. Run tests (when added):
   ```bash
   move test
   ```

## Module Description

The `hello` module provides a simple function `say_hello` that prints a greeting message.

## 🚧 Work In Progress (WIP)

### DEX Integration

1. **Automated Liquidity Management**

   - Integration with major Sui DEXes
   - Automatic LP position management
   - Yield farming strategy execution
   - Formula for optimal liquidity distribution:
     ```
     optimal_liquidity = f(volume_24h, volatility, current_fees)
     ```

2. **Fee Structure**
   - Protocol fee: 0.1% of managed assets
   - Performance fee: 10% of yield
   - Distribution formula:
     ```
     treasury_fee = (managed_assets * protocol_fee) + (yield * performance_fee)
     lp_holder_share = yield - treasury_fee
     ```

### Advanced Proposal Types

1. **Investment Proposals**

   - DEX liquidity provision
   - Yield farming participation
   - Token swaps

   ```move
   struct InvestmentProposal {
       strategy_type: StrategyType,
       target_protocol: address,
       amount: u64,
       expected_return: u64,
       risk_level: u8,
   }
   ```

2. **Parameter Update Proposals**

   - Fee adjustments
   - Voting threshold changes
   - Treasury policy updates

   ```move
   struct ParameterProposal {
       parameter_type: ParameterType,
       current_value: u64,
       proposed_value: u64,
       implementation_delay: u64,
   }
   ```

3. **Strategy Proposals**
   - Investment strategy changes
   - Risk management updates
   - Portfolio rebalancing
   ```move
   struct StrategyProposal {
       portfolio_allocation: vector<AssetAllocation>,
       risk_parameters: RiskParams,
       rebalancing_threshold: u64,
   }
   ```

### Manager Restrictions

1. **Transaction Limits**

   ```move
   struct ManagerLimits {
       daily_withdrawal_limit: u64,
       single_tx_limit: u64,
       cooldown_period: u64,
       required_collateral: u64,
   }
   ```

2. **Multi-Signature Requirements**

   - Critical operations require multiple signatures
   - Threshold scaling with transaction size:
     ```
     required_signatures = base_signatures + (amount / threshold_step)
     ```

3. **Performance-Based Restrictions**
   - Manager rating system
   - Automatic restriction triggers
   - Performance metrics:
     ```
     manager_score = f(roi, risk_adjusted_return, voting_participation)
     ```

### Risk Management

1. **Exposure Limits**

   ```move
   struct ExposureLimits {
       max_single_asset: Percentage,
       max_protocol_exposure: Percentage,
       min_liquidity_ratio: Percentage,
   }
   ```

2. **Circuit Breakers**
   - Automatic pause triggers
   - Gradual position unwinding
   - Emergency procedures

### Advanced Voting Mechanisms

1. **Time-Weighted Voting**

   ```
   vote_power = token_amount * holding_period_multiplier
   where holding_period_multiplier = min(holding_days / 365, 2.0)
   ```

2. **Stake-to-Vote**

   - LP token locking for voting
   - Increased voting power with lock duration
   - Early unstaking penalties

3. **Reputation System**
   ```move
   struct VoterReputation {
       successful_votes: u64,
       stake_time: u64,
       proposal_participation: u64,
       reputation_score: u64,
   }
   ```

### Treasury Policies

1. **Investment Rules**

   ```move
   struct InvestmentPolicy {
       min_yield_requirement: u64,
       max_risk_level: u8,
       diversification_requirement: u64,
       lockup_restrictions: vector<LockupRule>,
   }
   ```

2. **Emergency Procedures**

   - Emergency withdrawal process
   - Crisis management protocol
   - Recovery procedures

3. **Compliance Framework**
   - KYC/AML integration
   - Regulatory reporting
   - Audit requirements

### Technical Improvements

1. **Gas Optimization**

   - Batch processing
   - State compression
   - Efficient data structures

2. **Cross-Chain Integration**

   - Bridge integration
   - Cross-chain voting
   - Multi-chain treasury management

3. **Analytics and Reporting**
   - Performance metrics
   - Risk analytics
   - Voter participation statistics

### Development Roadmap

#### Phase 1: Core Enhancement

- [ ] Implementation of advanced proposal types
- [ ] Manager restriction system
- [ ] Basic DEX integration

#### Phase 2: Advanced Features

- [ ] Time-weighted voting
- [ ] Reputation system
- [ ] Advanced risk management

#### Phase 3: Ecosystem Integration

- [ ] Multi-DEX support
- [ ] Cross-chain capabilities
- [ ] Advanced analytics

#### Phase 4: Governance Evolution

- [ ] DAO integration
- [ ] Advanced policy framework
- [ ] Automated governance features

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed contribution guidelines.

## Security

For security concerns, please email security@aspis.com

## License

MIT
