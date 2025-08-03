/// Source escrow for APTOS cross-chain swaps
module cross_chain_swap_addr::escrow_src {
    use std::signer;
    use std::error;
    use std::vector;
    use std::option::{Self, Option};
    use aptos_framework::object::{Self, Object, ConstructorRef, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_std::aptos_hash;

    use cross_chain_swap_addr::time_locks::{Self, TimeLocks};

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_ESCROW_COMPLETED: u64 = 2;
    const E_INVALID_SECRET: u64 = 3;
    const E_TIMELOCK_NOT_REACHED: u64 = 4;
    const E_INSUFFICIENT_BALANCE: u64 = 5;

    /// Source escrow resource
    struct EscrowSrc has key {
        /// Order identification
        order_hash: vector<u8>,
        secret_hash: vector<u8>,
        
        /// Parties
        maker: address,  // Provider of tokens, receives safety deposit back
        taker: address,  // Recipient of tokens after secret reveal
        
        /// Asset information
        locked_store: Object<FungibleStore>, // Store for locked tokens
        safety_store: Object<FungibleStore>, // Store for safety deposit (APT)
        locked_amount: u64,
        safety_amount: u64,
        
        /// Time constraints
        timelocks: TimeLocks,
        
        /// State tracking
        completed: bool,
        is_cross_chain: bool,
        
        /// Cross-chain information (optional)
        evm_dst_chain_id: Option<u256>,
        evm_taker: Option<vector<u8>>, // 20-byte EVM address
        
        /// Extension reference for object operations
        extend_ref: ExtendRef,
    }

    /// Event emitted when source escrow is created
    #[event]
    struct SrcEscrowCreated has drop, store {
        escrow_address: address,
        order_hash: vector<u8>,
        maker: address,
        taker: address,
        locked_amount: u64,
        safety_amount: u64,
        is_cross_chain: bool,
    }

    /// Event emitted when tokens are withdrawn from source
    #[event]
    struct SrcTokensWithdrawn has drop, store {
        escrow_address: address,
        order_hash: vector<u8>,
        recipient: address,
        secret_revealed: bool,
    }

    /// Event emitted when source escrow is cancelled
    #[event]
    struct SrcEscrowCancelled has drop, store {
        escrow_address: address,
        order_hash: vector<u8>,
        cancelled_by: address,
    }

    /// Create a standard source escrow
    public fun create_escrow(
        creator: &signer,
        order_hash: vector<u8>,
        secret_hash: vector<u8>,
        maker: address,
        taker: address,
        locked_asset: FungibleAsset,
        safety_deposit: FungibleAsset,
        timelocks: TimeLocks,
    ): address {
        let locked_amount = fungible_asset::amount(&locked_asset);
        let safety_amount = fungible_asset::amount(&safety_deposit);
        
        assert!(locked_amount > 0, error::invalid_argument(E_INSUFFICIENT_BALANCE));
        assert!(safety_amount > 0, error::invalid_argument(E_INSUFFICIENT_BALANCE));

        // Create object for escrow
        let constructor_ref = object::create_object(@cross_chain_swap_addr);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);
        let escrow_address = signer::address_of(&object_signer);

        // Create fungible stores
        let locked_store = fungible_asset::create_store(&constructor_ref, fungible_asset::asset_metadata(&locked_asset));
        let safety_store = fungible_asset::create_store(&constructor_ref, fungible_asset::asset_metadata(&safety_deposit));

        // Deposit assets
        fungible_asset::deposit(locked_store, locked_asset);
        fungible_asset::deposit(safety_store, safety_deposit);

        // Set deployment time
        let final_timelocks = timelocks;
        time_locks::set_deployed_at(&mut final_timelocks, timestamp::now_seconds());

        // Create escrow resource
        let escrow = EscrowSrc {
            order_hash,
            secret_hash,
            maker,
            taker,
            locked_store,
            safety_store,
            locked_amount,
            safety_amount,
            timelocks: final_timelocks,
            completed: false,
            is_cross_chain: false,
            evm_dst_chain_id: option::none(),
            evm_taker: option::none(),
            extend_ref,
        };

        move_to(&object_signer, escrow);

        event::emit(SrcEscrowCreated {
            escrow_address,
            order_hash,
            maker,
            taker,
            locked_amount,
            safety_amount,
            is_cross_chain: false,
        });

        escrow_address
    }

