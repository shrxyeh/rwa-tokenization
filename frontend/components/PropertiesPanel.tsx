"use client";

import { useState } from "react";
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

type PropertyMeta = {
  name: string;
  location: string;
  valuationUSD: bigint;
  legalIdentifier: string;
  mintedAt: bigint;
  originalOwner: `0x${string}`;
};

// ─── Copy button ──────────────────────────────────────────────────────────────

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);

  function copy() {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    });
  }

  return (
    <button
      onClick={copy}
      className="ml-1.5 rounded p-0.5 text-zinc-600 transition-colors hover:bg-zinc-700 hover:text-zinc-300"
      title="Copy to clipboard"
    >
      {copied ? (
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
          <path d="M5 13l4 4L19 7" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      ) : (
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
          <rect x="9" y="9" width="13" height="13" rx="2" stroke="currentColor" strokeWidth="1.5" />
          <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" stroke="currentColor" strokeWidth="1.5" />
        </svg>
      )}
    </button>
  );
}

// ─── Detail modal ─────────────────────────────────────────────────────────────

function DetailModal({
  asset,
  meta,
  svgSrc,
  onClose,
}: {
  asset: AssetRecord;
  meta: PropertyMeta | undefined;
  svgSrc: string | null;
  onClose: () => void;
}) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-zinc-950/80 backdrop-blur-sm p-4"
      onClick={onClose}
    >
      <div
        className="relative w-full max-w-lg rounded-2xl border border-zinc-800 bg-zinc-900 shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        {/* NFT image */}
        <div className="relative h-52 bg-zinc-800">
          {svgSrc ? (
            <img src={svgSrc} alt={asset.assetName} className="h-full w-full object-cover" />
          ) : (
            <div className="flex h-full items-center justify-center text-zinc-700">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none">
                <path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
                <path d="M9 22V12h6v10" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
              </svg>
            </div>
          )}
          <button
            onClick={onClose}
            className="absolute right-3 top-3 rounded-full bg-zinc-950/60 p-1.5 text-zinc-400 backdrop-blur-sm hover:text-zinc-100 transition-colors"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
              <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            </svg>
          </button>
          <span className="absolute left-3 top-3 rounded-full bg-zinc-950/60 px-2 py-0.5 font-mono text-xs text-zinc-400 backdrop-blur-sm">
            #{asset.tokenId.toString()}
          </span>
        </div>

        {/* Details */}
        <div className="p-5 space-y-4">
          <div>
            <h2 className="text-base font-semibold text-zinc-100">{asset.assetName}</h2>
            {meta && <p className="mt-0.5 text-sm text-zinc-500">{meta.location}</p>}
          </div>

          <div className="rounded-lg border border-zinc-800 divide-y divide-zinc-800">
            {meta && (
              <>
                <Row label="Valuation">
                  <span className="font-medium text-amber-400">{fmtUSD(meta.valuationUSD)}</span>
                </Row>
                <Row label="Legal ID">
                  <span className="font-mono text-zinc-300">{meta.legalIdentifier}</span>
                </Row>
              </>
            )}
            <Row label="Token address">
              <span className="font-mono text-zinc-300">{shortAddr(asset.fractionToken)}</span>
              <CopyButton text={asset.fractionToken} />
            </Row>
            <Row label="Full address">
              <span className="font-mono text-xs text-zinc-500 break-all">{asset.fractionToken}</span>
              <CopyButton text={asset.fractionToken} />
            </Row>
            <Row label="Listed">
              <span className="text-zinc-400">{fmtDate(asset.createdAt)}</span>
            </Row>
          </div>

          <div className="flex gap-2">
            <a
              href={`https://sepolia.etherscan.io/token/${asset.fractionToken}`}
              target="_blank"
              rel="noopener noreferrer"
              className="btn-ghost flex-1 text-center text-xs"
            >
              View token on Etherscan ↗
            </a>
            <a
              href={`https://sepolia.etherscan.io/nft/${PROPERTY_NFT_ADDRESS}/${asset.tokenId}`}
              target="_blank"
              rel="noopener noreferrer"
              className="btn-ghost flex-1 text-center text-xs"
            >
              View NFT on Etherscan ↗
            </a>
          </div>
        </div>
      </div>
    </div>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 px-3 py-2.5 text-xs">
      <span className="shrink-0 text-zinc-500">{label}</span>
      <span className="flex items-center min-w-0">{children}</span>
    </div>
  );
}

