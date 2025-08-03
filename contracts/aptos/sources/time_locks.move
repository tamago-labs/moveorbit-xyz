/// Time locks module for APTOS cross-chain escrows
module cross_chain_swap_addr::time_locks {
    use std::error;
    use aptos_framework::timestamp;

    /// Error codes
    const E_INVALID_TIMELOCK: u64 = 1;
    const E_TIMELOCK_NOT_REACHED: u64 = 2;

    /// Time lock stages for escrow operations
    const STAGE_DST_WITHDRAWAL: u8 = 0;
    const STAGE_DST_PUBLIC_WITHDRAWAL: u8 = 1;
    const STAGE_DST_CANCELLATION: u8 = 2;
    const STAGE_DST_PUBLIC_CANCELLATION: u8 = 3;
    const STAGE_SRC_WITHDRAWAL: u8 = 4;
    const STAGE_SRC_PUBLIC_WITHDRAWAL: u8 = 5;
    const STAGE_SRC_CANCELLATION: u8 = 6;

    /// TimeLocks structure for escrow operations
    struct TimeLocks has copy, drop, store {
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
        dst_public_cancellation: u32,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
        deployed_at: u64, // Timestamp when the escrow was deployed
    }

    /// Create new time locks with specified delays
    public fun new(
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
        dst_public_cancellation: u32,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
    ): TimeLocks {
        // Validate timelock ordering
        assert!(dst_withdrawal <= dst_public_withdrawal, error::invalid_argument(E_INVALID_TIMELOCK));
        assert!(dst_public_withdrawal <= dst_cancellation, error::invalid_argument(E_INVALID_TIMELOCK));
        assert!(dst_cancellation <= dst_public_cancellation, error::invalid_argument(E_INVALID_TIMELOCK));
        assert!(src_withdrawal <= src_public_withdrawal, error::invalid_argument(E_INVALID_TIMELOCK));
        assert!(src_public_withdrawal <= src_cancellation, error::invalid_argument(E_INVALID_TIMELOCK));

        TimeLocks {
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
            dst_public_cancellation,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
            deployed_at: 0, // Will be set when escrow is deployed
        }
    }

    /// Set deployment timestamp
    public fun set_deployed_at(timelocks: &mut TimeLocks, deployed_at: u64) {
        timelocks.deployed_at = deployed_at;
    }

    /// Create timelocks with deployment timestamp
    public fun new_with_deployment(
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
        dst_public_cancellation: u32,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
        deployed_at: u64,
    ): TimeLocks {
        let timelocks = new(
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
            dst_public_cancellation,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
        );
        set_deployed_at(&mut timelocks, deployed_at);
        timelocks
    }

    /// Check if a specific stage time has been reached
    public fun is_stage_reached(timelocks: &TimeLocks, stage: u8): bool {
        let current_time = timestamp::now_seconds();
        let target_time = get_stage_time(timelocks, stage);
        current_time >= target_time
    }

    /// Get the absolute timestamp for a specific stage
    public fun get_stage_time(timelocks: &TimeLocks, stage: u8): u64 {
        let delay = if (stage == STAGE_DST_WITHDRAWAL) {
            (timelocks.dst_withdrawal as u64)
        } else if (stage == STAGE_DST_PUBLIC_WITHDRAWAL) {
            (timelocks.dst_public_withdrawal as u64)
        } else if (stage == STAGE_DST_CANCELLATION) {
            (timelocks.dst_cancellation as u64)
        } else if (stage == STAGE_DST_PUBLIC_CANCELLATION) {
            (timelocks.dst_public_cancellation as u64)
        } else if (stage == STAGE_SRC_WITHDRAWAL) {
            (timelocks.src_withdrawal as u64)
        } else if (stage == STAGE_SRC_PUBLIC_WITHDRAWAL) {
            (timelocks.src_public_withdrawal as u64)
        } else if (stage == STAGE_SRC_CANCELLATION) {
            (timelocks.src_cancellation as u64)
        } else {
            abort error::invalid_argument(E_INVALID_TIMELOCK)
        };
        
        timelocks.deployed_at + delay
    }

    /// Check if withdrawal is allowed (dst side)
    public fun can_withdraw_dst(timelocks: &TimeLocks): bool {
        is_stage_reached(timelocks, STAGE_DST_WITHDRAWAL)
    }

    /// Check if public withdrawal is allowed (dst side)
    public fun can_public_withdraw_dst(timelocks: &TimeLocks): bool {
        is_stage_reached(timelocks, STAGE_DST_PUBLIC_WITHDRAWAL)
    }

    /// Check if cancellation is allowed (dst side)
    public fun can_cancel_dst(timelocks: &TimeLocks): bool {
        is_stage_reached(timelocks, STAGE_DST_CANCELLATION)
    }

    /// Check if public cancellation is allowed (dst side)
    public fun can_public_cancel_dst(timelocks: &TimeLocks): bool {
        is_stage_reached(timelocks, STAGE_DST_PUBLIC_CANCELLATION)
    }

