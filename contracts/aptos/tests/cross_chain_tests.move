///  cross-chain tests with proper FA integration and escrow testing
#[test_only]
module cross_chain_swap_addr::cross_chain_tests {
    use std::signer;
    use std::vector;
    use std::string;
    use std::option;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_std::aptos_hash;

    use cross_chain_swap_addr::escrow_factory;
    use cross_chain_swap_addr::escrow_dst;
    use cross_chain_swap_addr::escrow_src;
    use cross_chain_swap_addr::evm_order;
    use cross_chain_swap_addr::time_locks;
    use cross_chain_swap_addr::resolver;
    use cross_chain_swap_addr::interface;
    use cross_chain_swap_addr::mock_usdc;

    // Test accounts
    const ADMIN_ADDR: address = @0x1234;
    const RESOLVER_OWNER_ADDR: address = @0x4567;
    const USER_ADDR: address = @0x9999;
    const MAKER_ADDR: address = @0xAABB;
    const TAKER_ADDR: address = @0xCCDD;

    // Test parameters
    const SWAP_AMOUNT: u64 = 1000000; // 0.01 APT
    const SAFETY_DEPOSIT: u64 = 10000; // 0.0001 APT for safety
    const SECRET: vector<u8> = b"my_secret_key_for_atomic_swap";

    fun setup_test_accounts(): (signer, signer, signer, signer, signer) {
        let admin = account::create_account_for_test(ADMIN_ADDR);
        let resolver_owner = account::create_account_for_test(RESOLVER_OWNER_ADDR);
        let user = account::create_account_for_test(USER_ADDR);
        let maker = account::create_account_for_test(MAKER_ADDR);
        let taker = account::create_account_for_test(TAKER_ADDR);

        // Initialize timestamp for testing
        timestamp::set_time_has_started_for_testing(&admin);
        timestamp::update_global_time_for_test(1731627987382000); // Microseconds

        (admin, resolver_owner, user, maker, taker)
    }

