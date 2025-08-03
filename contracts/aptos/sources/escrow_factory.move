/// Escrow Factory for APTOS cross-chain swaps
module cross_chain_swap_addr::escrow_factory {
    use std::signer;
    use std::error;
    use std::vector;
    use std::string::String; 
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_std::table::{Self, Table};

    use cross_chain_swap_addr::time_locks::{Self, TimeLocks};
    use cross_chain_swap_addr::escrow_src;
    use cross_chain_swap_addr::escrow_dst;
    use cross_chain_swap_addr::evm_order::{Self, CrossChainOrder, EVMOrder};

    /// Error codes
    const E_INVALID_SAFETY_DEPOSIT: u64 = 1;
    const E_INVALID_AMOUNT: u64 = 2;
    const E_ORDER_ALREADY_PROCESSED: u64 = 3;
    const E_UNAUTHORIZED_RESOLVER: u64 = 4;
    const E_INVALID_SECRET: u64 = 5;
    const E_NOT_AUTHORIZED: u64 = 6;

    /// Escrow Factory resource
    struct EscrowFactory has key {
        rescue_delay_src: u64,
        rescue_delay_dst: u64,
        // Cross-chain state tracking
        processed_orders: Table<vector<u8>, bool>, // order_hash -> processed
        authorized_resolvers: Table<address, bool>, // resolver -> authorized
        cross_chain_orders: Table<vector<u8>, CrossChainOrder>, // order_hash -> order
        admin: address,
    }

    /// Registry for multi-VM resolvers
    struct ResolverRegistry has key {
        evm_resolvers: Table<u256, vector<u8>>, // chain_id -> resolver_address (20 bytes)
        sui_resolvers: Table<u256, String>,     // chain_id -> resolver_address
        aptos_resolvers: Table<address, bool>,  // aptos_address -> active
        admin: address,
    }

    /// Event for cross-chain escrow creation
    #[event]
    struct CrossChainEscrowCreated has drop, store {
        order_hash: vector<u8>,
        escrow_address: address,
        src_chain_id: u256,
        dst_chain_id: u256,
        maker: vector<u8>,
        amount: u256,
        secret_hash: vector<u8>,
    }

    /// Event for resolver registration
    #[event]
    struct ResolverRegistered has drop, store {
        resolver_address: address,
        evm_chains: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        sui_chains: vector<u256>,
        sui_addresses: vector<String>,
    }

    /// Initialize factory and registry
    public fun initialize(account: &signer) {
        let factory = EscrowFactory {
            rescue_delay_src: 1800, // 30 minutes
            rescue_delay_dst: 1800, // 30 minutes
            processed_orders: table::new(),
            authorized_resolvers: table::new(),
            cross_chain_orders: table::new(),
            admin: signer::address_of(account),
        };
        move_to(account, factory);

        let registry = ResolverRegistry {
            evm_resolvers: table::new(),
            sui_resolvers: table::new(),
            aptos_resolvers: table::new(),
            admin: signer::address_of(account),
        };
        move_to(account, registry);
    }

