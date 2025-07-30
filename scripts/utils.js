 
const { randomBytes } = require('crypto');
const { solidityPackedKeccak256 } = require('ethers');
const { Web3 } = require('web3');
const { createWalletClient, createPublicClient, http, parseUnits, formatUnits, isAddress, getAddress } = require('viem');
  
const { privateKeyToAccount } = require('viem/accounts');

require('dotenv').config();
 

// 1inch router address  
const AGGREGATION_ROUTER_V6 = '0x111111125421cA6dc452d289314280a0f8842A65';
const MAX_UINT256 = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

// Polling configuration for order monitoring
const POLLING_CONFIG = {
    interval: 2000,           // 2 seconds
    maxAttempts: 50,          // Maximum polling attempts
    backoffMultiplier: 1.2    // Exponential backoff multiplier
};

// Standard ERC20 ABI for Web3 interactions
const ERC20_ABI = [
    {
        constant: true,
        inputs: [{ name: "_owner", type: "address" }],
        name: "balanceOf",
        outputs: [{ name: "balance", type: "uint256" }],
        type: "function"
    },
    {
        constant: true,
        inputs: [],
        name: "decimals",
        outputs: [{ name: "", type: "uint8" }],
        type: "function"
    },
    {
        constant: true,
        inputs: [
            { name: "_owner", type: "address" },
            { name: "_spender", type: "address" }
        ],
        name: "allowance",
        outputs: [{ name: "", type: "uint256" }],
        type: "function"
    },
    {
        constant: false,
        inputs: [
            { name: "_spender", type: "address" },
            { name: "_value", type: "uint256" }
        ],
        name: "approve",
        outputs: [{ name: "", type: "bool" }],
        type: "function"
    }
];

/**
 * Ensure address is properly checksummed for Viem
 * @param {string} address - Address to checksum
 * @returns {string} Properly checksummed address
 * @throws {Error} If address is invalid
 */
function ensureValidAddress(address) {
    if (!isAddress(address)) {
        throw new Error(`Invalid address: ${address}`);
    }
    return getAddress(address);
}

/**
 * Generate random 32-byte secret for atomic swaps
 * @returns {string} Hex string with 0x prefix
 */
function generateRandomSecret() {
    return '0x' + randomBytes(32).toString('hex');
}

/**
 * Generate multiple secrets for multi-fill orders
 * @param {number} count - Number of secrets to generate
 * @returns {Array<string>} Array of random secrets
 */
function generateMultipleSecrets(count = 1) {
    return Array.from({ length: count }, () => generateRandomSecret());
}

/**
 * Validate environment variables
 * @returns {object} Validated environment configuration
 * @throws {Error} If required environment variables are missing
 */
function validateEnvironment() {
    const config = {
        privateKey: process.env.WALLET_KEY,
        walletAddress: process.env.WALLET_ADDRESS,
        apiKey: process.env.DEV_PORTAL_KEY,
        rpcUrls: {
            ethereum: process.env.ETHEREUM_RPC_URL || CHAINS.ethereum.rpcUrl,
            polygon: process.env.POLYGON_RPC_URL || CHAINS.polygon.rpcUrl,
            binance: process.env.BINANCE_RPC_URL || CHAINS.binance.rpcUrl,
            base: process.env.BASE_RPC_URL || CHAINS.base.rpcUrl,
            arbitrum: process.env.ARBITRUM_RPC_URL || CHAINS.arbitrum.rpcUrl
        }
    };

    const required = ['privateKey', 'walletAddress', 'apiKey'];
    const missing = required.filter(key => !config[key]);
    
    if (missing.length > 0) {
        throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
    }
    
    // Validate private key format
    if (!config.privateKey.startsWith('0x') || config.privateKey.length !== 66) {
        throw new Error('WALLET_KEY must be a 64-character hex string with 0x prefix');
    }
    
    // Validate wallet address format
    if (!config.walletAddress.startsWith('0x') || config.walletAddress.length !== 42) {
        throw new Error('WALLET_ADDRESS must be a 40-character hex string with 0x prefix');
    }
    
    return config;
}

