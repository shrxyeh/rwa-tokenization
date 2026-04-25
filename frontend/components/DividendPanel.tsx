"use client";

import { useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { parseEther, formatEther } from "viem";
import { RWA_FACTORY_ABI, FRACTIONAL_TOKEN_ABI } from "@/lib/abis";
import { RWA_FACTORY_ADDRESS } from "@/lib/wagmiConfig";
import { fmtETH } from "@/lib/format";
import { useTransaction } from "@/hooks/useTransaction";

type AssetRecord = {
  tokenId: bigint;
  fractionToken: `0x${string}`;
  assetName: string;
  createdAt: bigint;
};

function RoundRow({
  addr,
  roundId,
  owner,
  onClaim,
  busy,
}: {
  addr: `0x${string}`;
  roundId: number;
  owner: `0x${string}`;
  onClaim: (id: number) => void;
  busy: boolean;
}) {
  const { data: round } = useReadContract({
    address: addr,
    abi: FRACTIONAL_TOKEN_ABI,
    functionName: "dividendRounds",
    args: [BigInt(roundId)],
  });

  const { data: claimed } = useReadContract({
    address: addr,
    abi: FRACTIONAL_TOKEN_ABI,
    functionName: "hasClaimed",
    args: [BigInt(roundId), owner],
  });

  const { data: votes } = useReadContract({
    address: addr,
    abi: FRACTIONAL_TOKEN_ABI,
    functionName: "getVotes",
    args: [owner],
  });

  if (!round) return null;

  // wagmi returns a tuple: [totalETH, snapshotBlock, claimedCount, totalSupplyAtSnapshot]
  const [totalETH, , , totalSupplyAtSnapshot] = round as readonly [bigint, bigint, bigint, bigint];
  const share =
    votes && totalSupplyAtSnapshot > 0n
      ? (Number(formatEther(totalETH)) * Number(votes as bigint)) /
        Number(totalSupplyAtSnapshot)
      : 0;

  return (
    <div className="flex items-center gap-3 rounded-lg bg-zinc-800/50 px-4 py-3 text-sm">
      <span className="w-16 font-mono text-xs text-zinc-500">Round {roundId}</span>
      <span className="flex-1 font-medium text-zinc-100">
        {fmtETH(totalETH)}
      </span>
      <span className="text-xs text-zinc-500">
        {share > 0 ? `≈ ${share.toFixed(6)} ETH` : "no votes"}
      </span>
      {claimed ? (
        <span className="rounded-full bg-emerald-500/10 px-2.5 py-0.5 text-xs font-medium text-emerald-400">
          Claimed
        </span>
      ) : (
        <button
          onClick={() => onClaim(roundId)}
          disabled={busy}
          className="btn-primary h-7 px-3 text-xs"
        >
          Claim
        </button>
      )}
    </div>
  );
}

function AssetDividends({ asset, owner }: { asset: AssetRecord; owner: `0x${string}` }) {
  const [depositAmt, setDepositAmt] = useState("");

  const { data: roundCount, refetch } = useReadContract({
    address: asset.fractionToken,
    abi: FRACTIONAL_TOKEN_ABI,
    functionName: "roundCount",
  });

  const { writeContractAsync, setHash, busy } = useTransaction(refetch);

  const rounds = Number(roundCount ?? 0n);

  async function deposit() {
    if (!depositAmt) return;
    try {
      const h = await writeContractAsync({
        address: asset.fractionToken,
        abi: FRACTIONAL_TOKEN_ABI,
        functionName: "depositDividend",
        value: parseEther(depositAmt),
      });
      setHash(h);
      setDepositAmt("");
    } catch (e: unknown) {
      alert((e instanceof Error ? e.message : String(e)).slice(0, 160));
    }
  }

  async function claim(roundId: number) {
    try {
      const h = await writeContractAsync({
        address: asset.fractionToken,
        abi: FRACTIONAL_TOKEN_ABI,
        functionName: "claimDividend",
        args: [BigInt(roundId)],
      });
      setHash(h);
    } catch (e: unknown) {
      alert((e instanceof Error ? e.message : String(e)).slice(0, 160));
    }
  }

  return (
    <div className="card p-5 space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold text-zinc-100">{asset.assetName}</h3>
        <span className="rounded-full bg-zinc-800 px-2.5 py-0.5 text-xs text-zinc-500">
          {rounds} {rounds === 1 ? "round" : "rounds"}
        </span>
      </div>

      {/* Deposit */}
      <div className="space-y-2 rounded-lg bg-zinc-800/40 p-3">
        <p className="text-xs font-medium text-zinc-500">Deposit ETH dividend</p>
        <div className="flex gap-2">
          <input
            type="text"
            value={depositAmt}
            onChange={(e) => setDepositAmt(e.target.value)}
            placeholder="0.0"
            className="input-base"
          />
          <button
            onClick={deposit}
            disabled={busy || !depositAmt}
            className="btn-primary"
          >
            {busy ? "Confirming…" : "Deposit"}
          </button>
        </div>
      </div>

      {/* Rounds */}
      {rounds > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs font-medium uppercase tracking-wider text-zinc-600">
            Distribution rounds
          </p>
          {Array.from({ length: rounds }, (_, i) => (
            <RoundRow
              key={i}
              addr={asset.fractionToken}
              roundId={i}
              owner={owner}
              onClaim={claim}
              busy={busy}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export function DividendPanel() {
  const { address, isConnected } = useAccount();

  const { data: assets, isLoading } = useReadContract({
    address: RWA_FACTORY_ADDRESS,
    abi: RWA_FACTORY_ABI,
    functionName: "getAllAssets",
  });

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center rounded-xl border border-zinc-800 bg-zinc-900 py-24 text-center">
        <svg width="36" height="36" viewBox="0 0 24 24" fill="none" className="mb-3 text-zinc-700">
          <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.5" />
          <path d="M12 7v1m0 8v1M9.17 9.17l.7.7m4.96 4.96l.7.7M7 12H6m12 0h-1M9.17 14.83l.7-.7m4.96-4.96l.7-.7"
            stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
        <p className="text-sm font-medium text-zinc-400">Connect your wallet</p>
        <p className="mt-1 text-xs text-zinc-600">
          Connect to deposit or claim dividends.
        </p>
      </div>
    );
  }

  const list = (assets as AssetRecord[] | undefined) ?? [];

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-zinc-100">Dividends</h1>
        <p className="mt-0.5 text-sm text-zinc-500">
          Deposit ETH and distribute to token holders proportionally
        </p>
      </div>

      {isLoading && (
        <div className="space-y-4">
          {[...Array(2)].map((_, i) => (
            <div key={i} className="card h-40 animate-pulse" />
          ))}
        </div>
      )}

      {!isLoading && list.length === 0 && (
        <p className="py-4 text-center text-sm text-zinc-600">No assets found.</p>
      )}

      {!isLoading && list.map((asset, i) => (
        <AssetDividends key={i} asset={asset} owner={address!} />
      ))}
    </div>
  );
}
