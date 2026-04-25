"use client";

interface Props {
  isPending: boolean;
  isConfirming: boolean;
  isSuccess: boolean;
  successMessage?: string;
  hash?: `0x${string}`;
}

export function TransactionStatus({
  isPending,
  isConfirming,
  isSuccess,
  successMessage = "Transaction confirmed",
  hash,
}: Props) {
  if (!isPending && !isConfirming && !isSuccess) return null;

  return (
    <div className="flex items-center gap-2 text-xs">
      {(isPending || isConfirming) && (
        <>
          <span className="h-2 w-2 rounded-full bg-amber-400 animate-pulse" />
          <span className="text-zinc-400">
            {isPending ? "Waiting for signature…" : "Confirming on-chain…"}
          </span>
        </>
      )}

      {isSuccess && (
        <>
          <span className="h-2 w-2 rounded-full bg-emerald-400" />
          <span className="font-medium text-emerald-400">{successMessage}</span>
          {hash && (
            <a
              href={`https://sepolia.etherscan.io/tx/${hash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-zinc-500 hover:text-zinc-300 underline underline-offset-2"
            >
              View tx
            </a>
          )}
        </>
      )}
    </div>
  );
}
