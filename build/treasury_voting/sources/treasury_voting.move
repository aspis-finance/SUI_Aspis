// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Liquidity Pool with LP tokens and voting capabilities
module treasury_voting::treasury_voting {
    use sui::event;
    use sui::vec_set::{Self, VecSet};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use std::string::String;
    use sui::vec_map::VecMap;
    use sui::bag::{Self, Bag};

    /// Capability that grants manager privileges
    public struct ManagerCap has key, store {
        id: object::UID,
    }

    /// Capability that grants pauser privileges
    public struct PauserCap has store, drop {}

    /// The treasury that holds assets and manages the pool
    public struct Treasury has key, store {
        id: object::UID,
        /// Current balance of SUI in the pool
        balance: Balance<SUI>,
        /// Total supply of LP tokens
        total_lp_supply: u64,
        /// Number of votes required for quorum
        required_votes: u64,
        /// Whether the treasury is paused
        is_paused: bool,
        /// Roles for different capabilities
        roles: Bag,
    }

    /// LP Token that represents pool share and voting power
    public struct LPToken has key, store {
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

    /// Role key for storing capabilities in the bag
    public struct RoleKey<phantom T> has store, drop, copy {
        owner: address
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
    const ENotAllowed: u64 = 8;
    const EIsPaused: u64 = 9;

    /// Initialize the module
    fun init(ctx: &mut TxContext) {
        let manager_cap = ManagerCap {
            id: object::new(ctx),
        };
        transfer::public_transfer(manager_cap, tx_context::sender(ctx));
    }

    /// Create a new treasury with initial settings
    public fun new(
        required_votes: u64,
        ctx: &mut TxContext,
    ) {
        let treasury = Treasury {
            id: object::new(ctx),
            balance: balance::zero(),
            total_lp_supply: 0,
            required_votes,
            is_paused: false,
            roles: bag::new(ctx),
        };

        let manager_cap = ManagerCap {
            id: object::new(ctx),
        };

        // Transfer manager capability to the creator using public_transfer for better composability
        transfer::public_transfer(manager_cap, tx_context::sender(ctx));
        // Share treasury object so it can be accessed by anyone
        transfer::share_object(treasury);
    }

    /// Create a new PauserCap
    public fun new_pauser(): PauserCap {
        PauserCap {}
    }

    /// Add a role to the treasury
    public fun add_role<C: store>(
        _manager_cap: &ManagerCap,
        treasury: &mut Treasury,
        role: C,
        owner: address,
    ) {
        treasury.roles.add(RoleKey<C> { owner }, role);
    }

    /// Toggle pause state of the treasury
    public fun toggle_pause(
        treasury: &mut Treasury,
        _pauser_cap: &PauserCap,
        ctx: &mut TxContext,
    ) {
        assert!(treasury.roles.contains(RoleKey<PauserCap> { owner: tx_context::sender(ctx) }), ENotAllowed);
        treasury.is_paused = !treasury.is_paused;
    }

    /// Deposit SUI and receive LP tokens
    public fun deposit(
        treasury: &mut Treasury,
        payment: Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        assert!(!treasury.is_paused, EIsPaused);
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

        let lp_token = LPToken {
            id: object::new(ctx),
            amount: lp_amount,
            treasury: object::id(treasury),
        };

        // Передаем LPToken отправителю транзакции
        transfer::public_transfer(lp_token, tx_context::sender(ctx))
    }

    /// Withdraw SUI by burning LP tokens
    public fun withdraw(
        treasury: &mut Treasury,
        lp_tokens: LPToken,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert!(!treasury.is_paused, EIsPaused);
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
        assert!(!treasury.is_paused, EIsPaused);
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
        assert!(!treasury.is_paused, EIsPaused);
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

    /// Calculate LP tokens based on deposit amount
    fun calculate_lp_tokens(treasury: &Treasury, deposit_amount: u64): u64 {
        if (treasury.total_lp_supply == 0) {
            deposit_amount
        } else {
            let current_balance = balance::value(&treasury.balance);
            (deposit_amount * treasury.total_lp_supply) / current_balance
        }
    }

    /// Calculate withdrawal amount based on LP tokens
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

    public fun is_paused(treasury: &Treasury): bool {
        treasury.is_paused
    }
}
