#!/bin/bash
set -e
echo "Applying: short share links instead of raw database IDs..."
mkdir -p "app/friend/[slug]" "app/api/friend/[slug]"
rm -rf "app/friend/[id]" "app/api/friend/[id]"

mkdir -p $(dirname 'lib/types.ts')
cat > 'lib/types.ts' << 'FILEEOF'
export type Category = "Food" | "Drinks" | "Other";
export type TaxTipMethod = "proportional" | "equal";
export type PaymentMethod = "Venmo" | "Zelle" | "Apple Cash" | "Cash App" | "Cash" | "PayPal" | "Other";

export type ReceiptCategory = "Dining" | "Trips" | "Roommates/Home" | "Transportation" | "Other";

export interface Person {
  id: string;
  user_id: string;
  name: string;
  first_name: string | null;
  last_name: string | null;
  is_self: boolean;
  preferred_payment_method: PaymentMethod | null;
  payment_handle: string | null;
  phone_number: string | null;
  reminder_template: string | null;
  share_slug: string;
  created_at: string;
}

export interface ReceiptItem {
  id: string;
  receipt_id: string;
  name: string;
  price: number;
  quantity: number;
  discount: number;
  category: Category;
  personIds: string[]; // hydrated from item_splits
  personUnits?: Record<string, number>; // portion weight per person, defaults to 1 each
}

export interface Group {
  id: string;
  user_id: string;
  name: string;
  memberIds: string[];
}

export interface Receipt {
  id: string;
  user_id: string;
  merchant: string;
  date: string; // ISO date
  subtotal: number;
  tax: number;
  tip: number;
  discount: number;
  total: number;
  tax_tip_method: TaxTipMethod;
  split_mode: "itemized" | "even";
  category: ReceiptCategory | null;
  image_path: string | null;
  image_mime: string | null;
  items: ReceiptItem[];
}

export interface Payment {
  id: string;
  user_id: string;
  person_id: string;
  receipt_id: string | null;
  amount: number;
  payment_date: string;
  payment_method: PaymentMethod;
}
FILEEOF

