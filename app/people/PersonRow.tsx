"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ChevronRight } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Person } from "@/lib/types";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

export default function PersonRow({ person, totalRemaining }: { person: Person; totalRemaining: number }) {
  const router = useRouter();
  const supabase = createClient();
  const [isSelf, setIsSelf] = useState(person.is_self);
  const [busy, setBusy] = useState(false);

  async function markAsSelf() {
    if (busy) return;
    setBusy(true);
    setIsSelf(true); // optimistic
    try {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) return;
      await supabase.from("people").update({ is_self: false }).eq("user_id", user.id).eq("is_self", true);
      const { error } = await supabase.from("people").update({ is_self: true }).eq("id", person.id);
      if (error) {
        console.error("mark as self failed", error);
        setIsSelf(false);
      }
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="w-full bg-white rounded-xl border border-line px-4 py-3 flex items-center gap-3">
      <button onClick={() => router.push(`/people/${person.id}`)} className="flex-1 min-w-0 text-left flex items-center gap-3">
        <div className="flex-1 min-w-0">
          <p className="text-[14px] font-medium text-ink flex items-center gap-1.5">
            {person.name}
            {isSelf && <span className="text-[10px] font-semibold text-accent bg-[#EFF7F3] px-1.5 py-0.5 rounded-full">YOU</span>}
          </p>
          <p className="text-[12px] text-muted">
            {isSelf ? "This is you" : totalRemaining > 0.005 ? "Owes you" : "Settled up"}
          </p>
        </div>
      </button>
      {!isSelf && (
        <>
          <button onClick={markAsSelf} disabled={busy} className="px-2.5 py-1.5 rounded-lg bg-[#F0EDE1] text-[11px] font-semibold text-[#5B5748] active:bg-[#E7E3D8] disabled:opacity-40 whitespace-nowrap">
            This is me
          </button>
          <span className={`font-mono text-[14px] font-semibold ${totalRemaining > 0.005 ? "text-owe" : "text-muted"}`}>
            {money(totalRemaining)}
          </span>
        </>
      )}
      <button onClick={() => router.push(`/people/${person.id}`)}>
        <ChevronRight size={16} className="text-[#C7C1AF]" />
      </button>
    </div>
  );
}
