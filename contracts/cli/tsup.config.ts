import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['cjs'],
  dts: true,
  clean: true,
  splitting: false,
  sourcemap: true,
  minify: false,
  target: 'node16',
  outDir: 'dist',
  banner: {
    js: '#!/usr/bin/env node',
  },
  external: [
    '@mysten/sui',
    'viem', 
    'commander',
    'prompts',
    'dotenv',
    'axios',
    'bignumber.js',
    '@aptos-labs/ts-sdk'
  ],
});