// ─── Property card ────────────────────────────────────────────────────────────

function PropertyCard({ asset }: { asset: AssetRecord }) {
  const [open, setOpen] = useState(false);

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
    <>
      <button
        onClick={() => setOpen(true)}
        className="card group overflow-hidden text-left transition-all hover:border-zinc-600 hover:shadow-lg hover:shadow-zinc-950/50 cursor-pointer w-full"
      >
        <div className="relative h-44 overflow-hidden bg-zinc-800">
          {svgSrc ? (
            <img src={svgSrc} alt={asset.assetName} className="h-full w-full object-cover transition-transform group-hover:scale-105" />
          ) : (
            <div className="flex h-full items-center justify-center">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none" className="text-zinc-700">
                <path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
                <path d="M9 22V12h6v10" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
              </svg>
            </div>
          )}
          <div className="absolute right-3 top-3">
            <span className="rounded-full bg-zinc-950/70 px-2 py-0.5 font-mono text-xs text-zinc-400 backdrop-blur-sm">
              #{asset.tokenId.toString()}
            </span>
          </div>
          {/* "Click to expand" hint */}
          <div className="absolute inset-0 flex items-center justify-center bg-zinc-950/0 transition-colors group-hover:bg-zinc-950/30">
            <span className="rounded-full bg-zinc-950/70 px-3 py-1 text-xs text-zinc-300 opacity-0 transition-opacity group-hover:opacity-100 backdrop-blur-sm">
              View details
            </span>
          </div>
        </div>

        <div className="space-y-3 p-4">
          <div>
            <h3 className="truncate text-sm font-semibold text-zinc-100">{asset.assetName}</h3>
            {meta && <p className="mt-0.5 text-xs text-zinc-500">{(meta as PropertyMeta).location}</p>}
          </div>

          {meta && (
            <div className="space-y-1.5">
              <div className="flex items-center justify-between text-xs">
                <span className="text-zinc-500">Valuation</span>
                <span className="font-medium text-amber-400">{fmtUSD((meta as PropertyMeta).valuationUSD)}</span>
              </div>
              <div className="flex items-center justify-between text-xs">
                <span className="text-zinc-500">Legal ID</span>
                <span className="font-mono text-zinc-300">{(meta as PropertyMeta).legalIdentifier}</span>
              </div>
              <div className="flex items-center justify-between gap-2 text-xs">
                <span className="text-zinc-500">Token</span>
                <div className="flex items-center gap-1">
                  <span className="font-mono text-zinc-400">{shortAddr(asset.fractionToken)}</span>
                  <CopyButton text={asset.fractionToken} />
                </div>
              </div>
            </div>
          )}

          <div className="border-t border-zinc-800 pt-2.5 text-xs text-zinc-600">
            Listed {fmtDate(asset.createdAt)}
          </div>
        </div>
      </button>

      {open && (
        <DetailModal
          asset={asset}
          meta={meta as PropertyMeta | undefined}
          svgSrc={svgSrc}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
}

// ─── Skeleton ─────────────────────────────────────────────────────────────────

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

// ─── Panel ────────────────────────────────────────────────────────────────────

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
          <p className="mt-0.5 text-sm text-zinc-500">Tokenized real-world assets on-chain</p>
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
          <svg width="40" height="40" viewBox="0 0 24 24" fill="none" className="mb-3 text-zinc-700">
            <path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
          </svg>
          <p className="text-sm font-medium text-zinc-400">No properties yet</p>
          <p className="mt-1 text-xs text-zinc-600">Use the Admin tab to tokenize a property</p>
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