    /// Register a multi-VM resolver
    public entry fun register_resolver(
        account: &signer,
        aptos_resolver: address,
        evm_chain_ids: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        sui_chain_ids: vector<u256>,
        sui_addresses: vector<String>,
    ) acquires ResolverRegistry {
        let registry = borrow_global_mut<ResolverRegistry>(signer::address_of(account));
        assert!(signer::address_of(account) == registry.admin, error::permission_denied(E_UNAUTHORIZED_RESOLVER));
        
        // Register APTOS resolver
        if (table::contains(&registry.aptos_resolvers, aptos_resolver)) {
            *table::borrow_mut(&mut registry.aptos_resolvers, aptos_resolver) = true;
        } else {
            table::add(&mut registry.aptos_resolvers, aptos_resolver, true);
        };
        
        // Register EVM resolvers for each chain
        let i = 0;
        let evm_len = vector::length(&evm_chain_ids);
        while (i < evm_len) {
            let chain_id = *vector::borrow(&evm_chain_ids, i);
            let evm_address = *vector::borrow(&evm_addresses, i);
            
            if (table::contains(&registry.evm_resolvers, chain_id)) {
                *table::borrow_mut(&mut registry.evm_resolvers, chain_id) = evm_address;
            } else {
                table::add(&mut registry.evm_resolvers, chain_id, evm_address);
            };
            
            i = i + 1;
        };

        // Register SUI resolvers for each chain
        i = 0;
        let sui_len = vector::length(&sui_chain_ids);
        while (i < sui_len) {
            let chain_id = *vector::borrow(&sui_chain_ids, i);
            let sui_address = *vector::borrow(&sui_addresses, i);
            
            if (table::contains(&registry.sui_resolvers, chain_id)) {
                *table::borrow_mut(&mut registry.sui_resolvers, chain_id) = sui_address;
            } else {
                table::add(&mut registry.sui_resolvers, chain_id, sui_address);
            };
            
            i = i + 1;
        };

        event::emit(ResolverRegistered {
            resolver_address: aptos_resolver,
            evm_chains: evm_chain_ids,
            evm_addresses,
            sui_chains: sui_chain_ids,
            sui_addresses,
        });
    }

    /// Authorize a resolver to create escrows
    public entry fun authorize_resolver(
        account: &signer,
        resolver: address,
    ) acquires EscrowFactory {
        let factory = borrow_global_mut<EscrowFactory>(signer::address_of(account));
        assert!(signer::address_of(account) == factory.admin, error::permission_denied(E_UNAUTHORIZED_RESOLVER));
        table::add(&mut factory.authorized_resolvers, resolver, true);
    }

    /// Process cross-chain order from EVM and create destination escrow
    public fun process_cross_chain_order(
        factory_addr: address,
        account: &signer,
        cross_chain_order: CrossChainOrder,
        locked_asset: FungibleAsset,
        safety_deposit: FungibleAsset,
        timelocks: TimeLocks,
    ): address acquires EscrowFactory {
        let factory = borrow_global_mut<EscrowFactory>(factory_addr);
        let sender = signer::address_of(account);
        assert!(table::contains(&factory.authorized_resolvers, sender), error::permission_denied(E_UNAUTHORIZED_RESOLVER));

        let order_hash = evm_order::get_cross_chain_order_hash(&cross_chain_order);
        assert!(!table::contains(&factory.processed_orders, order_hash), error::already_exists(E_ORDER_ALREADY_PROCESSED));

        // Get order information
        let (_, maker, taker, making_amount, taking_amount, secret_hash) = 
            evm_order::get_order_info(&cross_chain_order);

        // Validate amounts match assets
        let locked_amount = aptos_framework::fungible_asset::amount(&locked_asset);
        let safety_amount = aptos_framework::fungible_asset::amount(&safety_deposit);
        assert!((locked_amount as u256) >= taking_amount, error::invalid_argument(E_INVALID_AMOUNT));
        assert!(safety_amount > 0, error::invalid_argument(E_INVALID_SAFETY_DEPOSIT));

        // Convert EVM addresses to APTOS addresses for escrow
        // Note: In production, you'd want proper address conversion
        let aptos_maker = @0x1; // Placeholder - convert from EVM address
        let aptos_taker = sender; // Resolver acts as taker

        // Create destination escrow
        let escrow_address = escrow_dst::create_escrow_with_evm_order(
            account,
            order_hash,
            secret_hash,
            aptos_maker,
            aptos_taker,
            evm_order::get_cross_chain_src_chain_id(&cross_chain_order),
            maker,
            locked_asset,
            safety_deposit,
            timelocks,
        );

        // Track processed order
        table::add(&mut factory.processed_orders, order_hash, true);
        table::add(&mut factory.cross_chain_orders, order_hash, cross_chain_order);

        // Emit cross-chain event
        event::emit(CrossChainEscrowCreated {
            order_hash,
            escrow_address,
            src_chain_id: evm_order::get_cross_chain_src_chain_id(&cross_chain_order),
            dst_chain_id: evm_order::get_cross_chain_dst_chain_id(&cross_chain_order),
            maker,
            amount: taking_amount,
            secret_hash,
        });

        // Emit order processing event
        evm_order::emit_cross_chain_order_created(
            order_hash,
            maker,
            taker,
            evm_order::get_cross_chain_src_chain_id(&cross_chain_order),
            evm_order::get_cross_chain_dst_chain_id(&cross_chain_order),
            taking_amount
        );

        escrow_address
    }

