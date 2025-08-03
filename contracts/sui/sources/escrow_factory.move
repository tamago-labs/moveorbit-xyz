module cross_chain_swap::escrow_factory {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::table::{Self, Table};
    use sui::sui::SUI;
    
    use cross_chain_swap::time_locks::TimeLocks;
    use cross_chain_swap::escrow_src;
    use cross_chain_swap::escrow_dst;
    use cross_chain_swap::evm_order::{Self, CrossChainOrder, EVMOrder};

    // Error codes
    const E_INVALID_SAFETY_DEPOSIT: u64 = 1;
    const E_INVALID_AMOUNT: u64 = 2;
    const E_ORDER_ALREADY_PROCESSED: u64 = 3;
    const E_UNAUTHORIZED_RESOLVER: u64 = 4;
    const E_INVALID_SECRET: u64 = 5;
 
    public struct EscrowFactory has key {
        id: UID,
        rescue_delay_src: u64,
        rescue_delay_dst: u64,
        // Cross-chain state tracking
        processed_orders: Table<vector<u8>, bool>, // order_hash -> processed
        authorized_resolvers: Table<address, bool>, // resolver -> authorized
        cross_chain_orders: Table<vector<u8>, CrossChainOrder>, // order_hash -> order
        admin: address,
    }

    /// Registry for multi-VM resolvers
    public struct ResolverRegistry has key {
        id: UID,
        evm_resolvers: Table<u256, vector<u8>>, // chain_id -> resolver_address
        sui_resolvers: Table<address, bool>,    // sui_address -> active
        admin: address,
    }

    /// Event for cross-chain escrow creation
    public struct CrossChainEscrowCreated has copy, drop {
        order_hash: vector<u8>,
        escrow_id: object::ID,
        src_chain_id: u256,
        dst_chain_id: u256,
        maker: vector<u8>,
        amount: u256,
        secret_hash: vector<u8>,
    }

    /// Event for resolver registration
    public struct ResolverRegistered has copy, drop {
        resolver_address: address,
        evm_chains: vector<u256>,
        evm_addresses: vector<vector<u8>>,
    }

    /// Initialize factory with admin capabilities
    fun init(ctx: &mut TxContext) {
        let factory = EscrowFactory {
            id: object::new(ctx),
            rescue_delay_src: 1800, // 30 minutes
            rescue_delay_dst: 1800, // 30 minutes
            processed_orders: table::new(ctx),
            authorized_resolvers: table::new(ctx),
            cross_chain_orders: table::new(ctx),
            admin: tx_context::sender(ctx),
        };
        transfer::share_object(factory);

        let registry = ResolverRegistry {
            id: object::new(ctx),
            evm_resolvers: table::new(ctx),
            sui_resolvers: table::new(ctx),
            admin: tx_context::sender(ctx),
        };
        transfer::share_object(registry);
    }

    /// Test-only initialization function
    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }

    /// Register a multi-VM resolver
    public fun register_resolver(
        registry: &mut ResolverRegistry,
        sui_resolver: address,
        evm_chain_ids: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, E_UNAUTHORIZED_RESOLVER);
        
        // Register SUI resolver
        table::add(&mut registry.sui_resolvers, sui_resolver, true);
        
        // Register EVM resolvers for each chain
        let mut i = 0;
        let len = vector::length(&evm_chain_ids);
        while (i < len) {
            let chain_id = *vector::borrow(&evm_chain_ids, i);
            let evm_address = *vector::borrow(&evm_addresses, i);
            
            if (table::contains(&registry.evm_resolvers, chain_id)) {
                *table::borrow_mut(&mut registry.evm_resolvers, chain_id) = evm_address;
            } else {
                table::add(&mut registry.evm_resolvers, chain_id, evm_address);
            };
            
            i = i + 1;
        };

        sui::event::emit(ResolverRegistered {
            resolver_address: sui_resolver,
            evm_chains: evm_chain_ids,
            evm_addresses,
        });
    }

    /// Authorize a resolver to create escrows
    public fun authorize_resolver(
        factory: &mut EscrowFactory,
        resolver: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == factory.admin, E_UNAUTHORIZED_RESOLVER);
        table::add(&mut factory.authorized_resolvers, resolver, true);
    }

    /// Process cross-chain order from EVM and create destination escrow
    public fun process_cross_chain_order<T>(
        factory: &mut EscrowFactory,
        cross_chain_order: CrossChainOrder,
        locked_coin: Coin<T>,
        safety_coin: Coin<SUI>,
        timelocks: TimeLocks,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&factory.authorized_resolvers, sender), E_UNAUTHORIZED_RESOLVER);

        let order_hash = evm_order::get_cross_chain_order_hash(&cross_chain_order);
        assert!(!table::contains(&factory.processed_orders, order_hash), E_ORDER_ALREADY_PROCESSED);

        // Get order information
        let (_, maker, taker, making_amount, taking_amount, secret_hash) = 
            evm_order::get_order_info(&cross_chain_order);

        // Validate amounts match coins
        let coin_amount = (coin::value(&locked_coin) as u256);
        let safety_amount = (coin::value(&safety_coin) as u256);
        assert!(coin_amount >= taking_amount, E_INVALID_AMOUNT);
        assert!(safety_amount > 0, E_INVALID_SAFETY_DEPOSIT);

        // Convert EVM addresses to SUI addresses for escrow
        // Note: In production, you'd want proper address conversion
        let sui_maker = @0x1; // Placeholder - convert from EVM address
        let sui_taker = tx_context::sender(ctx); // Resolver acts as taker

        // Create destination escrow
        let escrow_id = escrow_dst::create_escrow_with_evm_order(
            order_hash,
            secret_hash,
            sui_maker,
            sui_taker,
            (taking_amount as u64),
            (safety_amount as u64),
            timelocks,
            locked_coin,
            safety_coin,
            clock,
            ctx
        );

        // Track processed order
        table::add(&mut factory.processed_orders, order_hash, true);
        table::add(&mut factory.cross_chain_orders, order_hash, cross_chain_order);

        // Emit cross-chain event
        sui::event::emit(CrossChainEscrowCreated {
            order_hash,
            escrow_id,
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
    }

    /// Create source escrow for EVM→SUI cross-chain swap
    public fun create_src_escrow_cross_chain<T>(
        factory: &mut EscrowFactory,
        evm_order: EVMOrder,
        order_hash: vector<u8>,
        secret_hash: vector<u8>,
        amount: u64,
        safety_deposit: u64,
        timelocks: TimeLocks,
        locked_coin: Coin<T>,
        safety_coin: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&factory.authorized_resolvers, sender), E_UNAUTHORIZED_RESOLVER);
        assert!(!table::contains(&factory.processed_orders, order_hash), E_ORDER_ALREADY_PROCESSED);

        assert!(coin::value(&locked_coin) >= amount, E_INVALID_AMOUNT);
        assert!(coin::value(&safety_coin) >= safety_deposit, E_INVALID_SAFETY_DEPOSIT);

        // Convert EVM maker address to SUI address
        let maker_evm = evm_order::get_evm_order_maker(&evm_order);
        let sui_maker = @0x1; // Placeholder - proper conversion needed
        let sui_taker = tx_context::sender(ctx);

        escrow_src::create_escrow_with_evm_order(
            order_hash,
            secret_hash,
            sui_maker,
            sui_taker,
            amount,
            safety_deposit,
            timelocks,
            locked_coin,
            safety_coin,
            clock,
            ctx
        );

        // Track the order
        table::add(&mut factory.processed_orders, order_hash, true);
    }

    /// Create traditional SUI-native escrow (backward compatibility)
    public fun create_src_escrow<T>(
        _factory: &EscrowFactory,
        order_hash: vector<u8>,
        hashlock: vector<u8>,
        maker: address,
        taker: address,
        amount: u64,
        safety_deposit: u64,
        timelocks: TimeLocks,
        locked_coin: Coin<T>,
        safety_coin: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(coin::value(&locked_coin) >= amount, E_INVALID_AMOUNT);
        assert!(coin::value(&safety_coin) >= safety_deposit, E_INVALID_SAFETY_DEPOSIT);

        escrow_src::create_escrow(
            order_hash,
            hashlock,
            maker,
            taker,
            amount,
            safety_deposit,
            timelocks,
            locked_coin,
            safety_coin,
            clock,
            ctx
        );
    }

    /// Create traditional SUI-native destination escrow (backward compatibility)  
    public fun create_dst_escrow<T>(
        _factory: &EscrowFactory,
        order_hash: vector<u8>,
        hashlock: vector<u8>,
        maker: address,
        taker: address,
        amount: u64,
        safety_deposit: u64,
        timelocks: TimeLocks,
        locked_coin: Coin<T>,
        safety_coin: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(coin::value(&locked_coin) >= amount, E_INVALID_AMOUNT);
        assert!(coin::value(&safety_coin) >= safety_deposit, E_INVALID_SAFETY_DEPOSIT);

        escrow_dst::create_escrow(
            order_hash,
            hashlock,
            maker,
            taker,
            amount,
            safety_deposit,
            timelocks,
            locked_coin,
            safety_coin,
            clock,
            ctx
        );
    }

    /// Withdraw from cross-chain escrow using secret
    public fun withdraw_cross_chain<T>(
        factory: &EscrowFactory,
        escrow: &mut escrow_dst::EscrowDst<T>,
        secret: vector<u8>,
        order_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Verify secret against stored order
        if (table::contains(&factory.cross_chain_orders, order_hash)) {
            let cross_chain_order = table::borrow(&factory.cross_chain_orders, order_hash);
            let secret_hash = evm_order::get_cross_chain_secret_hash(cross_chain_order);
            assert!(evm_order::verify_secret(&secret, &secret_hash), E_INVALID_SECRET);
        };

        // Perform withdrawal
        escrow_dst::withdraw(escrow, secret, clock, ctx);

        // Emit processing event
        evm_order::emit_order_processed(order_hash, true, tx_context::sender(ctx));
    }

    /// Check if order has been processed
    public fun is_order_processed(factory: &EscrowFactory, order_hash: vector<u8>): bool {
        table::contains(&factory.processed_orders, order_hash)
    }

    /// Check if resolver is authorized
    public fun is_resolver_authorized(factory: &EscrowFactory, resolver: address): bool {
        table::contains(&factory.authorized_resolvers, resolver)
    }

    /// Get cross-chain order by hash
    public fun get_cross_chain_order(
        factory: &EscrowFactory, 
        order_hash: vector<u8>
    ): &CrossChainOrder {
        table::borrow(&factory.cross_chain_orders, order_hash)
    }

    /// Check if EVM resolver is registered for chain
    public fun is_evm_resolver_registered(
        registry: &ResolverRegistry,
        chain_id: u256
    ): bool {
        table::contains(&registry.evm_resolvers, chain_id)
    }

    /// Get EVM resolver address for chain
    public fun get_evm_resolver(
        registry: &ResolverRegistry,
        chain_id: u256
    ): vector<u8> {
        *table::borrow(&registry.evm_resolvers, chain_id)
    }

    /// Admin functions
    public fun update_rescue_delays(
        factory: &mut EscrowFactory,
        new_src_delay: u64,
        new_dst_delay: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == factory.admin, E_UNAUTHORIZED_RESOLVER);
        factory.rescue_delay_src = new_src_delay;
        factory.rescue_delay_dst = new_dst_delay;
    }

    public fun transfer_admin(
        factory: &mut EscrowFactory,
        new_admin: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == factory.admin, E_UNAUTHORIZED_RESOLVER);
        factory.admin = new_admin;
    }

    // Getter functions
    public fun get_rescue_delay_src(factory: &EscrowFactory): u64 {
        factory.rescue_delay_src
    }

    public fun get_rescue_delay_dst(factory: &EscrowFactory): u64 {
        factory.rescue_delay_dst
    }

    public fun get_admin(factory: &EscrowFactory): address {
        factory.admin
    }
}
