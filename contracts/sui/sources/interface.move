module cross_chain_swap::interface {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::sui::SUI;
    use sui::hash;
    
    use cross_chain_swap::escrow_factory::{Self, EscrowFactory};
    use cross_chain_swap::escrow_dst::{Self, EscrowDst};
    use cross_chain_swap::resolver::{Self, Resolver};
    use cross_chain_swap::evm_order::{Self, EVMOrder, CrossChainOrder};
    use cross_chain_swap::time_locks::{Self, TimeLocks};

    // Error codes
    const E_UNAUTHORIZED: u64 = 1;
    const E_INVALID_SECRET: u64 = 2;
    const E_ORDER_NOT_FOUND: u64 = 3;

    /// Initialize the cross-chain swap protocol
    public fun initialize_protocol(ctx: &mut TxContext) {
        // Create and share factory
        escrow_factory::test_init(ctx);
    }

    /// Authorize a resolver to create escrows
    public fun authorize_resolver(
        factory: &mut EscrowFactory,
        resolver: address,
        ctx: &mut TxContext
    ) {
        escrow_factory::authorize_resolver(factory, resolver, ctx);
    }

    /// Register multi-VM resolver
    public fun register_multi_vm_resolver(
        resolver: &mut Resolver,
        evm_chain_ids: vector<u256>,
        evm_addresses: vector<vector<u8>>,
        ctx: &mut TxContext
    ) {
        resolver::register_multi_vm(resolver, evm_chain_ids, evm_addresses, ctx);
    }

    /// Process EVM to SUI cross-chain swap
    public fun process_evm_to_sui_swap<T>(
        resolver: &mut Resolver,
        factory: &mut EscrowFactory,
        // EVM order parameters
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
        // Create EVM order structure
        let evm_order = evm_order::new_evm_order(
            salt,
            maker,
            receiver,
            maker_asset,
            taker_asset,
            making_amount,
            taking_amount,
            maker_traits,
        );

        // Process the swap
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

    /// Complete swap with secret reveal
    public fun complete_swap_with_secret<T>(
        resolver: &mut Resolver,
        escrow: &mut EscrowDst<T>,
        order_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        resolver::complete_swap_with_secret(resolver, escrow, order_hash, clock, ctx);
    }

    /// Create destination escrow for testing
    public fun create_destination_escrow<T>(
        factory: &mut EscrowFactory,
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
        // Create timelocks
        let timelocks = time_locks::new(
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
            dst_public_cancellation,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
        );

        // Calculate secret hash
        let secret_hash = hash::keccak256(&secret);

        // Create destination escrow
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

    // === View Functions === //

    /// Check if order has been processed by factory
    public fun is_order_processed(factory: &EscrowFactory, order_hash: vector<u8>): bool {
        escrow_factory::is_order_processed(factory, order_hash)
    }

    /// Check if resolver is authorized
    public fun is_resolver_authorized(factory: &EscrowFactory, resolver: address): bool {
        escrow_factory::is_resolver_authorized(factory, resolver)
    }

    /// Check if resolver has secret for order
    public fun has_secret(resolver: &Resolver, order_hash: vector<u8>): bool {
        resolver::has_secret(resolver, order_hash)
    }

    /// Get secret hash for order (if exists)
    public fun get_secret_hash(resolver: &Resolver, order_hash: vector<u8>): vector<u8> {
        resolver::get_secret_hash(resolver, order_hash)
    }

    /// Check if EVM chain is supported by resolver
    public fun is_chain_supported(resolver: &Resolver, chain_id: u256): bool {
        resolver::is_chain_supported(resolver, chain_id)
    }

    /// Get EVM resolver address for chain
    public fun get_evm_resolver(resolver: &Resolver, chain_id: u256): vector<u8> {
        resolver::get_evm_resolver(resolver, chain_id)
    }

    /// Get all supported chain IDs
    public fun get_supported_chains(resolver: &Resolver): &vector<u256> {
        resolver::get_supported_chains(resolver)
    }

    /// Get resolver owner
    public fun get_resolver_owner(resolver: &Resolver): address {
        resolver::get_owner(resolver)
    }

    /// Get factory address from resolver
    public fun get_resolver_factory(resolver: &Resolver): address {
        resolver::get_factory(resolver)
    }

    // === Testing Functions === //

    #[test_only]
    public fun create_test_resolver(ctx: &mut TxContext): Resolver {
        resolver::create_test_resolver(ctx)
    }

    #[test_only]
    public fun add_test_secret(
        resolver: &mut Resolver,
        order_hash: vector<u8>,
        secret: vector<u8>
    ) {
        resolver::add_test_secret(resolver, order_hash, secret)
    }
}
