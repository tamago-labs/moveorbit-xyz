/// APTOS Resolver for cross-chain swaps with EVM and SUI
module cross_chain_swap_addr::resolver {
    use std::signer;
    use std::error;
    use std::vector;
    use std::string::String;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, FungibleStore};
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_std::table::{Self, Table};
    use aptos_std::aptos_hash;

    use cross_chain_swap_addr::escrow_dst;
    use cross_chain_swap_addr::escrow_src;
    use cross_chain_swap_addr::evm_order::{Self, EVMOrder, CrossChainOrder};
    use cross_chain_swap_addr::time_locks::{Self, TimeLocks};

    /// Error codes
    const E_UNAUTHORIZED: u64 = 1;
    const E_INVALID_SECRET: u64 = 2;
    const E_ORDER_NOT_FOUND: u64 = 3;
    const E_INSUFFICIENT_BALANCE: u64 = 4;
    const E_INVALID_EVM_ADDRESS: u64 = 5;
    const E_ORDER_ALREADY_PROCESSED: u64 = 6;
    const E_INVALID_VM_TYPE: u64 = 7;

    /// APTOS Resolver resource for cross-chain operations
    struct Resolver has key {
        /// Ownership and access control
        owner: address,
        authorized_operators: Table<address, bool>,
        
        /// Multi-VM configuration
        evm_resolvers: Table<u256, vector<u8>>, // chain_id -> evm_resolver_address (20 bytes)
        sui_resolvers: Table<u256, String>,     // chain_id -> sui_resolver_address
        supported_chains: vector<u256>,
        
        /// Secret management for cross-chain swaps
        order_secrets: Table<vector<u8>, vector<u8>>, // order_hash -> secret
        secret_hashes: Table<vector<u8>, vector<u8>>, // order_hash -> secret_hash
        
        /// Operational state
        processed_orders: Table<vector<u8>, bool>,
        factory_address: address,
    }

    /// Event emitted when resolver processes EVM order
    #[event]
    struct EVMOrderProcessed has drop, store {
        order_hash: vector<u8>,
        evm_chain_id: u256,
        aptos_escrow_address: address,
        resolver: address,
        amount: u256,
    }

    /// Event emitted when secret is revealed
    #[event]
    struct SecretRevealed has drop, store {
        order_hash: vector<u8>,
        secret_hash: vector<u8>,
        revealer: address,
    }

    /// Event emitted when resolver is registered for multiple VMs
    #[event]
    struct MultiVMRegistered has drop, store {
        resolver: address,
        evm_chains: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        sui_chains: vector<u256>,
        sui_addresses: vector<String>,
    }

    /// Initialize a new resolver
    public fun initialize_resolver(
        account: &signer,
        factory_address: address,
    ) {
        let resolver = Resolver {
            owner: signer::address_of(account),
            authorized_operators: table::new(),
            evm_resolvers: table::new(),
            sui_resolvers: table::new(),
            supported_chains: vector::empty(),
            order_secrets: table::new(),
            secret_hashes: table::new(),
            processed_orders: table::new(),
            factory_address,
        };
        
        move_to(account, resolver);
    }

    /// Register resolver for multiple VM chains
    public entry fun register_multi_vm(
        account: &signer,
        evm_chain_ids: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        sui_chain_ids: vector<u256>,
        sui_addresses: vector<String>,
    ) acquires Resolver {
        let resolver = borrow_global_mut<Resolver>(signer::address_of(account));
        assert!(signer::address_of(account) == resolver.owner, error::permission_denied(E_UNAUTHORIZED));
        
        assert!(vector::length(&evm_chain_ids) == vector::length(&evm_addresses), error::invalid_argument(E_INVALID_EVM_ADDRESS));
        assert!(vector::length(&sui_chain_ids) == vector::length(&sui_addresses), error::invalid_argument(E_INVALID_EVM_ADDRESS));

        // Register EVM resolvers
        let i = 0;
        let evm_len = vector::length(&evm_chain_ids);
        while (i < evm_len) {
            let chain_id = *vector::borrow(&evm_chain_ids, i);
            let evm_address = *vector::borrow(&evm_addresses, i);
            
            // Validate EVM address length
            assert!(vector::length(&evm_address) == 20, error::invalid_argument(E_INVALID_EVM_ADDRESS));
            
            // Update or add EVM resolver
            if (table::contains(&resolver.evm_resolvers, chain_id)) {
                *table::borrow_mut(&mut resolver.evm_resolvers, chain_id) = evm_address;
            } else {
                table::add(&mut resolver.evm_resolvers, chain_id, evm_address);
                vector::push_back(&mut resolver.supported_chains, chain_id);
            };
            
            i = i + 1;
        };

        // Register SUI resolvers
        let i = 0;
        let sui_len = vector::length(&sui_chain_ids);
        while (i < sui_len) {
            let chain_id = *vector::borrow(&sui_chain_ids, i);
            let sui_address = *vector::borrow(&sui_addresses, i);
            
            // Update or add SUI resolver
            if (table::contains(&resolver.sui_resolvers, chain_id)) {
                *table::borrow_mut(&mut resolver.sui_resolvers, chain_id) = sui_address;
            } else {
                table::add(&mut resolver.sui_resolvers, chain_id, sui_address);
                if (!vector::contains(&resolver.supported_chains, &chain_id)) {
                    vector::push_back(&mut resolver.supported_chains, chain_id);
                };
            };
            
            i = i + 1;
        };

        event::emit(MultiVMRegistered {
            resolver: signer::address_of(account),
            evm_chains: evm_chain_ids,
            evm_addresses,
            sui_chains: sui_chain_ids,
            sui_addresses,
        });
    }

    /// Submit order and secret for cross-chain processing
    public entry fun submit_order_and_secret(
        account: &signer,
        order_hash: vector<u8>,
        secret: vector<u8>,
    ) acquires Resolver {
        let caller = signer::address_of(account);
        let resolver = borrow_global_mut<Resolver>(caller);
        
        assert!(caller == resolver.owner || 
                table::contains(&resolver.authorized_operators, caller), 
                error::permission_denied(E_UNAUTHORIZED));
        
        // Calculate secret hash
        let secret_hash = aptos_hash::keccak256(secret);
        
        // Store secret and hash
        if (table::contains(&resolver.order_secrets, order_hash)) {
            *table::borrow_mut(&mut resolver.order_secrets, order_hash) = secret;
            *table::borrow_mut(&mut resolver.secret_hashes, order_hash) = secret_hash;
        } else {
            table::add(&mut resolver.order_secrets, order_hash, secret);
            table::add(&mut resolver.secret_hashes, order_hash, secret_hash);
        };
    }

    /// Complete cross-chain swap by revealing secret
    public entry fun complete_swap_with_secret(
        account: &signer,
        escrow_address: address,
        order_hash: vector<u8>,
    ) acquires Resolver {
        let caller = signer::address_of(account);
        let resolver = borrow_global<Resolver>(caller);
        
        assert!(table::contains(&resolver.order_secrets, order_hash), error::not_found(E_ORDER_NOT_FOUND));
        
        let secret = *table::borrow(&resolver.order_secrets, order_hash);
        let secret_hash = *table::borrow(&resolver.secret_hashes, order_hash);
        
        // Verify secret
        assert!(evm_order::verify_secret(&secret, &secret_hash), error::invalid_argument(E_INVALID_SECRET));
        
        // Withdraw from escrow using secret
        escrow_dst::withdraw(account, escrow_address, secret);
        
        // Emit secret reveal event
        event::emit(SecretRevealed {
            order_hash,
            secret_hash,
            revealer: caller,
        });
    }

    /// Emergency cancel swap and return funds
    public entry fun emergency_cancel_swap(
        account: &signer,
        escrow_address: address,
    ) acquires Resolver {
        let caller = signer::address_of(account);
        let resolver = borrow_global<Resolver>(caller);
        
        assert!(caller == resolver.owner, error::permission_denied(E_UNAUTHORIZED));
        
        // Cancel escrow
        escrow_dst::cancel(account, escrow_address);
    }

    /// Emergency withdraw to specific target
    public entry fun emergency_withdraw_to(
        account: &signer,
        escrow_address: address,
        order_hash: vector<u8>,
        target: address,
    ) acquires Resolver {
        let caller = signer::address_of(account);
        let resolver = borrow_global<Resolver>(caller);
        
        assert!(caller == resolver.owner, error::permission_denied(E_UNAUTHORIZED));
        assert!(table::contains(&resolver.order_secrets, order_hash), error::not_found(E_ORDER_NOT_FOUND));
        
        let secret = *table::borrow(&resolver.order_secrets, order_hash);
        
        // Withdraw to specific target
        escrow_dst::withdraw_to(account, escrow_address, secret, target);
    }

    /// Authorize operator to submit orders
    public entry fun authorize_operator(
        account: &signer,
        operator: address,
    ) acquires Resolver {
        let resolver = borrow_global_mut<Resolver>(signer::address_of(account));
        assert!(signer::address_of(account) == resolver.owner, error::permission_denied(E_UNAUTHORIZED));
        table::add(&mut resolver.authorized_operators, operator, true);
    }

    /// Revoke operator authorization
    public entry fun revoke_operator(
        account: &signer,
        operator: address,
    ) acquires Resolver {
        let resolver = borrow_global_mut<Resolver>(signer::address_of(account));
        assert!(signer::address_of(account) == resolver.owner, error::permission_denied(E_UNAUTHORIZED));
        if (table::contains(&resolver.authorized_operators, operator)) {
            table::remove(&mut resolver.authorized_operators, operator);
        };
    }

    /// Transfer ownership to new owner
    public entry fun transfer_ownership(
        account: &signer,
        new_owner: address,
    ) acquires Resolver {
        let resolver = borrow_global_mut<Resolver>(signer::address_of(account));
        assert!(signer::address_of(account) == resolver.owner, error::permission_denied(E_UNAUTHORIZED));
        resolver.owner = new_owner;
    }

    /// Update factory address in resolver
    public entry fun update_factory(
        account: &signer,
        new_factory: address,
    ) acquires Resolver {
        let resolver = borrow_global_mut<Resolver>(signer::address_of(account));
        assert!(signer::address_of(account) == resolver.owner, error::permission_denied(E_UNAUTHORIZED));
        resolver.factory_address = new_factory;
    }

    /// Remove processed order from storage (cleanup)
    public entry fun cleanup_processed_order(
        account: &signer,
        order_hash: vector<u8>,
    ) acquires Resolver {
        let resolver = borrow_global_mut<Resolver>(signer::address_of(account));
        assert!(signer::address_of(account) == resolver.owner, error::permission_denied(E_UNAUTHORIZED));
        
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

    // === View Functions === //

    /// Check if order has been processed
    public fun is_order_processed(resolver_addr: address, order_hash: vector<u8>): bool acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        table::contains(&resolver.processed_orders, order_hash)
    }

    /// Check if resolver has secret for order
    public fun has_secret(resolver_addr: address, order_hash: vector<u8>): bool acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        table::contains(&resolver.order_secrets, order_hash)
    }

    /// Get secret hash for order (if exists)
    public fun get_secret_hash(resolver_addr: address, order_hash: vector<u8>): vector<u8> acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        assert!(table::contains(&resolver.secret_hashes, order_hash), error::not_found(E_ORDER_NOT_FOUND));
        *table::borrow(&resolver.secret_hashes, order_hash)
    }

    /// Check if operator is authorized
    public fun is_operator_authorized(resolver_addr: address, operator: address): bool acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        table::contains(&resolver.authorized_operators, operator)
    }

    /// Check if EVM chain is supported
    public fun is_evm_chain_supported(resolver_addr: address, chain_id: u256): bool acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        table::contains(&resolver.evm_resolvers, chain_id)
    }

    /// Check if SUI chain is supported
    public fun is_sui_chain_supported(resolver_addr: address, chain_id: u256): bool acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        table::contains(&resolver.sui_resolvers, chain_id)
    }

    /// Get EVM resolver address for chain
    public fun get_evm_resolver(resolver_addr: address, chain_id: u256): vector<u8> acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        assert!(table::contains(&resolver.evm_resolvers, chain_id), error::not_found(E_ORDER_NOT_FOUND));
        *table::borrow(&resolver.evm_resolvers, chain_id)
    }

    /// Get SUI resolver address for chain
    public fun get_sui_resolver(resolver_addr: address, chain_id: u256): String acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        assert!(table::contains(&resolver.sui_resolvers, chain_id), error::not_found(E_ORDER_NOT_FOUND));
        *table::borrow(&resolver.sui_resolvers, chain_id)
    }

    /// Get all supported chain IDs
    public fun get_supported_chains(resolver_addr: address): vector<u256> acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        resolver.supported_chains
    }

    /// Get resolver owner
    public fun get_owner(resolver_addr: address): address acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        resolver.owner
    }

    /// Get factory address
    public fun get_factory(resolver_addr: address): address acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        resolver.factory_address
    }

    /// Verify secret matches hash without revealing secret
    public fun verify_secret_for_order(
        resolver_addr: address,
        order_hash: vector<u8>,
        secret: &vector<u8>
    ): bool acquires Resolver {
        let resolver = borrow_global<Resolver>(resolver_addr);
        if (!table::contains(&resolver.secret_hashes, order_hash)) {
            return false
        };
        
        let stored_hash = table::borrow(&resolver.secret_hashes, order_hash);
        evm_order::verify_secret(secret, stored_hash)
    }

    #[test_only]
    public fun create_test_resolver(account: &signer) {
        initialize_resolver(account, @0x1234);
    }

    #[test_only]
    public fun add_test_secret(
        resolver_addr: address,
        order_hash: vector<u8>,
        secret: vector<u8>
    ) acquires Resolver {
        let resolver = borrow_global_mut<Resolver>(resolver_addr);
        let secret_hash = aptos_hash::keccak256(secret);
        table::add(&mut resolver.order_secrets, order_hash, secret);
        table::add(&mut resolver.secret_hashes, order_hash, secret_hash);
    }
}
