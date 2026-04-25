export function parseContractError(err: unknown): string {
  if (!(err instanceof Error)) return String(err);

  const msg = err.message;

  const revertMatch = msg.match(/reverted with reason string '([^']+)'/);
  if (revertMatch) return revertMatch[1];

  const customMatch = msg.match(/reverted with the following reason:\s*(.+?)(\n|$)/);
  if (customMatch) return customMatch[1].trim();

  if (msg.includes("User rejected") || msg.includes("user rejected")) {
    return "Transaction rejected.";
  }

  return msg.split("\n")[0].slice(0, 160);
}
