/// Simplified Interface module for MoveOrbit Cross-Chain Swap Protocol on APTOS
/// Contains essential entry functions that work with APTOS Move constraints
module cross_chain_swap_addr::interface {
    use std::vector;
    use std::string::String;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;  
    use aptos_std::aptos_hash;

    use cross_chain_swap_addr::escrow_factory;
    use cross_chain_swap_addr::escrow_dst;
    use cross_chain_swap_addr::escrow_src;
    use cross_chain_swap_addr::resolver;

    /// Initialize the protocol (called once during deployment)
    public entry fun initialize_protocol(account: &signer) {
        escrow_factory::initialize(account);
    }

    /// Initialize a new resolver for cross-chain operations
    public entry fun initialize_resolver(
        account: &signer,
        factory_address: address,
    ) {
        resolver::initialize_resolver(account, factory_address);
    }

    /// Register resolver for multiple VM chains
    public entry fun register_multi_vm_resolver(
        account: &signer,
        evm_chain_ids: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        sui_chain_ids: vector<u256>,
        sui_addresses: vector<String>,
    ) {
        resolver::register_multi_vm(
            account,
            evm_chain_ids,
            evm_addresses,
            sui_chain_ids,
            sui_addresses,
        );
    }

    /// Register a multi-VM resolver in the factory registry
    public entry fun register_resolver_in_factory(
        account: &signer,
        aptos_resolver: address,
        evm_chain_ids: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        sui_chain_ids: vector<u256>,
        sui_addresses: vector<String>,
    ) {
        escrow_factory::register_resolver(
            account,
            aptos_resolver,
            evm_chain_ids,
            evm_addresses,
            sui_chain_ids,
            sui_addresses,
        );
    }

    /// Authorize a resolver to create escrows
    public entry fun authorize_resolver(
        account: &signer,
        resolver: address,
    ) {
        escrow_factory::authorize_resolver(account, resolver);
    }

    /// Submit order and secret for cross-chain processing
    public entry fun submit_order_and_secret(
        account: &signer,
        order_hash: vector<u8>,
        secret: vector<u8>,
    ) {
        resolver::submit_order_and_secret(account, order_hash, secret);
    }

    /// Complete cross-chain swap by revealing secret
    public entry fun complete_swap_with_secret(
        account: &signer,
        escrow_address: address,
        order_hash: vector<u8>,
    ) {
        resolver::complete_swap_with_secret(
            account,
            escrow_address,
            order_hash,
        );
    }

    /// Create a destination escrow with default timelock settings
    public entry fun create_destination_escrow_default(
        account: &signer,
        factory_address: address,
        order_hash: vector<u8>,
        secret: vector<u8>,
        maker: address,
        taker: address,
        locked_metadata: Object<Metadata>,
        safety_metadata: Object<Metadata>,
        locked_amount: u64,
        safety_amount: u64,
    ) {
        escrow_factory::create_dst_escrow(
            account,
            factory_address,
            order_hash,
            aptos_hash::keccak256(secret),
            maker,
            taker,
            locked_metadata,
            safety_metadata,
            locked_amount,
            safety_amount,
            300u32,  // dst_withdrawal: 5 minutes
            600u32,  // dst_public_withdrawal: 10 minutes  
            1800u32, // dst_cancellation: 30 minutes
            3600u32, // dst_public_cancellation: 1 hour
            120u32,  // src_withdrawal: 2 minutes
            300u32,  // src_public_withdrawal: 5 minutes
            900u32,  // src_cancellation: 15 minutes
        );
    }

    /// Create a source escrow with default timelock settings
    public entry fun create_source_escrow_default(
        account: &signer,
        factory_address: address,
        order_hash: vector<u8>,
        secret: vector<u8>,
        maker: address,
        taker: address,
        locked_metadata: Object<Metadata>,
        safety_metadata: Object<Metadata>,
        locked_amount: u64,
        safety_amount: u64,
    ) {
        escrow_factory::create_src_escrow(
            account,
            factory_address,
            order_hash,
            aptos_hash::keccak256(secret),
            maker,
            taker,
            locked_metadata,
            safety_metadata,
            locked_amount,
            safety_amount,
            300u32,  // dst_withdrawal: 5 minutes
            600u32,  // dst_public_withdrawal: 10 minutes  
            1800u32, // dst_cancellation: 30 minutes
            3600u32, // dst_public_cancellation: 1 hour
            120u32,  // src_withdrawal: 2 minutes
            300u32,  // src_public_withdrawal: 5 minutes
            900u32,  // src_cancellation: 15 minutes
        );
    }

