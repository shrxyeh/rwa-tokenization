"use client";

import { useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { isAddress, parseEther } from "viem";
import { RWA_FACTORY_ABI, FRACTIONAL_TOKEN_ABI, IDENTITY_REGISTRY_ABI } from "@/lib/abis";
import { RWA_FACTORY_ADDRESS, IDENTITY_REGISTRY_ADDRESS } from "@/lib/wagmiConfig";
import { fmtTokens, fmtDate, shortAddr } from "@/lib/format";
import { useTransaction } from "@/hooks/useTransaction";

type AssetRecord = {
  tokenId: bigint;
  fractionToken: `0x${string}`;
  assetName: string;
  createdAt: bigint;
};

type InvestorData = {
  kycExpiry: bigint;
  investorTier: number;
  jurisdiction: `0x${string}`;
  active: boolean;
};

function KycBadge({ data }: { data: InvestorData | undefined }) {
  if (!data?.active) {
    return (
      <span className="rounded-full bg-yellow-500/10 px-2.5 py-1 text-xs font-medium text-yellow-400">
        Not verified
      </span>
    );
  }
  return (
    <div className="flex items-center gap-2">
      <span className="rounded-full bg-emerald-500/10 px-2.5 py-1 text-xs font-medium text-emerald-400">
        Verified
      </span>
      <span className="text-xs text-zinc-500">
        Tier {data.investorTier} · Expires {fmtDate(data.kycExpiry)}
      </span>
    </div>
  );
}

function TokenHolding({ asset, owner }: { asset: AssetRecord; owner: `0x${string}` }) {
  const [to, setTo]       = useState("");
  const [amt, setAmt]     = useState("");
  const [open, setOpen]   = useState(false);

  const { data: balance, refetch } = useReadContract({
    address: asset.fractionToken,
    abi: FRACTIONAL_TOKEN_ABI,
    functionName: "balanceOf",
    args: [owner],
  });

  const { data: supply } = useReadContract({
    address: asset.fractionToken,
    abi: FRACTIONAL_TOKEN_ABI,
    functionName: "totalSupply",
  });

  const { data: symbol } = useReadContract({
    address: asset.fractionToken,
    abi: FRACTIONAL_TOKEN_ABI,
    functionName: "symbol",
  });

  const { writeContractAsync, setHash, busy } = useTransaction(refetch);

  const bal = balance as bigint | undefined;
  if (!bal || bal === BigInt(0)) return null;

  const pct =
    supply && (supply as bigint) > BigInt(0)
      ? ((Number(bal) / Number(supply as bigint)) * 100).toFixed(2)
      : "0.00";

  async function submit() {
    if (!isAddress(to) || !amt) return;
    try {
      const h = await writeContractAsync({
        address: asset.fractionToken,
        abi: FRACTIONAL_TOKEN_ABI,
        functionName: "transfer",
        args: [to as `0x${string}`, parseEther(amt)],
      });
      setHash(h);
      setTo(""); setAmt(""); setOpen(false);
    } catch (e: unknown) {
      alert((e instanceof Error ? e.message : String(e)).slice(0, 160));
    }
  }

  return (
    <div className="card p-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-sm font-medium text-zinc-100">{asset.assetName}</p>
          <p className="mt-0.5 font-mono text-xs text-zinc-500">{shortAddr(asset.fractionToken)}</p>
        </div>
        <div className="text-right">
          <p className="text-sm font-semibold text-amber-400">
            {fmtTokens(bal)} <span className="text-zinc-500">{symbol as string}</span>
          </p>
          <p className="mt-0.5 text-xs text-zinc-500">{pct}% of supply</p>
        </div>
      </div>

      <div className="mt-3 border-t border-zinc-800 pt-3">
        <button
          onClick={() => setOpen((v) => !v)}
          className="text-xs font-medium text-zinc-400 hover:text-zinc-200 transition-colors"
        >
          {open ? "Cancel" : "Transfer →"}
        </button>

        {open && (
          <div className="mt-3 space-y-2">
            <input
              type="text"
              value={to}
              onChange={(e) => setTo(e.target.value)}
              placeholder="Recipient (0x…)"
              className="input-base font-mono"
            />
            <div className="flex gap-2">
              <input
                type="text"
                value={amt}
                onChange={(e) => setAmt(e.target.value)}
                placeholder="Amount"
                className="input-base"
              />
              <button
                onClick={submit}
                disabled={busy || !to || !amt}
                className="btn-primary"
              >
                {busy ? "Sending…" : "Send"}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export function PortfolioPanel() {
  const { address, isConnected } = useAccount();

  const { data: assets, isLoading } = useReadContract({
    address: RWA_FACTORY_ADDRESS,
    abi: RWA_FACTORY_ABI,
    functionName: "getAllAssets",
  });

  const { data: investorData } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "getInvestor",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  if (!isConnected) {
    return (
      <EmptyState
        icon={<WalletIcon />}
        title="Connect your wallet"
        description="Connect to view your token holdings and transfer assets."
      />
    );
  }

  const list = (assets as AssetRecord[] | undefined) ?? [];
  const inv  = investorData as InvestorData | undefined;

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-zinc-100">Portfolio</h1>
        <p className="mt-0.5 text-sm text-zinc-500">
          {address ? shortAddr(address) : "—"}
        </p>
      </div>

      {/* Identity status */}
      <div className="card p-4">
        <div className="flex items-center justify-between">
          <p className="text-xs font-medium uppercase tracking-wider text-zinc-600">
            KYC Status
          </p>
          <KycBadge data={inv} />
        </div>
        {!inv?.active && (
          <p className="mt-2 text-xs text-zinc-600">
            An admin must add you to the registry before you can receive tokens.
          </p>
        )}
      </div>

      {/* Holdings */}
      <div className="space-y-3">
        {isLoading && (
          <div className="space-y-3">
            {[...Array(2)].map((_, i) => (
              <div key={i} className="card h-24 animate-pulse bg-zinc-900" />
            ))}
          </div>
        )}

        {!isLoading && list.length === 0 && (
          <p className="py-4 text-center text-sm text-zinc-600">No assets found.</p>
        )}

        {!isLoading && list.map((asset, i) => (
          <TokenHolding key={i} asset={asset} owner={address!} />
        ))}
      </div>
    </div>
  );
}

function EmptyState({
  icon,
  title,
  description,
}: {
  icon: React.ReactNode;
  title: string;
  description: string;
}) {
  return (
    <div className="flex flex-col items-center justify-center rounded-xl border border-zinc-800 bg-zinc-900 py-24 text-center">
      <div className="mb-3 text-zinc-700">{icon}</div>
      <p className="text-sm font-medium text-zinc-400">{title}</p>
      <p className="mt-1 max-w-xs text-xs text-zinc-600">{description}</p>
    </div>
  );
}

function WalletIcon() {
  return (
    <svg width="36" height="36" viewBox="0 0 24 24" fill="none">
      <rect x="2" y="6" width="20" height="14" rx="2" stroke="currentColor" strokeWidth="1.5" />
      <path d="M16 13a1 1 0 110 2 1 1 0 010-2z" fill="currentColor" />
      <path d="M2 10h20" stroke="currentColor" strokeWidth="1.5" />
      <path d="M6 6V4a2 2 0 012-2h8a2 2 0 012 2v2" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}
