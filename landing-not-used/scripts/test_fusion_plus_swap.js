 
const { SDK, HashLock, PrivateKeyProviderConnector, NetworkEnum } = require("@1inch/cross-chain-sdk");
const { randomBytes } = require('crypto');
const { Web3 } = require('web3');
const { solidityPackedKeccak256 } = require('ethers');

require('dotenv').config();

const {
    validateEnvironment, 
    logSecretInfo,
    logSwapParams,
    logError, 
    formatDuration,
    AGGREGATION_ROUTER_V6,
    MAX_UINT256, 
    getRandomBytes32
} = require('./utils');

// Configuration 
const TEST_CONFIG = { 
    srcChainId: NetworkEnum.ETHEREUM,
    dstChainId: NetworkEnum.POLYGON,
    srcTokenAddress: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WETH on Ethereum
    dstTokenAddress: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174', // USDC on Polygon
    amount: '1000000000000000', // 0.001 ETH (adjust to your balance)
    enableApproval: false,
    enableOrderPlacement: true, // Set to true when ready to place actual orders
    pollInterval: 5000 // 5 seconds 
};
 
class FusionPlusSDKTester {
    constructor() {
        this.config = null;
        this.sdk = null;
        this.web3Provider = null;
        this.web3 = null;
        this.startTime = Date.now();
    }

    async initialize() {
        try {
            console.log('🚀 Initializing Fusion+ SDK Tester...\n');
            
            // Validate environment variables
            this.config = validateEnvironment();
            console.log(`✅ Environment validated`);
            console.log(`   Wallet: ${this.config.walletAddress}`);
            
            // Initialize Web3 provider  
            const nodeUrl = this.config.rpcUrls.ethereum; // Use ethereum RPC
            console.log(`📡 Connecting to Web3 RPC: ${nodeUrl}`);
            
            // Create Web3 instance  
            this.web3 = new Web3(nodeUrl);
            
            // Create provider connector 
            this.web3Provider = new PrivateKeyProviderConnector(
                this.config.privateKey,
                this.web3
            );
            console.log(`✅ Web3 provider connector initialized`);
            
            // Initialize 1inch SDK  
            this.sdk = new SDK({
                url: 'https://api.1inch.dev/fusion-plus',
                authKey: this.config.apiKey,
                blockchainProvider: this.web3Provider
            });
            console.log(`✅ 1inch Fusion+ SDK initialized`);
            
        } catch (error) {
            logError(error, 'during initialization');
            throw error;
        }
    }

    async checkBalances() {
        console.log('\n💰 Checking wallet balances...');
        
        try {
            // Check ETH balance (since we're using WETH)
            const balance = await this.web3.eth.getBalance(this.config.walletAddress);
            const balanceInEth = this.web3.utils.fromWei(balance, 'ether');
            
            console.log(`   ETH balance: ${parseFloat(balanceInEth).toFixed(6)} ETH`);
            
            if (balance === '0') {
                console.warn(`⚠️  Warning: No ETH balance found`);
            }
            
            return { balance, balanceInEth };
            
        } catch (error) {
            logError(error, 'checking balances');
            return { balance: '0', balanceInEth: '0' };
        }
    }

    async checkTokenApproval() {
        console.log('\n🔓 Checking token approval...');
        
        try {
            // Standard ERC20 ABI for allowance check
            const erc20Abi = [
                {
                    constant: true,
                    inputs: [
                        { name: "_owner", type: "address" },
                        { name: "_spender", type: "address" }
                    ],
                    name: "allowance",
                    outputs: [{ name: "", type: "uint256" }],
                    type: "function"
                }
            ];
            
            const tokenContract = new this.web3.eth.Contract(erc20Abi, TEST_CONFIG.srcTokenAddress);
            
            const allowance = await tokenContract.methods.allowance(
                this.config.walletAddress,
                AGGREGATION_ROUTER_V6
            ).call();
            
            console.log(`   Current allowance: ${allowance.toString()}`);
            
            const needsApproval = allowance === '0';
            
            if (needsApproval) {
                console.log('   ⚠️  Token needs approval for Aggregation Router V6'); 
            } else {
                console.log('   ✅ Token already approved');
            }
            
            return !needsApproval;
            
        } catch (error) {
            logError(error, 'checking token approval');
            return false;
        }
    }