/**
 * Get token address for a specific chain and token symbol
 * @param {string} chainName - Name of the chain
 * @param {string} tokenSymbol - Token symbol (e.g., 'USDC')
 * @returns {string|null} Properly checksummed token address or null if not found
 */
function getTokenAddress(chainName, tokenSymbol) {
    const chain = CHAINS[chainName.toLowerCase()];
    if (!chain || !chain.tokens) {
        return null;
    }
    const address = chain.tokens[tokenSymbol.toUpperCase()];
    if (!address) {
        return null;
    }
    
    // Ensure the address is properly checksummed for Viem compatibility
    try {
        return ensureValidAddress(address);
    } catch (error) {
        console.warn(`Invalid address for ${tokenSymbol} on ${chainName}: ${address}`);
        return null;
    }
}

/**
 * Format token amount from human readable to wei/smallest unit
 * @param {string} amount - Human readable amount (e.g., "1.5")
 * @param {number} decimals - Token decimals
 * @returns {string} Amount in wei as string
 */
function formatTokenAmount(amount, decimals = 18) {
    const web3 = new Web3();
    return web3.utils.toWei(amount, decimals === 18 ? 'ether' : decimals);
}

/**
 * Format duration in milliseconds to human readable string
 * @param {number} ms - Duration in milliseconds
 * @returns {string} Formatted duration
 */
function formatDuration(ms) {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    
    if (hours > 0) {
        return `${hours}h ${minutes % 60}m ${seconds % 60}s`;
    } else if (minutes > 0) {
        return `${minutes}m ${seconds % 60}s`;
    } else {
        return `${seconds}s`;
    }
}

/**
 * Log error with context and formatting
 * @param {Error} error - Error object
 * @param {string} context - Context where error occurred
 */
function logError(error, context = '') {
    const timestamp = new Date().toISOString();
    console.error(`❌ [${timestamp}] Error ${context}:`);
    console.error(`   Message: ${error.message}`);
    
    if (error.response) {
        console.error(`   Status: ${error.response.status}`);
        if (error.response.data) {
            console.error(`   Response:`, JSON.stringify(error.response.data, null, 2));
        }
    }
    
    if (error.stack && process.env.NODE_ENV === 'development') {
        console.error(`   Stack: ${error.stack}`);
    }
}

/**
 * Log order information
 * @param {object} orderResponse - Order response from SDK
 * @param {string} action - Action performed (e.g., 'Placed', 'Updated')
 */
function logOrderInfo(orderResponse, action = '') {
    console.log(`\n📋 Order ${action}:`);
    if (orderResponse.orderHash) {
        console.log(`   Order Hash: ${orderResponse.orderHash}`);
    }
    if (orderResponse.quoteId) {
        console.log(`   Quote ID: ${orderResponse.quoteId}`);
    }
    if (orderResponse.srcChainId && orderResponse.dstChainId) {
        console.log(`   Route: Chain ${orderResponse.srcChainId} → Chain ${orderResponse.dstChainId}`);
    }
}

/**
 * Log secret information
 * @param {Array<string>} secrets - Array of secrets
 * @param {Array<string>} secretHashes - Array of secret hashes
 */
function logSecretInfo(secrets, secretHashes) {
    console.log(`\n🔐 Generated ${secrets.length} secret(s):`);
    secrets.forEach((secret, i) => {
        console.log(`   Secret ${i}: ${secret}`);
        console.log(`   Hash ${i}: ${secretHashes[i]}`);
    });
}

/**
 * Log swap parameters
 * @param {object} params - Swap parameters
 */
function logSwapParams(params) {
    console.log(`\n📊 Swap Parameters:`);
    console.log(`   Source Chain: ${params.srcChainId}`);
    console.log(`   Destination Chain: ${params.dstChainId}`);
    console.log(`   Source Token: ${params.srcTokenAddress}`);
    console.log(`   Destination Token: ${params.dstTokenAddress}`);
    console.log(`   Amount: ${params.amount}`);
    console.log(`   Wallet: ${params.walletAddress}`);
}

/**
 * Sleep for specified milliseconds
 * @param {number} ms - Milliseconds to sleep
 * @returns {Promise<void>}
 */
function delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Get chain configuration by name
 * @param {string} chainName - Chain name
 * @returns {object|null} Chain configuration
 */
