// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Liquidity Pool with LP tokens and voting capabilities
module treasury_voting::treasury_voting {
    use sui::event;
    use sui::object;
    use sui::vec_set::{Self, VecSet};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use std::string::String;
    use sui::vec_map::VecMap;

    /// Capability that grants manager privileges
    public struct ManagerCap has key {
        id: object::UID,
    }

    /// The treasury that holds assets and manages the pool
    public struct Treasury has key {
        id: object::UID,
        /// Current balance of SUI in the pool
        balance: Balance<SUI>,
        /// Total supply of LP tokens
        total_lp_supply: u64,
        /// Number of votes required for quorum
        required_votes: u64,
        /// Current pool value in USD (8 decimals)
        pool_value_usd: u64,
    }

    /// LP Token that represents pool share and voting power
    public struct LPToken has key {
        id: object::UID,
        /// The amount of LP tokens
        amount: u64,
        /// The ID of the Treasury this token refers to
        treasury: object::ID,
    }

    /// A proposed withdrawal from the treasury
    public struct WithdrawalProposal has key {
        id: object::UID,
        /// The ID of the Treasury this proposal is for
        treasury: object::ID,
        /// The address requesting the withdrawal
        proposer: address,
        /// The recipient address
        recipient: address,
        /// The amount to withdraw
        amount: u64,
        /// Current voters that have accepted the withdrawal
        current_voters: VecSet<object::ID>,
        /// Optional metadata about the withdrawal
        metadata: Option<VecMap<String, String>>,
    }

    // Events
    public struct DepositEvent has copy, drop {
        treasury: object::ID,
        depositor: address,
        amount: u64,
        lp_tokens: u64,
    }

    public struct WithdrawalEvent has copy, drop {
        treasury: object::ID,
        withdrawer: address,
        amount: u64,
        lp_tokens: u64,
    }

    public struct ProposalCreated has copy, drop {
        treasury: object::ID,
        proposal: object::ID,
        proposer: address,
        recipient: address,
        amount: u64,
    }

    public struct ProposalVoted has copy, drop {
        proposal: object::ID,
        voter: object::ID,
        signer: address,
    }

    public struct ProposalExecuted has copy, drop {
        treasury: object::ID,
        proposal: object::ID,
        proposer: address,
        recipient: address,
        amount: u64,
    }

    // Error codes
    const EInvalidAmount: u64 = 0;
    const EInsufficientBalance: u64 = 1;
    const EAlreadyVoted: u64 = 3;
    const ENotEnoughVotes: u64 = 4;
    const EInvalidProposal: u64 = 5;
    const EInvalidRecipient: u64 = 6;
    const EInvalidPoolValue: u64 = 7;

    /// Create a new treasury with initial settings
    public fun new(
        initial_balance: Balance<SUI>,
        required_votes: u64,
        initial_pool_value_usd: u64,
        ctx: &mut TxContext,
    ): (Treasury, ManagerCap) {
        assert!(initial_pool_value_usd > 0, EInvalidPoolValue);
        
        let treasury = Treasury {
            id: object::new(ctx),
            balance: initial_balance,
            total_lp_supply: 0,
            required_votes,
            pool_value_usd: initial_pool_value_usd,
        };

        let manager_cap = ManagerCap {
            id: object::new(ctx),
        };

        (treasury, manager_cap)
    }

    /// Deposit SUI and receive LP tokens
    public fun deposit(
        treasury: &mut Treasury,
        payment: Coin<SUI>,
        ctx: &mut TxContext,
    ): LPToken {
        let amount = coin::value(&payment);
        assert!(amount > 0, EInvalidAmount);

        // Calculate LP tokens to mint based on pool value
        let lp_amount = calculate_lp_tokens(treasury, amount);
        
        // Add deposit to pool
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut treasury.balance, payment_balance);
        treasury.total_lp_supply = treasury.total_lp_supply + lp_amount;

        event::emit(DepositEvent {
            treasury: object::id(treasury),
            depositor: tx_context::sender(ctx),
            amount,
            lp_tokens: lp_amount,
        });