    /// Create a cross-chain source escrow for EVM destination
    public fun create_escrow_with_evm_destination(
        creator: &signer,
        order_hash: vector<u8>,
        secret_hash: vector<u8>,
        aptos_maker: address,
        aptos_taker: address,
        evm_dst_chain_id: u256,
        evm_taker: vector<u8>, // 20-byte EVM taker address
        locked_asset: FungibleAsset,
        safety_deposit: FungibleAsset,
        timelocks: TimeLocks,
    ): address {
        let locked_amount = fungible_asset::amount(&locked_asset);
        let safety_amount = fungible_asset::amount(&safety_deposit);
        
        assert!(locked_amount > 0, error::invalid_argument(E_INSUFFICIENT_BALANCE));
        assert!(safety_amount > 0, error::invalid_argument(E_INSUFFICIENT_BALANCE));
        assert!(vector::length(&evm_taker) == 20, error::invalid_argument(E_INVALID_SECRET));

        // Create object for escrow
        let constructor_ref = object::create_object(@cross_chain_swap_addr);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);
        let escrow_address = signer::address_of(&object_signer);

        // Create fungible stores
        let locked_store = fungible_asset::create_store(&constructor_ref, fungible_asset::asset_metadata(&locked_asset));
        let safety_store = fungible_asset::create_store(&constructor_ref, fungible_asset::asset_metadata(&safety_deposit));

        // Deposit assets
        fungible_asset::deposit(locked_store, locked_asset);
        fungible_asset::deposit(safety_store, safety_deposit);

        // Set deployment time
        let final_timelocks = timelocks;
        time_locks::set_deployed_at(&mut final_timelocks, timestamp::now_seconds());

        // Create cross-chain escrow resource
        let escrow = EscrowSrc {
            order_hash,
            secret_hash,
            maker: aptos_maker,
            taker: aptos_taker,
            locked_store,
            safety_store,
            locked_amount,
            safety_amount,
            timelocks: final_timelocks,
            completed: false,
            is_cross_chain: true,
            evm_dst_chain_id: option::some(evm_dst_chain_id),
            evm_taker: option::some(evm_taker),
            extend_ref,
        };

        move_to(&object_signer, escrow);

        event::emit(SrcEscrowCreated {
            escrow_address,
            order_hash,
            maker: aptos_maker,
            taker: aptos_taker,
            locked_amount,
            safety_amount,
            is_cross_chain: true,
        });

