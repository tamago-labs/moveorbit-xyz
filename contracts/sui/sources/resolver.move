module cross_chain_swap::resolver {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use sui::table::{Self, Table};
    use sui::hash;
    use sui::sui::SUI;
    use std::vector;

    use cross_chain_swap::escrow_factory::{Self, EscrowFactory};
    use cross_chain_swap::escrow_dst::{Self, EscrowDst};
    use cross_chain_swap::evm_order::{Self, EVMOrder, CrossChainOrder};
    use cross_chain_swap::time_locks::{Self, TimeLocks};

    // Error codes
    const E_UNAUTHORIZED: u64 = 1;
    const E_INVALID_SECRET: u64 = 2;
    const E_ORDER_NOT_FOUND: u64 = 3;
    const E_INSUFFICIENT_BALANCE: u64 = 4;
    const E_INVALID_EVM_ADDRESS: u64 = 5;
    const E_ORDER_ALREADY_PROCESSED: u64 = 6;

    /// SUI Resolver that interfaces with EVM resolvers
    public struct Resolver has key {
        id: UID,
        owner: address,
        factory: address, // EscrowFactory address
        // Secret management for cross-chain swaps
        order_secrets: Table<vector<u8>, vector<u8>>, // order_hash -> secret
        secret_hashes: Table<vector<u8>, vector<u8>>, // order_hash -> secret_hash
        // Multi-VM configuration
        evm_resolvers: Table<u256, vector<u8>>, // chain_id -> evm_resolver_address
        supported_chains: vector<u256>,
        // Operational state
        processed_orders: Table<vector<u8>, bool>,
        authorized_operators: Table<address, bool>,
    }

    /// Event emitted when resolver processes EVM order
    public struct EVMOrderProcessed has copy, drop {
        order_hash: vector<u8>,
        evm_chain_id: u256,
        sui_escrow_id: object::ID,
        resolver: address,
        amount: u256,
    }

    /// Event emitted when secret is revealed
    public struct SecretRevealed has copy, drop {
        order_hash: vector<u8>,
        secret_hash: vector<u8>,
        revealer: address,
    }

    /// Event emitted when resolver is registered for EVM chains
    public struct MultiVMRegistered has copy, drop {
        resolver: address,
        evm_chains: vector<u256>,
        evm_addresses: vector<vector<u8>>,
    }

    /// Create a new resolver
    public fun new(
        factory_address: address,
        owner: address,
        ctx: &mut TxContext
    ): Resolver {
        Resolver {
            id: object::new(ctx),
            owner,
            factory: factory_address,
            order_secrets: table::new(ctx),
            secret_hashes: table::new(ctx),
            evm_resolvers: table::new(ctx),
            supported_chains: vector::empty(),
            processed_orders: table::new(ctx),
            authorized_operators: table::new(ctx),
        }
    }

    /// Initialize and share resolver
    public fun create_shared_resolver(
        factory_address: address,
        ctx: &mut TxContext
    ) {
        let resolver = new(factory_address, tx_context::sender(ctx), ctx);
        transfer::share_object(resolver);
    }

    /// Register resolver for multiple EVM chains
    public fun register_multi_vm(
        resolver: &mut Resolver,
        evm_chain_ids: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        assert!(vector::length(&evm_chain_ids) == vector::length(&evm_addresses), E_INVALID_EVM_ADDRESS);

        let mut i = 0;
        let len = vector::length(&evm_chain_ids);
        
        while (i < len) {
            let chain_id = *vector::borrow(&evm_chain_ids, i);
            let evm_address = *vector::borrow(&evm_addresses, i);
            
            // Validate EVM address length
            assert!(vector::length(&evm_address) == 20, E_INVALID_EVM_ADDRESS);
            
            // Update or add EVM resolver
            if (table::contains(&resolver.evm_resolvers, chain_id)) {
                *table::borrow_mut(&mut resolver.evm_resolvers, chain_id) = evm_address;
            } else {
                table::add(&mut resolver.evm_resolvers, chain_id, evm_address);
                vector::push_back(&mut resolver.supported_chains, chain_id);
            };
            
            i = i + 1;
        };

        sui::event::emit(MultiVMRegistered {
            resolver: tx_context::sender(ctx),
            evm_chains: evm_chain_ids,
            evm_addresses,
        });
    }

    /// Submit order and secret for cross-chain processing
    public fun submit_order_and_secret(
        resolver: &mut Resolver,
        order_hash: vector<u8>,
        secret: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == resolver.owner || 
                table::contains(&resolver.authorized_operators, tx_context::sender(ctx)), E_UNAUTHORIZED);
        
        // Calculate secret hash
        let secret_hash = hash::keccak256(&secret);
        
        // Store secret and hash
        if (table::contains(&resolver.order_secrets, order_hash)) {
            *table::borrow_mut(&mut resolver.order_secrets, order_hash) = secret;
            *table::borrow_mut(&mut resolver.secret_hashes, order_hash) = secret_hash;
        } else {
            table::add(&mut resolver.order_secrets, order_hash, secret);
            table::add(&mut resolver.secret_hashes, order_hash, secret_hash);
        };
    }

    /// Process EVM→SUI cross-chain swap
    public fun process_evm_to_sui_swap<T>(
        resolver: &mut Resolver,
        factory: &mut EscrowFactory,
        evm_order: EVMOrder,
        order_hash: vector<u8>,
        signature_r: vector<u8>,
        signature_vs: vector<u8>,
        evm_chain_id: u256,
        sui_chain_id: u256,
        destination_tokens: Coin<T>,
        safety_deposit: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        assert!(!table::contains(&resolver.processed_orders, order_hash), E_ORDER_ALREADY_PROCESSED);
        assert!(table::contains(&resolver.secret_hashes, order_hash), E_ORDER_NOT_FOUND);

        // Get secret hash for this order
        let secret_hash = *table::borrow(&resolver.secret_hashes, order_hash);

        // Create cross-chain order
        let cross_chain_order = evm_order::new_cross_chain_order(
            evm_order,
            order_hash,
            signature_r,
            signature_vs,
            sui_chain_id,
            evm_chain_id,
            secret_hash,
        );

        // Create timelocks for cross-chain swap
        let timelocks = create_default_timelocks();

        // Process the order through factory
        escrow_factory::process_cross_chain_order(
            factory,
            cross_chain_order,
            destination_tokens,
            safety_deposit,
            timelocks,
            clock,
            ctx
        );

        // Mark order as processed
        table::add(&mut resolver.processed_orders, order_hash, true);

        // Emit processing event
        let amount = evm_order::get_evm_order_taking_amount(&evm_order);
        sui::event::emit(EVMOrderProcessed {
            order_hash,
            evm_chain_id,
            sui_escrow_id: object::id_from_address(@0x0), // Placeholder - would get actual ID from factory
            resolver: tx_context::sender(ctx),
            amount,
        });
    }

    /// Complete cross-chain swap by revealing secret
    public fun complete_swap_with_secret<T>(
        resolver: &mut Resolver,
        escrow: &mut EscrowDst<T>,
        order_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(table::contains(&resolver.order_secrets, order_hash), E_ORDER_NOT_FOUND);
        
        let secret = *table::borrow(&resolver.order_secrets, order_hash);
        let secret_hash = *table::borrow(&resolver.secret_hashes, order_hash);
        
        // Verify secret
        assert!(evm_order::verify_secret(&secret, &secret_hash), E_INVALID_SECRET);
        
        // Withdraw from escrow using secret
        escrow_dst::withdraw(escrow, secret, clock, ctx);
        
        // Emit secret reveal event
        sui::event::emit(SecretRevealed {
            order_hash,
            secret_hash,
            revealer: tx_context::sender(ctx),
        });
    }

    /// Emergency withdraw for specific target
    public fun emergency_withdraw_to<T>(
        resolver: &mut Resolver,
        escrow: &mut EscrowDst<T>,
        order_hash: vector<u8>,
        target: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        assert!(table::contains(&resolver.order_secrets, order_hash), E_ORDER_NOT_FOUND);
        
        let secret = *table::borrow(&resolver.order_secrets, order_hash);
        
        // Withdraw to specific target
        escrow_dst::withdraw_to(escrow, secret, target, clock, ctx);
    }

    /// Cancel swap and return funds
    public fun cancel_swap<T>(
        resolver: &mut Resolver,
        escrow: &mut EscrowDst<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        
        // Cancel escrow
        escrow_dst::cancel(escrow, clock, ctx);
    }

    /// Authorize operator to submit orders
    public fun authorize_operator(
        resolver: &mut Resolver,
        operator: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        table::add(&mut resolver.authorized_operators, operator, true);
    }

    /// Revoke operator authorization
    public fun revoke_operator(
        resolver: &mut Resolver,
        operator: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        if (table::contains(&resolver.authorized_operators, operator)) {
            table::remove(&mut resolver.authorized_operators, operator);
        };
    }

    /// Transfer ownership to new owner
    public fun transfer_ownership(
        resolver: &mut Resolver,
        new_owner: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        resolver.owner = new_owner;
    }

    /// Create default timelocks for cross-chain swaps
    fun create_default_timelocks(): TimeLocks {
        time_locks::new(
            300u32,  // dst_withdrawal: 5 minutes
            600u32,  // dst_public_withdrawal: 10 minutes  
            1800u32, // dst_cancellation: 30 minutes
            3600u32, // dst_public_cancellation: 1 hour
            120u32,  // src_withdrawal: 2 minutes
            300u32,  // src_public_withdrawal: 5 minutes
            900u32,  // src_cancellation: 15 minutes
        )
    }

    /// Create custom timelocks for specific swap requirements
    public fun create_custom_timelocks(
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
        dst_public_cancellation: u32,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
    ): TimeLocks {
        time_locks::new(
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
            dst_public_cancellation,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
        )
    }

    /// Batch process multiple EVM orders (for efficiency)
    // public fun batch_process_evm_orders<T>(
    //     resolver: &mut Resolver,
    //     factory: &mut EscrowFactory,
    //     evm_orders: vector<EVMOrder>,
    //     order_hashes: vector<vector<u8>>,
    //     signatures_r: vector<vector<u8>>,
    //     signatures_vs: vector<vector<u8>>,
    //     evm_chain_id: u256,
    //     sui_chain_id: u256,
    //     destination_tokens: vector<Coin<T>>,
    //     safety_deposits: vector<Coin<SUI>>,
    //     clock: &Clock,
    //     ctx: &mut TxContext
    // ) {
    //     assert!(tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        
    //     let len = vector::length(&evm_orders);
    //     assert!(vector::length(&order_hashes) == len, E_INVALID_EVM_ADDRESS);
    //     assert!(vector::length(&signatures_r) == len, E_INVALID_EVM_ADDRESS);
    //     assert!(vector::length(&signatures_vs) == len, E_INVALID_EVM_ADDRESS);
    //     assert!(vector::length(&destination_tokens) == len, E_INVALID_EVM_ADDRESS);
    //     assert!(vector::length(&safety_deposits) == len, E_INVALID_EVM_ADDRESS);

    //     let mut i = 0;
    //     while (i < len) {
    //         let evm_order = *vector::borrow(&evm_orders, i);
    //         let order_hash = *vector::borrow(&order_hashes, i);
    //         let signature_r = *vector::borrow(&signatures_r, i);
    //         let signature_vs = *vector::borrow(&signatures_vs, i);
    //         let token = vector::pop_back(&mut destination_tokens);
    //         let safety = vector::pop_back(&mut safety_deposits);

    //         if (!table::contains(&resolver.processed_orders, order_hash) &&
    //             table::contains(&resolver.secret_hashes, order_hash)) {
                
    //             process_evm_to_sui_swap(
    //                 resolver, factory, evm_order, order_hash, signature_r, signature_vs,
    //                 evm_chain_id, sui_chain_id, token, safety, clock, ctx
    //             );
    //         } else {
    //             // Return unused coins
    //             transfer::public_transfer(token, tx_context::sender(ctx));
    //             transfer::public_transfer(safety, tx_context::sender(ctx));
    //         };
            
    //         i = i + 1;
    //     };

    //     // Destroy empty vectors
    //     vector::destroy_empty(destination_tokens);
    //     vector::destroy_empty(safety_deposits);
    // }

    // === View Functions === //

    /// Check if order has been processed
    public fun is_order_processed(resolver: &Resolver, order_hash: vector<u8>): bool {
        table::contains(&resolver.processed_orders, order_hash)
    }

    /// Check if resolver has secret for order
    public fun has_secret(resolver: &Resolver, order_hash: vector<u8>): bool {
        table::contains(&resolver.order_secrets, order_hash)
    }

    /// Get secret hash for order (if exists)
    public fun get_secret_hash(resolver: &Resolver, order_hash: vector<u8>): vector<u8> {
        assert!(table::contains(&resolver.secret_hashes, order_hash), E_ORDER_NOT_FOUND);
        *table::borrow(&resolver.secret_hashes, order_hash)
    }

    /// Check if operator is authorized
    public fun is_operator_authorized(resolver: &Resolver, operator: address): bool {
        table::contains(&resolver.authorized_operators, operator)
    }

    /// Check if EVM chain is supported
    public fun is_chain_supported(resolver: &Resolver, chain_id: u256): bool {
        table::contains(&resolver.evm_resolvers, chain_id)
    }

    /// Get EVM resolver address for chain
    public fun get_evm_resolver(resolver: &Resolver, chain_id: u256): vector<u8> {
        assert!(table::contains(&resolver.evm_resolvers, chain_id), E_ORDER_NOT_FOUND);
        *table::borrow(&resolver.evm_resolvers, chain_id)
    }

    /// Get all supported chain IDs
    public fun get_supported_chains(resolver: &Resolver): &vector<u256> {
        &resolver.supported_chains
    }

    /// Get resolver owner
    public fun get_owner(resolver: &Resolver): address {
        resolver.owner
    }

    /// Get factory address
    public fun get_factory(resolver: &Resolver): address {
        resolver.factory
    }

    /// Verify secret matches hash without revealing secret
    public fun verify_secret_for_order(
        resolver: &Resolver,
        order_hash: vector<u8>,
        secret: &vector<u8>
    ): bool {
        if (!table::contains(&resolver.secret_hashes, order_hash)) {
            return false
        };
        
        let stored_hash = table::borrow(&resolver.secret_hashes, order_hash);
        evm_order::verify_secret(secret, stored_hash)
    }

    // === Administrative Functions === //

    /// Update factory address (in case of factory upgrades)
    public fun update_factory(
        resolver: &mut Resolver,
        new_factory: address,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        resolver.factory = new_factory;
    }

    /// Remove processed order from storage (cleanup)
    public fun cleanup_processed_order(
        resolver: &mut Resolver,
        order_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == resolver.owner, E_UNAUTHORIZED);
        
        if (table::contains(&resolver.processed_orders, order_hash)) {
            table::remove(&mut resolver.processed_orders, order_hash);
        };
        if (table::contains(&resolver.order_secrets, order_hash)) {
            table::remove(&mut resolver.order_secrets, order_hash);
        };
        if (table::contains(&resolver.secret_hashes, order_hash)) {
            table::remove(&mut resolver.secret_hashes, order_hash);
        };
    }

    /// Emergency function to extract stuck tokens
    public fun emergency_extract_tokens<T>(
        _resolver: &Resolver,
        token: Coin<T>,
        recipient: address,
        ctx: &mut TxContext
    ) {
        // Only allow extraction to owner or authorized operators
        assert!(tx_context::sender(ctx) == _resolver.owner ||
                table::contains(&_resolver.authorized_operators, tx_context::sender(ctx)), E_UNAUTHORIZED);
        
        transfer::public_transfer(token, recipient);
    }

    // === Testing Functions === //

    #[test_only]
    public fun create_test_resolver(ctx: &mut TxContext): Resolver {
        new(@0x1234, tx_context::sender(ctx), ctx)
    }

    #[test_only]
    public fun add_test_secret(
        resolver: &mut Resolver,
        order_hash: vector<u8>,
        secret: vector<u8>
    ) {
        let secret_hash = hash::keccak256(&secret);
        table::add(&mut resolver.order_secrets, order_hash, secret);
        table::add(&mut resolver.secret_hashes, order_hash, secret_hash);
    }
}
