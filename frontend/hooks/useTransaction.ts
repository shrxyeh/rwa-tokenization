import { useState, useEffect } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";

export function useTransaction(onSuccess?: () => void) {
  const [hash, setHash] = useState<`0x${string}` | undefined>();
  const { writeContractAsync, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  useEffect(() => {
    if (isSuccess) {
      setHash(undefined);
      onSuccess?.();
    }
  }, [isSuccess]);

  return {
    writeContractAsync,
    setHash,
    isPending,
    isConfirming,
    isSuccess,
    busy: isPending || isConfirming,
  };
}