function getChainConfig(chainName) {
    return CHAINS[chainName.toLowerCase()] || null;
}

/**
 * Create hashlock for multiple fills (from Fusion+ SDK pattern)
 * @param {Array<string>} secretHashes - Array of secret hashes
 * @returns {Array<string>} Processed hashlock array
 */
function createMultipleFillsHashlock(secretHashes) {
    return secretHashes.map((secretHash, i) =>
        solidityPackedKeccak256(['uint64', 'bytes32'], [i, secretHash])
    );
}

/**
 * Log formatted message with timestamp
 * @param {string} message - Message to log
 * @param {string} level - Log level (info, warn, error)
 */
function log(message, level = 'info') {
    const timestamp = new Date().toISOString();
    const prefix = {
        info: '✅',
        warn: '⚠️',
        error: '❌',
        debug: '🔍'
    }[level] || 'ℹ️';
    
    console.log(`${prefix} [${timestamp}] ${message}`);
}

/**
 * Web3 Provider Connector Class
 * Provides Web3-specific blockchain interaction methods
 */
class Web3ProviderConnector {
    constructor(privateKey, rpcUrl) {
        this.web3 = new Web3(rpcUrl);
        this.account = this.web3.eth.accounts.privateKeyToAccount(privateKey);
        this.web3.eth.accounts.wallet.add(this.account);
        this.web3.eth.defaultAccount = this.account.address;
    }

    /**
     * Get token balance using Web3
     * @param {string} tokenAddress - Token contract address
     * @param {string} walletAddress - Wallet address
     * @returns {Promise<string>} Balance as string
     */
    async getTokenBalance(tokenAddress, walletAddress) {
        const contract = new this.web3.eth.Contract(ERC20_ABI, tokenAddress);
        return await contract.methods.balanceOf(walletAddress).call();
    }

    /**
     * Get token decimals using Web3
     * @param {string} tokenAddress - Token contract address
     * @returns {Promise<number>} Token decimals
     */
    async getTokenDecimals(tokenAddress) {
        const contract = new this.web3.eth.Contract(ERC20_ABI, tokenAddress);
        const decimals = await contract.methods.decimals().call();
        return Number(decimals);
    }

    /**
     * Check token allowance using Web3
     * @param {string} tokenAddress - Token contract address
     * @param {string} ownerAddress - Owner address
     * @param {string} spenderAddress - Spender address
     * @returns {Promise<string>} Allowance as string
     */
    async checkTokenApproval(tokenAddress, ownerAddress, spenderAddress) {
        const contract = new this.web3.eth.Contract(ERC20_ABI, tokenAddress);
        return await contract.methods.allowance(ownerAddress, spenderAddress).call();
    }

    /**
     * Approve token spending using Web3
     * @param {string} tokenAddress - Token contract address
     * @param {string} spenderAddress - Spender address
     * @param {string} amount - Amount to approve
     * @returns {Promise<object>} Transaction receipt
     */
    async approveToken(tokenAddress, spenderAddress, amount) {
        const contract = new this.web3.eth.Contract(ERC20_ABI, tokenAddress);
        
        const gasPrice = await this.web3.eth.getGasPrice();
        const gas = await contract.methods.approve(spenderAddress, amount).estimateGas({
            from: this.account.address
        });

        return await contract.methods.approve(spenderAddress, amount).send({
            from: this.account.address,
            gas: Math.floor(gas * 1.2), // Add 20% buffer
            gasPrice
        });
    }
}


/**
 * Create wallet client using Viem
 * @param {string} privateKey - Private key with 0x prefix
 * @param {string} chainName - Chain name (e.g., 'ethereum', 'polygon')
 * @returns {object} Wallet client
 */
function createWallet(privateKey, chainName) {
    const chainConfig = getChainConfig(chainName);
    if (!chainConfig || !chainConfig.viemChain) {
        throw new Error(`Chain ${chainName} not supported by Viem or configuration missing`);
    }
    
    const account = privateKeyToAccount(privateKey);
    return createWalletClient({
        account,
        chain: chainConfig.viemChain,
        transport: http(chainConfig.rpcUrl)
    });
}

