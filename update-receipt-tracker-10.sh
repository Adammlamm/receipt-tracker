#!/bin/bash
set -e
echo "Applying: scan security hardening + merge duplicate people..."

mkdir -p $(dirname 'app/api/scan-receipt/route.ts')
cat > 'app/api/scan-receipt/route.ts' << 'FILEEOF'
import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const maxDuration = 30;

// Belt-and-suspenders limits, independent of the site-wide middleware:
const ALLOWED_MEDIA_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);
const MAX_BYTES = 8 * 1024 * 1024; // 8MB
const DAILY_SCAN_LIMIT = 40; // generous for personal use, cheap insurance against runaway/abusive calls

const SYSTEM_PROMPT = `You read restaurant/store receipts from photos or PDFs and extract structured data.
Return ONLY valid JSON, no prose, no markdown fences, matching exactly this shape:

{
  "merchant": string,
  "date": string | null,       // YYYY-MM-DD if you can read it, else null
  "items": [
    { "name": string, "quantity": number, "unit_price": number, "category": "Food" | "Drinks" | "Other" }
  ],
  "subtotal": number | null,
  "tax": number | null,
  "tip": number | null,
  "discount": number | null,   // positive number representing amount subtracted, 0 if none
  "total": number | null
}

Rules:
- "unit_price" is the price for ONE unit of that item (if the receipt shows a line total for multiple quantity, divide it).
- Guess "category" per item: alcohol/beer/wine/cocktails -> "Drinks", soda/coffee/juice/water are also "Drinks", entrees/appetizers/sides -> "Food", anything else (fees, misc) -> "Other".
- If a value truly isn't visible on the receipt, use null rather than guessing.
- Do not include currency symbols in numbers.
- Respond with raw JSON only.`;

export async function POST(request: Request) {
  // 1. Require a genuine authenticated session, checked here directly rather than
  // trusting only the site-wide middleware — defense in depth.
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Please sign in to scan receipts." }, { status: 401 });
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      { error: "Receipt scanning isn't configured yet (missing ANTHROPIC_API_KEY)." },
      { status: 500 }
    );
  }

  const { imageBase64, mediaType } = await request.json();
  if (!imageBase64) {
    return NextResponse.json({ error: "No file provided." }, { status: 400 });
  }

  // 2. Only accept the file types we actually know how to send to the scanner.
  if (!ALLOWED_MEDIA_TYPES.has(mediaType)) {
    return NextResponse.json({ error: "Unsupported file type. Use a JPEG, PNG, WebP, or PDF." }, { status: 415 });
  }

  // 3. Guard against unexpectedly huge uploads (base64 is ~4/3 the size of the raw file).
  const approxBytes = (imageBase64.length * 3) / 4;
  if (approxBytes > MAX_BYTES + 2 * 1024 * 1024) {
    return NextResponse.json({ error: "That file is too large to scan (max ~8MB). Try a smaller photo or lighter PDF." }, { status: 413 });
  }

  // 4. Cap scans per account per day — cheap insurance against a compromised
  // session or a bug quietly running up API costs.
  const today = new Date().toISOString().slice(0, 10);
  const { data: usage } = await supabase
    .from("scan_usage")
    .select("count")
    .eq("user_id", user.id)
    .eq("day", today)
    .maybeSingle();

  if ((usage?.count ?? 0) >= DAILY_SCAN_LIMIT) {
    return NextResponse.json(
      { error: "You've hit today's scan limit. Enter this receipt manually, or try again tomorrow." },
      { status: 429 }
    );
  }

  await supabase
    .from("scan_usage")
    .upsert({ user_id: user.id, day: today, count: (usage?.count ?? 0) + 1 }, { onConflict: "user_id,day" });

  const isPdf = mediaType === "application/pdf";
  const contentBlock = isPdf
    ? { type: "document", source: { type: "base64", media_type: "application/pdf", data: imageBase64 } }
    : { type: "image", source: { type: "base64", media_type: mediaType, data: imageBase64 } };

  try {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 2000,
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: [contentBlock, { type: "text", text: "Extract this receipt into the JSON shape described." }],
          },
        ],
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error("Anthropic API error:", errText);
      return NextResponse.json({ error: "Receipt scan failed. Try entering it manually." }, { status: 502 });
    }

    const data = await res.json();
    const textBlock = data.content?.find((b: any) => b.type === "text");
    if (!textBlock) {
      return NextResponse.json({ error: "Couldn't read a response from the scanner." }, { status: 502 });
    }

    const cleaned = textBlock.text.replace(/```json|```/g, "").trim();
    let parsed;
    try {
      parsed = JSON.parse(cleaned);
    } catch {
      // The model didn't return valid JSON (e.g. it was refused, or the file wasn't a receipt) —
      // fail safely rather than passing unstructured text back to the client.
      return NextResponse.json({ error: "Couldn't read this as a receipt. Try entering it manually." }, { status: 422 });
    }
    return NextResponse.json(parsed);
  } catch (err) {
    console.error("scan-receipt error:", err);
    return NextResponse.json({ error: "Receipt scan failed. Try entering it manually." }, { status: 500 });
  }
}
FILEEOF