    async getQuote() {
        console.log('\n📊 Getting cross-chain quote...');
        
        try {
            const params = {
                srcChainId: TEST_CONFIG.srcChainId,
                dstChainId: TEST_CONFIG.dstChainId,
                srcTokenAddress: TEST_CONFIG.srcTokenAddress,
                dstTokenAddress: TEST_CONFIG.dstTokenAddress,
                amount: TEST_CONFIG.amount,
                enableEstimate: true,
                walletAddress: this.config.walletAddress
            };
            
            console.log('   Quote parameters:');
            logSwapParams(params);
            
            console.log('   Requesting quote from 1inch API...');
            
            try {
                const quote = await this.sdk.getQuote(params);
                console.log('   ✅ Quote received successfully');
                
                if (quote) {
                    console.log('   📋 Quote details available');
                     
                    try {
                        const preset = quote.getPreset();
                        console.log(`   Secrets required: ${preset.secretsCount}`);
                        return quote;
                    } catch (presetError) {
                        console.log('   ⚠️  Could not get preset info:', presetError.message);
                        return quote;
                    }
                }
                
                return quote;
                
            } catch (quoteError) {
                console.log('   ❌ Quote request failed:');
                logError(quoteError, 'getting quote from API');
                 
                if (quoteError.response) {
                    console.log(`   Status: ${quoteError.response.status}`);
                    console.log(`   Status Text: ${quoteError.response.statusText}`);
                    console.log(`   Response Data:`, JSON.stringify(quoteError.response.data, null, 2));
                }
                
                throw quoteError;
            }
            
        } catch (error) {
            logError(error, 'during quote process');
            throw error;
        }
    }

    async createSecrets(quote) {
        console.log('\n🔐 Generating secrets and hashlocks...');
        
        try { 
            const secretsCount = quote.getPreset().secretsCount;
            console.log(`   Generating ${secretsCount} secret(s)`);
            
            // Generate secrets  
            const secrets = Array.from({ length: secretsCount }).map(() => getRandomBytes32());
            const secretHashes = secrets.map(x => HashLock.hashSecret(x));
            
            // Create hashlock  
            const hashLock = secretsCount === 1
                ? HashLock.forSingleFill(secrets[0])
                : HashLock.forMultipleFills(
                    secretHashes.map((secretHash, i) =>
                        solidityPackedKeccak256(['uint64', 'bytes32'], [i, secretHash.toString()])
                    )
                );
            
            logSecretInfo(secrets, secretHashes);
            
            return { secrets, secretHashes, hashLock };
            
        } catch (error) {
            logError(error, 'generating secrets');
            throw error;
        }
    }

    async placeOrder(quote, orderParams) {
        console.log('\n📝 Placing cross-chain order...');
        
        if (!TEST_CONFIG.enableOrderPlacement) {
            console.log('   ⚠️  Order placement disabled in config - skipping');
            console.log('   💡 Set enableOrderPlacement: true to place actual orders');
            return null;
        }
        
        try {
            console.log('   Placing order...');
             
            const orderResponse = await this.sdk.placeOrder(quote, {
                walletAddress: this.config.walletAddress,
                hashLock: orderParams.hashLock,
                secretHashes: orderParams.secretHashes
            });
            
            console.log('   ✅ Order successfully placed');
            console.log(`   Order Hash: ${orderResponse.orderHash}`);
            
            return orderResponse;
            
        } catch (error) {
            logError(error, 'placing order');
            throw error;
        }
    }

