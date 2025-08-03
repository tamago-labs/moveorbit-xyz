"use client"

import React from 'react';
import { motion } from 'framer-motion';
import { ArrowRight, BookOpen, MessageCircle, Github } from 'lucide-react';

const GetStartedCTA = () => {
    const quickLinks = [
        {
            icon: <BookOpen size={20} />,
            title: "Documentation",
            description: "Complete guides and API reference",
            link: "/docs"
        },
        {
            icon: <MessageCircle size={20} />,
            title: "Discord",
            description: "Join our community for support",
            link: "#"
        },
        {
            icon: <Github size={20} />,
            title: "GitHub",
            description: "Open source code and updates",
            link: "#"
        }
    ];

    return (
        <div className="w-full py-24 pt-0 " >
            <div className="max-w-4xl mx-auto px-4 md:px-10">
                {/* Main CTA */}
                <motion.div
                    className="text-center mb-16"
                    initial={{ opacity: 0, y: 30 }}
                    whileInView={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.6 }}
                    viewport={{ once: true }}
                >
                    <h2 className="text-3xl md:text-4xl font-bold text-white mb-6 leading-tight">
                        Start Your First Swap 
                    </h2>
                    <p className="text-slate-400 text-base md:text-lg mb-8 max-w-2xl mx-auto leading-relaxed">
                        Experience seamless asset bridging between EVM and Move ecosystems with enterprise-grade security and lightning-fast settlements.
                    </p>
 
                    <motion.button
                        className="group inline-flex items-center gap-3 px-8 py-4 bg-white text-slate-900 font-semibold rounded-lg hover:bg-slate-100 transition-all duration-300 mb-4"
                        whileHover={{ scale: 1.02 }}
                        whileTap={{ scale: 0.98 }}
                    >
                        Launch MoveOrbit
                        <ArrowRight size={18} className="group-hover:translate-x-1 transition-transform" />
                    </motion.button>

                    <div className="text-slate-500 text-sm">
                        No registration required • Connect wallet to start
                    </div>
                </motion.div>

                {/* Quick Links */}
                <motion.div
                    className="grid grid-cols-1 md:grid-cols-3 gap-6"
                    initial={{ opacity: 0, y: 20 }}
                    whileInView={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.6, delay: 0.2 }}
                    viewport={{ once: true }}
                >
                    {quickLinks.map((link, index) => (
                        <motion.a
                            key={link.title}
                            href={link.link}
                            className="group bg-slate-800/30 backdrop-blur-sm rounded-lg border border-slate-700/40 p-6 hover:bg-slate-800/50 hover:border-slate-600/40 transition-all duration-300 text-center"
                            initial={{ opacity: 0, y: 20 }}
                            whileInView={{ opacity: 1, y: 0 }}
                            transition={{ duration: 0.4, delay: 0.3 + (index * 0.1) }}
                            viewport={{ once: true }}
                            whileHover={{ y: -4 }}
                        >
                            <div className="w-12 h-12 bg-slate-700 rounded-lg flex items-center justify-center text-slate-300 mx-auto mb-4 group-hover:bg-slate-600 group-hover:text-white transition-all duration-300">
                                {link.icon}
                            </div>
                            <h3 className="text-white font-semibold mb-2 group-hover:text-white transition-colors">
                                {link.title}
                            </h3>
                            <p className="text-slate-400 text-sm group-hover:text-slate-300 transition-colors">
                                {link.description}
                            </p>
                        </motion.a>
                    ))}
                </motion.div>

                

                {/* Security Notice */}
                {/* <motion.div
                    className="mt-12 bg-slate-800/20 backdrop-blur-sm rounded-lg border border-slate-700/30 p-6"
                    initial={{ opacity: 0, y: 20 }}
                    whileInView={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.6, delay: 0.6 }}
                    viewport={{ once: true }}
                >
                    <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                        <div>
                            <div className="text-white font-medium mb-1">Secure & Audited</div>
                            <div className="text-slate-400 text-sm">
                                Smart contracts audited by leading security firms. Your funds are always secure.
                            </div>
                        </div>
                        <div className="flex items-center gap-4">
                            <div className="text-slate-500 text-xs">Audited by:</div>
                            <div className="flex items-center gap-3">
                                <div className="bg-slate-700/50 px-3 py-1 rounded text-slate-300 text-xs font-medium">
                                    Certik
                                </div>
                                <div className="bg-slate-700/50 px-3 py-1 rounded text-slate-300 text-xs font-medium">
                                    Trail of Bits
                                </div>
                            </div>
                        </div>
                    </div>
                </motion.div> */}
            </div>
        </div>
    );
};

export default GetStartedCTA;