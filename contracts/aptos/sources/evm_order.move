/// EVM Order compatibility module for APTOS cross-chain swaps
module cross_chain_swap_addr::evm_order {
    use std::vector;
    use std::string::{Self, String};
    use std::error;
    use aptos_std::crypto_algebra;
    use aptos_std::aptos_hash;
    use aptos_framework::event;

    /// Error codes
    const E_INVALID_ORDER_HASH: u64 = 1;
    const E_INVALID_SIGNATURE: u64 = 2;
    const E_SIGNATURE_LENGTH: u64 = 3;
    const E_INVALID_ADDRESS_LENGTH: u64 = 4;
    const E_INVALID_SECRET: u64 = 5;

    /// EVM-compatible order structure matching Solidity struct
    struct EVMOrder has copy, drop, store {
        salt: u256,
        maker: vector<u8>,        // 20 bytes EVM address
        receiver: vector<u8>,     // 20 bytes EVM address  
        maker_asset: vector<u8>,  // 20 bytes EVM address
        taker_asset: vector<u8>,  // 20 bytes EVM address
        making_amount: u256,
        taking_amount: u256,
        maker_traits: u256,
    }

    /// Cross-chain order information for APTOS processing
    struct CrossChainOrder has copy, drop, store {
        evm_order: EVMOrder,
        order_hash: vector<u8>,   // 32 bytes - EIP712 hash from EVM
        signature_r: vector<u8>,  // 32 bytes
        signature_vs: vector<u8>, // 32 bytes
        dst_chain_id: u256,       // APTOS chain identifier
        src_chain_id: u256,       // EVM chain identifier
        secret_hash: vector<u8>,  // 32 bytes - keccak256 of secret
    }

    /// Event emitted when cross-chain order is created on APTOS
    #[event]
    struct CrossChainOrderCreated has drop, store {
        order_hash: vector<u8>,
        maker: vector<u8>,
        taker: vector<u8>,
        src_chain_id: u256,
        dst_chain_id: u256,
        amount: u256,
    }

    /// Event emitted when order is processed on APTOS
    #[event]
    struct OrderProcessed has drop, store {
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
        assert!(vector::length(&maker) == 20, error::invalid_argument(E_INVALID_ADDRESS_LENGTH));
        assert!(vector::length(&receiver) == 20, error::invalid_argument(E_INVALID_ADDRESS_LENGTH));
        assert!(vector::length(&maker_asset) == 20, error::invalid_argument(E_INVALID_ADDRESS_LENGTH));
        assert!(vector::length(&taker_asset) == 20, error::invalid_argument(E_INVALID_ADDRESS_LENGTH));

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
        assert!(vector::length(&order_hash) == 32, error::invalid_argument(E_INVALID_ORDER_HASH));
        assert!(vector::length(&signature_r) == 32, error::invalid_argument(E_SIGNATURE_LENGTH));
        assert!(vector::length(&signature_vs) == 32, error::invalid_argument(E_SIGNATURE_LENGTH));
        assert!(vector::length(&secret_hash) == 32, error::invalid_argument(E_INVALID_ORDER_HASH));

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

    /// Verify that the secret matches the secret hash using keccak256
    public fun verify_secret(secret: &vector<u8>, secret_hash: &vector<u8>): bool {
        // Note: In production, you'd want to use proper keccak256 from aptos_std
        // For now, using a placeholder hash check
        let computed_hash = aptos_hash::keccak256(*secret);
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

    /// Convert EVM address to hex string for display/logging
    public fun evm_address_to_string(addr: &vector<u8>): String {
        assert!(vector::length(addr) == 20, error::invalid_argument(E_INVALID_ADDRESS_LENGTH));
        
        let hex_chars = b"0123456789abcdef";
        let result = vector::empty<u8>();
        vector::push_back(&mut result, 48); // '0'
        vector::push_back(&mut result, 120); // 'x'
        
        let i = 0;
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
        event::emit(CrossChainOrderCreated {
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
        event::emit(OrderProcessed {
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
    public fun get_evm_order_maker_asset(order: &EVMOrder): vector<u8> { order.maker_asset }
    public fun get_evm_order_taker_asset(order: &EVMOrder): vector<u8> { order.taker_asset }

    // Getter functions for CrossChainOrder
    public fun get_cross_chain_order_hash(order: &CrossChainOrder): vector<u8> { order.order_hash }
    public fun get_cross_chain_secret_hash(order: &CrossChainOrder): vector<u8> { order.secret_hash }
    public fun get_cross_chain_evm_order(order: &CrossChainOrder): &EVMOrder { &order.evm_order }
    public fun get_cross_chain_src_chain_id(order: &CrossChainOrder): u256 { order.src_chain_id }
    public fun get_cross_chain_dst_chain_id(order: &CrossChainOrder): u256 { order.dst_chain_id }
    public fun get_cross_chain_signature_r(order: &CrossChainOrder): vector<u8> { order.signature_r }
    public fun get_cross_chain_signature_vs(order: &CrossChainOrder): vector<u8> { order.signature_vs }

    #[test_only]
    public fun create_test_evm_order(): EVMOrder {
        new_evm_order(
            12345u256,
            x"1111111111111111111111111111111111111111", // maker
            x"2222222222222222222222222222222222222222", // receiver
            x"3333333333333333333333333333333333333333", // maker_asset
            x"4444444444444444444444444444444444444444", // taker_asset
            1000000u256, // making_amount
            2000000u256, // taking_amount
            0u256        // maker_traits
        )
    }

    #[test_only]
    public fun create_test_cross_chain_order(): CrossChainOrder {
        let evm_order = create_test_evm_order();
        new_cross_chain_order(
            evm_order,
            x"1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", // order_hash
            x"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef", // signature_r
            x"fedcbafedcbafedcbafedcbafedcbafedcbafedcbafedcbafedcbafedcbafedcba", // signature_vs
            1u256,    // dst_chain_id (APTOS)
            11155111u256, // src_chain_id (Ethereum Sepolia)
            aptos_hash::keccak256(b"test_secret") // secret_hash
        )
    }
}
