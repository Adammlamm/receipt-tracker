#!/bin/bash
set -e
echo "Applying: swipe-left-to-delete for people..."

cat > 'app/people/PersonRow.tsx' << 'FILEEOF'
"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ChevronRight, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Person } from "@/lib/types";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

const MAX_OPEN = -84;

export default function PersonRow({ person, totalRemaining }: { person: Person; totalRemaining: number }) {
  const router = useRouter();
  const supabase = createClient();
  const [isSelf, setIsSelf] = useState(person.is_self);
  const [busy, setBusy] = useState(false);
  const [dragX, setDragX] = useState(0);
  const [deleted, setDeleted] = useState(false);

  const startRef = useRef<{ x: number; y: number } | null>(null);
  const baseXRef = useRef(0);
  const directionRef = useRef<"none" | "horizontal" | "vertical">("none");
  const wasOpenAtStartRef = useRef(false);

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

  async function deletePerson() {
    if (!confirm(`Delete ${person.name}? This also removes their item assignments and payment history.`)) {
      setDragX(0);
      return;
    }
    setDeleted(true);
    await supabase.from("people").delete().eq("id", person.id);
    router.refresh();
  }

  function onPointerDown(e: React.PointerEvent) {
    startRef.current = { x: e.clientX, y: e.clientY };
    baseXRef.current = dragX;
    wasOpenAtStartRef.current = dragX !== 0;
    directionRef.current = "none";
    try {
      (e.target as Element).setPointerCapture?.(e.pointerId);
    } catch {}
  }

  function onPointerMove(e: React.PointerEvent) {
    if (!startRef.current) return;
    const dx = e.clientX - startRef.current.x;
    const dy = e.clientY - startRef.current.y;

    if (directionRef.current === "none") {
      if (Math.abs(dx) > 8 || Math.abs(dy) > 8) {
        directionRef.current = Math.abs(dx) > Math.abs(dy) ? "horizontal" : "vertical";
      }
    }

    if (directionRef.current === "horizontal") {
      const next = Math.min(0, Math.max(MAX_OPEN, baseXRef.current + dx));
      setDragX(next);
    }
  }

  function onPointerUp() {
    if (directionRef.current === "horizontal") {
      const shouldOpen = dragX < MAX_OPEN / 2;
      setDragX(shouldOpen ? MAX_OPEN : 0);
    }
    startRef.current = null;
    directionRef.current = "none";
  }

  function onClickCapture(e: React.MouseEvent) {
    // If the row was already open when this tap started, treat the tap as "close", not as the button's normal action.
    if (wasOpenAtStartRef.current) {
      e.preventDefault();
      e.stopPropagation();
      setDragX(0);
      wasOpenAtStartRef.current = false;
    }
  }

  if (deleted) return null;

  return (
    <div className="relative overflow-hidden rounded-xl">
      <div className="absolute inset-y-0 right-0 w-[84px] flex items-center justify-center bg-owe rounded-r-xl">
        <button onClick={deletePerson} className="flex flex-col items-center gap-0.5 text-white px-2 py-2">
          <Trash2 size={16} />
          <span className="text-[10px] font-semibold">Delete</span>
        </button>
      </div>

      <div
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        onClickCapture={onClickCapture}
        style={{ transform: `translateX(${dragX}px)`, transition: startRef.current ? "none" : "transform 180ms ease" }}
        className="relative w-full bg-white border border-line rounded-xl px-4 py-3 flex items-center gap-3 touch-pan-y"
      >
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
    </div>
  );
}
FILEEOF

echo "Done. Now run: git add . && git commit -m \"Add swipe-to-delete for people\" && git push"
