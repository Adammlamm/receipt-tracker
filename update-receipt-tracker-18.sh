#!/bin/bash
set -e
echo "Applying: phone number field for people..."

mkdir -p $(dirname 'lib/types.ts')
cat > 'lib/types.ts' << 'FILEEOF'
export type Category = "Food" | "Drinks" | "Other";
export type TaxTipMethod = "proportional" | "equal";
export type PaymentMethod = "Venmo" | "Zelle" | "Apple Cash" | "Cash" | "PayPal" | "Other";

export type ReceiptCategory = "Dining" | "Trips" | "Roommates/Home" | "Transportation" | "Other";

export interface Person {
  id: string;
  user_id: string;
  name: string;
  is_self: boolean;
  preferred_payment_method: PaymentMethod | null;
  payment_handle: string | null;
  phone_number: string | null;
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

mkdir -p $(dirname 'app/friend/[id]/page.tsx')
cat > 'app/friend/[id]/page.tsx' << 'FILEEOF'
"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { CheckCircle2, Receipt } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { PaymentMethod } from "@/lib/types";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash", "PayPal", "Other"];

export default function FriendPage() {
  const params = useParams();
  const personId = params.id as string;
  const supabase = createClient();

  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [name, setName] = useState("");
  const [method, setMethod] = useState<PaymentMethod | null>(null);
  const [handle, setHandle] = useState("");
  const [phone, setPhone] = useState("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    (async () => {
      const { data, error } = await supabase.rpc("get_person_public_info", { p_id: personId });
      const row = Array.isArray(data) ? data[0] : data;
      if (error || !row) {
        setNotFound(true);
      } else {
        setName(row.name);
        setMethod(row.preferred_payment_method ?? null);
        setHandle(row.payment_handle ?? "");
        setPhone(row.phone_number ?? "");
      }
      setLoading(false);
    })();
  }, [personId]);

  async function save() {
    setSaving(true);
    const { error } = await supabase.rpc("update_person_payment_info", {
      p_id: personId,
      p_method: method,
      p_handle: handle.trim() || null,
      p_phone: phone.trim() || null,
    });
    setSaving(false);
    if (!error) setSaved(true);
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-paper flex items-center justify-center">
        <p className="text-[13px] text-muted">Loading…</p>
      </div>
    );
  }

  if (notFound) {
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

  return (
    <div className="min-h-screen bg-paper">
      <div className="max-w-md mx-auto px-6 pt-10 pb-10">
        <div className="w-11 h-11 rounded-full bg-[#EFF7F3] flex items-center justify-center mb-4">
          <Receipt size={20} className="text-accent" />
        </div>
        <h1 className="text-[19px] font-semibold text-ink mb-1">Hi {name} 👋</h1>
        <p className="text-[13px] text-muted mb-6">
          Let them know how you'd like to get paid back when it's time to settle up.
        </p>

        {saved ? (
          <div className="bg-white rounded-xl border border-line p-5 flex items-start gap-3">
            <CheckCircle2 size={20} className="text-accent shrink-0 mt-0.5" />
            <div>
              <p className="text-[14px] font-semibold text-ink">Saved</p>
              <p className="text-[13px] text-muted mt-0.5">Your payment info is all set. You can close this page.</p>
            </div>
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-line p-4">
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
                placeholder={method === "Venmo" ? "@venmo-username" : `${method} username or phone`}
                className="w-full rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40 mb-4"
              />
            )}
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Phone number (optional)</p>
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
              {saving ? "Saving…" : "Save"}
            </button>
          </div>
        )}

        <p className="text-[11px] text-[#B4AEA0] text-center mt-8">Receipt Tracker</p>
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/people/[id]/PersonActions.tsx')
cat > 'app/people/[id]/PersonActions.tsx' << 'FILEEOF'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Pencil, Trash2, Check, X, Merge, Share2 } from "lucide-react";
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
  const [phone, setPhone] = useState(person.phone_number || "");
  const [saving, setSaving] = useState(false);
  const [merging, setMerging] = useState(false);
  const [mergeTargetId, setMergeTargetId] = useState<string>("");
  const [mergeBusy, setMergeBusy] = useState(false);
  const [linkCopied, setLinkCopied] = useState(false);

  const otherPeople = allPeople.filter((p) => p.id !== person.id);

  async function shareLink() {
    const url = `${window.location.origin}/friend/${person.id}`;
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
    if (!name.trim()) return;
    await supabase.from("people").update({ name: name.trim() }).eq("id", person.id);
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
    </div>
  );
}
FILEEOF

echo "All files updated."
echo "Now run: git add . && git commit -m \"Add phone number field for people\" && git push"
