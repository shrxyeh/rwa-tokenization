"use client";

import { useReadContract } from "wagmi";
import { RWA_FACTORY_ABI, PROPERTY_NFT_ABI } from "@/lib/abis";
import { RWA_FACTORY_ADDRESS, PROPERTY_NFT_ADDRESS } from "@/lib/wagmiConfig";
import type { AssetRecord, PropertyMetadata } from "@/types/contracts";

export function useAllAssets() {
  const { data, isLoading, refetch } = useReadContract({
    address: RWA_FACTORY_ADDRESS,
    abi: RWA_FACTORY_ABI,
    functionName: "getAllAssets",
  });

  return {
    assets: (data as AssetRecord[] | undefined) ?? [],
    isLoading,
    refetch,
  };
}

export function usePropertyDetails(tokenId: bigint | undefined) {
  const { data, isLoading } = useReadContract({
    address: PROPERTY_NFT_ADDRESS,
    abi: PROPERTY_NFT_ABI,
    functionName: "getPropertyDetails",
    args: tokenId !== undefined ? [tokenId] : undefined,
    query: { enabled: tokenId !== undefined },
  });

  return {
    property: data as PropertyMetadata | undefined,
    isLoading,
  };
}
