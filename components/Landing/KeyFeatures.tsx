"use client"

import React from 'react';
import { motion } from 'framer-motion';
import { Shield, Layers, Settings, Zap } from 'lucide-react';

const KeyFeaturesGrid = () => {
  const features = [
    {
      icon: <Shield size={28} />,
      title: "Atomic Swaps",
      description: "Zero counterparty risk with hash-time locked contracts ensuring either both transactions complete or both fail",
      color: "from-green-500 to-emerald-600",
      bgColor: "bg-green-500/10",
      borderColor: "border-green-500/20"
    },
    {
      icon: <Layers size={28} />,
      title: "Partial Fills",
      description: "Execute large orders in smaller chunks with multiple secrets for better liquidity and reduced slippage",
      color: "from-blue-500 to-blue-600", 
      bgColor: "bg-blue-500/10",
      borderColor: "border-blue-500/20"
    },
    {
      icon: <Settings size={28} />,
      title: "Order Management", 
      description: "Cancel or modify orders before execution with flexible timelock parameters and safety deposits",
      color: "from-purple-500 to-purple-600",
      bgColor: "bg-purple-500/10", 
      borderColor: "border-purple-500/20"
    },
    {
      icon: <Zap size={28} />,
      title: "Cross-Chain Native",
      description: "Purpose-built for EVM ↔ Move ecosystems with optimized bridging between different blockchain architectures",
      color: "from-cyan-500 to-cyan-600",
      bgColor: "bg-cyan-500/10",
      borderColor: "border-cyan-500/20"
    }
  ];

  return (
    <div className="w-full py-20  ">
      <div className="max-w-6xl mx-auto px-4 md:px-10">
        {/* Header */}
        <motion.div
          className="text-center mb-16"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          viewport={{ once: true }}
        >
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-4">
            Key Features
          </h2>
          <p className="text-slate-400 text-lg max-w-2xl mx-auto">
            Advanced cross-chain technology designed for security, flexibility, and seamless user experience
          </p>
        </motion.div>

        {/* Features Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {features.map((feature, index) => (
            <motion.div
              key={feature.title}
              className={`${feature.bgColor} backdrop-blur-sm rounded-xl border ${feature.borderColor} p-8 hover:scale-[1.02] transition-all duration-300 group`}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.6, delay: index * 0.1 }}
              viewport={{ once: true }}
            >
              {/* Icon */}
              <motion.div
                className={`w-16 h-16 rounded-xl bg-gradient-to-r ${feature.color} flex items-center justify-center text-white mb-6 group-hover:scale-110 transition-transform duration-300`}
                whileHover={{ rotate: 5 }}
              >
                {feature.icon}
              </motion.div>

              {/* Content */}
              <div>
                <h3 className="text-xl font-bold text-white mb-4 group-hover:text-white transition-colors">
                  {feature.title}
                </h3>
                <p className="text-slate-400 leading-relaxed group-hover:text-slate-300 transition-colors">
                  {feature.description}
                </p>
              </div>

              {/* Subtle background gradient */}
              <div className={`absolute inset-0 rounded-xl bg-gradient-to-br ${feature.color} opacity-0 group-hover:opacity-5 transition-opacity duration-300 pointer-events-none`} />
            </motion.div>
          ))}
        </div>

        {/* Bottom highlight */}
        <motion.div
          className="mt-16 text-center"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.6 }}
          viewport={{ once: true }}
        >
          <div className="bg-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700/50 p-8 max-w-3xl mx-auto">
            <div className="flex items-center justify-center gap-3 mb-4">
              <div className="w-8 h-8 bg-gradient-to-r from-blue-500 to-purple-500 rounded-lg flex items-center justify-center">
                <Shield size={16} className="text-white" />
              </div>
              <h4 className="text-lg font-semibold text-white">Built on 1inch Fusion+</h4>
            </div>
            <p className="text-slate-400 text-sm max-w-2xl mx-auto">
              Leveraging battle-tested infrastructure with enhanced security mechanisms specifically optimized for cross-chain operations between EVM and Move-based networks.
            </p>
          </div>
        </motion.div>
      </div>
    </div>
  );
};

export default KeyFeaturesGrid;