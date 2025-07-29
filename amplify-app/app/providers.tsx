"use client";

import { useState, useEffect, useRef } from "react";
import { motion } from 'framer-motion';
import { Amplify } from "aws-amplify";

import outputs from "@/amplify_outputs.json";
import "@aws-amplify/ui-react/styles.css";

Amplify.configure(outputs);

export function Providers({ children }: any) {


    return (
        <div className="relative min-h-screen overflow-hidden bg-slate-900">
            {/* Subtle radial gradient */}
            <div className="absolute inset-0 bg-radial-gradient from-slate-800 to-transparent opacity-50" />

            {/* Abstract gradient blobs */}
            <div className="absolute inset-0 overflow-hidden">
                <motion.div
                    className="absolute rounded-full bg-blue-600/10 blur-3xl"
                    style={{
                        width: '40%',
                        height: '40%',
                        top: '10%',
                        left: '20%',
                    }}
                    animate={{
                        x: [0, 50, -30, 0],
                        y: [0, -30, 40, 0],
                    }}
                    transition={{
                        duration: 20,
                        repeat: Infinity,
                        ease: "easeInOut"
                    }}
                />

                <motion.div
                    className="absolute rounded-full bg-purple-600/10 blur-3xl"
                    style={{
                        width: '50%',
                        height: '50%',
                        bottom: '10%',
                        right: '10%',
                    }}
                    animate={{
                        x: [0, -40, 20, 0],
                        y: [0, 40, -30, 0],
                    }}
                    transition={{
                        duration: 25,
                        repeat: Infinity,
                        ease: "easeInOut"
                    }}
                />

                <motion.div
                    className="absolute rounded-full bg-cyan-600/10 blur-3xl"
                    style={{
                        width: '30%',
                        height: '30%',
                        bottom: '20%',
                        left: '10%',
                    }}
                    animate={{
                        x: [0, 30, -20, 0],
                        y: [0, -20, 30, 0],
                    }}
                    transition={{
                        duration: 18,
                        repeat: Infinity,
                        ease: "easeInOut"
                    }}
                />
            </div>

            {/* Subtle noise texture overlay */}
            <div
                className="absolute inset-0 opacity-30 mix-blend-overlay"
                style={{
                    backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.65' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)' opacity='0.1'/%3E%3C/svg%3E")`,
                    backgroundRepeat: 'repeat',
                    backgroundSize: '200px 200px'
                }}
            />

            {/* Bottom highlight gradient */}
            <div className="absolute bottom-0 left-0 right-0 h-1/3 bg-gradient-to-t from-blue-600/5 to-transparent" />
            {/* <WalletProvider>
                <AccountProvider>
                    {children}
                </AccountProvider>
            </WalletProvider> */}
            {children}
        </div>
    );
}

