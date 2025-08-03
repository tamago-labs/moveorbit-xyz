#[test_only]
module cross_chain_swap::cross_chain_tests {
    use sui::test_scenario::{Self, Scenario, next_tx, later_epoch, ctx};
    use sui::coin::{Self, Coin, mint_for_testing};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::test_utils::assert_eq;
    use sui::clock::{Self, Clock};
    
    use cross_chain_swap::escrow_factory::{Self, EscrowFactory, ResolverRegistry};
    use cross_chain_swap::escrow_dst::{Self, EscrowDst};
    use cross_chain_swap::escrow_src::{Self, EscrowSrc};
    use cross_chain_swap::evm_order::{Self, EVMOrder, CrossChainOrder};
    use cross_chain_swap::time_locks::{Self, TimeLocks};
    use cross_chain_swap::resolver::{Self, Resolver};

    // Test accounts
    const ADMIN: address = @0x1234;
    const RESOLVER_OWNER: address = @0x4567;
    const USER: address = @0x9999;
    const MAKER: address = @0xAABB;
    const TAKER: address = @0xCCDD;

    // Test parameters
    const SWAP_AMOUNT: u64 = 1000000; // 0.01 test tokens
    const SAFETY_DEPOSIT: u64 = 10000; // 10K MIST for safety
    const SECRET: vector<u8> = b"my_secret_key_for_atomic_swap";

    // Test token types
    public struct TestUSDC has drop {}
    public struct TestBTC has drop {}

    // Setup function to initialize the protocol
    fun setup_test(): Scenario {
        let mut scenario = test_scenario::begin(ADMIN);
        {
            escrow_factory::test_init(ctx(&mut scenario));
        };
        scenario
    }

