"use client";

import { useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { isAddress, parseEther, padHex, toHex } from "viem";
import { IDENTITY_REGISTRY_ABI, RWA_FACTORY_ABI } from "@/lib/abis";
import {
  IDENTITY_REGISTRY_ADDRESS,
  RWA_FACTORY_ADDRESS,
  PROPERTY_NFT_ADDRESS,
} from "@/lib/wagmiConfig";
import { useTransaction } from "@/hooks/useTransaction";

// ─── small presentational helpers ─────────────────────────────────────────────

function SectionHeader({ title, description }: { title: string; description?: string }) {
  return (
    <div className="mb-4">
      <h2 className="text-sm font-semibold text-zinc-100">{title}</h2>
      {description && (
        <p className="mt-0.5 text-xs text-zinc-500">{description}</p>
      )}
    </div>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <label className="block text-xs font-medium text-zinc-400">{label}</label>
      {children}
    </div>
  );
}

// ─── Add Investor ─────────────────────────────────────────────────────────────

function AddInvestorForm() {
  const [addr, setAddr]   = useState("");
  const [juris, setJuris] = useState("US");
  const [tier, setTier]   = useState<"1" | "2">("2");
  const [days, setDays]   = useState("365");

  const { writeContractAsync, setHash, busy, isSuccess } = useTransaction();

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!isAddress(addr)) return alert("Invalid address");

    const expiry  = BigInt(Math.floor(Date.now() / 1000) + Number(days) * 86_400);
    const jurCode = padHex(toHex(juris.trim().slice(0, 32)), { dir: "right", size: 32 });

    try {
      const h = await writeContractAsync({
        address: IDENTITY_REGISTRY_ADDRESS,
        abi: IDENTITY_REGISTRY_ABI,
        functionName: "addInvestor",
        args: [addr as `0x${string}`, expiry, jurCode, Number(tier)],
      });
      setHash(h);
      setAddr("");
    } catch (e: unknown) {
      alert((e instanceof Error ? e.message : String(e)).slice(0, 160));
    }
  }

  return (
    <form onSubmit={submit} className="card p-5 space-y-4">
      <SectionHeader
        title="Add investor"
        description="Grants KYC-verified status required to receive and transfer tokens."
      />

      <Field label="Wallet address">
        <input
          type="text"
          value={addr}
          onChange={(e) => setAddr(e.target.value)}
          placeholder="0x…"
          required
          className="input-base font-mono"
        />
      </Field>

      <div className="grid grid-cols-3 gap-3">
        <Field label="Jurisdiction">
          <input
            type="text"
            value={juris}
            onChange={(e) => setJuris(e.target.value)}
            placeholder="US"
            maxLength={32}
            required
            className="input-base"
          />
        </Field>
        <Field label="Tier">
          <select
            value={tier}
            onChange={(e) => setTier(e.target.value as "1" | "2")}
            className="input-base"
          >
            <option value="2">2 — Accredited</option>
            <option value="1">1 — Retail</option>
          </select>
        </Field>
        <Field label="Validity (days)">
          <input
            type="number"
            value={days}
            onChange={(e) => setDays(e.target.value)}
            min="1"
            required
            className="input-base"
          />
        </Field>
      </div>

      <div className="flex items-center gap-3">
        <button type="submit" disabled={busy} className="btn-primary">
          {busy ? "Confirming…" : "Add investor"}
        </button>
        {isSuccess && (
          <span className="text-xs font-medium text-emerald-400">
            Investor added ✓
          </span>
        )}
      </div>
    </form>
  );
}

// ─── Tokenize Property ────────────────────────────────────────────────────────

const defaultForm = {
  name: "",
  location: "",
  valuation: "",
  legalId: "",
  tokenName: "",
  symbol: "",
  supply: "1000000",
};

