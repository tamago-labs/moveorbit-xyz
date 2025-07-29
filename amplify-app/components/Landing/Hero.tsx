"use client"

import React from 'react';
import { motion } from 'framer-motion';
import { ArrowRight, Zap, Shield, Globe, ChevronUp, ChevronDown } from 'lucide-react';

const HeroSection = () => {
    // Mock data for cross-chain assets
    const crossChainAssets = [
        { symbol: 'ETH', chain: 'Ethereum', price: '$3,124.50', change: '+2.3%', isUp: true },
        { symbol: 'SUI', chain: 'Sui', price: '$4.82', change: '+5.7%', isUp: true },
        { symbol: 'APT', chain: 'Aptos', price: '$12.45', change: '-1.2%', isUp: false },
        { symbol: 'USDC', chain: 'Multi-chain', price: '$1.00', change: '+0.1%', isUp: true },
        { symbol: 'BTC', chain: 'Wrapped', price: '$97,342', change: '+1.8%', isUp: true },
        { symbol: 'MOVE', chain: 'Movement', price: '$2.15', change: '+12.4%', isUp: true },
    ];

    const crossChainAssets2 = [
        { name: 'ETH', color: '#627eea' },
        { name: 'APT', color: '#00d4ff' },
        { name: 'SUI', color: '#4da2ff' },
        { name: 'BTC', color: '#f7931a' },
        { name: 'USDC', color: '#2775ca' },
        { name: 'USDT', color: '#26a17b' }
      ]

    return (
        <div className="relative w-full  py-20">

            <div className="max-w-7xl mx-auto px-4 md:px-10 relative z-10">
                <div className="flex flex-col lg:flex-row items-center justify-between gap-16">
                    {/* Left column - Hero content */}
                    <div className="w-full lg:w-1/2 space-y-8">
                        <motion.div
                            className="inline-flex items-center gap-2 px-4 py-2 bg-blue-500/10 border border-blue-500/20 rounded-full text-blue-400 text-sm"
                            initial={{ opacity: 0, y: 20 }}
                            animate={{ opacity: 1, y: 0 }}
                            transition={{ duration: 0.5 }}
                        >
                            <Zap size={16} className="text-blue-400" />
                            Powered by 1inch Fusion+ Protocol
                        </motion.div>

                        <motion.h1
                            className="text-4xl md:text-5xl lg:text-6xl font-bold text-white leading-tight"
                            initial={{ opacity: 0, y: 30 }}
                            animate={{ opacity: 1, y: 0 }}
                            transition={{ duration: 0.6, delay: 0.1 }}
                        >
                            Where
                            <span className="bg-gradient-to-r from-blue-400 via-purple-400 to-cyan-400 bg-clip-text text-transparent">
                                {" "}EVM x Move{" "}
                            </span>
                            Innovation
                        </motion.h1>

                        <motion.p
                            className="text-slate-400 text-base md:text-lg max-w-2xl leading-relaxed"
                            initial={{ opacity: 0, y: 30 }}
                            animate={{ opacity: 1, y: 0 }}
                            transition={{ duration: 0.6, delay: 0.2 }}
                        >
                            Faster, cheaper cross-chain swaps between EVM chains and Move-based ecosystems like Aptos and Sui
                        </motion.p>
 
                        {/* CTA Buttons */}
                        <motion.div
            className="flex flex-col sm:flex-row gap-3 sm:gap-4 pt-4 w-full max-w-md"
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.4 }}
        >
            <button className="group flex-1 px-4 py-3 sm:px-8 sm:py-4 bg-gradient-to-r from-blue-500 via-purple-500 to-cyan-500 text-white font-medium sm:font-semibold text-sm sm:text-base rounded-xl flex items-center justify-center gap-2 sm:gap-3 hover:shadow-xl hover:shadow-blue-500/25 transition-all duration-300 hover:scale-105">
                Start Trading
                <ArrowRight size={16} className="sm:w-[18px] sm:h-[18px] group-hover:translate-x-1 transition-transform" />
            </button>

            <button className="flex-1 px-4 py-3 sm:px-8 sm:py-4 bg-slate-800/80 backdrop-blur-sm text-white font-medium sm:font-semibold text-sm sm:text-base rounded-xl border border-slate-700/50 hover:bg-slate-700/80 hover:border-slate-600/50 transition-all duration-300">
                Explore Docs
            </button>
        </motion.div>


                    </div>

                    {/* Right column - Interactive visualization */}
                    <div className="w-full lg:w-1/2 flex justify-center">
                        <div className="relative w-full max-w-lg aspect-square">

            


                            {/* Connection lines */}
                            {crossChainAssets.map((asset, i) => {
                                const angle = (i * 60) * (Math.PI / 180);
                                const radius = 180;
                                const x1 = 50 + (Math.cos(angle) * 12);
                                const y1 = 50 + (Math.sin(angle) * 12);
                                const x2 = 50 + (Math.cos(angle) * 35);
                                const y2 = 50 + (Math.sin(angle) * 35);

                                return (
                                    <svg key={`line-${i}`} className="absolute top-0 left-0 w-full h-full z-0">
                                        <motion.line
                                            x1={`${x1}%`}
                                            y1={`${y1}%`}
                                            x2={`${x2}%`}
                                            y2={`${y2}%`}
                                            stroke="url(#connectionGradient)"
                                            strokeWidth="2"
                                            strokeDasharray="8,4"
                                            initial={{ opacity: 0 }}
                                            animate={{
                                                opacity: [0, 0.6, 0.6, 0.3, 0.6],
                                                strokeDashoffset: [0, -12, -24, -36, -48]
                                            }}
                                            transition={{
                                                duration: 6,
                                                times: [0, 0.2, 0.7, 0.85, 1],
                                                repeat: Infinity,
                                                delay: i * 1.2,
                                                repeatDelay: 8
                                            }}
                                        />
                                        <defs>
                                            <linearGradient id="connectionGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                                                <stop offset="0%" stopColor="#3b82f6" />
                                                <stop offset="50%" stopColor="#8b5cf6" />
                                                <stop offset="100%" stopColor="#06b6d4" />
                                            </linearGradient>
                                        </defs>
                                    </svg>
                                );
                            })}


                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default HeroSection;