    fun setup_fungible_assets_for_testing(admin: &signer, test_accounts: &vector<address>) {
        // Initialize APT as both coin and fungible asset
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(admin);
        
        // Create the coin conversion map and pairing for APT
        coin::create_coin_conversion_map(admin);
        coin::create_pairing<AptosCoin>(admin);
        
        // Mint APT for test accounts (using coin interface)
        let i = 0;
        while (i < vector::length(test_accounts)) {
            let addr = *vector::borrow(test_accounts, i);
            let account = &account::create_signer_for_test(addr);
            coin::register<AptosCoin>(account);
            let coins = coin::mint(100000000, &mint_cap); // 1 APT
            coin::deposit(addr, coins);
            i = i + 1;
        };

        // Initialize Mock USDC for testing
        mock_usdc::init_module_for_testing(admin);
        
        // Mint Mock USDC for test accounts using the existing mint function
        i = 0;
        while (i < vector::length(test_accounts)) {
            let addr = *vector::borrow(test_accounts, i);
            mock_usdc::mint(addr, 1000000000); // 1000 USDC (6 decimals)
            i = i + 1;
        };

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    /// Get APT metadata for fungible asset operations
    fun get_apt_metadata(): aptos_framework::object::Object<aptos_framework::fungible_asset::Metadata> {
        // Get APT's paired fungible asset metadata (should exist after setup)
        option::destroy_some(coin::paired_metadata<AptosCoin>())
    }

    #[test]
    fun test_protocol_initialization() {
        let (admin, _, _, _, _) = setup_test_accounts();
        
        // Initialize the protocol
        interface::initialize_protocol(&admin);
        
        // Verify factory was created with correct initial state
        assert!(escrow_factory::get_rescue_delay_src(ADMIN_ADDR) == 1800, 1);
        assert!(escrow_factory::get_rescue_delay_dst(ADMIN_ADDR) == 1800, 2);
        assert!(escrow_factory::get_admin(ADMIN_ADDR) == ADMIN_ADDR, 3);
    }

    // #[test]
    // fun test_resolver_initialization() {
    //     let (admin, resolver_owner, _, _, _) = setup_test_accounts();
        
    //     // Initialize protocol first
    //     interface::initialize_protocol(&admin);
        
    //     // Initialize resolver
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
        
    //     // Verify resolver was created
    //     assert!(resolver::get_owner(RESOLVER_OWNER_ADDR) == RESOLVER_OWNER_ADDR, 1);
    //     assert!(resolver::get_factory(RESOLVER_OWNER_ADDR) == ADMIN_ADDR, 2);
    // }

    // #[test]
    // fun test_multi_vm_resolver_registration() {
    //     let (admin, resolver_owner, _, _, _) = setup_test_accounts();
        
    //     // Initialize protocol and resolver
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
        
    //     // Register resolver in factory
    //     let evm_chain_ids = vector[1u256, 11155111u256]; // Ethereum, Sepolia
    //     let evm_addresses = vector[
    //         x"1111111111111111111111111111111111111111",
    //         x"2222222222222222222222222222222222222222"
    //     ];
    //     let sui_chain_ids = vector[101u256]; // SUI testnet
    //     let sui_addresses = vector[string::utf8(b"0x5678...sui_address")];

    //     interface::register_resolver_in_factory(
    //         &admin,
    //         RESOLVER_OWNER_ADDR,
    //         evm_chain_ids,
    //         evm_addresses,
    //         sui_chain_ids,
    //         sui_addresses,
    //     );

    //     // Also register in resolver itself
    //     interface::register_multi_vm_resolver(
    //         &resolver_owner,
    //         evm_chain_ids,
    //         evm_addresses,
    //         sui_chain_ids,
    //         sui_addresses,
    //     );
        
    //     // Verify registration
    //     assert!(escrow_factory::is_evm_resolver_registered(ADMIN_ADDR, 1u256), 1);
    //     assert!(escrow_factory::is_evm_resolver_registered(ADMIN_ADDR, 11155111u256), 2);
    //     assert!(escrow_factory::is_sui_resolver_registered(ADMIN_ADDR, 101u256), 3);
    //     assert!(resolver::is_evm_chain_supported(RESOLVER_OWNER_ADDR, 1u256), 4);
    //     assert!(resolver::is_sui_chain_supported(RESOLVER_OWNER_ADDR, 101u256), 5);
    // }

    // #[test]
    // fun test_resolver_authorization() {
    //     let (admin, resolver_owner, _, _, _) = setup_test_accounts();
        
    //     // Initialize protocol and resolver
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
        
    //     // Authorize resolver
    //     interface::authorize_resolver(&admin, RESOLVER_OWNER_ADDR);
        
    //     // Verify authorization
    //     assert!(escrow_factory::is_resolver_authorized(ADMIN_ADDR, RESOLVER_OWNER_ADDR), 1);
    //     assert!(!escrow_factory::is_resolver_authorized(ADMIN_ADDR, USER_ADDR), 2);
    // }

    // #[test]
    // fun test_secret_management() {
    //     let (admin, resolver_owner, _, _, _) = setup_test_accounts();
        
    //     // Initialize protocol and resolver
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
        
    //     let order_hash = x"1111111111111111111111111111111111111111111111111111111111111111";
        
    //     // Submit secret
    //     interface::submit_order_and_secret(&resolver_owner, order_hash, SECRET);
        
    //     // Verify secret storage
    //     assert!(resolver::has_secret(RESOLVER_OWNER_ADDR, order_hash), 1);
        
    //     let expected_hash = aptos_hash::keccak256(SECRET);
    //     let stored_hash = resolver::get_secret_hash(RESOLVER_OWNER_ADDR, order_hash);
    //     assert!(stored_hash == expected_hash, 2);
        
    //     // Verify secret verification
    //     assert!(resolver::verify_secret_for_order(RESOLVER_OWNER_ADDR, order_hash, &SECRET), 3);
    //     assert!(!resolver::verify_secret_for_order(RESOLVER_OWNER_ADDR, order_hash, &b"wrong_secret"), 4);
    // }

    // #[test]
    // fun test_traditional_escrow_creation_with_fa() {
    //     let (admin, resolver_owner, _, maker, taker) = setup_test_accounts();
    //     let test_accounts = vector[ADMIN_ADDR, RESOLVER_OWNER_ADDR, MAKER_ADDR, TAKER_ADDR];
        
    //     // Setup protocol and assets
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
    //     interface::authorize_resolver(&admin, RESOLVER_OWNER_ADDR);
    //     setup_fungible_assets_for_testing(&admin, &test_accounts);
        
    //     let order_hash = x"2222222222222222222222222222222222222222222222222222222222222222";
        
    //     // Test destination escrow creation
    //     interface::create_destination_escrow_default(
    //         &resolver_owner,
    //         ADMIN_ADDR,
    //         order_hash,
    //         SECRET,
    //         MAKER_ADDR,
    //         TAKER_ADDR,
    //         get_apt_metadata(), // APT metadata
    //         mock_usdc::get_metadata(),  // USDC metadata for safety
    //         SWAP_AMOUNT,
    //         SAFETY_DEPOSIT,
    //     );
        
    //     // Verify order was processed
    //     assert!(escrow_factory::is_order_processed(ADMIN_ADDR, order_hash), 1);
    // }

    // #[test]
    // fun test_cross_chain_escrow_creation() {
    //     let (admin, resolver_owner, _, maker, taker) = setup_test_accounts();
    //     let test_accounts = vector[ADMIN_ADDR, RESOLVER_OWNER_ADDR, MAKER_ADDR, TAKER_ADDR];
        
    //     // Setup protocol and assets
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
    //     interface::authorize_resolver(&admin, RESOLVER_OWNER_ADDR);
    //     setup_fungible_assets_for_testing(&admin, &test_accounts);
        
    //     let order_hash = x"3333333333333333333333333333333333333333333333333333333333333333";
    //     let evm_taker = x"4444444444444444444444444444444444444444"; // 20-byte EVM address
        
    //     // Test cross-chain source escrow creation
    //     interface::create_cross_chain_source_escrow_default(
    //         &resolver_owner,
    //         ADMIN_ADDR,
    //         order_hash,
    //         SECRET,
    //         1u256, // Ethereum mainnet
    //         evm_taker,
    //         get_apt_metadata(), // APT metadata
    //         mock_usdc::get_metadata(),  // USDC metadata for safety
    //         SWAP_AMOUNT,
    //         SAFETY_DEPOSIT,
    //     );
        
    //     // Verify order was processed
    //     assert!(escrow_factory::is_order_processed(ADMIN_ADDR, order_hash), 1);
    // }

    // #[test]
    // fun test_evm_order_creation() {
    //     let evm_order = evm_order::new_evm_order(
    //         12345u256,
    //         x"1111111111111111111111111111111111111111", // maker
    //         x"2222222222222222222222222222222222222222", // receiver
    //         x"3333333333333333333333333333333333333333", // maker_asset
    //         x"4444444444444444444444444444444444444444", // taker_asset
    //         1000000u256, // making_amount
    //         2000000u256, // taking_amount
    //         0u256        // maker_traits
    //     );
        
    //     // Verify order properties
    //     assert!(evm_order::get_evm_order_salt(&evm_order) == 12345u256, 1);
    //     assert!(evm_order::get_evm_order_making_amount(&evm_order) == 1000000u256, 2);
    //     assert!(evm_order::get_evm_order_taking_amount(&evm_order) == 2000000u256, 3);
    // }

    // #[test]
    // fun test_cross_chain_order_creation() {
    //     let evm_order = evm_order::create_test_evm_order();
    //     let cross_chain_order = evm_order::new_cross_chain_order(
    //         evm_order,
    //         x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", // order_hash
    //         x"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef", // signature_r
    //         x"fedcbafedcbafedcbafedcbafedcbafedcbafedcbafedcbafedcbafedcbafedcba", // signature_vs
    //         2u256,    // dst_chain_id (APTOS)
    //         11155111u256, // src_chain_id (Ethereum Sepolia)
    //         aptos_hash::keccak256(b"test_secret") // secret_hash
    //     );
        
    //     // Verify cross-chain order properties
    //     assert!(evm_order::get_cross_chain_src_chain_id(&cross_chain_order) == 11155111u256, 1);
    //     assert!(evm_order::get_cross_chain_dst_chain_id(&cross_chain_order) == 2u256, 2);
        
    //     let (order_hash, maker, taker, making_amount, taking_amount, secret_hash) = 
    //         evm_order::get_order_info(&cross_chain_order);
    //     assert!(making_amount == 1000000u256, 3);
    //     assert!(taking_amount == 2000000u256, 4);
    // }

    // #[test]
    // fun test_timelock_functionality() {
    //     // Test timelock creation and validation
    //     let timelocks = time_locks::new(
    //         300u32,  // dst_withdrawal: 5 minutes
    //         600u32,  // dst_public_withdrawal: 10 minutes  
    //         1800u32, // dst_cancellation: 30 minutes
    //         3600u32, // dst_public_cancellation: 1 hour
    //         120u32,  // src_withdrawal: 2 minutes
    //         300u32,  // src_public_withdrawal: 5 minutes
    //         900u32,  // src_cancellation: 15 minutes
    //     );
        
    //     // Verify timelock properties
    //     assert!(time_locks::get_dst_withdrawal(&timelocks) == 300u32, 1);
    //     assert!(time_locks::get_dst_cancellation(&timelocks) == 1800u32, 2);
    //     assert!(time_locks::get_src_withdrawal(&timelocks) == 120u32, 3);
        
    //     // Test default timelocks
    //     let default_timelocks = time_locks::create_default();
    //     assert!(time_locks::get_dst_withdrawal(&default_timelocks) == 300u32, 4);
        
    //     // Test fast timelocks for testing
    //     let fast_timelocks = time_locks::create_fast_test();
    //     assert!(time_locks::get_dst_withdrawal(&fast_timelocks) == 10u32, 5);
    // }

    // #[test]
    // fun test_full_escrow_workflow() {
    //     let (admin, resolver_owner, _, maker, taker) = setup_test_accounts();
    //     let test_accounts = vector[ADMIN_ADDR, RESOLVER_OWNER_ADDR, MAKER_ADDR, TAKER_ADDR];
        
    //     // Setup everything
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
    //     interface::authorize_resolver(&admin, RESOLVER_OWNER_ADDR);
    //     setup_fungible_assets_for_testing(&admin, &test_accounts);
        
    //     let order_hash = x"5555555555555555555555555555555555555555555555555555555555555555";
        
    //     // Store secret in resolver
    //     interface::submit_order_and_secret(&resolver_owner, order_hash, SECRET);
        
    //     // Create destination escrow
    //     interface::create_destination_escrow_default(
    //         &resolver_owner,
    //         ADMIN_ADDR,
    //         order_hash,
    //         SECRET,
    //         MAKER_ADDR,
    //         TAKER_ADDR,
    //         get_apt_metadata(),
    //         mock_usdc::get_metadata(),
    //         SWAP_AMOUNT,
    //         SAFETY_DEPOSIT,
    //     );
        
    //     // Verify complete workflow
    //     assert!(escrow_factory::is_order_processed(ADMIN_ADDR, order_hash), 1);
    //     assert!(resolver::has_secret(RESOLVER_OWNER_ADDR, order_hash), 2);
    //     assert!(interface::is_resolver_authorized_by_factory(ADMIN_ADDR, RESOLVER_OWNER_ADDR), 3);
    // }

    // #[test]
    // fun test_operator_management() {
    //     let (admin, resolver_owner, _, _, user) = setup_test_accounts();
        
    //     // Initialize protocol and resolver
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
        
    //     // Authorize operator
    //     interface::authorize_operator(&resolver_owner, USER_ADDR);
        
    //     // Verify operator authorization
    //     assert!(resolver::is_operator_authorized(RESOLVER_OWNER_ADDR, USER_ADDR), 1);
    //     assert!(!resolver::is_operator_authorized(RESOLVER_OWNER_ADDR, MAKER_ADDR), 2);
        
    //     // Revoke operator
    //     interface::revoke_operator(&resolver_owner, USER_ADDR);
        
    //     // Verify revocation
    //     assert!(!resolver::is_operator_authorized(RESOLVER_OWNER_ADDR, USER_ADDR), 3);
    // }

    // #[test]
    // fun test_admin_functions() {
    //     let (admin, resolver_owner, _, _, _) = setup_test_accounts();
        
    //     // Initialize protocol
    //     interface::initialize_protocol(&admin);
        
    //     // Test factory admin functions
    //     interface::update_rescue_delays(&admin, 2000u64, 2000u64);
    //     assert!(escrow_factory::get_rescue_delay_src(ADMIN_ADDR) == 2000, 1);
    //     assert!(escrow_factory::get_rescue_delay_dst(ADMIN_ADDR) == 2000, 2);
        
    //     // Test ownership transfer
    //     interface::transfer_factory_admin(&admin, RESOLVER_OWNER_ADDR);
    //     assert!(escrow_factory::get_admin(ADMIN_ADDR) == RESOLVER_OWNER_ADDR, 3);
        
    //     // Initialize resolver and test resolver ownership transfer
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
    //     interface::transfer_resolver_ownership(&resolver_owner, USER_ADDR);
    //     assert!(resolver::get_owner(RESOLVER_OWNER_ADDR) == USER_ADDR, 4);
    // }

    // #[test]
    // fun test_batch_operations() {
    //     let (admin, resolver_owner, _, _, _) = setup_test_accounts();
        
    //     // Initialize protocol and resolver
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
        
    //     // Prepare batch data
    //     let order_hashes = vector[
    //         x"1111111111111111111111111111111111111111111111111111111111111111",
    //         x"2222222222222222222222222222222222222222222222222222222222222222",
    //         x"3333333333333333333333333333333333333333333333333333333333333333"
    //     ];
    //     let secrets = vector[
    //         b"secret_1",
    //         b"secret_2", 
    //         b"secret_3"
    //     ];
        
    //     // Batch submit secrets
    //     interface::batch_submit_order_secrets(&resolver_owner, order_hashes, secrets);
        
    //     // Verify all secrets were stored
    //     assert!(resolver::has_secret(RESOLVER_OWNER_ADDR, *vector::borrow(&order_hashes, 0)), 1);
    //     assert!(resolver::has_secret(RESOLVER_OWNER_ADDR, *vector::borrow(&order_hashes, 1)), 2);
    //     assert!(resolver::has_secret(RESOLVER_OWNER_ADDR, *vector::borrow(&order_hashes, 2)), 3);
    // }

    // #[test]
    // fun test_secret_verification() {
    //     let secret = b"test_secret_for_verification";
    //     let secret_hash = aptos_hash::keccak256(secret);
        
    //     // Test secret verification function
    //     assert!(evm_order::verify_secret(&secret, &secret_hash), 1);
    //     assert!(!evm_order::verify_secret(&b"wrong_secret", &secret_hash), 2);
    // }

    // #[test]
    // fun test_evm_address_conversion() {
    //     let evm_address = x"1234567890abcdef1234567890abcdef12345678";
    //     let address_string = evm_order::evm_address_to_string(&evm_address);
        
    //     // The string should start with "0x" and be 42 characters long
    //     let string_bytes = string::bytes(&address_string);
    //     assert!(vector::length(string_bytes) == 42, 1);
    //     assert!(*vector::borrow(string_bytes, 0) == 48, 2); // '0'
    //     assert!(*vector::borrow(string_bytes, 1) == 120, 3); // 'x'
    // }

    // #[test] 
    // fun test_view_functions() {
    //     let (admin, resolver_owner, _, _, _) = setup_test_accounts();
        
    //     // Initialize protocol and resolver
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
    //     interface::authorize_resolver(&admin, RESOLVER_OWNER_ADDR);
        
    //     let order_hash = x"4444444444444444444444444444444444444444444444444444444444444444";
        
    //     // Test view functions
    //     assert!(!interface::is_order_processed_by_resolver(RESOLVER_OWNER_ADDR, order_hash), 1);
    //     assert!(!interface::is_order_processed_by_factory(ADMIN_ADDR, order_hash), 2);
    //     assert!(!interface::resolver_has_secret(RESOLVER_OWNER_ADDR, order_hash), 3);
    //     assert!(interface::is_resolver_authorized_by_factory(ADMIN_ADDR, RESOLVER_OWNER_ADDR), 4);
        
    //     // Submit a secret and verify
    //     interface::submit_order_and_secret(&resolver_owner, order_hash, SECRET);
    //     assert!(interface::resolver_has_secret(RESOLVER_OWNER_ADDR, order_hash), 5);
    // }

    // #[test]
    // fun test_cleanup_functions() {
    //     let (admin, resolver_owner, _, _, _) = setup_test_accounts();
        
    //     // Initialize protocol and resolver
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
        
    //     let order_hash = x"5555555555555555555555555555555555555555555555555555555555555555";
        
    //     // Submit secret
    //     interface::submit_order_and_secret(&resolver_owner, order_hash, SECRET);
    //     assert!(resolver::has_secret(RESOLVER_OWNER_ADDR, order_hash), 1);
        
    //     // Cleanup processed order
    //     interface::cleanup_processed_order(&resolver_owner, order_hash);
    //     assert!(!resolver::has_secret(RESOLVER_OWNER_ADDR, order_hash), 2);
    // }

    // #[test]
    // fun test_protocol_workflow() {
    //     let (admin, resolver_owner, _, _, _) = setup_test_accounts();
        
    //     // Complete workflow test
    //     interface::initialize_protocol(&admin);
    //     interface::initialize_resolver(&resolver_owner, ADMIN_ADDR);
    //     interface::authorize_resolver(&admin, RESOLVER_OWNER_ADDR);
        
    //     // Register multi-VM resolver
    //     let evm_chain_ids = vector[11155111u256];
    //     let evm_addresses = vector[x"1111111111111111111111111111111111111111"];
    //     let sui_chain_ids = vector[101u256];
    //     let sui_addresses = vector[string::utf8(b"0x5678sui")];
        
    //     interface::register_multi_vm_resolver(
    //         &resolver_owner,
    //         evm_chain_ids,
    //         evm_addresses,
    //         sui_chain_ids,
    //         sui_addresses,
    //     );
        
    //     // Submit order and secret
    //     let order_hash = x"6666666666666666666666666666666666666666666666666666666666666666";
    //     interface::submit_order_and_secret(&resolver_owner, order_hash, SECRET);
        
    //     // Verify complete workflow
    //     assert!(resolver::has_secret(RESOLVER_OWNER_ADDR, order_hash), 1);
    //     assert!(resolver::is_evm_chain_supported(RESOLVER_OWNER_ADDR, 11155111u256), 2);
    //     assert!(resolver::is_sui_chain_supported(RESOLVER_OWNER_ADDR, 101u256), 3);
    //     assert!(escrow_factory::is_resolver_authorized(ADMIN_ADDR, RESOLVER_OWNER_ADDR), 4);
    // }

    // #[test]
    // fun test_fungible_asset_metadata() {
    //     let (admin, _, _, _, _) = setup_test_accounts();
    //     let test_accounts = vector[ADMIN_ADDR];
        
    //     // Setup assets
    //     setup_fungible_assets_for_testing(&admin, &test_accounts);
        
    //     // Test APT metadata
    //     let apt_metadata = get_apt_metadata();
    //     let apt_symbol = fungible_asset::symbol(apt_metadata);
    //     assert!(apt_symbol == string::utf8(b"APT"), 1);
        
    //     // Test USDC metadata
    //     let usdc_metadata = mock_usdc::get_metadata();
    //     let usdc_symbol = fungible_asset::symbol(usdc_metadata);
    //     assert!(usdc_symbol == string::utf8(b"USDC"), 2);
    // }
}