    /// Create source escrow for APTOS→EVM cross-chain swap
    public entry fun create_src_escrow_cross_chain(
        account: &signer,
        factory_addr: address,
        order_hash: vector<u8>,
        secret_hash: vector<u8>,
        evm_dst_chain_id: u256,
        evm_taker: vector<u8>, // 20-byte EVM address
        locked_metadata: Object<Metadata>,
        safety_metadata: Object<Metadata>,
        locked_amount: u64,
        safety_amount: u64,
        // Timelock parameters
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
        dst_public_cancellation: u32,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
    ) acquires EscrowFactory {
        let factory = borrow_global_mut<EscrowFactory>(factory_addr);
        let sender = signer::address_of(account);
        assert!(table::contains(&factory.authorized_resolvers, sender), error::permission_denied(E_UNAUTHORIZED_RESOLVER));
        assert!(!table::contains(&factory.processed_orders, order_hash), error::already_exists(E_ORDER_ALREADY_PROCESSED));

        assert!(locked_amount > 0, error::invalid_argument(E_INVALID_AMOUNT));
        assert!(safety_amount > 0, error::invalid_argument(E_INVALID_SAFETY_DEPOSIT));

        // Create timelocks
        let timelocks = time_locks::new_with_deployment(
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
            dst_public_cancellation,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
            aptos_framework::timestamp::now_seconds(),
        );

        // Extract assets from primary stores
        let locked_asset = primary_fungible_store::withdraw(account, locked_metadata, locked_amount);
        let safety_deposit = primary_fungible_store::withdraw(account, safety_metadata, safety_amount);

        // Create source escrow
        let aptos_maker = sender;
        let aptos_taker = @0x2; // Placeholder for cross-chain taker

        escrow_src::create_escrow_with_evm_destination(
            account,
            order_hash,
            secret_hash,
            aptos_maker,
            aptos_taker,
            evm_dst_chain_id,
            evm_taker,
            locked_asset,
            safety_deposit,
            timelocks,
        );

        // Track the order
        table::add(&mut factory.processed_orders, order_hash, true);
    }

    /// Create traditional APTOS-native destination escrow (backward compatibility)
    public entry fun create_dst_escrow(
        account: &signer,
        factory_addr: address,
        order_hash: vector<u8>,
        secret_hash: vector<u8>,
        maker: address,
        taker: address,
        locked_metadata: Object<Metadata>,
        safety_metadata: Object<Metadata>,
        locked_amount: u64,
        safety_amount: u64,
        // Timelock parameters
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
        dst_public_cancellation: u32,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
    ) acquires EscrowFactory {
        let factory = borrow_global_mut<EscrowFactory>(factory_addr);
        let sender = signer::address_of(account);
        assert!(table::contains(&factory.authorized_resolvers, sender), error::permission_denied(E_UNAUTHORIZED_RESOLVER));
        assert!(!table::contains(&factory.processed_orders, order_hash), error::already_exists(E_ORDER_ALREADY_PROCESSED));

        assert!(locked_amount > 0, error::invalid_argument(E_INVALID_AMOUNT));
        assert!(safety_amount > 0, error::invalid_argument(E_INVALID_SAFETY_DEPOSIT));

        // Create timelocks
        let timelocks = time_locks::new_with_deployment(
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
            dst_public_cancellation,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
            aptos_framework::timestamp::now_seconds(),
        );

        // Extract assets from primary stores
        let locked_asset = primary_fungible_store::withdraw(account, locked_metadata, locked_amount);
        let safety_deposit = primary_fungible_store::withdraw(account, safety_metadata, safety_amount);

        escrow_dst::create_escrow(
            account,
            order_hash,
            secret_hash,
            maker,
            taker,
            locked_asset,
            safety_deposit,
            timelocks,
        );

        // Track the order
        table::add(&mut factory.processed_orders, order_hash, true);
    }

