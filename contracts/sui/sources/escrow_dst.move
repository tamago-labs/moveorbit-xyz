module cross_chain_swap::escrow_dst {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::hash;
    use sui::sui::SUI;
    use cross_chain_swap::time_locks::{Self, TimeLocks};
    use cross_chain_swap::evm_order;

    const E_INVALID_CALLER: u64 = 1;
    const E_INVALID_SECRET: u64 = 2;
    const E_INVALID_WITHDRAWAL_TIME: u64 = 3;
    const E_INVALID_CANCELLATION_TIME: u64 = 4;
    const E_ESCROW_ALREADY_COMPLETED: u64 = 5;
    const E_INSUFFICIENT_BALANCE: u64 = 6;

    /// Enhanced destination escrow with EVM order support using Balance for efficiency
    public struct EscrowDst<phantom T> has key {
        id: UID,
        order_hash: vector<u8>,        // EVM order hash or SUI native hash
        hashlock: vector<u8>,          // Secret hash (keccak256)
        maker: address,                // SUI address of maker
        taker: address,                // SUI address of taker (resolver)
        amount: u64,                   // Token amount to be transferred
        safety_deposit: u64,           // Safety deposit amount
        timelocks: TimeLocks,          // Withdrawal and cancellation times
        locked_balance: Balance<T>,    // Locked tokens using Balance for efficiency
        safety_balance: Balance<SUI>,  // Safety deposit in SUI using Balance
        is_cross_chain: bool,          // Flag for cross-chain vs native
        completed: bool,               // Prevent double completion
        evm_order_hash: vector<u8>,    // Original EVM order hash for cross-chain
    }

    /// Event for escrow creation
    public struct EscrowCreated has copy, drop {
        escrow_id: object::ID,
        order_hash: vector<u8>,
        maker: address,
        taker: address,
        amount: u64,
        is_cross_chain: bool,
        evm_order_hash: vector<u8>,
    }

    /// Event for successful withdrawal
    public struct EscrowWithdrawn has copy, drop {
        escrow_id: object::ID,
        order_hash: vector<u8>,
        secret_hash: vector<u8>,
        withdrawer: address,
        amount: u64,
    }

    /// Event for escrow cancellation
    public struct EscrowCancelled has copy, drop {
        escrow_id: object::ID,
        order_hash: vector<u8>,
        canceller: address,
        reason: u8, // 1=timeout, 2=manual
    }

    /// Create escrow with EVM order compatibility using Balance
    public fun create_escrow_with_evm_order<T>(
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
    ): object::ID {
        // Validate inputs
        assert!(coin::value(&locked_coin) >= amount, E_INSUFFICIENT_BALANCE);
        assert!(coin::value(&safety_coin) >= safety_deposit, E_INSUFFICIENT_BALANCE);
        assert!(vector::length(&hashlock) == 32, E_INVALID_SECRET);

        let mut timelocks_mut = timelocks;
        time_locks::set_deployed_at(&mut timelocks_mut, clock::timestamp_ms(clock) / 1000);
        
        // Convert coins to balances for efficient storage
        let locked_balance = coin::into_balance(locked_coin);
        let safety_balance = coin::into_balance(safety_coin);
        
        let escrow = EscrowDst {
            id: object::new(ctx),
            order_hash,
            hashlock,
            maker,
            taker,
            amount,
            safety_deposit,
            timelocks: timelocks_mut,
            locked_balance,
            safety_balance,
            is_cross_chain: true,
            completed: false,
            evm_order_hash: order_hash, // For cross-chain, this is the EVM order hash
        };

        let escrow_id = object::id(&escrow);
        
        sui::event::emit(EscrowCreated {
            escrow_id,
            order_hash: escrow.order_hash,
            maker,
            taker,
            amount,
            is_cross_chain: true,
            evm_order_hash: escrow.evm_order_hash,
        });

        transfer::share_object(escrow);
        escrow_id
    }

    /// Create traditional SUI-native escrow (backward compatibility) using Balance
    public fun create_escrow<T>(
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
        assert!(coin::value(&locked_coin) >= amount, E_INSUFFICIENT_BALANCE);
        assert!(coin::value(&safety_coin) >= safety_deposit, E_INSUFFICIENT_BALANCE);

        let mut timelocks_mut = timelocks;
        time_locks::set_deployed_at(&mut timelocks_mut, clock::timestamp_ms(clock) / 1000);
        
        // Convert coins to balances for efficient storage
        let locked_balance = coin::into_balance(locked_coin);
        let safety_balance = coin::into_balance(safety_coin);
        
        let escrow = EscrowDst {
            id: object::new(ctx),
            order_hash,
            hashlock,
            maker,
            taker,
            amount,
            safety_deposit,
            timelocks: timelocks_mut,
            locked_balance,
            safety_balance,
            is_cross_chain: false,
            completed: false,
            evm_order_hash: vector::empty<u8>(),
        };

        let escrow_id = object::id(&escrow);
        
        sui::event::emit(EscrowCreated {
            escrow_id,
            order_hash: escrow.order_hash,
            maker,
            taker,
            amount,
            is_cross_chain: false,
            evm_order_hash: vector::empty<u8>(),
        });

        transfer::share_object(escrow);
    }

    /// Withdraw tokens using secret (taker only during withdrawal window)
    public fun withdraw<T>(
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == escrow.taker, E_INVALID_CALLER);
        assert!(!escrow.completed, E_ESCROW_ALREADY_COMPLETED);
        
        let now = clock::timestamp_ms(clock) / 1000;
        assert!(now >= time_locks::dst_withdrawal_start(&escrow.timelocks), E_INVALID_WITHDRAWAL_TIME);
        assert!(now < time_locks::dst_cancellation_start(&escrow.timelocks), E_INVALID_WITHDRAWAL_TIME);
        
        verify_secret(&secret, &escrow.hashlock);
        
        // Transfer locked tokens to maker
        let locked_withdrawn = balance::split(&mut escrow.locked_balance, escrow.amount);
        let locked_coin = coin::from_balance(locked_withdrawn, ctx);
        transfer::public_transfer(locked_coin, escrow.maker);
        
        // Transfer safety deposit to taker
        let safety_withdrawn = balance::split(&mut escrow.safety_balance, escrow.safety_deposit);
        let safety_coin = coin::from_balance(safety_withdrawn, ctx);
        transfer::public_transfer(safety_coin, tx_context::sender(ctx));
        
        escrow.completed = true;

        sui::event::emit(EscrowWithdrawn {
            escrow_id: object::id(escrow),
            order_hash: escrow.order_hash,
            secret_hash: escrow.hashlock,
            withdrawer: tx_context::sender(ctx),
            amount: escrow.amount,
        });

        // Emit EVM-compatible event if cross-chain
        if (escrow.is_cross_chain) {
            evm_order::emit_order_processed(escrow.evm_order_hash, true, tx_context::sender(ctx));
        };
    }

    /// Withdraw to specific address (taker only during withdrawal window)
    public fun withdraw_to<T>(
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        target: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == escrow.taker, E_INVALID_CALLER);
        assert!(!escrow.completed, E_ESCROW_ALREADY_COMPLETED);
        
        let now = clock::timestamp_ms(clock) / 1000;
        assert!(now >= time_locks::dst_withdrawal_start(&escrow.timelocks), E_INVALID_WITHDRAWAL_TIME);
        assert!(now < time_locks::dst_cancellation_start(&escrow.timelocks), E_INVALID_WITHDRAWAL_TIME);
        
        verify_secret(&secret, &escrow.hashlock);
        
        // Transfer locked tokens to specified target
        let locked_withdrawn = balance::split(&mut escrow.locked_balance, escrow.amount);
        let locked_coin = coin::from_balance(locked_withdrawn, ctx);
        transfer::public_transfer(locked_coin, target);
        
        // Transfer safety deposit to taker
        let safety_withdrawn = balance::split(&mut escrow.safety_balance, escrow.safety_deposit);
        let safety_coin = coin::from_balance(safety_withdrawn, ctx);
        transfer::public_transfer(safety_coin, tx_context::sender(ctx));
        
        escrow.completed = true;

        sui::event::emit(EscrowWithdrawn {
            escrow_id: object::id(escrow),
            order_hash: escrow.order_hash,
            secret_hash: escrow.hashlock,
            withdrawer: tx_context::sender(ctx),
            amount: escrow.amount,
        });
    }

    /// Public withdrawal (anyone can call during public withdrawal window)
    public fun public_withdraw<T>(
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!escrow.completed, E_ESCROW_ALREADY_COMPLETED);
        
        let now = clock::timestamp_ms(clock) / 1000;
        assert!(now >= time_locks::dst_pub_withdrawal_start(&escrow.timelocks), E_INVALID_WITHDRAWAL_TIME);
        assert!(now < time_locks::dst_cancellation_start(&escrow.timelocks), E_INVALID_WITHDRAWAL_TIME);
        
        verify_secret(&secret, &escrow.hashlock);
        
        // Transfer locked tokens to maker
        let locked_withdrawn = balance::split(&mut escrow.locked_balance, escrow.amount);
        let locked_coin = coin::from_balance(locked_withdrawn, ctx);
        transfer::public_transfer(locked_coin, escrow.maker);
        
        // Transfer safety deposit to caller (incentive for public withdrawal)
        let safety_withdrawn = balance::split(&mut escrow.safety_balance, escrow.safety_deposit);
        let safety_coin = coin::from_balance(safety_withdrawn, ctx);
        transfer::public_transfer(safety_coin, tx_context::sender(ctx));
        
        escrow.completed = true;

        sui::event::emit(EscrowWithdrawn {
            escrow_id: object::id(escrow),
            order_hash: escrow.order_hash,
            secret_hash: escrow.hashlock,
            withdrawer: tx_context::sender(ctx),
            amount: escrow.amount,
        });
    }

    /// Cancel escrow and return funds to taker
    public fun cancel<T>(
        escrow: &mut EscrowDst<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == escrow.taker, E_INVALID_CALLER);
        assert!(!escrow.completed, E_ESCROW_ALREADY_COMPLETED);
        
        let now = clock::timestamp_ms(clock) / 1000;
        assert!(now >= time_locks::dst_cancellation_start(&escrow.timelocks), E_INVALID_CANCELLATION_TIME);
        
        // Return locked tokens to taker
        let locked_withdrawn = balance::split(&mut escrow.locked_balance, escrow.amount);
        let locked_coin = coin::from_balance(locked_withdrawn, ctx);
        transfer::public_transfer(locked_coin, escrow.taker);
        
        // Return safety deposit to taker
        let safety_withdrawn = balance::split(&mut escrow.safety_balance, escrow.safety_deposit);
        let safety_coin = coin::from_balance(safety_withdrawn, ctx);
        transfer::public_transfer(safety_coin, tx_context::sender(ctx));
        
        escrow.completed = true;

        sui::event::emit(EscrowCancelled {
            escrow_id: object::id(escrow),
            order_hash: escrow.order_hash,
            canceller: tx_context::sender(ctx),
            reason: 1, // timeout
        });

        // Emit EVM-compatible event if cross-chain
        if (escrow.is_cross_chain) {
            evm_order::emit_order_processed(escrow.evm_order_hash, false, tx_context::sender(ctx));
        };
    }

    /// Manual cancel by authorized party (before timeout)
    public fun emergency_cancel<T>(
        escrow: &mut EscrowDst<T>,
        ctx: &mut TxContext
    ) {
        // Only taker can manually cancel
        assert!(tx_context::sender(ctx) == escrow.taker, E_INVALID_CALLER);
        assert!(!escrow.completed, E_ESCROW_ALREADY_COMPLETED);
        
        // Return all funds to taker
        let locked_withdrawn = balance::split(&mut escrow.locked_balance, escrow.amount);
        let locked_coin = coin::from_balance(locked_withdrawn, ctx);
        transfer::public_transfer(locked_coin, escrow.taker);
        
        let safety_withdrawn = balance::split(&mut escrow.safety_balance, escrow.safety_deposit);
        let safety_coin = coin::from_balance(safety_withdrawn, ctx);
        transfer::public_transfer(safety_coin, escrow.taker);
        
        escrow.completed = true;

        sui::event::emit(EscrowCancelled {
            escrow_id: object::id(escrow),
            order_hash: escrow.order_hash,
            canceller: tx_context::sender(ctx),
            reason: 2, // manual
        });
    }

    /// Verify secret against hashlock using keccak256
    fun verify_secret(secret: &vector<u8>, hashlock: &vector<u8>) {
        let computed_hash = hash::keccak256(secret);
        assert!(computed_hash == *hashlock, E_INVALID_SECRET);
    }

    // Getter functions
    public fun get_hashlock<T>(escrow: &EscrowDst<T>): vector<u8> { escrow.hashlock }
    public fun get_maker<T>(escrow: &EscrowDst<T>): address { escrow.maker }
    public fun get_taker<T>(escrow: &EscrowDst<T>): address { escrow.taker }
    public fun get_amount<T>(escrow: &EscrowDst<T>): u64 { escrow.amount }
    public fun get_safety_deposit<T>(escrow: &EscrowDst<T>): u64 { escrow.safety_deposit }
    public fun is_completed<T>(escrow: &EscrowDst<T>): bool { escrow.completed }
    public fun is_cross_chain<T>(escrow: &EscrowDst<T>): bool { escrow.is_cross_chain }
    public fun get_evm_order_hash<T>(escrow: &EscrowDst<T>): vector<u8> { escrow.evm_order_hash }
    public fun get_order_hash<T>(escrow: &EscrowDst<T>): vector<u8> { escrow.order_hash }

    /// Get current balance amounts (for monitoring)
    public fun get_balance_amounts<T>(escrow: &EscrowDst<T>): (u64, u64) {
        (
            balance::value(&escrow.locked_balance),
            balance::value(&escrow.safety_balance)
        )
    }

    /// Get withdrawal time information
    public fun get_withdrawal_times<T>(escrow: &EscrowDst<T>): (u64, u64, u64) {
        (
            time_locks::dst_withdrawal_start(&escrow.timelocks),
            time_locks::dst_pub_withdrawal_start(&escrow.timelocks),
            time_locks::dst_cancellation_start(&escrow.timelocks)
        )
    }

    /// Check if withdrawal is currently allowed
    public fun can_withdraw<T>(escrow: &EscrowDst<T>, clock: &Clock): bool {
        if (escrow.completed) return false;
        
        let now = clock::timestamp_ms(clock) / 1000;
        now >= time_locks::dst_withdrawal_start(&escrow.timelocks) && 
        now < time_locks::dst_cancellation_start(&escrow.timelocks)
    }

    /// Check if public withdrawal is currently allowed
    public fun can_public_withdraw<T>(escrow: &EscrowDst<T>, clock: &Clock): bool {
        if (escrow.completed) return false;
        
        let now = clock::timestamp_ms(clock) / 1000;
        now >= time_locks::dst_pub_withdrawal_start(&escrow.timelocks) && 
        now < time_locks::dst_cancellation_start(&escrow.timelocks)
    }

    /// Check if cancellation is currently allowed
    public fun can_cancel<T>(escrow: &EscrowDst<T>, clock: &Clock): bool {
        if (escrow.completed) return false;
        
        let now = clock::timestamp_ms(clock) / 1000;
        now >= time_locks::dst_cancellation_start(&escrow.timelocks)
    }
}