mkdir -p $(dirname 'app/friend/[slug]/page.tsx')
cat > 'app/friend/[slug]/page.tsx' << 'FILEEOF'
"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { CheckCircle2, Receipt, Copy, ExternalLink, ChevronDown, ChevronUp } from "lucide-react";
import { PaymentMethod } from "@/lib/types";
import { buildPaymentLink, supportsPaymentLink } from "@/lib/paymentLinks";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash App", "Cash", "PayPal", "Other"];

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}
function fmtDate(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

interface ReceiptRow {
  id: string;
  merchant: string;
  date: string;
  category: string | null;
  owed: number;
  paid: number;
  remaining: number;
  items: { name: string; category: string }[];
}

interface FriendInfo {
  name: string;
  first_name: string | null;
  last_name: string | null;
  preferred_payment_method: PaymentMethod | null;
  payment_handle: string | null;
  phone_number: string | null;
  totalOwed: number;
  totalPaid: number;
  totalRemaining: number;
  receipts: ReceiptRow[];
  owner: { name: string; preferred_payment_method: PaymentMethod | null; payment_handle: string | null } | null;
}

export default function FriendPage() {
  const params = useParams();
  const slug = params.slug as string;

  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [info, setInfo] = useState<FriendInfo | null>(null);

  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [method, setMethod] = useState<PaymentMethod | null>(null);
  const [handle, setHandle] = useState("");
  const [phone, setPhone] = useState("");
  const [payAmount, setPayAmount] = useState("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [showReceipts, setShowReceipts] = useState(false);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    (async () => {
      try {
        const res = await fetch(`/api/friend/${slug}`);
        if (!res.ok) {
          setNotFound(true);
        } else {
          const data: FriendInfo = await res.json();
          setInfo(data);
          setFirstName(data.first_name || data.name);
          setLastName(data.last_name || "");
          setMethod(data.preferred_payment_method);
          setHandle(data.payment_handle ?? "");
          setPhone(data.phone_number ?? "");
          setPayAmount(data.totalRemaining > 0 ? data.totalRemaining.toFixed(2) : "");
        }
      } catch {
        setNotFound(true);
      } finally {
        setLoading(false);
      }
    })();
  }, [slug]);

  async function save() {
    setSaving(true);
    try {
      const res = await fetch(`/api/friend/${slug}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          first_name: firstName.trim() || undefined,
          last_name: lastName.trim(),
          preferred_payment_method: method,
          payment_handle: handle.trim() || null,
          phone_number: phone.trim() || null,
        }),
      });
      if (res.ok) setSaved(true);
    } finally {
      setSaving(false);
    }
  }

  async function copyHandle(text: string) {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {}
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-paper flex items-center justify-center">
        <p className="text-[13px] text-muted">Loading…</p>
      </div>
    );
  }

  if (notFound || !info) {
    return (
      <div className="min-h-screen bg-paper flex items-center justify-center px-6">
        <div className="text-center max-w-sm">
          <div className="w-12 h-12 rounded-full bg-[#F0EDE1] flex items-center justify-center mx-auto mb-4">
            <Receipt size={22} className="text-muted" />
          </div>
          <h1 className="text-[17px] font-semibold text-ink mb-1.5">Link not found</h1>
          <p className="text-[13px] text-muted">This link doesn't look right — ask whoever sent it for a fresh one.</p>
        </div>
      </div>
    );
  }

  const owner = info.owner;
  const ownerLink =
    owner?.preferred_payment_method && owner.payment_handle && supportsPaymentLink(owner.preferred_payment_method)
      ? buildPaymentLink(owner.preferred_payment_method, owner.payment_handle, Number(payAmount) || 0, `Receipt Tracker`)
      : null;

  return (
    <div className="min-h-screen bg-paper">
      <div className="max-w-md mx-auto px-6 pt-10 pb-10">
        <div className="w-11 h-11 rounded-full bg-[#EFF7F3] flex items-center justify-center mb-4">
          <Receipt size={20} className="text-accent" />
        </div>
        <h1 className="text-[19px] font-semibold text-ink mb-1">Hi {info.name} 👋</h1>
        <p className="text-[13px] text-muted mb-5">Here's what you owe, and a quick way to add your info or pay back.</p>

        {/* Balance summary */}
        <div className="bg-white rounded-xl border border-line p-4 mb-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1">You owe</p>
          <p className={`font-mono text-[28px] font-semibold ${info.totalRemaining > 0.005 ? "text-owe" : "text-accent"}`}>
            {money(info.totalRemaining)}
          </p>
          {info.totalPaid > 0 && (
            <p className="text-[12px] text-muted mt-1">{money(info.totalPaid)} already paid</p>
          )}
        </div>

        {/* Pay now */}
        {info.totalRemaining > 0.005 && owner?.preferred_payment_method && owner.payment_handle && (
          <div className="bg-white rounded-xl border border-line p-4 mb-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">
              Pay {owner.name} back via {owner.preferred_payment_method}
            </p>
            <div className="flex items-center gap-2 mb-3">
              <span className="text-[14px] text-muted">$</span>
              <input
                inputMode="decimal"
                value={payAmount}
                onChange={(e) => setPayAmount(e.target.value)}
                className="flex-1 rounded-lg border border-line bg-white px-3 py-2 text-[14px] outline-none focus:ring-2 focus:ring-accent/40"
              />
            </div>
            {ownerLink ? (
              <a
                href={ownerLink}
                target="_blank"
                rel="noopener noreferrer"
                className="w-full flex items-center justify-center gap-1.5 rounded-xl bg-accent text-white font-semibold py-3 text-[14px]"
              >
                <ExternalLink size={15} /> Pay {money(Number(payAmount) || 0)} via {owner.preferred_payment_method}
              </a>
            ) : (
              <button
                onClick={() => copyHandle(owner.payment_handle!)}
                className="w-full flex items-center justify-center gap-1.5 rounded-xl border border-line bg-white text-ink font-semibold py-3 text-[14px]"
              >
                <Copy size={15} />
                {copied ? "Copied!" : `Copy ${owner.name}'s ${owner.preferred_payment_method} info`}
              </button>
            )}
            {!ownerLink && (
              <p className="text-[11px] text-muted mt-2 text-center">
                {owner.preferred_payment_method} doesn't support pre-filled links — copy their info above and send it from your own {owner.preferred_payment_method} app.
              </p>
            )}
          </div>
        )}

        {/* Receipts */}
        {info.receipts.length > 0 && (
          <div className="bg-white rounded-xl border border-line mb-3 overflow-hidden">
            <button
              onClick={() => setShowReceipts(!showReceipts)}
              className="w-full flex items-center justify-between px-4 py-3"
            >
              <span className="text-[13px] font-semibold text-ink">
                {info.receipts.length} receipt{info.receipts.length === 1 ? "" : "s"}
              </span>
              {showReceipts ? <ChevronUp size={16} className="text-muted" /> : <ChevronDown size={16} className="text-muted" />}
            </button>
            {showReceipts && (
              <div className="border-t border-[#EDE9DC]">
                {info.receipts.map((r) => (
                  <div key={r.id} className="px-4 py-3 border-b border-[#EDE9DC] last:border-b-0">
                    <div className="flex items-center justify-between mb-0.5">
                      <span className="text-[13px] font-medium text-ink">{r.merchant}</span>
                      <span className="font-mono text-[13px] font-semibold text-ink">{money(r.owed)}</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-[11px] text-muted">{fmtDate(r.date)} · {r.items.map((i) => i.name).join(", ")}</span>
                      <span className={`text-[11px] font-medium ${r.remaining > 0.005 ? "text-owe" : "text-accent"}`}>
                        {r.remaining > 0.005 ? `${money(r.remaining)} due` : "Paid"}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Edit info */}
        {saved ? (
          <div className="bg-white rounded-xl border border-line p-5 flex items-start gap-3">
            <CheckCircle2 size={20} className="text-accent shrink-0 mt-0.5" />
            <div>
              <p className="text-[14px] font-semibold text-ink">Saved</p>
              <p className="text-[13px] text-muted mt-0.5">Your info is all set. You can close this page.</p>
            </div>
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-line p-4">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Your name</p>
            <div className="flex gap-2 mb-4">
              <input
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                placeholder="First name"
                className="flex-1 rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40"
              />
              <input
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                placeholder="Last name"
                className="flex-1 rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40"
              />
            </div>

            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Your preferred payment method</p>
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
                placeholder={method === "Venmo" ? "@venmo-username" : `${method} username or phone`}
                className="w-full rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40 mb-4"
              />
            )}
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Phone number (optional)</p>
            <input
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              type="tel"
              placeholder="(555) 555-5555"
              className="w-full rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40 mb-4"
            />
            <button
              onClick={save}
              disabled={saving}
              className="w-full rounded-xl bg-accent text-white font-semibold py-3 text-[14px] disabled:opacity-40"
            >
              {saving ? "Saving…" : "Save my info"}
            </button>
          </div>
        )}

        <p className="text-[11px] text-[#B4AEA0] text-center mt-8">Receipt Tracker</p>
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/api/friend/[slug]/route.ts')
cat > 'app/api/friend/[slug]/route.ts' << 'FILEEOF'
import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/service";
import { computeReceiptShares, allocatePersonPayments } from "@/lib/split";
import { Receipt, Payment, PaymentMethod } from "@/lib/types";

const ALLOWED_METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash App", "Cash", "PayPal", "Other"];

async function loadOwnerReceiptsAndPayments(supabase: ReturnType<typeof createServiceClient>, userId: string) {
  const { data: receiptsRaw } = await supabase.from("receipts").select("*").eq("user_id", userId);
  const receiptIds = (receiptsRaw ?? []).map((r: any) => r.id);

  const { data: items } = receiptIds.length
    ? await supabase.from("receipt_items").select("*").in("receipt_id", receiptIds)
    : { data: [] };
  const itemIds = (items ?? []).map((i: any) => i.id);

  const { data: splits } = itemIds.length
    ? await supabase.from("item_splits").select("*").in("item_id", itemIds)
    : { data: [] };

  const { data: payments } = await supabase.from("payments").select("*").eq("user_id", userId);

  const receipts: Receipt[] = (receiptsRaw ?? []).map((r: any) => ({
    ...r,
    items: (items ?? [])
      .filter((i: any) => i.receipt_id === r.id)
      .map((i: any) => {
        const itemSplits = (splits ?? []).filter((s: any) => s.item_id === i.id);
        return {
          ...i,
          personIds: itemSplits.map((s: any) => s.person_id),
          personUnits: Object.fromEntries(itemSplits.map((s: any) => [s.person_id, s.units ?? 1])),
        };
      }),
  }));

  return { receipts, payments: (payments ?? []) as Payment[] };
}

export async function GET(request: Request, { params }: { params: { slug: string } }) {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({ error: "This feature isn't fully configured yet." }, { status: 500 });
  }
  const supabase = createServiceClient();

  const { data: person } = await supabase.from("people").select("*").eq("share_slug", params.slug).maybeSingle();
  if (!person) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }
  const personId = person.id;

  const { data: owner } = await supabase
    .from("people")
    .select("name, preferred_payment_method, payment_handle")
    .eq("user_id", person.user_id)
    .eq("is_self", true)
    .maybeSingle();

  const { receipts, payments } = await loadOwnerReceiptsAndPayments(supabase, person.user_id);
  const alloc = allocatePersonPayments(personId, receipts, payments);

  const receiptDetails = alloc.personReceipts.map(({ receipt, owed }) => {
    const myItems = (receipt.items ?? [])
      .filter((it) => it.personIds.includes(personId))
      .map((it) => ({ name: it.name, category: it.category }));
    return {
      id: receipt.id,
      merchant: receipt.merchant,
      date: receipt.date,
      category: receipt.category,
      owed,
      paid: alloc.paidMap[receipt.id] ?? 0,
      remaining: alloc.remainingMap[receipt.id] ?? 0,
      items: myItems,
    };
  });

  return NextResponse.json({
    name: person.name,
    first_name: person.first_name,
    last_name: person.last_name,
    preferred_payment_method: person.preferred_payment_method,
    payment_handle: person.payment_handle,
    phone_number: person.phone_number,
    totalOwed: alloc.totalOwed,
    totalPaid: alloc.totalPaid,
    totalRemaining: alloc.totalRemaining,
    receipts: receiptDetails,
    owner: owner ?? null,
  });
}

export async function POST(request: Request, { params }: { params: { slug: string } }) {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({ error: "This feature isn't fully configured yet." }, { status: 500 });
  }
  const supabase = createServiceClient();

  const { data: existing } = await supabase.from("people").select("id").eq("share_slug", params.slug).maybeSingle();
  if (!existing) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }
  const personId = existing.id;

  const body = await request.json();
  // Explicit whitelist — never spread the raw body into an update.
  const update: Record<string, any> = {};
  if (typeof body.first_name === "string" && body.first_name.trim()) {
    const first = body.first_name.trim().slice(0, 100);
    const last = typeof body.last_name === "string" ? body.last_name.trim().slice(0, 100) : "";
    update.first_name = first;
    update.last_name = last;
    update.name = `${first} ${last}`.trim();
  } else if (typeof body.name === "string" && body.name.trim()) {
    update.name = body.name.trim().slice(0, 100);
  }
  if (body.preferred_payment_method === null || ALLOWED_METHODS.includes(body.preferred_payment_method)) {
    update.preferred_payment_method = body.preferred_payment_method;
  }
  if (typeof body.payment_handle === "string" || body.payment_handle === null) {
    update.payment_handle = body.payment_handle ? String(body.payment_handle).slice(0, 100) : null;
  }
  if (typeof body.phone_number === "string" || body.phone_number === null) {
    update.phone_number = body.phone_number ? String(body.phone_number).slice(0, 30) : null;
  }

  if (Object.keys(update).length === 0) {
    return NextResponse.json({ error: "nothing to update" }, { status: 400 });
  }

  const { error } = await supabase.from("people").update(update).eq("id", personId);
  if (error) {
    return NextResponse.json({ error: "save_failed" }, { status: 500 });
  }
  return NextResponse.json({ ok: true });
}
FILEEOF