    /// Create traditional APTOS-native source escrow (backward compatibility)  
    public entry fun create_src_escrow(
        account: &signer,
        factory_addr: address,
        order_hash: vector<u8>,
        secret_hash: vector<u8>,
        maker: address,
        taker: address,
        locked_metadata: Object<Metadata>,
        safety_metadata: Object<Metadata>,
        locked_amount: u64,
        safety_amount: u64,
        // Timelock parameters
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
        dst_public_cancellation: u32,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
    ) acquires EscrowFactory {
        let factory = borrow_global_mut<EscrowFactory>(factory_addr);
        let sender = signer::address_of(account);
        assert!(table::contains(&factory.authorized_resolvers, sender), error::permission_denied(E_UNAUTHORIZED_RESOLVER));
        assert!(!table::contains(&factory.processed_orders, order_hash), error::already_exists(E_ORDER_ALREADY_PROCESSED));

        assert!(locked_amount > 0, error::invalid_argument(E_INVALID_AMOUNT));
        assert!(safety_amount > 0, error::invalid_argument(E_INVALID_SAFETY_DEPOSIT));

        // Create timelocks
        let timelocks = time_locks::new_with_deployment(
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
            dst_public_cancellation,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
            aptos_framework::timestamp::now_seconds(),
        );

        // Extract assets from primary stores
        let locked_asset = primary_fungible_store::withdraw(account, locked_metadata, locked_amount);
        let safety_deposit = primary_fungible_store::withdraw(account, safety_metadata, safety_amount);

        escrow_src::create_escrow(
            account,
            order_hash,
            secret_hash,
            maker,
            taker,
            locked_asset,
            safety_deposit,
            timelocks,
        );

        // Track the order
        table::add(&mut factory.processed_orders, order_hash, true);
    }

    /// Withdraw from cross-chain escrow using secret
    public entry fun withdraw_cross_chain(
        account: &signer,
        factory_addr: address,
        escrow_address: address,
        secret: vector<u8>,
        order_hash: vector<u8>,
    ) acquires EscrowFactory {
        let factory = borrow_global<EscrowFactory>(factory_addr);
        
        // Verify secret against stored order
        if (table::contains(&factory.cross_chain_orders, order_hash)) {
            let cross_chain_order = table::borrow(&factory.cross_chain_orders, order_hash);
            let secret_hash = evm_order::get_cross_chain_secret_hash(cross_chain_order);
            assert!(evm_order::verify_secret(&secret, &secret_hash), error::invalid_argument(E_INVALID_SECRET));
        };

        // Perform withdrawal
        escrow_dst::withdraw(account, escrow_address, secret);

        // Emit processing event
        evm_order::emit_order_processed(order_hash, true, signer::address_of(account));
    }

    /// Check if order has been processed
    public fun is_order_processed(factory_addr: address, order_hash: vector<u8>): bool acquires EscrowFactory {
        let factory = borrow_global<EscrowFactory>(factory_addr);
        table::contains(&factory.processed_orders, order_hash)
    }

    /// Check if resolver is authorized
    public fun is_resolver_authorized(factory_addr: address, resolver: address): bool acquires EscrowFactory {
        let factory = borrow_global<EscrowFactory>(factory_addr);
        table::contains(&factory.authorized_resolvers, resolver)
    }

