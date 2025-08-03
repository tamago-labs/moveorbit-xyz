module cross_chain_swap::time_locks {
    use sui::clock::{Self, Clock};

    const E_INVALID_TIME: u64 = 1;

    public struct TimeLocks has copy, drop, store {
        deployed_at: u64,
        src_withdrawal: u32,
        src_public_withdrawal: u32, 
        src_cancellation: u32,
        src_public_cancellation: u32,
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
    }

    public fun new(
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
        src_public_cancellation: u32,
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
    ): TimeLocks {
        TimeLocks {
            deployed_at: 0,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
            src_public_cancellation,
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
        }
    }

    public fun set_deployed_at(timelocks: &mut TimeLocks, timestamp: u64) {
        timelocks.deployed_at = timestamp;
    }

    public fun src_withdrawal_start(timelocks: &TimeLocks): u64 {
        timelocks.deployed_at + (timelocks.src_withdrawal as u64)
    }

    public fun src_cancellation_start(timelocks: &TimeLocks): u64 {
        timelocks.deployed_at + (timelocks.src_cancellation as u64)
    }

    public fun src_pub_cancellation_start(timelocks: &TimeLocks): u64 {
        timelocks.deployed_at + (timelocks.src_public_cancellation as u64)
    }

    public fun dst_withdrawal_start(timelocks: &TimeLocks): u64 {
        timelocks.deployed_at + (timelocks.dst_withdrawal as u64)
    }

    public fun dst_pub_withdrawal_start(timelocks: &TimeLocks): u64 {
        timelocks.deployed_at + (timelocks.dst_public_withdrawal as u64)
    }

    public fun dst_cancellation_start(timelocks: &TimeLocks): u64 {
        timelocks.deployed_at + (timelocks.dst_cancellation as u64)
    }

    public fun rescue_start(timelocks: &TimeLocks, rescue_delay: u64): u64 {
        timelocks.deployed_at + rescue_delay
    }

    public fun check_time_after(clock: &Clock, start_time: u64) {
        assert!(clock::timestamp_ms(clock) >= start_time * 1000, E_INVALID_TIME);
    }

    public fun check_time_before(clock: &Clock, end_time: u64) {
        assert!(clock::timestamp_ms(clock) < end_time * 1000, E_INVALID_TIME);
    }
}