    /// Check if withdrawal is allowed (src side)
    public fun can_withdraw_src(timelocks: &TimeLocks): bool {
        is_stage_reached(timelocks, STAGE_SRC_WITHDRAWAL)
    }

    /// Check if public withdrawal is allowed (src side)
    public fun can_public_withdraw_src(timelocks: &TimeLocks): bool {
        is_stage_reached(timelocks, STAGE_SRC_PUBLIC_WITHDRAWAL)
    }

    /// Check if cancellation is allowed (src side)
    public fun can_cancel_src(timelocks: &TimeLocks): bool {
        is_stage_reached(timelocks, STAGE_SRC_CANCELLATION)
    }

    /// Get remaining time until a stage is reached
    public fun time_until_stage(timelocks: &TimeLocks, stage: u8): u64 {
        let current_time = timestamp::now_seconds();
        let target_time = get_stage_time(timelocks, stage);
        if (current_time >= target_time) {
            0
        } else {
            target_time - current_time
        }
    }

    /// Create default timelocks for testing/demo
    public fun create_default(): TimeLocks {
        new(
            300u32,  // dst_withdrawal: 5 minutes
            600u32,  // dst_public_withdrawal: 10 minutes  
            1800u32, // dst_cancellation: 30 minutes
            3600u32, // dst_public_cancellation: 1 hour
            120u32,  // src_withdrawal: 2 minutes
            300u32,  // src_public_withdrawal: 5 minutes
            900u32,  // src_cancellation: 15 minutes
        )
    }

    /// Create fast timelocks for testing
    public fun create_fast_test(): TimeLocks {
        new(
            10u32,  // dst_withdrawal: 10 seconds
            20u32,  // dst_public_withdrawal: 20 seconds  
            60u32,  // dst_cancellation: 1 minute
            120u32, // dst_public_cancellation: 2 minutes
            5u32,   // src_withdrawal: 5 seconds
            15u32,  // src_public_withdrawal: 15 seconds
            45u32,  // src_cancellation: 45 seconds
        )
    }

    // Getter functions
    public fun get_dst_withdrawal(timelocks: &TimeLocks): u32 { timelocks.dst_withdrawal }
    public fun get_dst_public_withdrawal(timelocks: &TimeLocks): u32 { timelocks.dst_public_withdrawal }
    public fun get_dst_cancellation(timelocks: &TimeLocks): u32 { timelocks.dst_cancellation }
    public fun get_dst_public_cancellation(timelocks: &TimeLocks): u32 { timelocks.dst_public_cancellation }
    public fun get_src_withdrawal(timelocks: &TimeLocks): u32 { timelocks.src_withdrawal }
    public fun get_src_public_withdrawal(timelocks: &TimeLocks): u32 { timelocks.src_public_withdrawal }
    public fun get_src_cancellation(timelocks: &TimeLocks): u32 { timelocks.src_cancellation }
    public fun get_deployed_at(timelocks: &TimeLocks): u64 { timelocks.deployed_at }

    // Constants for stage access
    public fun stage_dst_withdrawal(): u8 { STAGE_DST_WITHDRAWAL }
    public fun stage_dst_public_withdrawal(): u8 { STAGE_DST_PUBLIC_WITHDRAWAL }
    public fun stage_dst_cancellation(): u8 { STAGE_DST_CANCELLATION }
    public fun stage_dst_public_cancellation(): u8 { STAGE_DST_PUBLIC_CANCELLATION }
    public fun stage_src_withdrawal(): u8 { STAGE_SRC_WITHDRAWAL }
    public fun stage_src_public_withdrawal(): u8 { STAGE_SRC_PUBLIC_WITHDRAWAL }
    public fun stage_src_cancellation(): u8 { STAGE_SRC_CANCELLATION }
 

    #[test_only]
    public fun set_time_for_testing(time: u64) {
        timestamp::set_time_has_started_for_testing(&aptos_framework::account::create_signer_for_test(@0x1));
        timestamp::update_global_time_for_test(time * 1000000); // Convert to microseconds
    }

    #[test]
    fun test_timelock_creation() {
        let timelocks = create_default();
        assert!(get_dst_withdrawal(&timelocks) == 300u32, 1);
        assert!(get_dst_cancellation(&timelocks) == 1800u32, 2);
        assert!(get_src_withdrawal(&timelocks) == 120u32, 3);
    }

    #[test]
    fun test_timelock_stages() {
        set_time_for_testing(1000000);
        let timelocks = create_fast_test();
        set_deployed_at(&mut timelocks, 1000000);

        // Initially no stages should be reached
        assert!(!can_withdraw_dst(&timelocks), 1);
        assert!(!can_cancel_dst(&timelocks), 2);

        // Move time forward
        set_time_for_testing(1000010); // +10 seconds
        assert!(can_withdraw_dst(&timelocks), 3);
        assert!(!can_cancel_dst(&timelocks), 4);

        // Move further forward
        set_time_for_testing(1000060); // +60 seconds
        assert!(can_cancel_dst(&timelocks), 5);
    }
}