/**
 * Create public client for reading blockchain data using Viem
 * @param {string} chainName - Chain name (e.g., 'ethereum', 'polygon')
 * @returns {object} Public client
 */
function createPublic(chainName) {
    const chainConfig = getChainConfig(chainName);
    if (!chainConfig || !chainConfig.viemChain) {
        throw new Error(`Chain ${chainName} not supported by Viem or configuration missing`);
    }
    
    return createPublicClient({
        chain: chainConfig.viemChain,
        transport: http(chainConfig.rpcUrl)
    });
}

/**
 * Parse token amount from human readable format using Viem
 * @param {string} amount - Human readable amount (e.g., "1.5")
 * @param {number} decimals - Token decimals (default 18)
 * @returns {string} Raw amount as string
 */
function parseTokenAmount(amount, decimals = 18) {
    return parseUnits(amount, decimals).toString();
}

/**
 * Format token amount for display using Viem
 * @param {string|bigint} amount - Raw token amount
 * @param {number} decimals - Token decimals (default 18)
 * @returns {string} Formatted amount
 */
function formatTokenAmountViem(amount, decimals = 18) {
    return formatUnits(BigInt(amount), decimals);
}

/**
 * Check token allowance for 1inch router using Viem
 * @param {object} publicClient - Viem public client
 * @param {string} tokenAddress - Token contract address
 * @param {string} ownerAddress - Token owner address
 * @returns {Promise<bigint>} Current allowance
 */
async function checkAllowance(publicClient, tokenAddress, ownerAddress) {
    const allowance = await publicClient.readContract({
        address: ensureValidAddress(tokenAddress),
        abi: [
            {
                name: 'allowance',
                type: 'function',
                stateMutability: 'view',
                inputs: [
                    { name: 'owner', type: 'address' },
                    { name: 'spender', type: 'address' }
                ],
                outputs: [{ name: '', type: 'uint256' }]
            }
        ],
        functionName: 'allowance',
        args: [ensureValidAddress(ownerAddress), ensureValidAddress(AGGREGATION_ROUTER_V6)]
    });
    
    return allowance;
}

/**
 * Approve tokens for 1inch router using Viem
 * @param {object} walletClient - Viem wallet client
 * @param {string} tokenAddress - Token contract address
 * @param {string} amount - Amount to approve (use max uint256 for unlimited)
 * @returns {Promise<string>} Transaction hash
 */
async function approveToken(walletClient, tokenAddress, amount = null) {
    // Use max uint256 for unlimited approval if no amount specified
    const approvalAmount = amount || (2n ** 256n - 1n).toString();
    
    const hash = await walletClient.writeContract({
        address: ensureValidAddress(tokenAddress),
        abi: [
            {
                name: 'approve',
                type: 'function',
                stateMutability: 'nonpayable',
                inputs: [
                    { name: 'spender', type: 'address' },
                    { name: 'amount', type: 'uint256' }
                ],
                outputs: [{ name: '', type: 'bool' }]
            }
        ],
        functionName: 'approve',
        args: [ensureValidAddress(AGGREGATION_ROUTER_V6), BigInt(approvalAmount)]
    });
    
    return hash;
}

/**
 * Get token balance using Viem
 * @param {object} publicClient - Viem public client
 * @param {string} tokenAddress - Token contract address
 * @param {string} ownerAddress - Token owner address
 * @returns {Promise<bigint>} Token balance
 */
async function getTokenBalance(publicClient, tokenAddress, ownerAddress) {
    const balance = await publicClient.readContract({
        address: ensureValidAddress(tokenAddress),
        abi: [
            {
                name: 'balanceOf',
                type: 'function',
                stateMutability: 'view',
                inputs: [{ name: 'account', type: 'address' }],
                outputs: [{ name: '', type: 'uint256' }]
            }
        ],
        functionName: 'balanceOf',
        args: [ensureValidAddress(ownerAddress)]
    });
    
    return balance;
}

/**
 * Wait for transaction confirmation using Viem
 * @param {object} publicClient - Viem public client
 * @param {string} hash - Transaction hash
 * @param {number} confirmations - Number of confirmations to wait for
 * @returns {Promise<object>} Transaction receipt
 */
