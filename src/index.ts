#!/usr/bin/env node

import dotenv from 'dotenv';
import { interactiveCommand } from './commands/interactive';
import { logger } from './utils/logger';

// Load environment variables
dotenv.config();

// Validate environment setup
function validateEnvironment() {
  const requiredEnvVars = [
    'USER_SUI_PRIVATE_KEY', 
    'USER_EVM_PRIVATE_KEY',
    'RESOLVER_SUI_PRIVATE_KEY',
    'RESOLVER_EVM_PRIVATE_KEY'
  ];
  
  const missingVars = requiredEnvVars.filter(varName => !process.env[varName]);

  if (missingVars.length > 0) {
    logger.error('Missing required environment variables:');
    missingVars.forEach(varName => {
      logger.error(`  - ${varName}`);
    });
    logger.info('\nPlease set up your .env file based on .env.example');
    logger.info('You need separate private keys for:');
    logger.info('  - User (for creating orders)');
    logger.info('  - Resolver (for processing swaps)');
    logger.info('  - Both EVM and SUI chains');
    process.exit(1);
  }
}

async function main() {
  try {
    console.log('🚀 Welcome to MoveOrbit Cross-Chain Swap CLI');
    console.log('================================================');
    
    // Validate environment
    validateEnvironment();
    
    // Always run in interactive mode
    await interactiveCommand.parseAsync(['interactive'], { from: 'user' });
    
  } catch (error) {
    logger.error('CLI execution failed:', error);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  logger.info('\n👋 Goodbye! Thanks for using MoveOrbit CLI');
  process.exit(0);
});

process.on('SIGTERM', () => {
  logger.info('\n👋 CLI terminated');
  process.exit(0);
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection:', { promise, reason });
  process.exit(1);
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  logger.error('Uncaught Exception:', error);
  process.exit(1);
});

// Start the CLI
main();