        LPToken {
            id: object::new(ctx),
            amount: lp_amount,
            treasury: object::id(treasury),
        }
    }

    /// Withdraw SUI by burning LP tokens
    public fun withdraw(
        treasury: &mut Treasury,
        lp_tokens: LPToken,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert!(lp_tokens.treasury == object::id(treasury), EInvalidProposal);
        let amount = calculate_withdrawal_amount(treasury, lp_tokens.amount);
        assert!(amount <= balance::value(&treasury.balance), EInsufficientBalance);

        treasury.total_lp_supply = treasury.total_lp_supply - lp_tokens.amount;
        let LPToken { id, amount: lp_amount, treasury: _ } = lp_tokens;
        object::delete(id);

        event::emit(WithdrawalEvent {
            treasury: object::id(treasury),
            withdrawer: tx_context::sender(ctx),
            amount,
            lp_tokens: lp_amount,
        });

        coin::from_balance(balance::split(&mut treasury.balance, amount), ctx)
    }

    /// Create a withdrawal proposal (manager only)
    public fun create_proposal(
        treasury: &Treasury,
        _manager_cap: &ManagerCap,
        recipient: address,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(recipient != @0x0, EInvalidRecipient);
        assert!(amount <= balance::value(&treasury.balance), EInsufficientBalance);

        let proposal_uid = object::new(ctx);
        let proposal_id = object::uid_to_inner(&proposal_uid);

        let proposal = WithdrawalProposal {
            id: proposal_uid,
            treasury: object::id(treasury),
            proposer: tx_context::sender(ctx),
            recipient,
            amount,
            current_voters: vec_set::empty(),
            metadata: option::none(),
        };

        event::emit(ProposalCreated {
            treasury: object::id(treasury),
            proposal: proposal_id,
            proposer: tx_context::sender(ctx),
            recipient,
            amount,
        });

        transfer::share_object(proposal);
    }

    /// Vote on a withdrawal proposal using LP tokens
    public fun vote(
        proposal: &mut WithdrawalProposal,
        lp_tokens: &LPToken,
        ctx: &TxContext,
    ) {
        assert!(proposal.treasury == lp_tokens.treasury, EInvalidProposal);
        let voter_id = object::id(lp_tokens);
        assert!(!vec_set::contains(&proposal.current_voters, &voter_id), EAlreadyVoted);
        
        vec_set::insert(&mut proposal.current_voters, voter_id);

        event::emit(ProposalVoted {
            proposal: object::id(proposal),
            voter: voter_id,
            signer: tx_context::sender(ctx),
        });
    }

    /// Execute a withdrawal proposal if quorum is reached
    public fun execute_proposal(
        treasury: &mut Treasury,
        proposal: &mut WithdrawalProposal,
        _manager_cap: &ManagerCap,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert!(proposal.treasury == object::id(treasury), EInvalidProposal);
        assert!(
            vec_set::size(&proposal.current_voters) >= treasury.required_votes,
            ENotEnoughVotes,
        );

        let amount = proposal.amount;
        assert!(amount <= balance::value(&treasury.balance), EInsufficientBalance);

        event::emit(ProposalExecuted {
            treasury: proposal.treasury,
            proposal: object::id(proposal),
            proposer: proposal.proposer,
            recipient: proposal.recipient,
            amount,
        });

        coin::from_balance(balance::split(&mut treasury.balance, amount), ctx)
    }

    /// Helper function to calculate LP tokens to mint
    fun calculate_lp_tokens(treasury: &Treasury, deposit_amount: u64): u64 {
        if (treasury.total_lp_supply == 0) {
            deposit_amount
        } else {
            let current_balance = balance::value(&treasury.balance);
            (deposit_amount * treasury.total_lp_supply) / (current_balance - deposit_amount)
        }
    }

    /// Helper function to calculate withdrawal amount
    fun calculate_withdrawal_amount(treasury: &Treasury, lp_amount: u64): u64 {
        (lp_amount * balance::value(&treasury.balance)) / treasury.total_lp_supply
    }

    // Accessors
    public fun balance(treasury: &Treasury): &Balance<SUI> {
        &treasury.balance
    }

    public fun total_lp_supply(treasury: &Treasury): u64 {
        treasury.total_lp_supply
    }

    public fun pool_value_usd(treasury: &Treasury): u64 {
        treasury.pool_value_usd
    }
}
