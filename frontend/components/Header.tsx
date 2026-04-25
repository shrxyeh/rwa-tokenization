"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useReadContract } from "wagmi";
import { IDENTITY_REGISTRY_ABI } from "@/lib/abis";
import { IDENTITY_REGISTRY_ADDRESS } from "@/lib/wagmiConfig";

export function Header() {
  const { data: paused } = useReadContract({
    address: IDENTITY_REGISTRY_ADDRESS,
    abi: IDENTITY_REGISTRY_ABI,
    functionName: "paused",
  });

  return (
    <header className="sticky top-0 z-10 border-b border-zinc-800 bg-zinc-950/90 backdrop-blur-sm">
      <div className="flex h-14 items-center justify-between px-6">
        <div className="flex items-center gap-3">
          <div className="flex h-7 w-7 items-center justify-center rounded-md bg-amber-400">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
              <path d="M8 1L14 5V11L8 15L2 11V5L8 1Z" fill="#09090b" strokeWidth="0" />
              <path d="M8 4L11 6V10L8 12L5 10V6L8 4Z" fill="#f59e0b" />
            </svg>
          </div>
          <span className="text-sm font-semibold tracking-tight text-zinc-100">
            RWA Platform
          </span>
          {paused && (
            <span className="rounded-full bg-red-500/10 px-2 py-0.5 text-xs font-medium text-red-400">
              Transfers paused
            </span>
          )}
        </div>

        <ConnectButton
          accountStatus="address"
          chainStatus="icon"
          showBalance={false}
        />
      </div>
    </header>
  );
}
