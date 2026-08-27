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
