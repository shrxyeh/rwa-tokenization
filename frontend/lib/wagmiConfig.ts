import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { sepolia, anvil } from "wagmi/chains";

export const config = getDefaultConfig({
  appName: "RWA Tokenization",
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "demo",
  chains: [sepolia, anvil],
  ssr: true,
});

export const IDENTITY_REGISTRY_ADDRESS = (
  process.env.NEXT_PUBLIC_IDENTITY_REGISTRY_ADDRESS ?? "0x0000000000000000000000000000000000000000"
) as `0x${string}`;

export const PROPERTY_NFT_ADDRESS = (
  process.env.NEXT_PUBLIC_PROPERTY_NFT_ADDRESS ?? "0x0000000000000000000000000000000000000000"
) as `0x${string}`;

export const RWA_FACTORY_ADDRESS = (
  process.env.NEXT_PUBLIC_RWA_FACTORY_ADDRESS ?? "0x0000000000000000000000000000000000000000"
) as `0x${string}`;
