import { randomBytes, createHash } from 'crypto';
import { logger } from '../utils/logger';

export interface SwapSecret {
  secret: string;
  secretHash: string;
  orderHash: string;
}

export class SecretManager {
  private secrets: Map<string, SwapSecret> = new Map();

  generateSecret(): string {
    return '0x' + randomBytes(32).toString('hex');
  }

  hashSecret(secret: string): string {
    // Remove 0x prefix if present
    const cleanSecret = secret.startsWith('0x') ? secret.slice(2) : secret;
    
    // Create keccak256 hash (using SHA3-256 as approximation)
    const hash = createHash('sha3-256').update(Buffer.from(cleanSecret, 'hex')).digest('hex');
    return '0x' + hash;
  }

  createSecretForOrder(orderHash: string): SwapSecret {
    const secret = this.generateSecret();
    const secretHash = this.hashSecret(secret);
    
    const swapSecret: SwapSecret = {
      secret,
      secretHash,
      orderHash,
    };

    this.secrets.set(orderHash, swapSecret);
    
    logger.debug('Generated secret for order', {
      orderHash,
      secretHash,
      secretLength: secret.length,
    });

    return swapSecret;
  }

  getSecret(orderHash: string): SwapSecret | undefined {
    return this.secrets.get(orderHash);
  }

  storeSecret(orderHash: string, secret: string): SwapSecret {
    const secretHash = this.hashSecret(secret);
    
    const swapSecret: SwapSecret = {
      secret,
      secretHash,
      orderHash,
    };

    this.secrets.set(orderHash, swapSecret);
    return swapSecret;
  }

  verifySecret(secret: string, expectedHash: string): boolean {
    const computedHash = this.hashSecret(secret);
    return computedHash === expectedHash;
  }

  removeSecret(orderHash: string): boolean {
    return this.secrets.delete(orderHash);
  }

  getAllSecrets(): SwapSecret[] {
    return Array.from(this.secrets.values());
  }

  clearAllSecrets(): void {
    this.secrets.clear();
    logger.info('All secrets cleared from memory');
  }
}

// Global secret manager instance
export const secretManager = new SecretManager();
