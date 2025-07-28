"use client"

import { Gem, Menu, X,  SquareMousePointer } from "lucide-react"
import Link from "next/link"
import { motion } from 'framer-motion'
import { usePathname } from 'next/navigation'
import { useState } from 'react'

const Header = () => {
    const pathname = usePathname()
    const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false)

    const toggleMobileMenu = () => {
        setIsMobileMenuOpen(!isMobileMenuOpen)
    }

    const closeMobileMenu = () => {
        setIsMobileMenuOpen(false)
    }

    return (
        <>
            <nav className="flex max-w-7xl w-full mx-auto justify-between items-center mb-4 px-4 md:px-0">
                {/* Logo Section */}
                <div className="flex items-center">
                    <Link href="/" onClick={closeMobileMenu} className="flex items-center space-x-3 md:space-x-4 group">
                        <div className="relative flex items-center justify-center w-10 h-10 md:w-12 md:h-12">
                            <div className="absolute inset-0 bg-blue-500/20 rounded-xl blur-sm group-hover:bg-blue-500/30 transition-all duration-300"></div>
                            <div className="relative flex items-center justify-center w-8 h-8 md:w-10 md:h-10 rounded-xl bg-gradient-to-br from-blue-600 via-purple-600 to-blue-800 shadow-lg shadow-blue-500/25">
                                <SquareMousePointer className="w-4 h-4 md:w-5 md:h-5 text-white font-bold" strokeWidth={2.5} />                      
                            </div>
                        </div>
                        <div className="flex flex-col">
                            <span className="text-white text-lg md:text-2xl font-bold">Move</span>
                            <span className="text-transparent bg-gradient-to-r from-blue-400 via-purple-400 to-cyan-400 bg-clip-text text-lg md:text-2xl font-bold -mt-2">Orbit</span>
                        </div>
                    </Link>
                </div>

                {/* Desktop Navigation */}
                <div className="hidden md:flex text-base space-x-20 text-gray-300">
                    <Link href="/trade" className={`hover:text-white transition-colors ${pathname === "/trade" ? "text-white" : ""}`}>
                        Trade
                    </Link>
                    <Link href="/markets" className={`hover:text-white transition-colors ${pathname === "/markets" ? "text-white" : ""}`}>
                        Orders
                    </Link>
                    <Link href="/rewards" className={`hover:text-white transition-colors ${pathname === "/rewards" ? "text-white" : ""}`}>
                        Account
                    </Link>
                </div>

                {/* Desktop Connect Wallet Button */}
                <button className="hidden md:block px-6 py-2 rounded-full bg-gradient-to-r from-blue-500 to-purple-600 text-white font-medium hover:shadow-lg hover:from-blue-600 hover:to-purple-700 transition-all">
                    Connect Wallet
                </button>

                {/* Mobile Menu Button */}
                <button
                    onClick={toggleMobileMenu}
                    className="md:hidden p-2 text-white hover:text-gray-300 transition-colors"
                    aria-label="Toggle mobile menu"
                >
                    {isMobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
                </button>
            </nav>

            {/* Mobile Menu Overlay */}
            {isMobileMenuOpen && (
                <motion.div
                    className="md:hidden fixed inset-0 bg-black/50 backdrop-blur-sm z-50"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    onClick={closeMobileMenu}
                >
                    <motion.div
                        className="absolute top-0 right-0 w-64 h-full bg-gray-900 shadow-xl"
                        initial={{ x: "100%" }}
                        animate={{ x: 0 }}
                        exit={{ x: "100%" }}
                        transition={{ type: "tween", duration: 0.3 }}
                        onClick={(e) => e.stopPropagation()}
                    >
                        {/* Mobile Menu Header */}
                        <div className="flex justify-between items-center p-4 border-b border-gray-700">
                            <span className="text-white font-bold text-lg">Menu</span>
                            <button
                                onClick={closeMobileMenu}
                                className="p-1 text-white hover:text-gray-300 transition-colors"
                            >
                                <X size={20} />
                            </button>
                        </div>

                        {/* Mobile Navigation Links */}
                        <div className="flex flex-col p-4 space-y-6">
                            <Link
                                href="/trade"
                                onClick={closeMobileMenu}
                                className={`text-lg hover:text-white transition-colors ${pathname === "/trade" ? "text-white font-semibold" : "text-gray-300"}`}
                            >
                                Trade
                            </Link>
                            <Link
                                href="/markets"
                                onClick={closeMobileMenu}
                                className={`text-lg hover:text-white transition-colors ${pathname === "/markets" ? "text-white font-semibold" : "text-gray-300"}`}
                            >
                                Orders
                            </Link>
                            <Link
                                href="/rewards"
                                onClick={closeMobileMenu}
                                className={`text-lg hover:text-white transition-colors ${pathname === "/rewards" ? "text-white font-semibold" : "text-gray-300"}`}
                            >
                                Account
                            </Link>
                        </div>

                        {/* Mobile Connect Wallet Button */}
                        <div className="p-4 mt-8">
                            <button
                                onClick={closeMobileMenu}
                                className="w-full px-6 py-3 rounded-full bg-gradient-to-r from-blue-500 to-purple-600 text-white font-medium hover:shadow-lg hover:from-blue-600 hover:to-purple-700 transition-all"
                            >
                                Connect Wallet
                            </button>
                        </div>
                    </motion.div>
                </motion.div>
            )}
        </>
    )
}

export default Header