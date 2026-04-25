"use client";

import { useReadContract } from "wagmi";
import { IDENTITY_REGISTRY_ABI } from "@/lib/abis";
import { IDENTITY_REGISTRY_ADDRESS } from "@/lib/wagmiConfig";
import type { InvestorData } from "@/types/contracts";

export function useIdentity(address: `0x${string}` | undefined) {
  const { data: verified, isLoading: loadingVerified } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "isVerified",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: investorData, isLoading: loadingData } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getInvestor",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  return {
    isVerified: verified ?? false,
    investor: investorData as InvestorData | undefined,
    isLoading: loadingVerified || loadingData,
  };
}
