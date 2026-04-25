export function fmtUSD(n: bigint | number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(Number(n));
}

export function fmtETH(wei: bigint, precision = 4): string {
  const eth = Number(wei) / 1e18;
  if (eth === 0) return "0 ETH";
  if (eth < 0.0001) return `<0.0001 ETH`;
  return `${eth.toLocaleString("en-US", { maximumFractionDigits: precision })} ETH`;
}

export function fmtTokens(wei: bigint): string {
  const n = Number(wei) / 1e18;
  return n.toLocaleString("en-US", { maximumFractionDigits: 2 });
}

export function fmtDate(unixSeconds: bigint | number): string {
  return new Date(Number(unixSeconds) * 1000).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

export function shortAddr(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}