function TokenizeForm() {
  const [form, setForm] = useState(defaultForm);

  const { writeContractAsync, setHash, busy, isSuccess } = useTransaction();

  function set(key: keyof typeof form) {
    return (e: React.ChangeEvent<HTMLInputElement>) =>
      setForm((prev) => ({ ...prev, [key]: e.target.value }));
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const { name, location, valuation, legalId, tokenName, symbol, supply } = form;

    try {
      const h = await writeContractAsync({
        address: RWA_FACTORY_ADDRESS,
        abi: RWA_FACTORY_ABI,
        functionName: "createAsset",
        args: [
          {
            name,
            location,
            valuationUSD: BigInt(valuation),
            legalIdentifier: legalId,
            mintedAt: BigInt(0),
            originalOwner: "0x0000000000000000000000000000000000000000",
          },
          tokenName,
          symbol,
          parseEther(supply),
          PROPERTY_NFT_ADDRESS,
        ],
      });
      setHash(h);
      setForm(defaultForm);
    } catch (e: unknown) {
      alert((e instanceof Error ? e.message : String(e)).slice(0, 160));
    }
  }

  return (
    <form onSubmit={submit} className="card p-5 space-y-4">
      <SectionHeader
        title="Tokenize property"
        description="Mints a property NFT and deploys a compliant ERC-20 fraction token."
      />

      <div className="grid grid-cols-2 gap-3">
        <Field label="Property name">
          <input value={form.name} onChange={set("name")} placeholder="Sunset Apartments" required className="input-base" />
        </Field>
        <Field label="Location">
          <input value={form.location} onChange={set("location")} placeholder="Miami, FL" required className="input-base" />
        </Field>
        <Field label="Valuation (USD)">
          <input type="number" value={form.valuation} onChange={set("valuation")} placeholder="1200000" min="1" required className="input-base" />
        </Field>
        <Field label="Legal identifier">
          <input value={form.legalId} onChange={set("legalId")} placeholder="DEED-FL-001" required className="input-base" />
        </Field>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <Field label="Token name">
          <input value={form.tokenName} onChange={set("tokenName")} placeholder="Sunset Token" required className="input-base" />
        </Field>
        <Field label="Symbol">
          <input value={form.symbol} onChange={set("symbol")} placeholder="SST" maxLength={8} required className="input-base" />
        </Field>
        <Field label="Total fractions">
          <input type="number" value={form.supply} onChange={set("supply")} min="1" required className="input-base" />
        </Field>
      </div>

      <div className="flex items-center gap-3">
        <button type="submit" disabled={busy} className="btn-primary">
          {busy ? "Confirming…" : "Create asset"}
        </button>
        {isSuccess && (
          <span className="text-xs font-medium text-emerald-400">
            Asset created ✓
          </span>
        )}
      </div>
    </form>
  );
}

// ─── Transfer Controls ────────────────────────────────────────────────────────

function PauseControl() {
  const { data: paused, refetch } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "paused",
  });

  const { writeContractAsync, setHash, busy } = useTransaction(refetch);

  async function toggle() {
    try {
      const h = await writeContractAsync({
        address: IDENTITY_REGISTRY_ADDRESS,
        abi: IDENTITY_REGISTRY_ABI,
        functionName: paused ? "unpauseAllTransfers" : "pauseAllTransfers",
      });
      setHash(h);
    } catch (e: unknown) {
      alert((e instanceof Error ? e.message : String(e)).slice(0, 160));
    }
  }

  return (
    <div className="card p-5">
      <SectionHeader
        title="Transfer controls"
        description="Pausing blocks all fraction token transfers via the IdentityRegistry."
      />

      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <span
            className={[
              "h-2 w-2 rounded-full",
              paused ? "bg-red-400 animate-pulse-slow" : "bg-emerald-400",
            ].join(" ")}
          />
          <span className="text-sm text-zinc-300">
            Transfers are currently{" "}
            <span className={paused ? "font-semibold text-red-400" : "font-semibold text-emerald-400"}>
              {paused ? "paused" : "active"}
            </span>
          </span>
        </div>

        <button
          onClick={toggle}
          disabled={busy}
          className={[
            "btn-ghost",
            paused
              ? "text-emerald-400 hover:bg-emerald-500/10"
              : "text-red-400 hover:bg-red-500/10",
          ].join(" ")}
        >
          {busy ? "Confirming…" : paused ? "Unpause" : "Pause"}
        </button>
      </div>
    </div>
  );
}

// ─── Panel ────────────────────────────────────────────────────────────────────

export function AdminPanel() {
  const { isConnected } = useAccount();

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center rounded-xl border border-zinc-800 bg-zinc-900 py-24 text-center">
        <svg width="36" height="36" viewBox="0 0 24 24" fill="none" className="mb-3 text-zinc-700">
          <rect x="5" y="11" width="14" height="10" rx="2" stroke="currentColor" strokeWidth="1.5" />
          <path d="M8 11V7a4 4 0 018 0v4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
          <circle cx="12" cy="16" r="1" fill="currentColor" />
        </svg>
        <p className="text-sm font-medium text-zinc-400">Connect your wallet</p>
        <p className="mt-1 text-xs text-zinc-600">
          Admin functions require an owner or agent account.
        </p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-xl space-y-4">
      <div className="mb-6">
        <h1 className="text-lg font-semibold text-zinc-100">Admin</h1>
        <p className="mt-0.5 text-sm text-zinc-500">
          Owner and agent operations
        </p>
      </div>

      <AddInvestorForm />
      <TokenizeForm />
      <PauseControl />
    </div>
  );
}