mkdir -p $(dirname 'app/people/[id]/PersonActions.tsx')
cat > 'app/people/[id]/PersonActions.tsx' << 'FILEEOF'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Pencil, Trash2, Check, X, Merge, Share2, MessageCircle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Person, PaymentMethod } from "@/lib/types";
import { DEFAULT_REMINDER_TEMPLATE_WITH_METHOD, REMINDER_PLACEHOLDERS } from "@/lib/paymentLinks";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash App", "Cash", "PayPal", "Other"];

export default function PersonActions({ person, allPeople }: { person: Person; allPeople: Person[] }) {
  const router = useRouter();
  const supabase = createClient();
  const [editingName, setEditingName] = useState(false);
  const [firstName, setFirstName] = useState(person.first_name || person.name);
  const [lastName, setLastName] = useState(person.last_name || "");
  const [method, setMethod] = useState<PaymentMethod | null>(person.preferred_payment_method);
  const [handle, setHandle] = useState(person.payment_handle || "");
  const [phone, setPhone] = useState(person.phone_number || "");
  const [template, setTemplate] = useState(person.reminder_template || "");
  const [templateSaved, setTemplateSaved] = useState(false);
  const [saving, setSaving] = useState(false);
  const [merging, setMerging] = useState(false);
  const [mergeTargetId, setMergeTargetId] = useState<string>("");
  const [mergeBusy, setMergeBusy] = useState(false);
  const [linkCopied, setLinkCopied] = useState(false);

  const otherPeople = allPeople.filter((p) => p.id !== person.id);

  async function saveTemplate() {
    await supabase.from("people").update({ reminder_template: template.trim() || null }).eq("id", person.id);
    setTemplateSaved(true);
    setTimeout(() => setTemplateSaved(false), 2000);
    router.refresh();
  }

  async function shareLink() {
    const url = `${window.location.origin}/friend/${person.share_slug}`;
    if (navigator.share) {
      try {
        await navigator.share({ title: "Add your payment info", text: `Hey — add your Venmo/Zelle so I know how to pay you back:`, url });
      } catch (e) {
        // user cancelled the share sheet — not an error
      }
    } else {
      await navigator.clipboard.writeText(url);
      setLinkCopied(true);
      setTimeout(() => setLinkCopied(false), 2000);
    }
  }

  async function saveName() {
    if (!firstName.trim()) return;
    const fullName = `${firstName.trim()} ${lastName.trim()}`.trim();
    await supabase.from("people").update({ name: fullName, first_name: firstName.trim(), last_name: lastName.trim() }).eq("id", person.id);
    setEditingName(false);
    router.refresh();
  }

  async function savePaymentInfo() {
    setSaving(true);
    await supabase.from("people").update({ preferred_payment_method: method, payment_handle: handle.trim() || null, phone_number: phone.trim() || null }).eq("id", person.id);
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
          <div className="w-full bg-white rounded-xl border border-line p-3 mb-1">
            <div className="flex gap-2 mb-2">
              <input
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                placeholder="First name"
                className="flex-1 rounded-lg border border-line px-2.5 py-1.5 text-[14px] outline-none"
                autoFocus
              />
              <input
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                placeholder="Last name"
                className="flex-1 rounded-lg border border-line px-2.5 py-1.5 text-[14px] outline-none"
              />
            </div>
            <div className="flex gap-2">
              <button onClick={saveName} className="flex-1 rounded-lg bg-accent text-white text-[13px] font-semibold py-1.5 flex items-center justify-center gap-1">
                <Check size={14} /> Save
              </button>
              <button
                onClick={() => {
                  setEditingName(false);
                  setFirstName(person.first_name || person.name);
                  setLastName(person.last_name || "");
                }}
                className="px-3 rounded-lg bg-[#F0EDE1] text-[13px] font-semibold"
              >
                <X size={14} className="text-muted" />
              </button>
            </div>
          </div>
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

      {!person.is_self && (
        <button
          onClick={shareLink}
          className="w-full flex items-center justify-center gap-1.5 rounded-xl border border-line bg-white py-2.5 text-[13px] font-semibold text-accent mt-3"
        >
          <Share2 size={14} /> {linkCopied ? "Link copied!" : `Send ${person.name} a link to add their info`}
        </button>
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
        <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Phone number</p>
        <input
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          type="tel"
          placeholder="(555) 555-5555"
          className="w-full rounded-lg border border-line bg-white px-3 py-2 text-[13px] outline-none focus:ring-2 focus:ring-accent/40 mb-3"
        />
        <button onClick={savePaymentInfo} disabled={saving} className="text-[12px] font-semibold text-accent">
          {saving ? "Saving…" : "Save"}
        </button>
      </div>

      {person.is_self && (
        <div className="bg-white rounded-xl border border-line p-3.5 mt-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5 flex items-center gap-1.5">
            <MessageCircle size={12} /> Reminder text message
          </p>
          <p className="text-[11px] text-muted mb-2">Customize the wording — tap a placeholder to add it.</p>
          <textarea
            value={template}
            onChange={(e) => setTemplate(e.target.value)}
            placeholder={DEFAULT_REMINDER_TEMPLATE_WITH_METHOD}
            rows={4}
            className="w-full rounded-lg border border-line bg-white px-3 py-2 text-[13px] outline-none focus:ring-2 focus:ring-accent/40 mb-2"
          />
          <div className="flex flex-wrap gap-1.5 mb-3">
            {REMINDER_PLACEHOLDERS.map((p) => (
              <button
                key={p.key}
                onClick={() => setTemplate((t) => t + (t && !t.endsWith(" ") ? " " : "") + p.key)}
                title={p.label}
                className="px-2.5 py-1 rounded-full text-[11px] font-mono font-medium border bg-[#F0EDE1] text-[#5B5748] border-line"
              >
                {p.key}
              </button>
            ))}
          </div>
          <button onClick={saveTemplate} className="text-[12px] font-semibold text-accent">
            {templateSaved ? "Saved!" : "Save template"}
          </button>
        </div>
      )}
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/people/[id]/page.tsx')
cat > 'app/people/[id]/page.tsx' << 'FILEEOF'
import { headers } from "next/headers";
import Link from "next/link";
import { MessageCircle } from "lucide-react";
import { loadPeople, loadReceipts, loadPayments } from "@/lib/data";
import { allocatePersonPayments } from "@/lib/split";
import { buildReminderSmsLink } from "@/lib/paymentLinks";
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

  const owner = people.find((p) => p.is_self);
  const host = headers().get("host");
  const friendLink = host ? `https://${host}/friend/${person.share_slug}` : "";

  const unpaidReceipts = personReceipts.filter(({ receipt }) => remainingMap[receipt.id] > 0.005);
  const receiptSummary =
    unpaidReceipts.length === 1
      ? `${unpaidReceipts[0].receipt.merchant} (${fmtDate(unpaidReceipts[0].receipt.date)})`
      : `${unpaidReceipts.length} receipts`;

  const reminderLink =
    person.phone_number && totalRemaining > 0.005 && friendLink
      ? buildReminderSmsLink({
          phone: person.phone_number,
          friendFirstName: person.first_name || person.name,
          totalRemaining,
          receiptSummary,
          ownerMethod: owner?.preferred_payment_method ?? null,
          ownerHandle: owner?.payment_handle ?? null,
          friendPreferredMethod: person.preferred_payment_method,
          friendLink,
          template: owner?.reminder_template ?? null,
        })
      : null;

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
              className="block text-center rounded-xl bg-accent text-white font-semibold py-3.5 mb-3"
            >
              Record payment
            </Link>

            {reminderLink ? (
              <a
                href={reminderLink}
                className="flex items-center justify-center gap-1.5 rounded-xl border border-line bg-white text-ink font-semibold py-3 text-[14px] mb-7"
              >
                <MessageCircle size={16} /> Text {person.first_name || person.name} a reminder
              </a>
            ) : totalRemaining > 0.005 ? (
              <p className="text-[12px] text-muted text-center mb-7">
                Add {person.first_name || person.name}'s phone number below to send a text reminder.
              </p>
            ) : (
              <div className="mb-7" />
            )}
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

echo "Files updated. Running tests..."
npm test
echo "Now run: git add . && git commit -m \"Use short share links instead of raw database IDs\" && git push"