    #[test]
    fun test_factory_initialization() {
        let mut scenario = setup_test();
        
        // Verify factory and registry were created
        next_tx(&mut scenario, ADMIN);
        {
            let factory = test_scenario::take_shared<EscrowFactory>(&scenario);
            let registry = test_scenario::take_shared<ResolverRegistry>(&scenario);
            
            // Verify initial state
            assert!(escrow_factory::get_rescue_delay_src(&factory) == 1800, 1);
            assert!(escrow_factory::get_rescue_delay_dst(&factory) == 1800, 2);
            assert!(escrow_factory::get_admin(&factory) == ADMIN, 3);
            
            test_scenario::return_shared(factory);
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_resolver_registration() {
        let mut scenario = setup_test();
        
        // Admin registers a multi-VM resolver
        next_tx(&mut scenario, ADMIN);
        {
            let mut registry = test_scenario::take_shared<ResolverRegistry>(&scenario);
            
            let evm_chain_ids = vector[1u256, 11155111u256, 42161u256]; // Ethereum, Sepolia, Arbitrum
            let evm_addresses = vector[
                x"1111111111111111111111111111111111111111",
                x"2222222222222222222222222222222222222222",
                x"3333333333333333333333333333333333333333"
            ];

            escrow_factory::register_resolver(
                &mut registry,
                RESOLVER_OWNER,
                evm_chain_ids,
                evm_addresses,
                ctx(&mut scenario)
            );
            
            // Verify registration
            assert!(escrow_factory::is_evm_resolver_registered(&registry, 1u256), 1);
            assert!(escrow_factory::is_evm_resolver_registered(&registry, 11155111u256), 2);
            assert!(escrow_factory::is_evm_resolver_registered(&registry, 42161u256), 3);
            
            test_scenario::return_shared(registry);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_resolver_authorization() {
        let mut scenario = setup_test();
        
        // Admin authorizes resolver
        next_tx(&mut scenario, ADMIN);
        {
            let mut factory = test_scenario::take_shared<EscrowFactory>(&scenario);
            
            escrow_factory::authorize_resolver(
                &mut factory,
                RESOLVER_OWNER,
                ctx(&mut scenario)
            );
            
            // Verify authorization
            assert!(escrow_factory::is_resolver_authorized(&factory, RESOLVER_OWNER), 1);
            assert!(!escrow_factory::is_resolver_authorized(&factory, USER), 2);
            
            test_scenario::return_shared(factory);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_native_sui_escrow_creation() {
        let mut scenario = setup_test();

        // User creates a native SUI escrow
        next_tx(&mut scenario, USER);
        { 
            let mut clock = clock::create_for_testing(ctx(&mut scenario));

            clock.set_for_testing(1731627987382);

            // Create test coins
            let test_coin = mint_for_testing<TestUSDC>(SWAP_AMOUNT, ctx(&mut scenario));
            let safety_coin = mint_for_testing<SUI>(SAFETY_DEPOSIT, ctx(&mut scenario));
            
            // Create timelocks
            let timelocks = time_locks::new(
                300u32,  // dst_withdrawal (5 mins)
                600u32,  // dst_public_withdrawal (10 mins)
                1800u32, // dst_cancellation (30 mins)
                3600u32, // dst_public_cancellation (1 hour)
                120u32,  // src_withdrawal (2 mins)
                300u32,  // src_public_withdrawal (5 mins)
                900u32,  // src_cancellation (15 mins)
            );
            
            // Create escrow
            escrow_dst::create_escrow(
                x"1111111111111111111111111111111111111111111111111111111111111111",
                sui::hash::keccak256(&SECRET),
                MAKER,
                TAKER,
                SWAP_AMOUNT,
                SAFETY_DEPOSIT,
                timelocks,
                test_coin,
                safety_coin,
                &clock,
                ctx(&mut scenario)
            );
            
            clock.destroy_for_testing();
        };
        
        // Verify escrow was created correctly
        next_tx(&mut scenario, TAKER);
        {
            let escrow = test_scenario::take_shared<EscrowDst<TestUSDC>>(&scenario);
            
            // Check escrow properties
            assert!(escrow_dst::get_amount(&escrow) == SWAP_AMOUNT, 1);
            assert!(escrow_dst::get_safety_deposit(&escrow) == SAFETY_DEPOSIT, 2);
            assert!(escrow_dst::get_maker(&escrow) == MAKER, 3);
            assert!(escrow_dst::get_taker(&escrow) == TAKER, 4);
            assert!(!escrow_dst::is_completed(&escrow), 5);
            assert!(!escrow_dst::is_cross_chain(&escrow), 6);
            
            // Check balance amounts (using Balance<T> optimization)
            let (locked_amount, safety_amount) = escrow_dst::get_balance_amounts(&escrow);
            assert!(locked_amount >= SWAP_AMOUNT, 7);
            assert!(safety_amount >= SAFETY_DEPOSIT, 8);
            
            test_scenario::return_shared(escrow);
        };
        
        test_scenario::end(scenario);
    }

    // #[test]
    // fun test_cross_chain_escrow_creation() {
    //     let mut scenario = setup_test();
        
    //     // Setup: Initialize factory and authorize resolver
    //     next_tx(&mut scenario, ADMIN);
    //     {
    //         let mut factory = test_scenario::take_shared<EscrowFactory>(&scenario);
            
    //         escrow_factory::authorize_resolver(&mut factory, RESOLVER_OWNER, ctx(&mut scenario));
            
    //         test_scenario::return_shared(factory);
    //     };
         
        
    //     // User provides tokens to resolver for cross-chain swap
    //     next_tx(&mut scenario, USER);
    //     {
    //         let test_coin = mint_for_testing<TestBTC>(SWAP_AMOUNT, ctx(&mut scenario));
    //         let safety_coin = mint_for_testing<SUI>(SAFETY_DEPOSIT, ctx(&mut scenario));
            
    //         transfer::public_transfer(test_coin, RESOLVER_OWNER);
    //         transfer::public_transfer(safety_coin, RESOLVER_OWNER);
    //     };
        
    //     // Resolver processes cross-chain order
    //     next_tx(&mut scenario, RESOLVER_OWNER);
    //     {
    //         let mut factory = test_scenario::take_shared<EscrowFactory>(&scenario);
    //         let test_coin = test_scenario::take_from_sender<Coin<TestBTC>>(&scenario);
    //         let safety_coin = test_scenario::take_from_sender<Coin<SUI>>(&scenario); 
    //         let mut clock = sui::clock::create_for_testing(ctx(&mut scenario));
            
    //         // Create EVM order
    //         let evm_order = evm_order::new_evm_order(
    //             12345u256,
    //             x"1234567890123456789012345678901234567890", // maker
    //             x"0987654321098765432109876543210987654321", // receiver
    //             x"959C3Bcf9AedF4c22061d8f935C477D9E47f02CA", // maker_asset
    //             x"5F7392Ec616F829Ab54092e7F167F518835Ac740", // taker_asset
    //             1000000u256,
    //             2000000u256,
    //             0u256
    //         );
            
    //         // Create cross-chain order
    //         let order_hash = x"2222222222222222222222222222222222222222222222222222222222222222";
    //         let secret_hash = sui::hash::keccak256(&SECRET);
            
    //         let cross_chain_order = evm_order::new_cross_chain_order(
    //             evm_order,
    //             order_hash,
    //             x"3333333333333333333333333333333333333333333333333333333333333333", // signature_r
    //             x"4444444444444444444444444444444444444444444444444444444444444444", // signature_vs
    //             1u256, // dst_chain_id (SUI)
    //             11155111u256, // src_chain_id (Ethereum Sepolia)
    //             secret_hash,
    //         );
            
    //         // Create timelocks
    //         let timelocks = time_locks::new(
    //             300u32, 600u32, 1800u32, 3600u32, 120u32, 300u32, 900u32
    //         );
            
    //         // Process cross-chain order
    //         escrow_factory::process_cross_chain_order(
    //             &mut factory,
    //             cross_chain_order,
    //             test_coin,
    //             safety_coin,
    //             timelocks,
    //             &clock,
    //             ctx(&mut scenario)
    //         );
            
    //         // Verify order was processed
    //         assert!(escrow_factory::is_order_processed(&factory, order_hash), 1);
            
    //         test_scenario::return_shared(factory);
    //         clock.destroy_for_testing();
    //     };
        
    //     // Verify cross-chain escrow was created
    //     next_tx(&mut scenario, RESOLVER_OWNER);
    //     {
    //         let escrow = test_scenario::take_shared<EscrowDst<TestBTC>>(&scenario);
            
    //         // Verify cross-chain properties
    //         assert!(escrow_dst::is_cross_chain(&escrow), 1);
    //         assert!(escrow_dst::get_amount(&escrow) == SWAP_AMOUNT, 2);
    //         assert!(!escrow_dst::is_completed(&escrow), 3);
            
    //         // Verify Balance<T> optimization is working
    //         let (locked_amount, safety_amount) = escrow_dst::get_balance_amounts(&escrow);
    //         assert!(locked_amount == SWAP_AMOUNT, 4);
    //         assert!(safety_amount == SAFETY_DEPOSIT, 5);
            
    //         test_scenario::return_shared(escrow);
    //     };
        
    //     test_scenario::end(scenario);
    // }

    #[test]
    fun test_escrow_withdrawal_with_secret() {
        let mut scenario = setup_test();
        
        next_tx(&mut scenario, USER);
        {
            let mut clock = sui::clock::create_for_testing(ctx(&mut scenario));
            clock.set_for_testing(1731627987382);
            
            let test_coin = mint_for_testing<TestUSDC>(SWAP_AMOUNT, ctx(&mut scenario));
            let safety_coin = mint_for_testing<SUI>(SAFETY_DEPOSIT, ctx(&mut scenario));
            
            let timelocks = time_locks::new(
                300u32, 600u32, 1800u32, 3600u32, 120u32, 300u32, 900u32
            );
            
            escrow_dst::create_escrow(
                x"3333333333333333333333333333333333333333333333333333333333333333",
                sui::hash::keccak256(&SECRET),
                MAKER,
                TAKER,
                SWAP_AMOUNT,
                SAFETY_DEPOSIT,
                timelocks,
                test_coin,
                safety_coin,
                &clock,
                ctx(&mut scenario)
            );
            
            clock.destroy_for_testing();
        };
        
        // Fast forward time to withdrawal period
        next_tx(&mut scenario, TAKER);
        {
            let mut escrow = test_scenario::take_shared<EscrowDst<TestUSDC>>(&scenario);

        
            // Advance time to withdrawal period (5+ minutes) 
            let mut clock = sui::clock::create_for_testing(ctx(&mut scenario));
            clock.set_for_testing(1731627987382+400_000);  // 400 seconds

            // Verify withdrawal is allowed
            assert!(escrow_dst::can_withdraw(&escrow, &clock), 1);
            
            // Withdraw using secret
            escrow_dst::withdraw(&mut escrow, SECRET, &clock, ctx(&mut scenario));
            
            // Verify escrow is completed
            assert!(escrow_dst::is_completed(&escrow), 2);
            
            // Verify balances are drained (using Balance<T> optimization)
            let (locked_amount, safety_amount) = escrow_dst::get_balance_amounts(&escrow);
            assert!(locked_amount == 0, 3);
            assert!(safety_amount == 0, 4);
            
            test_scenario::return_shared(escrow);
            clock.destroy_for_testing();
        };
        
        // Verify maker received tokens
        next_tx(&mut scenario, MAKER);
        {
            let received_coin = test_scenario::take_from_address<Coin<TestUSDC>>(&scenario, MAKER);
            assert!(coin::value(&received_coin) == SWAP_AMOUNT, 1);
            test_scenario::return_to_address(MAKER, received_coin);
        };
        
        // Verify taker received safety deposit
        next_tx(&mut scenario, TAKER);
        {
            let safety_received = test_scenario::take_from_address<Coin<SUI>>(&scenario, TAKER);
            assert!(coin::value(&safety_received) == SAFETY_DEPOSIT, 1);
            test_scenario::return_to_address(TAKER, safety_received);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_escrow_timeout_cancellation() {
        let mut scenario = setup_test();
         
        
        next_tx(&mut scenario, USER);
        {
            let mut clock = sui::clock::create_for_testing(ctx(&mut scenario)); 
            
            let test_coin = mint_for_testing<TestUSDC>(SWAP_AMOUNT, ctx(&mut scenario));
            let safety_coin = mint_for_testing<SUI>(SAFETY_DEPOSIT, ctx(&mut scenario));
            
            let timelocks = time_locks::new(
                300u32, 600u32, 1800u32, 3600u32, 120u32, 300u32, 900u32
            );
            
            escrow_dst::create_escrow(
                x"4444444444444444444444444444444444444444444444444444444444444444",
                sui::hash::keccak256(&SECRET),
                MAKER,
                TAKER,
                SWAP_AMOUNT,
                SAFETY_DEPOSIT,
                timelocks,
                test_coin,
                safety_coin,
                &clock,
                ctx(&mut scenario)
            );
            
            clock.destroy_for_testing();
        };
        
        // Fast forward past cancellation time
        next_tx(&mut scenario, TAKER);
        {
            let mut escrow = test_scenario::take_shared<EscrowDst<TestUSDC>>(&scenario);
            let mut clock = sui::clock::create_for_testing(ctx(&mut scenario)); 
            
            // Advance time past cancellation period (30+ minutes) 
            clock.set_for_testing(1731627987382+2000_000);  //  2000 seconds (33+ minutes)

            // Verify cancellation is allowed
            assert!(escrow_dst::can_cancel(&escrow, &clock), 1);
            
            // Cancel the escrow
            escrow_dst::cancel(&mut escrow, &clock, ctx(&mut scenario));
            
            // Verify escrow is completed
            assert!(escrow_dst::is_completed(&escrow), 2);
            
            test_scenario::return_shared(escrow);
            clock.destroy_for_testing();
        };
        
        // Verify taker received the locked tokens (timeout cancellation returns to taker)
        next_tx(&mut scenario, TAKER);
        {
            let received_coin = test_scenario::take_from_address<Coin<TestUSDC>>(&scenario, TAKER);
            let safety_received = test_scenario::take_from_address<Coin<SUI>>(&scenario, TAKER);
            
            assert!(coin::value(&received_coin) == SWAP_AMOUNT, 1);
            assert!(coin::value(&safety_received) == SAFETY_DEPOSIT, 2);
            
            test_scenario::return_to_address(TAKER, received_coin);
            test_scenario::return_to_address(TAKER, safety_received);
        };
        
        test_scenario::end(scenario);
    }
 

    #[test]
    fun test_end_to_end_cross_chain_swap() {
        let mut scenario = setup_test();
        
        // Setup: Initialize everything
        next_tx(&mut scenario, ADMIN);
        {
            let mut factory = test_scenario::take_shared<EscrowFactory>(&scenario);
            let mut registry = test_scenario::take_shared<ResolverRegistry>(&scenario);
            
            // Authorize resolver
            escrow_factory::authorize_resolver(&mut factory, RESOLVER_OWNER, ctx(&mut scenario));
            
            // Register multi-VM resolver
            let evm_chain_ids = vector[11155111u256]; // Sepolia
            let evm_addresses = vector[x"1111111111111111111111111111111111111111"];
            
            escrow_factory::register_resolver(
                &mut registry,
                RESOLVER_OWNER,
                evm_chain_ids,
                evm_addresses,
                ctx(&mut scenario)
            );
             
            
            test_scenario::return_shared(factory);
            test_scenario::return_shared(registry);
        };
        
        // Create SUI resolver with secret management
        next_tx(&mut scenario, RESOLVER_OWNER);
        {
            resolver::create_shared_resolver(@0x1234, ctx(&mut scenario));
        };
        
        // User wants to swap: provide tokens to resolver
        next_tx(&mut scenario, USER);
        {
            let btc_coin = mint_for_testing<TestBTC>(SWAP_AMOUNT, ctx(&mut scenario));
            let safety_coin = mint_for_testing<SUI>(SAFETY_DEPOSIT, ctx(&mut scenario));
            
            transfer::public_transfer(btc_coin, RESOLVER_OWNER);
            transfer::public_transfer(safety_coin, RESOLVER_OWNER);
        };
        
        // Resolver submits secret and processes cross-chain order
        next_tx(&mut scenario, RESOLVER_OWNER);
        {
            let mut resolver_obj = test_scenario::take_shared<Resolver>(&scenario);
            let mut factory = test_scenario::take_shared<EscrowFactory>(&scenario);
            let btc_coin = test_scenario::take_from_sender<Coin<TestBTC>>(&scenario);
            let safety_coin = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
            let mut clock = sui::clock::create_for_testing(ctx(&mut scenario)); 
            
            let order_hash = x"7777777777777777777777777777777777777777777777777777777777777777";
            
            // Submit secret to resolver
            resolver::submit_order_and_secret(&mut resolver_obj, order_hash, SECRET, ctx(&mut scenario));
            
            // Create and process cross-chain order
            let evm_order = evm_order::new_evm_order(
                99999u256,
                x"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", // EVM maker
                x"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", // EVM receiver
                x"CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC", // BTC token on EVM
                x"DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD", // USDC token on EVM
                (SWAP_AMOUNT as u256),
                (SWAP_AMOUNT as u256),
                0u256
            );
            
            resolver::process_evm_to_sui_swap(
                &mut resolver_obj,
                &mut factory,
                evm_order,
                order_hash,
                x"8888888888888888888888888888888888888888888888888888888888888888", // signature_r
                x"9999999999999999999999999999999999999999999999999999999999999999", // signature_vs
                11155111u256, // EVM chain (Sepolia)
                1u256,        // SUI chain
                btc_coin,
                safety_coin,
                &clock,
                ctx(&mut scenario)
            );
            
            // Verify order was processed
            assert!(resolver::is_order_processed(&resolver_obj, order_hash), 1);
            assert!(escrow_factory::is_order_processed(&factory, order_hash), 2);
            
            test_scenario::return_shared(resolver_obj);
            test_scenario::return_shared(factory);
            clock.destroy_for_testing();
        };
        
        // Complete the swap by revealing secret
        next_tx(&mut scenario, RESOLVER_OWNER);
        {
            let mut resolver_obj = test_scenario::take_shared<Resolver>(&scenario);
            let mut escrow = test_scenario::take_shared<EscrowDst<TestBTC>>(&scenario);
            let mut clock = sui::clock::create_for_testing(ctx(&mut scenario));
            
            let order_hash = x"7777777777777777777777777777777777777777777777777777777777777777";
            
            // Fast forward time
            clock::increment_for_testing(&mut clock, 400_000);
            
            // Complete swap using secret
            resolver::complete_swap_with_secret(
                &mut resolver_obj,
                &mut escrow,
                order_hash,
                &clock,
                ctx(&mut scenario)
            );
            
            // Verify swap completed
            assert!(escrow_dst::is_completed(&escrow), 1);
            
            test_scenario::return_shared(resolver_obj);
            test_scenario::return_shared(escrow);
            clock.destroy_for_testing();
        };
        
        // Verify funds were distributed correctly
        next_tx(&mut scenario, @0x1); // SUI maker placeholder
        {
            let received_btc = test_scenario::take_from_address<Coin<TestBTC>>(&scenario, @0x1);
            assert!(coin::value(&received_btc) == SWAP_AMOUNT, 1);
            test_scenario::return_to_address(@0x1, received_btc);
        };
        
        next_tx(&mut scenario, RESOLVER_OWNER);
        {
            let safety_received = test_scenario::take_from_address<Coin<SUI>>(&scenario, RESOLVER_OWNER);
            assert!(coin::value(&safety_received) == SAFETY_DEPOSIT, 1);
            test_scenario::return_to_address(RESOLVER_OWNER, safety_received);
        };
        
        test_scenario::end(scenario);
    }
}
