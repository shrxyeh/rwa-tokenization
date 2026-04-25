// Extracts a human-readable message from a wagmi/viem contract error.
export function parseContractError(err: unknown): string {
  if (!(err instanceof Error)) return String(err);

  const msg = err.message;

  // Pull the revert reason out of viem's verbose error string
  const revertMatch = msg.match(/reverted with reason string '([^']+)'/);
  if (revertMatch) return revertMatch[1];

  const customMatch = msg.match(/reverted with the following reason:\s*(.+?)(\n|$)/);
  if (customMatch) return customMatch[1].trim();

  // User rejected the transaction in their wallet
  if (msg.includes("User rejected") || msg.includes("user rejected")) {
    return "Transaction rejected.";
  }

  // Trim viem stack traces — keep only the first line
  return msg.split("\n")[0].slice(0, 160);
}