    /// Get cross-chain order by hash
    public fun get_cross_chain_order(
        factory_addr: address, 
        order_hash: vector<u8>
    ): CrossChainOrder acquires EscrowFactory {
        let factory = borrow_global<EscrowFactory>(factory_addr);
        *table::borrow(&factory.cross_chain_orders, order_hash)
    }

    /// Check if EVM resolver is registered for chain
    public fun is_evm_resolver_registered(
        registry_addr: address,
        chain_id: u256
    ): bool acquires ResolverRegistry {
        let registry = borrow_global<ResolverRegistry>(registry_addr);
        table::contains(&registry.evm_resolvers, chain_id)
    }

    /// Check if SUI resolver is registered for chain
    public fun is_sui_resolver_registered(
        registry_addr: address,
        chain_id: u256
    ): bool acquires ResolverRegistry {
        let registry = borrow_global<ResolverRegistry>(registry_addr);
        table::contains(&registry.sui_resolvers, chain_id)
    }

    /// Check if APTOS resolver is registered
    public fun is_aptos_resolver_registered(
        registry_addr: address,
        resolver: address
    ): bool acquires ResolverRegistry {
        let registry = borrow_global<ResolverRegistry>(registry_addr);
        table::contains(&registry.aptos_resolvers, resolver)
    }

    /// Get EVM resolver address for chain
    public fun get_evm_resolver(
        registry_addr: address,
        chain_id: u256
    ): vector<u8> acquires ResolverRegistry {
        let registry = borrow_global<ResolverRegistry>(registry_addr);
        *table::borrow(&registry.evm_resolvers, chain_id)
    }

    /// Get SUI resolver address for chain
    public fun get_sui_resolver(
        registry_addr: address,
        chain_id: u256
    ): String acquires ResolverRegistry {
        let registry = borrow_global<ResolverRegistry>(registry_addr);
        *table::borrow(&registry.sui_resolvers, chain_id)
    }

    /// Admin functions
    public entry fun update_rescue_delays(
        account: &signer,
        new_src_delay: u64,
        new_dst_delay: u64,
    ) acquires EscrowFactory {
        let factory = borrow_global_mut<EscrowFactory>(signer::address_of(account));
        assert!(signer::address_of(account) == factory.admin, error::permission_denied(E_UNAUTHORIZED_RESOLVER));
        factory.rescue_delay_src = new_src_delay;
        factory.rescue_delay_dst = new_dst_delay;
    }

    public entry fun transfer_admin(
        account: &signer,
        new_admin: address,
    ) acquires EscrowFactory {
        let factory = borrow_global_mut<EscrowFactory>(signer::address_of(account));
        assert!(signer::address_of(account) == factory.admin, error::permission_denied(E_UNAUTHORIZED_RESOLVER));
        factory.admin = new_admin;
    }

    public entry fun transfer_registry_admin(
        account: &signer,
        new_admin: address,
    ) acquires ResolverRegistry {
        let registry = borrow_global_mut<ResolverRegistry>(signer::address_of(account));
        assert!(signer::address_of(account) == registry.admin, error::permission_denied(E_UNAUTHORIZED_RESOLVER));
        registry.admin = new_admin;
    }

    // Getter functions
    public fun get_rescue_delay_src(factory_addr: address): u64 acquires EscrowFactory {
        let factory = borrow_global<EscrowFactory>(factory_addr);
        factory.rescue_delay_src
    }

    public fun get_rescue_delay_dst(factory_addr: address): u64 acquires EscrowFactory {
        let factory = borrow_global<EscrowFactory>(factory_addr);
        factory.rescue_delay_dst
    }

    public fun get_admin(factory_addr: address): address acquires EscrowFactory {
        let factory = borrow_global<EscrowFactory>(factory_addr);
        factory.admin
    }

    public fun get_registry_admin(registry_addr: address): address acquires ResolverRegistry {
        let registry = borrow_global<ResolverRegistry>(registry_addr);
        registry.admin
    }

    #[test_only]
    public fun test_initialize(account: &signer) {
        initialize(account);
    }
}