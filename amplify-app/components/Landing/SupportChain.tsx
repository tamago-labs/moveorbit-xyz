"use client"

import React from 'react';
import { motion } from 'framer-motion';

const SupportedChainsSection = () => {

  const evmChains = [
    { name: 'Ethereum', symbol: 'ETH', color: 'bg-blue-500' },
    { name: 'BSC', symbol: 'BNB', color: 'bg-yellow-500' },
    { name: 'Polygon', symbol: 'MATIC', color: 'bg-purple-500' },
  ];

  const moveChains = [
    { name: 'Aptos', symbol: 'APT', color: 'bg-green-500' },
    { name: 'Sui', symbol: 'SUI', color: 'bg-cyan-500' },
    // { name: 'Movement', symbol: 'MOVE', color: 'bg-indigo-500' },
  ];

  return (
    <div className="w-full py-16" >
      <div className="max-w-6xl mx-auto px-4 md:px-10">
        {/* Header */}
        <motion.div
          className="text-center mb-12"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          viewport={{ once: true }}
        >
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            Supported Networks
          </h2>
          <p className="text-slate-400 text-lg max-w-2xl mx-auto">
            Bridge assets seamlessly between EVM and Move-based ecosystems
          </p>
        </motion.div>

        {/* Chains Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          {/* EVM Chains */}
          <motion.div
            className="space-y-4"
            initial={{ opacity: 0, x: -30 }}
            whileInView={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.6, delay: 0.2 }}
            viewport={{ once: true }}
          >
            <div className="flex items-center gap-3 mb-6">
              <div className="w-3 h-3 bg-blue-500 rounded-full"></div>
              <h3 className="text-xl font-semibold text-white">EVM Chains</h3>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {evmChains.map((chain, index) => (
                <motion.div
                  key={chain.symbol}
                  className="bg-slate-800/50 backdrop-blur-sm rounded-lg border border-slate-700/50 p-4 hover:bg-slate-700/50 hover:border-slate-600/50 transition-all duration-300"
                  initial={{ opacity: 0, y: 20 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.4, delay: 0.3 + (index * 0.1) }}
                  viewport={{ once: true }}
                >
                  <div className="flex items-center gap-3">
                    <div className={`w-8 h-8 ${chain.color} rounded-full flex items-center justify-center`}>
                      <span className="text-white text-xs font-bold">
                        {chain.symbol.slice(0, 2)}
                      </span>
                    </div>
                    <div>
                      <div className="text-white font-medium text-sm">{chain.name}</div>
                      <div className="text-slate-400 text-xs">{chain.symbol}</div>
                    </div>
                  </div>
                </motion.div>
              ))}
            </div>
          </motion.div>

          {/* Move Chains */}
          <motion.div
            className="space-y-4"
            initial={{ opacity: 0, x: 30 }}
            whileInView={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.6, delay: 0.4 }}
            viewport={{ once: true }}
          >
            <div className="flex items-center gap-3 mb-6">
              <div className="w-3 h-3 bg-cyan-500 rounded-full"></div>
              <h3 className="text-xl font-semibold text-white">Move Chains</h3>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              {moveChains.map((chain, index) => (
                <motion.div
                  key={chain.symbol}
                  className="bg-slate-800/50 backdrop-blur-sm rounded-lg border border-slate-700/50 p-4 hover:bg-slate-700/50 hover:border-slate-600/50 transition-all duration-300"
                  initial={{ opacity: 0, y: 20 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.4, delay: 0.5 + (index * 0.1) }}
                  viewport={{ once: true }}
                >
                  <div className="flex items-center gap-3">
                    <div className={`w-8 h-8 ${chain.color} rounded-full flex items-center justify-center`}>
                      <span className="text-white text-xs font-bold">
                        {chain.symbol.slice(0, 2)}
                      </span>
                    </div>
                    <div>
                      <div className="text-white font-medium text-sm">{chain.name}</div>
                      <div className="text-slate-400 text-xs">{chain.symbol}</div>
                    </div>
                  </div>
                </motion.div>
              ))}
            </div>

            {/* Coming Soon Badge */}
            {/* <motion.div
              className="bg-slate-800/30 backdrop-blur-sm rounded-lg border border-slate-700/30 p-4 mt-4"
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              transition={{ duration: 0.4, delay: 0.8 }}
              viewport={{ once: true }}
            >
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 bg-slate-600/50 rounded-full flex items-center justify-center">
                  <span className="text-slate-400 text-xs font-bold">+</span>
                </div>
                <div>
                  <div className="text-slate-400 font-medium text-sm">More chains</div>
                  <div className="text-slate-500 text-xs">Coming soon</div>
                </div>
              </div>
            </motion.div> */}
          </motion.div>
        </div>

        {/* Bottom Stats */}
        <motion.div
          className="text-center mt-12 pt-8 border-t border-slate-800/50"
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          transition={{ duration: 0.6, delay: 0.6 }}
          viewport={{ once: true }}
        >
          <div className="grid grid-cols-1 sm:grid-cols-1 gap-6 max-w-lg mx-auto">
            <div>
              <div className="text-slate-400 font-medium text-sm">More chains</div>
              {/* <div className="text-slate-500 text-xs">Coming soon</div> */}
            </div>
            {/* <div>
              <div className="text-2xl font-bold text-white">9+</div>
              <div className="text-slate-400 text-sm">Total Networks</div>
            </div>
            <div>
              <div className="text-2xl font-bold text-white">2</div>
              <div className="text-slate-400 text-sm">Ecosystems</div>
            </div>
            <div>
              <div className="text-2xl font-bold text-white">100+</div>
              <div className="text-slate-400 text-sm">Token Pairs</div>
            </div> */}
          </div>
        </motion.div>
      </div>
    </div>
  );
};

export default SupportedChainsSection;