mkdir -p $(dirname 'app/people/[id]/page.tsx')
cat > 'app/people/[id]/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { loadPeople, loadReceipts, loadPayments } from "@/lib/data";
import { allocatePersonPayments } from "@/lib/split";
import BottomNav from "@/components/BottomNav";
import PersonActions from "./PersonActions";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}
function fmtDate(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export default async function PersonDetailPage({ params }: { params: { id: string } }) {
  const [people, receipts, payments] = await Promise.all([loadPeople(), loadReceipts(), loadPayments()]);
  const person = people.find((p) => p.id === params.id);
  if (!person) return <p className="p-5 text-muted text-sm">Person not found.</p>;

  const alloc = allocatePersonPayments(person.id, receipts, payments);
  const { personReceipts, remainingMap, totalRemaining } = alloc;

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Link href="/people" className="text-[13px] text-muted">Back</Link>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink truncate px-2">{person.name}</h1>
        <div className="w-9" />
      </div>

      <div className="px-5 pt-5">
        {person.is_self ? (
          <div className="mb-6">
            <span className="text-[11px] font-semibold text-accent bg-[#EFF7F3] px-2 py-1 rounded-full">This is you</span>
            <p className="text-[13px] text-muted mt-2">You don't owe yourself — your share of receipts is already excluded from totals.</p>
          </div>
        ) : (
          <>
            <p className="text-[12px] text-muted">Total outstanding</p>
            <p className={`font-mono text-[26px] font-semibold mb-6 ${totalRemaining > 0.005 ? "text-owe" : "text-accent"}`}>
              {money(totalRemaining)}
            </p>

            <Link
              href={`/payments/new?personId=${person.id}`}
              className="block text-center rounded-xl bg-accent text-white font-semibold py-3.5 mb-7"
            >
              Record payment
            </Link>
          </>
        )}

        <PersonActions person={person} allPeople={people} />

        <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Receipts</p>
        <div className="space-y-2 mb-8">
          {personReceipts.length === 0 && <p className="text-[13px] text-muted">No receipts yet.</p>}
          {personReceipts.map(({ receipt, owed }) => (
            <Link
              key={receipt.id}
              href={`/receipts/${receipt.id}`}
              className="block bg-white rounded-xl border border-line px-4 py-3"
            >
              <div className="flex items-center justify-between mb-1">
                <span className="text-[14px] font-medium text-ink">{receipt.merchant}</span>
                <span className="font-mono text-[14px] font-semibold text-ink">{money(owed)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-[11px] text-muted">{fmtDate(receipt.date)}</span>
                <span className={`text-[11px] font-medium ${remainingMap[receipt.id] > 0.005 ? "text-owe" : "text-accent"}`}>
                  {remainingMap[receipt.id] > 0.005 ? `${money(remainingMap[receipt.id])} due` : "Paid"}
                </span>
              </div>
            </Link>
          ))}
        </div>
      </div>

      <BottomNav />
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/people/[id]/PersonActions.tsx')
cat > 'app/people/[id]/PersonActions.tsx' << 'FILEEOF'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Pencil, Trash2, Check, X, Merge } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Person, PaymentMethod } from "@/lib/types";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash", "PayPal", "Other"];

export default function PersonActions({ person, allPeople }: { person: Person; allPeople: Person[] }) {
  const router = useRouter();
  const supabase = createClient();
  const [editingName, setEditingName] = useState(false);
  const [name, setName] = useState(person.name);
  const [method, setMethod] = useState<PaymentMethod | null>(person.preferred_payment_method);
  const [handle, setHandle] = useState(person.payment_handle || "");
  const [saving, setSaving] = useState(false);
  const [merging, setMerging] = useState(false);
  const [mergeTargetId, setMergeTargetId] = useState<string>("");
  const [mergeBusy, setMergeBusy] = useState(false);

  const otherPeople = allPeople.filter((p) => p.id !== person.id);

  async function saveName() {
    if (!name.trim()) return;
    await supabase.from("people").update({ name: name.trim() }).eq("id", person.id);
    setEditingName(false);
    router.refresh();
  }

  async function savePaymentInfo() {
    setSaving(true);
    await supabase.from("people").update({ preferred_payment_method: method, payment_handle: handle.trim() || null }).eq("id", person.id);
    setSaving(false);
    router.refresh();
  }

  async function deletePerson() {
    if (!confirm(`Delete ${person.name}? This also removes their item assignments and payment history.`)) return;
    await supabase.from("people").delete().eq("id", person.id);
    router.push("/people");
    router.refresh();
  }

  async function mergeInto() {
    const target = otherPeople.find((p) => p.id === mergeTargetId);
    if (!target) return;
    if (!confirm(`Merge ${person.name} into ${target.name}? All their item assignments and payment history move to ${target.name}, and ${person.name} is removed. This can't be undone.`)) {
      return;
    }
    setMergeBusy(true);
    try {
      // Reassign item_splits, combining shares when both people already had a split on the same item
      // (the (item_id, person_id) unique constraint means we can't just blindly reassign).
      const { data: sourceSplits } = await supabase.from("item_splits").select("*").eq("person_id", person.id);
      for (const split of sourceSplits ?? []) {
        const { data: existing } = await supabase
          .from("item_splits")
          .select("*")
          .eq("item_id", split.item_id)
          .eq("person_id", target.id)
          .maybeSingle();
        if (existing) {
          await supabase
            .from("item_splits")
            .update({ units: (existing.units ?? 1) + (split.units ?? 1) })
            .eq("item_id", split.item_id)
            .eq("person_id", target.id);
          await supabase.from("item_splits").delete().eq("item_id", split.item_id).eq("person_id", person.id);
        } else {
          await supabase.from("item_splits").update({ person_id: target.id }).eq("item_id", split.item_id).eq("person_id", person.id);
        }
      }

      // Reassign payments outright — no collision risk, payments aren't unique per person.
      await supabase.from("payments").update({ person_id: target.id }).eq("person_id", person.id);

      // Reassign group memberships, same collision handling as item_splits.
      const { data: sourceGroups } = await supabase.from("group_members").select("*").eq("person_id", person.id);
      for (const gm of sourceGroups ?? []) {
        const { data: existingGm } = await supabase
          .from("group_members")
          .select("*")
          .eq("group_id", gm.group_id)
          .eq("person_id", target.id)
          .maybeSingle();
        if (!existingGm) {
          await supabase.from("group_members").update({ person_id: target.id }).eq("group_id", gm.group_id).eq("person_id", person.id);
        } else {
          await supabase.from("group_members").delete().eq("group_id", gm.group_id).eq("person_id", person.id);
        }
      }

      await supabase.from("people").delete().eq("id", person.id);
      router.push(`/people/${target.id}`);
      router.refresh();
    } catch (e) {
      console.error("merge failed", e);
      alert("Something went wrong merging — nothing was changed. Try again.");
    } finally {
      setMergeBusy(false);
    }
  }

  return (
    <div className="mb-6">
      <div className="flex items-center gap-2 mb-1 flex-wrap">
        {editingName ? (
          <>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="flex-1 rounded-lg border border-line bg-white px-2.5 py-1.5 text-[14px] outline-none"
              autoFocus
            />
            <button onClick={saveName} className="p-1.5 rounded-full bg-accent text-white"><Check size={14} /></button>
            <button onClick={() => { setEditingName(false); setName(person.name); }} className="p-1.5 rounded-full bg-[#F0EDE1]"><X size={14} className="text-muted" /></button>
          </>
        ) : (
          <>
            <button onClick={() => setEditingName(true)} className="flex items-center gap-1 text-[12px] text-muted">
              <Pencil size={12} /> Rename
            </button>
            <span className="text-[12px] text-[#D8D3C4]">·</span>
            {otherPeople.length > 0 && (
              <>
                <button onClick={() => setMerging(!merging)} className="flex items-center gap-1 text-[12px] text-muted">
                  <Merge size={12} /> Merge into…
                </button>
                <span className="text-[12px] text-[#D8D3C4]">·</span>
              </>
            )}
            <button onClick={deletePerson} className="flex items-center gap-1 text-[12px] text-owe">
              <Trash2 size={12} /> Delete
            </button>
          </>
        )}
      </div>

      {merging && (
        <div className="bg-white rounded-xl border border-line p-3.5 mt-2 mb-1">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">
            Merge {person.name} into…
          </p>
          <div className="flex flex-wrap gap-1.5 mb-3">
            {otherPeople.map((p) => (
              <button
                key={p.id}
                onClick={() => setMergeTargetId(p.id)}
                className={`px-3 py-1.5 rounded-full text-[12px] font-medium border ${mergeTargetId === p.id ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}
              >
                {p.name}
              </button>
            ))}
          </div>
          <button
            onClick={mergeInto}
            disabled={!mergeTargetId || mergeBusy}
            className="text-[12px] font-semibold text-owe disabled:opacity-40"
          >
            {mergeBusy ? "Merging…" : "Merge and delete this person"}
          </button>
        </div>
      )}

      <div className="bg-white rounded-xl border border-line p-3.5 mt-3">
        <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Preferred payment method</p>
        <div className="flex flex-wrap gap-1.5 mb-3">
          {METHODS.map((m) => (
            <button
              key={m}
              onClick={() => setMethod(method === m ? null : m)}
              className={`px-3 py-1.5 rounded-full text-[12px] font-medium border ${method === m ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}
            >
              {m}
            </button>
          ))}
        </div>
        {method && method !== "Cash" && (
          <input
            value={handle}
            onChange={(e) => setHandle(e.target.value)}
            placeholder={method === "Venmo" ? "@venmo-username" : method === "Apple Cash" || method === "Other" ? "Phone or details" : `${method} username or phone`}
            className="w-full rounded-lg border border-line bg-white px-3 py-2 text-[13px] outline-none focus:ring-2 focus:ring-accent/40 mb-3"
          />
        )}
        <button onClick={savePaymentInfo} disabled={saving} className="text-[12px] font-semibold text-accent">
          {saving ? "Saving…" : "Save"}
        </button>
      </div>
    </div>
  );
}
FILEEOF

echo "All files updated."
echo "Now run: git add . && git commit -m \"Add scan security hardening and merge duplicate people\" && git push"
