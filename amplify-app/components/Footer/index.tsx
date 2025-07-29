import React from 'react'; 

const Footer = () => {
    const currentYear = new Date().getFullYear();

    return (
        <footer className="relative   overflow-hidden">
            {/* Gradient overlay at the top */}
            <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-slate-700 to-transparent" />

            <div className="max-w-7xl mx-auto px-6 md:px-10">

                {/* Social links and disclaimer */}
                <div className=" mt-6  flex flex-col md:flex-row justify-between items-center gap-4">
                    <div className="flex gap-6">
                        <span className="text-slate-500 text-sm text-center md:text-left">
                            Made with ❤️ during ETHGlobal Unite DeFi
                        </span> 
                    </div>

                    <p className="text-slate-500 text-sm text-center md:text-right">
                        &copy; {currentYear} MoveOrbit.xyz. All rights reserved.
                    </p>
                </div>
            </div>
        </footer>
    );
};

export default Footer;