    /// Create cross-chain source escrow with default timelock settings
    public entry fun create_cross_chain_source_escrow_default(
        account: &signer,
        factory_address: address,
        order_hash: vector<u8>,
        secret: vector<u8>,
        evm_dst_chain_id: u256,
        evm_taker: vector<u8>, // 20-byte EVM address
        locked_metadata: Object<Metadata>,  // Changed from Object<FungibleStore>
        safety_metadata: Object<Metadata>,  // Changed from Object<FungibleStore>
        locked_amount: u64,
        safety_amount: u64,
    ) {
        escrow_factory::create_src_escrow_cross_chain(
            account,
            factory_address,
            order_hash,
            aptos_hash::keccak256(secret),
            evm_dst_chain_id,
            evm_taker,
            locked_metadata,
            safety_metadata,
            locked_amount,
            safety_amount,
            300u32,  // dst_withdrawal: 5 minutes
            600u32,  // dst_public_withdrawal: 10 minutes  
            1800u32, // dst_cancellation: 30 minutes
            3600u32, // dst_public_cancellation: 1 hour
            120u32,  // src_withdrawal: 2 minutes
            300u32,  // src_public_withdrawal: 5 minutes
            900u32,  // src_cancellation: 15 minutes
        );
    }

    /// Withdraw from destination escrow using secret
    public entry fun withdraw_from_destination(
        account: &signer,
        escrow_address: address,
        secret: vector<u8>,
    ) {
        escrow_dst::withdraw(account, escrow_address, secret);
    }

    /// Withdraw from destination escrow to specific target
    public entry fun withdraw_to_target(
        account: &signer,
        escrow_address: address,
        secret: vector<u8>,
        target: address,
    ) {
        escrow_dst::withdraw_to(account, escrow_address, secret, target);
    }

    /// Cancel destination escrow (after timeout)
    public entry fun cancel_destination_escrow(
        account: &signer,
        escrow_address: address,
    ) {
        escrow_dst::cancel(account, escrow_address);
    }

    /// Withdraw from source escrow using secret
    public entry fun withdraw_from_source(
        account: &signer,
        escrow_address: address,
        secret: vector<u8>,
    ) {
        escrow_src::withdraw(account, escrow_address, secret);
    }

    /// Cancel source escrow (after timeout)
    public entry fun cancel_source_escrow(
        account: &signer,
        escrow_address: address,
    ) {
        escrow_src::cancel(account, escrow_address);
    }

    /// Withdraw from cross-chain escrow using secret
    public entry fun withdraw_cross_chain_escrow(
        account: &signer,
        factory_address: address,
        escrow_address: address,
        secret: vector<u8>,
        order_hash: vector<u8>,
    ) {
        escrow_factory::withdraw_cross_chain(
            account,
            factory_address,
            escrow_address,
            secret,
            order_hash,
        );
    }

    /// Emergency functions for resolver owner

    /// Emergency cancel swap and return funds
    public entry fun emergency_cancel_swap(
        account: &signer,
        escrow_address: address,
    ) {
        resolver::emergency_cancel_swap(account, escrow_address);
    }

    /// Emergency withdraw for specific target
    public entry fun emergency_withdraw_to(
        account: &signer,
        escrow_address: address,
        order_hash: vector<u8>,
        target: address,
    ) {
        resolver::emergency_withdraw_to(
            account,
            escrow_address,
            order_hash,
            target,
        );
    }

    /// Authorize operator to submit orders
    public entry fun authorize_operator(
        account: &signer,
        operator: address,
    ) {
        resolver::authorize_operator(account, operator);
    }

    /// Revoke operator authorization
    public entry fun revoke_operator(
        account: &signer,
        operator: address,
    ) {
        resolver::revoke_operator(account, operator);
    }