    async monitorOrder(orderResponse, secrets) {
        if (!orderResponse) {
            console.log('\n⏭️  Skipping order monitoring (no order placed)');
            return;
        }
        
        console.log('\n👀 Monitoring order execution...');
        
        const orderHash = orderResponse.orderHash;
        const startTime = Date.now();
        
        try { 
            const intervalId = setInterval(async () => {
                try {
                    console.log('   Polling for fills until order status is set to "executed"...');
                    
                    // Check order status first
                    const order = await this.sdk.getOrderStatus(orderHash);
                    
                    if (order.status === 'executed') {
                        console.log('   🎯 Order is complete. Exiting.');
                        clearInterval(intervalId);
                        return;
                    }
                    
                    console.log(`   Order status: ${order.status}`);
                    
                    // Check for fills ready to accept secrets
                    const fillsObject = await this.sdk.getReadyToAcceptSecretFills(orderHash);
                    
                    if (fillsObject.fills.length > 0) {
                        console.log(`   🔓 Found ${fillsObject.fills.length} fill(s) ready for secret submission`);
                        
                        fillsObject.fills.forEach(async (fill) => {
                            try {
                                await this.sdk.submitSecret(orderHash, secrets[fill.idx]);
                                console.log(`   ✅ Fill order found! Secret submitted: ${JSON.stringify(fill.idx, null, 2)}`);
                            } catch (secretError) {
                                logError(secretError, `submitting secret for fill ${fill.idx}`);
                            }
                        });
                    }
                    
                    // Safety timeout after 5 minutes
                    if (Date.now() - startTime > 300000) {
                        console.log('   ⏰ Monitoring timeout reached');
                        clearInterval(intervalId);
                    }
                    
                } catch (pollError) { 
                    if (pollError.response) {
                        console.error('   Error during polling:', {
                            status: pollError.response.status,
                            statusText: pollError.response.statusText,
                            data: pollError.response.data
                        });
                    } else if (pollError.request) {
                        console.error('   No response received:', pollError.request);
                    } else {
                        console.error('   Polling error:', pollError.message);
                    }
                }
                
            }, TEST_CONFIG.pollInterval); // Use 5 second interval  
            
        } catch (error) {
            logError(error, 'setting up order monitoring');
        }
    }

    async runFullTest() {
        const totalStartTime = Date.now();
        
        try {
            console.log('🧪 Starting Fusion+ SDK Test \n');
            console.log('=' .repeat(50));  
            
            // Step 1: Initialize
            await this.initialize();
            
            // Step 2: Check balances
            const balanceInfo = await this.checkBalances();
            
            // Step 3: Check token approval
            const isApproved = await this.checkTokenApproval();
            
            // Step 4: Get quote
            const quote = await this.getQuote();
            
            // Step 5: Generate secrets
            const orderParams = await this.createSecrets(quote);
            
            // Step 6: Place order (if enabled)
            const orderResponse = await this.placeOrder(quote, orderParams);
            
            // Step 7: Monitor order (if placed)
            if (orderResponse) {
                await this.monitorOrder(orderResponse, orderParams.secrets);
            }
            
            const totalDuration = formatDuration(Date.now() - totalStartTime);
            console.log(`\n🎉 Test completed! Total time: ${totalDuration}`);
            console.log('=' .repeat(50));
            
        } catch (error) {
            logError(error, 'during full test execution');
            
            const totalDuration = formatDuration(Date.now() - totalStartTime);
            console.log(`\n💥 Test failed after ${totalDuration}`);
            console.log('=' .repeat(50));
            
            process.exit(1);
        }
    }

    async runQuoteOnlyTest() {
        try {
            console.log('📊 Starting Quote-Only Test \n');
            console.log('=' .repeat(40));
            
            await this.initialize();
            await this.checkBalances();
            const quote = await this.getQuote();
            
            if (quote) {
                const orderParams = await this.createSecrets(quote);
                console.log('\n✅ Quote and secrets generated successfully!');
                console.log('💡 To place actual orders, set enableOrderPlacement: true');
            }
            
            console.log('=' .repeat(40));
            
            return quote;
            
        } catch (error) {
            logError(error, 'during quote-only test');
            process.exit(1);
        }
    }
}

// Main execution
async function main() {
    const tester = new FusionPlusSDKTester();
    
    // Check command line arguments
    const args = process.argv.slice(2);
    const quoteOnly = args.includes('--quote-only') || args.includes('-q');
    
    if (quoteOnly) {
        await tester.runQuoteOnlyTest();
    } else {
        await tester.runFullTest();
    }
}

// Run the test
if (require.main === module) {
    main().catch(error => {
        console.error('Fatal error:', error);
        process.exit(1);
    });
}

module.exports = { FusionPlusSDKTester, TEST_CONFIG };
