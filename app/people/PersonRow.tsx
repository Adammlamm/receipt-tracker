"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { ChevronRight, UserCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Person } from "@/lib/types";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

export default function PersonRow({ person, totalRemaining }: { person: Person; totalRemaining: number }) {
  const router = useRouter();
  const supabase = createClient();

  async function markAsSelf(e: React.MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    // Unset any existing "you", then set this one
    await supabase.from("people").update({ is_self: false }).eq("user_id", user.id).eq("is_self", true);
    await supabase.from("people").update({ is_self: true }).eq("id", person.id);
    router.refresh();
  }

  return (
    <Link href={`/people/${person.id}`} className="w-full bg-white rounded-xl border border-line px-4 py-3 flex items-center gap-3">
      <div className="flex-1 min-w-0">
        <p className="text-[14px] font-medium text-ink flex items-center gap-1.5">
          {person.name}
          {person.is_self && <span className="text-[10px] font-semibold text-accent bg-[#EFF7F3] px-1.5 py-0.5 rounded-full">YOU</span>}
        </p>
        <p className="text-[12px] text-muted">
          {person.is_self ? "This is you" : totalRemaining > 0.005 ? "Owes you" : "Settled up"}
        </p>
      </div>
      {!person.is_self && (
        <>
          <button onClick={markAsSelf} className="p-1.5 rounded-full active:bg-[#F5F3EC]" title="Mark as you">
            <UserCheck size={15} className="text-muted" />
          </button>
          <span className={`font-mono text-[14px] font-semibold ${totalRemaining > 0.005 ? "text-owe" : "text-muted"}`}>
            {money(totalRemaining)}
          </span>
        </>
      )}
      <ChevronRight size={16} className="text-[#C7C1AF]" />
    </Link>
  );
}