    /// Transfer resolver ownership
    public entry fun transfer_resolver_ownership(
        account: &signer,
        new_owner: address,
    ) {
        resolver::transfer_ownership(account, new_owner);
    }

    /// Update factory address in resolver
    public entry fun update_resolver_factory(
        account: &signer,
        new_factory: address,
    ) {
        resolver::update_factory(account, new_factory);
    }

    /// Factory admin functions

    /// Update rescue delays in factory
    public entry fun update_rescue_delays(
        account: &signer,
        new_src_delay: u64,
        new_dst_delay: u64,
    ) {
        escrow_factory::update_rescue_delays(
            account,
            new_src_delay,
            new_dst_delay,
        );
    }

    /// Transfer factory admin
    public entry fun transfer_factory_admin(
        account: &signer,
        new_admin: address,
    ) {
        escrow_factory::transfer_admin(account, new_admin);
    }

    /// Transfer registry admin
    public entry fun transfer_registry_admin(
        account: &signer,
        new_admin: address,
    ) {
        escrow_factory::transfer_registry_admin(account, new_admin);
    }

    /// Cleanup functions

    /// Remove processed order from storage (cleanup)
    public entry fun cleanup_processed_order(
        account: &signer,
        order_hash: vector<u8>,
    ) {
        resolver::cleanup_processed_order(account, order_hash);
    }

    /// Batch operations for efficiency

    /// Batch submit multiple order secrets
    public entry fun batch_submit_order_secrets(
        account: &signer,
        order_hashes: vector<vector<u8>>,
        secrets: vector<vector<u8>>,
    ) {
        let i = 0;
        let len = vector::length(&order_hashes);
        
        while (i < len) {
            let order_hash = *vector::borrow(&order_hashes, i);
            let secret = *vector::borrow(&secrets, i);
            
            resolver::submit_order_and_secret(account, order_hash, secret);
            
            i = i + 1;
        };
    }

    // View functions (no entry needed for read-only functions)

    /// Check if order has been processed by resolver
    public fun is_order_processed_by_resolver(resolver_addr: address, order_hash: vector<u8>): bool {
        resolver::is_order_processed(resolver_addr, order_hash)
    }

    /// Check if order has been processed by factory
    public fun is_order_processed_by_factory(factory_addr: address, order_hash: vector<u8>): bool {
        escrow_factory::is_order_processed(factory_addr, order_hash)
    }

    /// Check if resolver has secret for order
    public fun resolver_has_secret(resolver_addr: address, order_hash: vector<u8>): bool {
        resolver::has_secret(resolver_addr, order_hash)
    }

    /// Check if operator is authorized
    public fun is_operator_authorized(resolver_addr: address, operator: address): bool {
        resolver::is_operator_authorized(resolver_addr, operator)
    }

    /// Check if EVM chain is supported by resolver
    public fun is_evm_chain_supported(resolver_addr: address, chain_id: u256): bool {
        resolver::is_evm_chain_supported(resolver_addr, chain_id)
    }

    /// Check if SUI chain is supported by resolver
    public fun is_sui_chain_supported(resolver_addr: address, chain_id: u256): bool {
        resolver::is_sui_chain_supported(resolver_addr, chain_id)
    }

    /// Check if resolver is authorized by factory
    public fun is_resolver_authorized_by_factory(factory_addr: address, resolver: address): bool {
        escrow_factory::is_resolver_authorized(factory_addr, resolver)
    }

    /// Check if destination escrow can withdraw
    public fun can_withdraw_destination(escrow_address: address): bool {
        escrow_dst::can_withdraw(escrow_address)
    }

    /// Check if destination escrow can cancel
    public fun can_cancel_destination(escrow_address: address): bool {
        escrow_dst::can_cancel(escrow_address)
    }

    /// Check if source escrow can withdraw
    public fun can_withdraw_source(escrow_address: address): bool {
        escrow_src::can_withdraw(escrow_address)
    }

    /// Check if source escrow can cancel
    public fun can_cancel_source(escrow_address: address): bool {
        escrow_src::can_cancel(escrow_address)
    }
}