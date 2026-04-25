"use client";

import { useReadContract } from "wagmi";
import { RWA_FACTORY_ABI, PROPERTY_NFT_ABI } from "@/lib/abis";
import { RWA_FACTORY_ADDRESS, PROPERTY_NFT_ADDRESS } from "@/lib/wagmiConfig";
import { fmtUSD, fmtDate, shortAddr } from "@/lib/format";

type AssetRecord = {
  tokenId: bigint;
  fractionToken: `0x${string}`;
  assetName: string;
  createdAt: bigint;
};

function Skeleton() {
  return (
    <div className="card overflow-hidden animate-pulse">
      <div className="h-44 bg-zinc-800" />
      <div className="space-y-3 p-4">
        <div className="h-4 w-2/3 rounded bg-zinc-800" />
        <div className="h-3 w-1/2 rounded bg-zinc-800" />
        <div className="h-3 w-3/4 rounded bg-zinc-800" />
      </div>
    </div>
  );
}

function PropertyCard({ asset }: { asset: AssetRecord }) {
  const { data: meta } = useReadContract({
    address: PROPERTY_NFT_ADDRESS,
    abi: PROPERTY_NFT_ABI,
    functionName: "getPropertyDetails",
    args: [asset.tokenId],
  });

  const { data: uri } = useReadContract({
    address: PROPERTY_NFT_ADDRESS,
    abi: PROPERTY_NFT_ABI,
    functionName: "tokenURI",
    args: [asset.tokenId],
  });

  const svgSrc = (() => {
    if (!uri) return null;
    try {
      const json = JSON.parse(atob((uri as string).split(",")[1]));
      return (json.image as string) ?? null;
    } catch {
      return null;
    }
  })();

  return (
    <div className="card group overflow-hidden transition-all hover:border-zinc-700">
      <div className="relative h-44 overflow-hidden bg-zinc-800">
        {svgSrc ? (
          <img src={svgSrc} alt={asset.assetName} className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full items-center justify-center">
            <svg
              width="48"
              height="48"
              viewBox="0 0 24 24"
              fill="none"
              className="text-zinc-700"
            >
              <path
                d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinejoin="round"
              />
              <path
                d="M9 22V12h6v10"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinejoin="round"
              />
            </svg>
          </div>
        )}
        <div className="absolute right-3 top-3">
          <span className="rounded-full bg-zinc-950/70 px-2 py-0.5 font-mono text-xs text-zinc-400 backdrop-blur-sm">
            #{asset.tokenId.toString()}
          </span>
        </div>
      </div>

      <div className="space-y-3 p-4">
        <div>
          <h3 className="truncate text-sm font-semibold text-zinc-100">
            {asset.assetName}
          </h3>
          {meta && (
            <p className="mt-0.5 text-xs text-zinc-500">{meta.location}</p>
          )}
        </div>

        {meta && (
          <div className="space-y-1.5">
            <div className="flex items-center justify-between text-xs">
              <span className="text-zinc-500">Valuation</span>
              <span className="font-medium text-amber-400">
                {fmtUSD(meta.valuationUSD)}
              </span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-zinc-500">Legal ID</span>
              <span className="font-mono text-zinc-300">{meta.legalIdentifier}</span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-zinc-500">Token</span>
              <span className="font-mono text-zinc-400">{shortAddr(asset.fractionToken)}</span>
            </div>
          </div>
        )}

        <div className="border-t border-zinc-800 pt-2.5 text-xs text-zinc-600">
          Listed {fmtDate(asset.createdAt)}
        </div>
      </div>
    </div>
  );
}

export function PropertiesPanel() {
  const { data: assets, isLoading, isError } = useReadContract({
    address: RWA_FACTORY_ADDRESS,
    abi: RWA_FACTORY_ABI,
    functionName: "getAllAssets",
  });

  const list = (assets as AssetRecord[] | undefined) ?? [];

  return (
    <div className="mx-auto max-w-5xl">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold text-zinc-100">Properties</h1>
          <p className="mt-0.5 text-sm text-zinc-500">
            Tokenized real-world assets on-chain
          </p>
        </div>
        {!isLoading && !isError && (
          <span className="rounded-full bg-zinc-800 px-3 py-1 text-xs font-medium text-zinc-400">
            {list.length} {list.length === 1 ? "asset" : "assets"}
          </span>
        )}
      </div>

      {isLoading && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {[...Array(3)].map((_, i) => <Skeleton key={i} />)}
        </div>
      )}

      {isError && (
        <div className="flex flex-col items-center justify-center rounded-xl border border-zinc-800 bg-zinc-900 py-20 text-center">
          <p className="text-sm font-medium text-zinc-400">Could not load properties</p>
          <p className="mt-1 text-xs text-zinc-600">
            Check your contract address in <code className="font-mono">.env.local</code>
          </p>
        </div>
      )}

      {!isLoading && !isError && list.length === 0 && (
        <div className="flex flex-col items-center justify-center rounded-xl border border-zinc-800 bg-zinc-900 py-20 text-center">
          <svg
            width="40"
            height="40"
            viewBox="0 0 24 24"
            fill="none"
            className="mb-3 text-zinc-700"
          >
            <path
              d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinejoin="round"
            />
          </svg>
          <p className="text-sm font-medium text-zinc-400">No properties yet</p>
          <p className="mt-1 text-xs text-zinc-600">
            Use the Admin tab to tokenize a property
          </p>
        </div>
      )}

      {!isLoading && !isError && list.length > 0 && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {list.map((asset, i) => (
            <PropertyCard key={i} asset={asset} />
          ))}
        </div>
      )}
    </div>
  );
}
