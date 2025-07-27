import GetStartedCTA from "@/components/Landing/CTA";
import HeroSection from "@/components/Landing/Hero";
import HowItWorksSection from "@/components/Landing/HowItWorks";
import KeyFeaturesGrid from "@/components/Landing/KeyFeatures";
import SupportedChainsSection from "@/components/Landing/SupportChain";
import WhyChooseMoveOrbit from "@/components/Landing/WhyChooseMoveOrbit";

 

export default function App() {
   
  return (
    <main>
       <HeroSection/>
       <SupportedChainsSection/>
       <HowItWorksSection/>
       {/* <KeyFeaturesGrid/> */}
       <WhyChooseMoveOrbit/>
       <GetStartedCTA/>
    </main>
  );
}
