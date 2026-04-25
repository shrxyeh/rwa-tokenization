"use client";

import { useState } from "react";
import { Header } from "@/components/Header";
import { PropertiesPanel } from "@/components/PropertiesPanel";
import { PortfolioPanel } from "@/components/PortfolioPanel";
import { DividendPanel } from "@/components/DividendPanel";
import { AdminPanel } from "@/components/AdminPanel";

const TABS = [
  { id: "properties", label: "Properties" },
  { id: "portfolio",  label: "Portfolio"  },
  { id: "dividends",  label: "Dividends"  },
  { id: "admin",      label: "Admin"      },
] as const;

type TabId = (typeof TABS)[number]["id"];

export default function Page() {
  const [active, setActive] = useState<TabId>("properties");

  return (
    <div className="flex min-h-screen flex-col">
      <Header />

      <div className="border-b border-zinc-800 px-6">
        <nav className="flex gap-1" role="tablist">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              role="tab"
              aria-selected={active === tab.id}
              onClick={() => setActive(tab.id)}
              className={[
                "relative px-4 py-3.5 text-sm font-medium transition-colors",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400/50 rounded-t-md",
                active === tab.id
                  ? "text-zinc-100 after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:bg-amber-400"
                  : "text-zinc-500 hover:text-zinc-300",
              ].join(" ")}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      <main className="flex-1 px-6 py-8">
        {active === "properties" && <PropertiesPanel />}
        {active === "portfolio"  && <PortfolioPanel />}
        {active === "dividends"  && <DividendPanel />}
        {active === "admin"      && <AdminPanel />}
      </main>
    </div>
  );
}
