#[test_only]
module treasury_voting::treasury_voting_tests {
    use sui::test_scenario::{Self};
    use sui::coin::{Self};
    use sui::balance;
    use sui::sui::SUI;
    use treasury_voting::treasury_voting::{Self, Treasury, ManagerCap, PauserCap, WithdrawalProposal};

    #[test]
    fun test_treasury_creation() {
        let user = @0xA;
        let scenario = test_scenario::begin(user);
        
        // Create treasury
        let (treasury, manager_cap) = treasury_voting::new(
            2, // required votes
            test_scenario::ctx(&mut scenario),
        );

        // Share objects
        test_scenario::return_shared(treasury);
        test_scenario::return_to_sender(&scenario, manager_cap);
        test_scenario::next_tx(&mut scenario, user);

        // Take objects for verification
        let treasury = test_scenario::take_shared<Treasury>(&scenario);
        
        // Verify treasury state
        assert!(treasury_voting::total_lp_supply(&treasury) == 0, 0);
        assert!(balance::value(treasury_voting::balance(&treasury)) == 0, 1);
        assert!(!treasury_voting::is_paused(&treasury), 2);

        // Return objects
        test_scenario::return_shared(treasury);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_role_management() {
        let user = @0xA;
        let mut scenario = test_scenario::begin(user);

        // Create initial balance
        let initial_balance = balance::create_for_testing(1000);
        let required_votes = 2;
        let initial_pool_value = 1000;

        // Create and share treasury
        let (treasury, manager_cap) = treasury_voting::new(
            initial_balance,
            required_votes,
            initial_pool_value,
            test_scenario::ctx(&mut scenario),
        );
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(manager_cap);
        test_scenario::next_tx(&mut scenario, user);

        // Take objects for role management
        let mut treasury = test_scenario::take_shared<treasury_voting::Treasury>(&scenario);
        let manager_cap = test_scenario::take_shared<treasury_voting::ManagerCap>(&scenario);

        // Create pauser capability
        let pauser_cap = treasury_voting::new_pauser();

        // Add pauser role
        treasury_voting::add_role(&manager_cap, &mut treasury, pauser_cap, user);

        // Create new pauser capability for toggle
        let pauser_cap2 = treasury_voting::new_pauser();

        // Verify pause functionality works
        treasury_voting::toggle_pause(&mut treasury, &pauser_cap2, test_scenario::ctx(&mut scenario));
        assert!(treasury_voting::is_paused(&treasury), 4);

        // Return objects
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(manager_cap);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = treasury_voting::ENotAllowed)]
    fun test_unauthorized_pause() {
        let user = @0xA;
        let other_user = @0xB;
        let mut scenario = test_scenario::begin(user);

        // Create initial balance
        let initial_balance = balance::create_for_testing(1000);
        let required_votes = 2;
        let initial_pool_value = 1000;

        // Create and share treasury
        let (treasury, manager_cap) = treasury_voting::new(
            initial_balance,
            required_votes,
            initial_pool_value,
            test_scenario::ctx(&mut scenario),
        );
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(manager_cap);
        test_scenario::next_tx(&mut scenario, user);

        // Take objects for role management
        let mut treasury = test_scenario::take_shared<treasury_voting::Treasury>(&scenario);
        let manager_cap = test_scenario::take_shared<treasury_voting::ManagerCap>(&scenario);

        // Create pauser capability for other user
        let pauser_cap = treasury_voting::new_pauser();
        treasury_voting::add_role(&manager_cap, &mut treasury, pauser_cap, other_user);

        // Return objects
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(manager_cap);
        test_scenario::next_tx(&mut scenario, other_user);

        // Take treasury for unauthorized pause attempt
        let mut treasury = test_scenario::take_shared<treasury_voting::Treasury>(&scenario);

        // Create new pauser capability for toggle
        let pauser_cap2 = treasury_voting::new_pauser();

        // Try to pause with unauthorized user - this should fail
        treasury_voting::toggle_pause(&mut treasury, &pauser_cap2, test_scenario::ctx(&mut scenario));

        // Return treasury
        test_scenario::return_shared(treasury);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = treasury_voting::EIsPaused)]
    fun test_operations_when_paused() {
        let user = @0xA;
        let mut scenario = test_scenario::begin(user);

        // Create initial balance
        let initial_balance = balance::create_for_testing(1000);
        let required_votes = 2;
        let initial_pool_value = 1000;

        // Create treasury
        let (mut treasury, manager_cap) = treasury_voting::new(
            initial_balance,
            required_votes,
            initial_pool_value,
            test_scenario::ctx(&mut scenario),
        );

        // Create and add pauser role
        let pauser_cap = treasury_voting::new_pauser();
        treasury_voting::add_role(&manager_cap, &mut treasury, pauser_cap, user);
        test_scenario::next_tx(&mut scenario, user);

        // Create new pauser capability for toggle
        let pauser_cap2 = treasury_voting::new_pauser();

        // Pause the treasury
        treasury_voting::toggle_pause(&mut treasury, &pauser_cap2, test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, user);

        // Try to deposit while paused - this should fail
        let test_coin = coin::mint_for_testing(100, test_scenario::ctx(&mut scenario));
        let lp_tokens = treasury_voting::deposit(&mut treasury, test_coin, test_scenario::ctx(&mut scenario));
        
        // Since we expect this to fail, we won't reach this point
        // But we need to handle the LP tokens in case we do
        let withdrawn_coin = treasury_voting::withdraw(&mut treasury, lp_tokens, test_scenario::ctx(&mut scenario));
        let withdrawn_balance = coin::into_balance(withdrawn_coin);
        balance::destroy_for_testing(withdrawn_balance);

        test_scenario::return_shared(treasury);
        test_scenario::return_shared(manager_cap);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_deposit_and_withdraw() {
        let user = @0xA;
        let scenario = test_scenario::begin(user);

        // Create treasury
        let (treasury, manager_cap) = treasury_voting::new(
            2,
            test_scenario::ctx(&mut scenario),
        );

        // Create test coin
        let coin = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(&mut scenario));
        
        // Deposit coins and get LP tokens
        let lp_tokens = treasury_voting::deposit(
            &mut treasury,
            coin,
            test_scenario::ctx(&mut scenario),
        );

        // Verify deposit
        assert!(treasury_voting::total_lp_supply(&treasury) == 1000, 0);
        assert!(balance::value(treasury_voting::balance(&treasury)) == 1000, 1);

        // Withdraw using LP tokens
        let withdrawn_coin = treasury_voting::withdraw(
            &mut treasury,
            lp_tokens,
            test_scenario::ctx(&mut scenario),
        );

        // Verify withdrawal
        assert!(treasury_voting::total_lp_supply(&treasury) == 0, 2);
        assert!(balance::value(treasury_voting::balance(&treasury)) == 0, 3);
        assert!(coin::value(&withdrawn_coin) == 1000, 4);

        // Cleanup
        coin::destroy_for_testing(withdrawn_coin);
        test_scenario::return_shared(treasury);
        test_scenario::return_to_sender(&scenario, manager_cap);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_proposal_creation_and_voting() {
        let user = @0xA;
        let scenario = test_scenario::begin(user);

        // Create treasury and deposit
        let (treasury, manager_cap) = treasury_voting::new(2, test_scenario::ctx(&mut scenario));
        let coin = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(&mut scenario));
        let lp_tokens = treasury_voting::deposit(&mut treasury, coin, test_scenario::ctx(&mut scenario));

        // Create proposal
        treasury_voting::create_proposal(
            &treasury,
            &manager_cap,
            user,
            500,
            test_scenario::ctx(&mut scenario),
        );

        test_scenario::next_tx(&mut scenario, user);

        // Take proposal for voting
        let proposal = test_scenario::take_shared<WithdrawalProposal>(&scenario);

        // Vote with LP tokens
        treasury_voting::vote(
            &mut proposal,
            &lp_tokens,
            test_scenario::ctx(&mut scenario),
        );

        // Execute proposal
        let withdrawn_coin = treasury_voting::execute_proposal(
            &mut treasury,
            &mut proposal,
            &manager_cap,
            test_scenario::ctx(&mut scenario),
        );

        // Verify results
        assert!(coin::value(&withdrawn_coin) == 500, 0);
        assert!(balance::value(treasury_voting::balance(&treasury)) == 500, 1);

        // Cleanup
        coin::destroy_for_testing(withdrawn_coin);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(proposal);
        test_scenario::return_to_sender(&scenario, manager_cap);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = treasury_voting::EInvalidAmount)]
    fun test_deposit_zero_amount() {
        let user = @0xA;
        let mut scenario = test_scenario::begin(user);

        // Create initial balance
        let initial_balance = balance::create_for_testing(1000);
        let required_votes = 2;
        let initial_pool_value = 1000;

        // Create treasury
        let (mut treasury, manager_cap) = treasury_voting::new(
            initial_balance,
            required_votes,
            initial_pool_value,
            test_scenario::ctx(&mut scenario),
        );

        // Try to deposit zero amount - this should fail
        let test_coin = coin::mint_for_testing(0, test_scenario::ctx(&mut scenario));
        let lp_tokens = treasury_voting::deposit(&mut treasury, test_coin, test_scenario::ctx(&mut scenario));
        
        // Since we expect this to fail, we won't reach this point
        // But we need to handle the LP tokens in case we do
        let withdrawn_coin = treasury_voting::withdraw(&mut treasury, lp_tokens, test_scenario::ctx(&mut scenario));
        let withdrawn_balance = coin::into_balance(withdrawn_coin);
        balance::destroy_for_testing(withdrawn_balance);

        test_scenario::return_shared(treasury);
        test_scenario::return_shared(manager_cap);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = treasury_voting::EAlreadyVoted)]
    fun test_double_vote() {
        let user = @0xA;
        let mut scenario = test_scenario::begin(user);

        // Create initial balance
        let initial_balance = balance::create_for_testing(1000);
        let required_votes = 2;
        let initial_pool_value = 1000;

        // Create treasury
        let (mut treasury, manager_cap) = treasury_voting::new(
            initial_balance,
            required_votes,
            initial_pool_value,
            test_scenario::ctx(&mut scenario),
        );

        // Create test coin for deposit
        let deposit_amount = 100;
        let test_coin = coin::mint_for_testing(deposit_amount, test_scenario::ctx(&mut scenario));

        // Deposit to get LP tokens
        let lp_tokens = treasury_voting::deposit(&mut treasury, test_coin, test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, user);

        // Create proposal
        let recipient = @0xB;
        let proposal_amount = 50;
        treasury_voting::create_proposal(&treasury, &manager_cap, recipient, proposal_amount, test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, user);

        // Vote first time
        let mut proposal = test_scenario::take_shared<WithdrawalProposal>(&scenario);
        treasury_voting::vote(&mut proposal, &lp_tokens, test_scenario::ctx(&mut scenario));
        test_scenario::return_shared(proposal);
        test_scenario::next_tx(&mut scenario, user);

        // Try to vote again - this should fail
        let mut proposal = test_scenario::take_shared<WithdrawalProposal>(&scenario);
        treasury_voting::vote(&mut proposal, &lp_tokens, test_scenario::ctx(&mut scenario));
        test_scenario::return_shared(proposal);

        // Consume LP tokens by withdrawing
        let withdrawn_coin = treasury_voting::withdraw(&mut treasury, lp_tokens, test_scenario::ctx(&mut scenario));
        let withdrawn_balance = coin::into_balance(withdrawn_coin);
        balance::destroy_for_testing(withdrawn_balance);

        test_scenario::return_shared(treasury);
        test_scenario::return_shared(manager_cap);
        test_scenario::end(scenario);
    }
} 