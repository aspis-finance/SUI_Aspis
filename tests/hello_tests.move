#[test_only]
module my_addr::hello_tests {
    use sui::test_scenario::{Self, Scenario};
    use my_addr::hello::{Self, GreetingObject};

    #[test]
    fun test_greeting_flow() {
        let user = @0xA;
        let scenario = test_scenario::begin(user);
        let ctx = test_scenario::ctx(&mut scenario);

        // Create a new greeting
        hello::create_greeting(ctx);
        test_scenario::next_tx(&mut scenario, user);

        // Get the greeting object
        let greeting = test_scenario::take_shared<GreetingObject>(&scenario);
        let message = hello::get_message(&greeting);
        assert!(std::string::utf8(b"Hello, Sui!") == *message, 0);

        // Update the greeting
        hello::update_greeting(&mut greeting, b"Hello, Test!", ctx);
        test_scenario::return_shared(greeting);
        test_scenario::next_tx(&mut scenario, user);

        test_scenario::end(scenario);
    }
} 