        escrow_address
    }

    /// Withdraw locked tokens using the secret (taker calls this after revealing secret on destination)
    public fun withdraw(caller: &signer, escrow_address: address, secret: vector<u8>) acquires EscrowSrc {
        let escrow = borrow_global_mut<EscrowSrc>(escrow_address);
        let caller_addr = signer::address_of(caller);
        
        assert!(!escrow.completed, error::permission_denied(E_ESCROW_COMPLETED));
        assert!(time_locks::can_withdraw_src(&escrow.timelocks), error::permission_denied(E_TIMELOCK_NOT_REACHED));
        
        // Verify secret
        let computed_hash = aptos_hash::keccak256(secret);
        assert!(computed_hash == escrow.secret_hash, error::invalid_argument(E_INVALID_SECRET));

        // Mark as completed
        escrow.completed = true;

        // Get object signer for transfers
        let object_signer = object::generate_signer_for_extending(&escrow.extend_ref);

        // Transfer locked tokens to taker
        let locked_asset = fungible_asset::withdraw(&object_signer, escrow.locked_store, escrow.locked_amount);
        primary_fungible_store::deposit(escrow.taker, locked_asset);

        // Return safety deposit to maker
        let safety_asset = fungible_asset::withdraw(&object_signer, escrow.safety_store, escrow.safety_amount);
        primary_fungible_store::deposit(escrow.maker, safety_asset);

        event::emit(SrcTokensWithdrawn {
            escrow_address,
            order_hash: escrow.order_hash,
            recipient: escrow.taker,
            secret_revealed: true,
        });
    }

    /// Cancel source escrow after timeout (returns funds to maker)
    public fun cancel(caller: &signer, escrow_address: address) acquires EscrowSrc {
        let escrow = borrow_global_mut<EscrowSrc>(escrow_address);
        let caller_addr = signer::address_of(caller);
        
        assert!(!escrow.completed, error::permission_denied(E_ESCROW_COMPLETED));
        assert!(time_locks::can_cancel_src(&escrow.timelocks), error::permission_denied(E_TIMELOCK_NOT_REACHED));

        // Mark as completed
        escrow.completed = true;

        // Get object signer for transfers
        let object_signer = object::generate_signer_for_extending(&escrow.extend_ref);

        // Return locked tokens to maker (timeout cancellation)
        let locked_asset = fungible_asset::withdraw(&object_signer, escrow.locked_store, escrow.locked_amount);
        primary_fungible_store::deposit(escrow.maker, locked_asset);

        // Return safety deposit to maker
        let safety_asset = fungible_asset::withdraw(&object_signer, escrow.safety_store, escrow.safety_amount);
        primary_fungible_store::deposit(escrow.maker, safety_asset);

        event::emit(SrcEscrowCancelled {
            escrow_address,
            order_hash: escrow.order_hash,
            cancelled_by: caller_addr,
        });
    }

    /// Check if withdrawal is allowed
    public fun can_withdraw(escrow_address: address): bool acquires EscrowSrc {
        let escrow = borrow_global<EscrowSrc>(escrow_address);
        !escrow.completed && time_locks::can_withdraw_src(&escrow.timelocks)
    }

    /// Check if cancellation is allowed
    public fun can_cancel(escrow_address: address): bool acquires EscrowSrc {
        let escrow = borrow_global<EscrowSrc>(escrow_address);
        !escrow.completed && time_locks::can_cancel_src(&escrow.timelocks)
    }

    /// Verify secret without revealing it
    public fun verify_secret(escrow_address: address, secret: &vector<u8>): bool acquires EscrowSrc {
        let escrow = borrow_global<EscrowSrc>(escrow_address);
        let computed_hash = aptos_hash::keccak256(*secret);
        computed_hash == escrow.secret_hash
    }

    // Getter functions
    public fun get_order_hash(escrow_address: address): vector<u8> acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).order_hash
    }

    public fun get_maker(escrow_address: address): address acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).maker
    }

    public fun get_taker(escrow_address: address): address acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).taker
    }

    public fun get_locked_amount(escrow_address: address): u64 acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).locked_amount
    }

    public fun get_safety_amount(escrow_address: address): u64 acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).safety_amount
    }

    public fun is_completed(escrow_address: address): bool acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).completed
    }

    public fun is_cross_chain(escrow_address: address): bool acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).is_cross_chain
    }

    public fun get_evm_dst_chain_id(escrow_address: address): Option<u256> acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).evm_dst_chain_id
    }

    public fun get_evm_taker(escrow_address: address): Option<vector<u8>> acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).evm_taker
    }

    public fun get_secret_hash(escrow_address: address): vector<u8> acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).secret_hash
    }

    public fun get_timelocks(escrow_address: address): TimeLocks acquires EscrowSrc {
        borrow_global<EscrowSrc>(escrow_address).timelocks
    }

    /// Get current balance amounts in the stores
    public fun get_current_balances(escrow_address: address): (u64, u64) acquires EscrowSrc {
        let escrow = borrow_global<EscrowSrc>(escrow_address);
        let locked_balance = fungible_asset::balance(escrow.locked_store);
        let safety_balance = fungible_asset::balance(escrow.safety_store);
        (locked_balance, safety_balance)
    }

    #[test_only]
    public fun create_test_src_escrow_address(): address {
        @0x5678
    }
}
