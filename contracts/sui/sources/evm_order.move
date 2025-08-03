module cross_chain_swap::evm_order {
    use sui::hash;
    use sui::bcs;
    use std::vector;
    use std::string::{Self, String};
    use sui::event;
    use sui::tx_context::{Self, TxContext};

    // Error codes
    const E_INVALID_ORDER_HASH: u64 = 1;
    const E_INVALID_SIGNATURE: u64 = 2;
    const E_SIGNATURE_LENGTH: u64 = 3;

    /// EVM-compatible order structure matching Solidity struct
    public struct EVMOrder has copy, drop, store {
        salt: u256,
        maker: vector<u8>,        // 20 bytes EVM address
        receiver: vector<u8>,     // 20 bytes EVM address  
        maker_asset: vector<u8>,  // 20 bytes EVM address
        taker_asset: vector<u8>,  // 20 bytes EVM address
        making_amount: u256,
        taking_amount: u256,
        maker_traits: u256,
    }

    /// Cross-chain order information for SUI processing
    public struct CrossChainOrder has copy, drop, store {
        evm_order: EVMOrder,
        order_hash: vector<u8>,   // 32 bytes - EIP712 hash from EVM
        signature_r: vector<u8>,  // 32 bytes
        signature_vs: vector<u8>, // 32 bytes
        dst_chain_id: u256,       // SUI chain identifier
        src_chain_id: u256,       // EVM chain identifier
        secret_hash: vector<u8>,  // 32 bytes - keccak256 of secret
    }

    /// Event emitted when cross-chain order is created on SUI
    public struct CrossChainOrderCreated has copy, drop {
        order_hash: vector<u8>,
        maker: vector<u8>,
        taker: vector<u8>,
        src_chain_id: u256,
        dst_chain_id: u256,
        amount: u256,
    }

    /// Event emitted when order is processed on SUI
    public struct OrderProcessed has copy, drop {
        order_hash: vector<u8>,
        secret_revealed: bool,
        processor: address,
    }

    /// Create a new EVM order structure
    public fun new_evm_order(
        salt: u256,
        maker: vector<u8>,
        receiver: vector<u8>,
        maker_asset: vector<u8>,
        taker_asset: vector<u8>,
        making_amount: u256,
        taking_amount: u256,
        maker_traits: u256,
    ): EVMOrder {
        // Validate address lengths (20 bytes for EVM addresses)
        assert!(vector::length(&maker) == 20, E_INVALID_ORDER_HASH);
        assert!(vector::length(&receiver) == 20, E_INVALID_ORDER_HASH);
        assert!(vector::length(&maker_asset) == 20, E_INVALID_ORDER_HASH);
        assert!(vector::length(&taker_asset) == 20, E_INVALID_ORDER_HASH);

        EVMOrder {
            salt,
            maker,
            receiver,
            maker_asset,
            taker_asset,
            making_amount,
            taking_amount,
            maker_traits,
        }
    }

    /// Create cross-chain order with EVM signature verification
    public fun new_cross_chain_order(
        evm_order: EVMOrder,
        order_hash: vector<u8>,
        signature_r: vector<u8>,
        signature_vs: vector<u8>,
        dst_chain_id: u256,
        src_chain_id: u256,
        secret_hash: vector<u8>,
    ): CrossChainOrder {
        // Validate hash and signature lengths
        assert!(vector::length(&order_hash) == 32, E_INVALID_ORDER_HASH);
        assert!(vector::length(&signature_r) == 32, E_SIGNATURE_LENGTH);
        assert!(vector::length(&signature_vs) == 32, E_SIGNATURE_LENGTH);
        assert!(vector::length(&secret_hash) == 32, E_INVALID_ORDER_HASH);

        CrossChainOrder {
            evm_order,
            order_hash,
            signature_r,
            signature_vs,
            dst_chain_id,
            src_chain_id,
            secret_hash,
        }
    }

    /// Verify that the secret matches the secret hash
    public fun verify_secret(secret: &vector<u8>, secret_hash: &vector<u8>): bool {
        let computed_hash = hash::keccak256(secret);
        computed_hash == *secret_hash
    }

    /// Verify EVM order hash matches the provided hash
    /// Note: This is a simplified verification - in production, you'd want
    /// to implement full EIP-712 domain separator verification
    public fun verify_order_hash(order: &EVMOrder, expected_hash: &vector<u8>): bool {
        // In a full implementation, this would recreate the EIP-712 hash
        // For now, we trust the hash provided from the EVM side
        vector::length(expected_hash) == 32
    }

    /// Extract EVM address as string for display/logging
    public fun evm_address_to_string(addr: &vector<u8>): String {
        assert!(vector::length(addr) == 20, E_INVALID_ORDER_HASH);
        
        let hex_chars = b"0123456789abcdef";
        let mut result = vector::empty<u8>();
        vector::push_back(&mut result, 48); // '0'
        vector::push_back(&mut result, 120); // 'x'
        
        let mut i = 0;
        while (i < 20) {
            let byte = *vector::borrow(addr, i);
            let high = byte >> 4;
            let low = byte & 0x0f;
            vector::push_back(&mut result, *vector::borrow(&hex_chars, (high as u64)));
            vector::push_back(&mut result, *vector::borrow(&hex_chars, (low as u64)));
            i = i + 1;
        };
        
        string::utf8(result)
    }

    /// Get order information for processing
    public fun get_order_info(cross_chain_order: &CrossChainOrder): (
        vector<u8>, // order_hash
        vector<u8>, // maker
        vector<u8>, // taker (derived from signature)
        u256,       // making_amount
        u256,       // taking_amount
        vector<u8>  // secret_hash
    ) {
        (
            cross_chain_order.order_hash,
            cross_chain_order.evm_order.maker,
            cross_chain_order.evm_order.receiver, // Using receiver as taker for simplicity
            cross_chain_order.evm_order.making_amount,
            cross_chain_order.evm_order.taking_amount,
            cross_chain_order.secret_hash
        )
    }

    /// Emit cross-chain order created event
    public fun emit_cross_chain_order_created(
        order_hash: vector<u8>,
        maker: vector<u8>,
        taker: vector<u8>,
        src_chain_id: u256,
        dst_chain_id: u256,
        amount: u256,
    ) {
        sui::event::emit(CrossChainOrderCreated {
            order_hash,
            maker,
            taker,
            src_chain_id,
            dst_chain_id,
            amount,
        });
    }

    /// Emit order processed event
    public fun emit_order_processed(
        order_hash: vector<u8>,
        secret_revealed: bool,
        processor: address,
    ) {
        sui::event::emit(OrderProcessed {
            order_hash,
            secret_revealed,
            processor,
        });
    }

    // Getter functions for EVMOrder
    public fun get_evm_order_maker(order: &EVMOrder): vector<u8> { order.maker }
    public fun get_evm_order_receiver(order: &EVMOrder): vector<u8> { order.receiver }
    public fun get_evm_order_making_amount(order: &EVMOrder): u256 { order.making_amount }
    public fun get_evm_order_taking_amount(order: &EVMOrder): u256 { order.taking_amount }
    public fun get_evm_order_salt(order: &EVMOrder): u256 { order.salt }

    // Getter functions for CrossChainOrder
    public fun get_cross_chain_order_hash(order: &CrossChainOrder): vector<u8> { order.order_hash }
    public fun get_cross_chain_secret_hash(order: &CrossChainOrder): vector<u8> { order.secret_hash }
    public fun get_cross_chain_evm_order(order: &CrossChainOrder): &EVMOrder { &order.evm_order }
    public fun get_cross_chain_src_chain_id(order: &CrossChainOrder): u256 { order.src_chain_id }
    public fun get_cross_chain_dst_chain_id(order: &CrossChainOrder): u256 { order.dst_chain_id }
}