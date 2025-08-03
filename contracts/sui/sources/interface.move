/// Interface module for MoveOrbit Cross-Chain Swap Protocol
/// Contains all entry functions for external interaction with the protocol
module cross_chain_swap::interface {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Coin};
    use sui::clock::Clock;
    use sui::sui::SUI;
    use std::vector;

    use cross_chain_swap::escrow_factory::{Self, EscrowFactory, ResolverRegistry};
    use cross_chain_swap::escrow_dst::{Self, EscrowDst};
    use cross_chain_swap::escrow_src::{Self, EscrowSrc};
    use cross_chain_swap::evm_order::{Self, EVMOrder, CrossChainOrder};
    use cross_chain_swap::time_locks::{Self, TimeLocks};
    use cross_chain_swap::resolver::{Self, Resolver};

    // Error codes
    const E_UNAUTHORIZED: u64 = 1;
    const E_INVALID_PARAMETERS: u64 = 2;

    

    /// Create and share a new resolver for cross-chain operations
    entry fun create_resolver(
        factory_address: address,
        ctx: &mut TxContext
    ) {
        resolver::create_shared_resolver(factory_address, ctx);
    }

    /// Register resolver for multiple EVM chains
    entry fun register_multi_vm_resolver(
        resolver: &mut Resolver,
        evm_chain_ids: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        ctx: &mut TxContext
    ) {
        resolver::register_multi_vm(resolver, evm_chain_ids, evm_addresses, ctx);
    }

    /// Register a multi-VM resolver in the factory registry
    entry fun register_resolver_in_factory(
        registry: &mut ResolverRegistry,
        sui_resolver: address,
        evm_chain_ids: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        ctx: &mut TxContext
    ) {
        escrow_factory::register_resolver(
            registry,
            sui_resolver,
            evm_chain_ids,
            evm_addresses,
            ctx
        );
    }

    /// Authorize a resolver to create escrows
    entry fun authorize_resolver(
        factory: &mut EscrowFactory,
        resolver: address,
        ctx: &mut TxContext
    ) {
        escrow_factory::authorize_resolver(factory, resolver, ctx);
    }

    /// Submit order and secret for cross-chain processing
    entry fun submit_order_and_secret(
        resolver: &mut Resolver,
        order_hash: vector<u8>,
        secret: vector<u8>,
        ctx: &mut TxContext
    ) {
        resolver::submit_order_and_secret(resolver, order_hash, secret, ctx);
    }

    /// Process EVM to SUI cross-chain swap
    entry fun process_evm_to_sui_swap<T>(
        resolver: &mut Resolver,
        factory: &mut EscrowFactory,
        // EVM Order parameters
        salt: u256,
        maker: vector<u8>,
        receiver: vector<u8>,
        maker_asset: vector<u8>,
        taker_asset: vector<u8>,
        making_amount: u256,
        taking_amount: u256,
        maker_traits: u256,
        // Cross-chain parameters
        order_hash: vector<u8>,
        signature_r: vector<u8>,
        signature_vs: vector<u8>,
        evm_chain_id: u256,
        sui_chain_id: u256,
        // Assets
        destination_tokens: Coin<T>,
        safety_deposit: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Create EVM order
        let evm_order = evm_order::new_evm_order(
            salt,
            maker,
            receiver,
            maker_asset,
            taker_asset,
            making_amount,
            taking_amount,
            maker_traits
        );

        resolver::process_evm_to_sui_swap(
            resolver,
            factory,
            evm_order,
            order_hash,
            signature_r,
            signature_vs,
            evm_chain_id,
            sui_chain_id,
            destination_tokens,
            safety_deposit,
            clock,
            ctx
        );
    }

    /// Complete cross-chain swap by revealing secret
    entry fun complete_swap_with_secret<T>(
        resolver: &mut Resolver,
        escrow: &mut EscrowDst<T>,
        order_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        resolver::complete_swap_with_secret(
            resolver,
            escrow,
            order_hash,
            clock,
            ctx
        );
    }

    /// Create a standard SUI-native destination escrow
    entry fun create_destination_escrow<T>(
        factory: &EscrowFactory,
        order_hash: vector<u8>,
        secret: vector<u8>,
        maker: address,
        taker: address,
        amount: u64,
        safety_deposit: u64,
        // Timelock parameters
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
        dst_public_cancellation: u32,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
        // Assets
        locked_coin: Coin<T>,
        safety_coin: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let secret_hash = sui::hash::keccak256(&secret);
        let timelocks = time_locks::new(
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
            dst_public_cancellation,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
        );

        escrow_factory::create_dst_escrow(
            factory,
            order_hash,
            secret_hash,
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

    /// Create a standard SUI-native source escrow
    entry fun create_source_escrow<T>(
        factory: &EscrowFactory,
        order_hash: vector<u8>,
        secret: vector<u8>,
        maker: address,
        taker: address,
        amount: u64,
        safety_deposit: u64,
        // Timelock parameters
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
        dst_public_cancellation: u32,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
        // Assets
        locked_coin: Coin<T>,
        safety_coin: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let secret_hash = sui::hash::keccak256(&secret);
        let timelocks = time_locks::new(
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
            dst_public_cancellation,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
        );

        escrow_factory::create_src_escrow(
            factory,
            order_hash,
            secret_hash,
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

    /// Withdraw from destination escrow using secret
    entry fun withdraw_from_destination<T>(
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        escrow_dst::withdraw(escrow, secret, clock, ctx);
    }

    /// Withdraw from destination escrow to specific target
    entry fun withdraw_to_target<T>(
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        target: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        escrow_dst::withdraw_to(escrow, secret, target, clock, ctx);
    }

    /// Cancel destination escrow (after timeout)
    entry fun cancel_destination_escrow<T>(
        escrow: &mut EscrowDst<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        escrow_dst::cancel(escrow, clock, ctx);
    }

    /// Withdraw from source escrow using secret
    entry fun withdraw_from_source<T>(
        escrow: &mut EscrowSrc<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        escrow_src::withdraw(escrow, secret, clock, ctx);
    }

    /// Cancel source escrow (after timeout)
    entry fun cancel_source_escrow<T>(
        escrow: &mut EscrowSrc<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        escrow_src::cancel(escrow, clock, ctx);
    }

    /// Emergency functions for resolver owner

    /// Emergency cancel swap and return funds
    entry fun emergency_cancel_swap<T>(
        resolver: &mut Resolver,
        escrow: &mut EscrowDst<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        resolver::cancel_swap(resolver, escrow, clock, ctx);
    }

    /// Emergency withdraw for specific target
    entry fun emergency_withdraw_to<T>(
        resolver: &mut Resolver,
        escrow: &mut EscrowDst<T>,
        order_hash: vector<u8>,
        target: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        resolver::emergency_withdraw_to(
            resolver,
            escrow,
            order_hash,
            target,
            clock,
            ctx
        );
    }

    /// Authorize operator to submit orders
    entry fun authorize_operator(
        resolver: &mut Resolver,
        operator: address,
        ctx: &mut TxContext
    ) {
        resolver::authorize_operator(resolver, operator, ctx);
    }

    /// Revoke operator authorization
    entry fun revoke_operator(
        resolver: &mut Resolver,
        operator: address,
        ctx: &mut TxContext
    ) {
        resolver::revoke_operator(resolver, operator, ctx);
    }

    /// Transfer resolver ownership
    entry fun transfer_resolver_ownership(
        resolver: &mut Resolver,
        new_owner: address,
        ctx: &mut TxContext
    ) {
        resolver::transfer_ownership(resolver, new_owner, ctx);
    }

    /// Update factory address in resolver
    entry fun update_resolver_factory(
        resolver: &mut Resolver,
        new_factory: address,
        ctx: &mut TxContext
    ) {
        resolver::update_factory(resolver, new_factory, ctx);
    }

    /// Emergency extract stuck tokens from resolver
    entry fun emergency_extract_tokens<T>(
        resolver: &Resolver,
        token: Coin<T>,
        recipient: address,
        ctx: &mut TxContext
    ) {
        resolver::emergency_extract_tokens(resolver, token, recipient, ctx);
    }

    /// Factory admin functions

    /// Update rescue delays in factory
    entry fun update_rescue_delays(
        factory: &mut EscrowFactory,
        new_src_delay: u64,
        new_dst_delay: u64,
        ctx: &mut TxContext
    ) {
        escrow_factory::update_rescue_delays(
            factory,
            new_src_delay,
            new_dst_delay,
            ctx
        );
    }

    /// Transfer factory admin
    entry fun transfer_factory_admin(
        factory: &mut EscrowFactory,
        new_admin: address,
        ctx: &mut TxContext
    ) {
        escrow_factory::transfer_admin(factory, new_admin, ctx);
    }
 

    // View functions (no entry needed for read-only functions)

    /// Check if order has been processed
    public fun is_order_processed_by_resolver(resolver: &Resolver, order_hash: vector<u8>): bool {
        resolver::is_order_processed(resolver, order_hash)
    }

    /// Check if order has been processed by factory
    public fun is_order_processed_by_factory(factory: &EscrowFactory, order_hash: vector<u8>): bool {
        escrow_factory::is_order_processed(factory, order_hash)
    }

    /// Check if resolver has secret for order
    public fun resolver_has_secret(resolver: &Resolver, order_hash: vector<u8>): bool {
        resolver::has_secret(resolver, order_hash)
    }

    /// Check if operator is authorized
    public fun is_operator_authorized(resolver: &Resolver, operator: address): bool {
        resolver::is_operator_authorized(resolver, operator)
    }

    /// Check if chain is supported by resolver
    public fun is_chain_supported(resolver: &Resolver, chain_id: u256): bool {
        resolver::is_chain_supported(resolver, chain_id)
    }

    /// Check if resolver is authorized by factory
    public fun is_resolver_authorized_by_factory(factory: &EscrowFactory, resolver: address): bool {
        escrow_factory::is_resolver_authorized(factory, resolver)
    }
}
