"use client";

import { useEffect } from "react";
import { AlertTriangle } from "lucide-react";

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <div className="min-h-screen bg-paper flex items-center justify-center px-6">
      <div className="text-center max-w-sm">
        <div className="w-12 h-12 rounded-full bg-[#FBEDEA] flex items-center justify-center mx-auto mb-4">
          <AlertTriangle size={22} className="text-owe" />
        </div>
        <h1 className="text-[17px] font-semibold text-ink mb-1.5">Something went wrong</h1>
        <p className="text-[13px] text-muted mb-6">
          That's on us, not your data — nothing was lost. Try again, and if it keeps happening, come back in a bit.
        </p>
        <button onClick={() => reset()} className="rounded-xl bg-accent text-white font-semibold py-3 px-6 text-[14px]">
          Try again
        </button>
      </div>
    </div>
  );
}