async function waitForTransaction(publicClient, hash, confirmations = 1) {
    const receipt = await publicClient.waitForTransactionReceipt({
        hash,
        confirmations
    });
    
    return receipt;
}

/**
 * Estimate gas for transaction using Viem
 * @param {object} publicClient - Viem public client
 * @param {object} transaction - Transaction object
 * @returns {Promise<bigint>} Estimated gas
 */
async function estimateGas(publicClient, transaction) {
    try {
        const gas = await publicClient.estimateGas(transaction);
        return gas;
    } catch (error) {
        log(`Gas estimation failed: ${error.message}`, 'warn');
        return 500000n; // Fallback gas limit
    }
}

/**
 * Viem Provider Connector Class
 * Provides Viem-specific blockchain interaction methods with Web3-like interface
 */
class ViemProviderConnector {
    constructor(privateKey, chainName) {
        this.privateKey = privateKey;
        this.chainName = chainName;
        this.walletClient = createWallet(privateKey, chainName);
        this.publicClient = createPublic(chainName);
        this.account = privateKeyToAccount(privateKey);
    }

    /**
     * Get token balance using Viem
     * @param {string} tokenAddress - Token contract address
     * @param {string} walletAddress - Wallet address
     * @returns {Promise<bigint>} Balance as bigint
     */
    async getTokenBalance(tokenAddress, walletAddress) {
        return await getTokenBalance(this.publicClient, tokenAddress, walletAddress);
    }

    /**
     * Get token decimals using Viem
     * @param {string} tokenAddress - Token contract address
     * @returns {Promise<number>} Token decimals
     */
    async getTokenDecimals(tokenAddress) {
        const decimals = await this.publicClient.readContract({
            address: ensureValidAddress(tokenAddress),
            abi: [
                {
                    name: 'decimals',
                    type: 'function',
                    stateMutability: 'view',
                    inputs: [],
                    outputs: [{ name: '', type: 'uint8' }]
                }
            ],
            functionName: 'decimals'
        });
        return Number(decimals);
    }

    /**
     * Check token allowance using Viem
     * @param {string} tokenAddress - Token contract address
     * @param {string} ownerAddress - Owner address
     * @param {string} spenderAddress - Spender address
     * @returns {Promise<bigint>} Allowance as bigint
     */
    async checkTokenApproval(tokenAddress, ownerAddress, spenderAddress) {
        return await checkAllowance(this.publicClient, tokenAddress, ownerAddress);
    }

    /**
     * Approve token spending using Viem
     * @param {string} tokenAddress - Token contract address
     * @param {string} spenderAddress - Spender address
     * @param {string} amount - Amount to approve
     * @returns {Promise<string>} Transaction hash
     */
    async approveToken(tokenAddress, spenderAddress, amount) {
        return await approveToken(this.walletClient, tokenAddress, amount);
    }
}

function getRandomBytes32() {
    return '0x' + Buffer.from(randomBytes(32)).toString('hex');
}


module.exports = {
    // Constants
    CHAINS,
    AGGREGATION_ROUTER_V6,
    MAX_UINT256,
    POLLING_CONFIG,
    ERC20_ABI,
    
    // Secret generation
    generateRandomSecret,
    generateMultipleSecrets,
    
    // Environment and configuration
    validateEnvironment,
    getTokenAddress,
    getChainConfig,
    ensureValidAddress,
    
    // Formatting and utilities
    formatTokenAmount,
    formatDuration,
    
    // Logging functions
    logError,
    logOrderInfo,
    logSecretInfo,
    logSwapParams,
    log,
    
    // Helper functions
    delay,
    createMultipleFillsHashlock,
    
    // Web3 Provider Connector
    Web3ProviderConnector,
    
    // ===============================================
    // VIEM FUNCTIONS (RESTORED)
    // ===============================================
    
    // Viem client creation
    createWallet,
    createPublic,
    
    // Viem token utilities
    parseTokenAmount,
    formatTokenAmountViem,
    
    // Viem blockchain interactions
    checkAllowance,
    approveToken,
    getTokenBalance,
    waitForTransaction,
    estimateGas,
    
    // Viem Provider Connector
    ViemProviderConnector,
    getRandomBytes32
};
