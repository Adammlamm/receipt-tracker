"use client";

import { useEffect, useState } from "react";
import { useRouter, useParams } from "next/navigation";
import { Plus, Trash2, X, CheckCircle2, AlertTriangle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { computeReceiptShares } from "@/lib/split";
import { Category, Person, Group, TaxTipMethod, ReceiptCategory } from "@/lib/types";

const CATEGORIES: Category[] = ["Food", "Drinks", "Other"];
const RECEIPT_CATEGORIES: ReceiptCategory[] = ["Dining", "Trips", "Roommates/Home", "Transportation", "Other"];

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

interface DraftItem {
  id: string;
  name: string;
  price: string;
  discount: string;
  quantity: number;
  category: Category;
  personIds: string[];
  personUnits: Record<string, number>;
  splitType: "even" | "shares" | "exact" | "percent";
}

type Phase = "basics" | "participants" | "items" | "review";

export default function EditReceiptPage() {
  const router = useRouter();
  const params = useParams();
  const receiptId = params.id as string;
  const supabase = createClient();

  const [loading, setLoading] = useState(true);
  const [phase, setPhase] = useState<Phase>("basics");
  const [people, setPeople] = useState<Person[]>([]);
  const [groups, setGroups] = useState<Group[]>([]);
  const [merchant, setMerchant] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [subtotal, setSubtotal] = useState("");
  const [tax, setTax] = useState("");
  const [tip, setTip] = useState("");
  const [discount, setDiscount] = useState("");
  const [total, setTotal] = useState("");
  const [selectedTipPct, setSelectedTipPct] = useState<number | null>(null);
  const [receiptCategory, setReceiptCategory] = useState<ReceiptCategory | null>(null);
  const [items, setItems] = useState<DraftItem[]>([]);
  const [taxTipMethod, setTaxTipMethod] = useState<TaxTipMethod>("proportional");
  const [splitMode, setSplitMode] = useState<"itemized" | "even">("itemized");
  const [evenParticipants, setEvenParticipants] = useState<string[]>([]);
  const [newPersonName, setNewPersonName] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    (async () => {
      const { data: p } = await supabase.from("people").select("*").order("name");
      setPeople(p ?? []);
      const { data: g } = await supabase.from("groups").select("*").order("name");
      const { data: m } = await supabase.from("group_members").select("*");
      setGroups(
        (g ?? []).map((grp) => ({ ...grp, memberIds: (m ?? []).filter((x) => x.group_id === grp.id).map((x) => x.person_id) }))
      );

      const { data: receipt } = await supabase.from("receipts").select("*").eq("id", receiptId).single();
      if (!receipt) {
        setLoading(false);
        return;
      }
      setMerchant(receipt.merchant || "");
      setDate(receipt.date || new Date().toISOString().slice(0, 10));
      setSubtotal(String(receipt.subtotal ?? ""));
      setTax(String(receipt.tax ?? ""));
      setTip(String(receipt.tip ?? ""));
      setDiscount(String(receipt.discount ?? ""));
      setTotal(String(receipt.total ?? ""));
      setTaxTipMethod(receipt.tax_tip_method || "proportional");
      setSplitMode(receipt.split_mode || "itemized");
      setReceiptCategory(receipt.category || null);

      const { data: dbItems } = await supabase.from("receipt_items").select("*").eq("receipt_id", receiptId);
      const itemIds = (dbItems ?? []).map((i) => i.id);
      const { data: dbSplits } = itemIds.length
        ? await supabase.from("item_splits").select("*").in("item_id", itemIds)
        : { data: [] };

      if (receipt.split_mode === "even") {
        const evenItem = (dbItems ?? [])[0];
        if (evenItem) {
          const splitsForItem = (dbSplits ?? []).filter((s) => s.item_id === evenItem.id);
          setEvenParticipants(splitsForItem.map((s) => s.person_id));
        }
      } else {
        setItems(
          (dbItems ?? []).map((i) => {
            const splitsForItem = (dbSplits ?? []).filter((s) => s.item_id === i.id);
            const personUnits = Object.fromEntries(splitsForItem.map((s) => [s.person_id, s.units ?? 1]));
            const values = Object.values(personUnits);
            const allSame = values.length > 0 && values.every((v) => v === values[0]);
            return {
              id: i.id,
              name: i.name,
              price: String(i.price),
              discount: i.discount ? String(i.discount) : "",
              quantity: i.quantity || 1,
              category: i.category,
              personIds: splitsForItem.map((s) => s.person_id),
              personUnits,
              splitType: allSame ? "even" : "shares",
            } as DraftItem;
          })
        );
      }
      setLoading(false);
    })();
  }, [receiptId]);

  const itemsSum = items.reduce((s, it) => s + Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0)), 0);

  function addItem() {
    setItems([...items, { id: crypto.randomUUID(), name: "", price: "", discount: "", quantity: 1, category: "Food", personIds: [], personUnits: {}, splitType: "even" }]);
  }
  function updateItem(id: string, patch: Partial<DraftItem>) {
    setItems(items.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  }
  function removeItem(id: string) {
    setItems(items.filter((it) => it.id !== id));
  }
  function togglePerson(itemId: string, personId: string) {
    setItems(
      items.map((it) => {
        if (it.id !== itemId) return it;
        const has = it.personIds.includes(personId);
        return { ...it, personIds: has ? it.personIds.filter((id) => id !== personId) : [...it.personIds, personId] };
      })
    );
  }
  function setItemPeople(itemId: string, ids: string[]) {
    setItems(items.map((it) => (it.id === itemId ? { ...it, personIds: ids } : it)));
  }
  function setSplitType(itemId: string, type: DraftItem["splitType"]) {
    setItems(
      items.map((it) => {
        if (it.id !== itemId) return it;
        const count = it.personIds.length || 1;
        const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
        let personUnits: Record<string, number> = {};
        if (type === "shares") personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, 1]));
        else if (type === "exact") {
          const each = Math.round((effectivePrice / count) * 100) / 100;
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, each]));
        } else if (type === "percent") {
          const each = Math.round((100 / count) * 100) / 100;
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, each]));
        }
        return { ...it, splitType: type, personUnits };
      })
    );
  }
  function setWeight(itemId: string, personId: string, value: number) {
    setItems(
      items.map((it) => (it.id === itemId ? { ...it, personUnits: { ...it.personUnits, [personId]: Math.max(0, value) } } : it))
    );
  }
  function assignCategoryToEveryone(category: Category) {
    const everyone = people.map((p) => p.id);
    setItems(items.map((it) => (it.category === category ? { ...it, personIds: everyone } : it)));
  }
  function assignCategoryToGroup(category: Category, group: Group) {
    setItems(items.map((it) => (it.category === category ? { ...it, personIds: group.memberIds } : it)));
  }

  async function addPerson() {
    if (!newPersonName.trim()) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    const { data } = await supabase.from("people").insert({ user_id: user.id, name: newPersonName.trim() }).select().single();
    if (data) setPeople([...people, data]);
    setNewPersonName("");
  }

  const validItems =
    splitMode === "even"
      ? [
          {
            id: "even-split",
            name: "Whole bill",
            price:
              Number(total) ||
              (Number(subtotal) || 0) + (Number(tax) || 0) + (Number(tip) || 0) - (Number(discount) || 0),
            discount: 0,
            quantity: 1,
            category: "Other" as Category,
            personIds: evenParticipants,
            personUnits: {} as Record<string, number>,
            splitType: "even" as const,
          },
        ]
      : items
          .filter((it) => it.name.trim() && Number(it.price) > 0)
          .map((it) => ({ ...it, price: Number(it.price), discount: Number(it.discount) || 0 }));

  const draftReceipt = {
    merchant: merchant.trim() || "Untitled receipt",
    date,
    subtotal: Number(subtotal) || itemsSum,
    tax: Number(tax) || 0,
    tip: Number(tip) || 0,
    discount: Number(discount) || 0,
    total: Number(total) || (Number(subtotal) || itemsSum) + (Number(tax) || 0) + (Number(tip) || 0) - (Number(discount) || 0),
    items: validItems,
    tax_tip_method: taxTipMethod,
    split_mode: splitMode,
  };
  const shares = computeReceiptShares(draftReceipt as any);

  // Reconciliation
  const calculatedTotal =
    draftReceipt.subtotal + draftReceipt.tax + draftReceipt.tip - draftReceipt.discount;
  const totalDifference = Math.round((draftReceipt.total - calculatedTotal) * 100) / 100;
  const assignedTotal = Object.values(shares).reduce((s: number, sh: any) => s + sh.total, 0);
  const unassigned = Math.round((draftReceipt.total - assignedTotal) * 100) / 100;
  const unassignedItems = splitMode === "itemized" ? validItems.filter((it) => it.personIds.length === 0) : [];

  async function save() {
    setSaving(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;

    const { error } = await supabase
      .from("receipts")
      .update({
        merchant: draftReceipt.merchant,
        date: draftReceipt.date,
        subtotal: draftReceipt.subtotal,
        tax: draftReceipt.tax,
        tip: draftReceipt.tip,
        discount: draftReceipt.discount,
        total: draftReceipt.total,
        tax_tip_method: taxTipMethod,
        split_mode: splitMode,
        category: receiptCategory,
      })
      .eq("id", receiptId);

    if (error) {
      setSaving(false);
      return;
    }

    await supabase.from("receipt_items").delete().eq("receipt_id", receiptId);

    for (const item of validItems) {
      const { data: savedItem } = await supabase
        .from("receipt_items")
        .insert({
          receipt_id: receiptId,
          name: item.name,
          price: Number(item.price),
          discount: Number(item.discount) || 0,
          category: item.category,
          quantity: item.quantity || 1,
        })
        .select()
        .single();
      if (savedItem && item.personIds.length) {
        await supabase.from("item_splits").insert(
          item.personIds.map((personId) => ({
            item_id: savedItem.id,
            person_id: personId,
            units: item.personUnits?.[personId] ?? 1,
          }))
        );
      }
    }

    router.push(`/receipts/${receiptId}`);
    router.refresh();
  }

  function backFrom(p: Phase) {
    if (p === "basics") router.push(`/receipts/${receiptId}`);
    else if (p === "participants") setPhase("basics");
    else if (p === "items") setPhase("basics");
    else if (p === "review") setPhase(splitMode === "even" ? "participants" : "items");
  }

  const titles: Record<Phase, string> = {
    basics: "Edit Receipt",
    participants: "Who's In?",
    items: "Items",
    review: "Review & Split",
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-[13px] text-muted">Loading receipt…</p>
      </div>
    );
  }

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <button onClick={() => backFrom(phase)} className="text-[13px] text-muted">
          Back
        </button>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink">{titles[phase]}</h1>
        <button onClick={() => router.push(`/receipts/${receiptId}`)} className="p-1">
          <X size={18} className="text-muted" />
        </button>
      </div>

      {phase === "basics" && (
        <div className="px-5 pt-4 animate-page-in">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Merchant</p>
          <input value={merchant} onChange={(e) => setMerchant(e.target.value)} placeholder="e.g. King Pocha"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Date</p>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <div className="grid grid-cols-2 gap-2 mb-3">
            {[
              ["Subtotal", subtotal, setSubtotal],
              ["Tax", tax, setTax],
              ["Tip", tip, (v: string) => { setTip(v); setSelectedTipPct(null); }],
              ["Discount", discount, setDiscount],
            ].map(([label, val, setter]: any) => (
              <div key={label}>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">{label}</p>
                <input inputMode="decimal" value={val} onChange={(e) => setter(e.target.value)} placeholder="0.00"
                  className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40" />
              </div>
            ))}
          </div>

          {Number(subtotal) > 0 && (
            <div className="mb-4">
              <p className="text-[11px] text-muted mb-1.5">Tip wasn't printed on the receipt? Calculate it:</p>
              <div className="flex gap-1.5">
                {[15, 18, 20, 25].map((pct) => (
                  <button
                    key={pct}
                    onClick={() => {
                      const calcTip = Math.round(((Number(subtotal) + Number(tax || 0)) * pct) / 100 * 100) / 100;
                      setTip(String(calcTip));
                      setSelectedTipPct(pct);
                      const newTotal = Number(subtotal) + Number(tax || 0) + calcTip - Number(discount || 0);
                      setTotal(String(Math.round(newTotal * 100) / 100));
                    }}
                    className={`flex-1 px-2 py-2 rounded-lg text-[13px] font-medium border ${selectedTipPct === pct ? "bg-accent text-white border-accent" : "bg-white text-[#5B5748] border-line"}`}
                  >
                    {pct}%
                  </button>
                ))}
              </div>
            </div>
          )}

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Total</p>
          <input inputMode="decimal" value={total} onChange={(e) => setTotal(e.target.value)} placeholder="0.00"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-1.5" />
          {(Number(subtotal) > 0 || Number(tax) > 0 || Number(tip) > 0) && (
            <button
              onClick={() => {
                const calc = Number(subtotal || 0) + Number(tax || 0) + Number(tip || 0) - Number(discount || 0);
                setTotal(String(Math.round(calc * 100) / 100));
              }}
              className="text-[12px] text-accent font-medium mb-6"
            >
              Use calculated total ({money(Number(subtotal || 0) + Number(tax || 0) + Number(tip || 0) - Number(discount || 0))})
            </button>
          )}
          {!(Number(subtotal) > 0 || Number(tax) > 0 || Number(tip) > 0) && <div className="mb-6" />}

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Category (optional)</p>
          <div className="flex flex-wrap gap-1.5 mb-6">
            {RECEIPT_CATEGORIES.map((c) => (
              <button
                key={c}
                onClick={() => setReceiptCategory(receiptCategory === c ? null : c)}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${receiptCategory === c ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}
              >
                {c}
              </button>
            ))}
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">How do you want to split it?</p>
          <div className="flex gap-1.5 mb-6">
            <button onClick={() => setSplitMode("itemized")}
              className={`flex-1 px-3.5 py-3 rounded-xl text-[13px] font-medium border ${splitMode === "itemized" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              By item
            </button>
            <button onClick={() => setSplitMode("even")}
              className={`flex-1 px-3.5 py-3 rounded-xl text-[13px] font-medium border ${splitMode === "even" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Whole bill, evenly
            </button>
          </div>

          <button
            onClick={() => setPhase(splitMode === "even" ? "participants" : "items")}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6"
          >
            Continue
          </button>
        </div>
      )}

      {phase === "participants" && (
        <div className="px-5 pt-4 animate-page-in">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-4">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Who was there?</p>
          <div className="flex flex-wrap gap-1.5 mb-4">
            <button onClick={() => setEvenParticipants(people.map((p) => p.id))}
              className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${evenParticipants.length === people.length && people.length > 0 ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Everyone
            </button>
            {people.map((p) => (
              <button key={p.id} onClick={() => setEvenParticipants((cur) => cur.includes(p.id) ? cur.filter((x) => x !== p.id) : [...cur, p.id])}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${evenParticipants.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                {p.name}
              </button>
            ))}
          </div>

          {evenParticipants.length > 0 && (
            <p className="text-[13px] text-muted mb-6">
              {money((Number(total) || Number(subtotal) || 0) / evenParticipants.length)} each · {evenParticipants.length} people
            </p>
          )}

          <button onClick={() => setPhase("review")} disabled={evenParticipants.length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>
      )}

      {phase === "items" && (
        <div className="px-5 pt-4 animate-page-in">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-3">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

          {groups.length > 0 && (items.some((it) => it.category === "Food") || items.some((it) => it.category === "Drinks")) && (
            <div className="bg-white rounded-xl border border-line p-3 mb-3">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Quick assign by category</p>
              <div className="flex flex-wrap gap-1.5">
                <button onClick={() => assignCategoryToEveryone("Food")} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
                  🍽️ Food → Everyone
                </button>
                {groups.map((g) => (
                  <button key={g.id} onClick={() => assignCategoryToGroup("Drinks", g)} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
                    🍺 Drinks → {g.name}
                  </button>
                ))}
              </div>
            </div>
          )}

          <div className="space-y-3">
            {items.map((it) => (
              <div key={it.id} className="bg-white rounded-xl border border-line p-3.5">
                <div className="flex gap-2 mb-2.5">
                  <input className="flex-1 rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none" placeholder="Item name"
                    value={it.name} onChange={(e) => updateItem(it.id, { name: e.target.value })} />
                  <input inputMode="decimal" className="w-24 rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none" placeholder="$"
                    value={it.price} onChange={(e) => updateItem(it.id, { price: e.target.value })} />
                  <button onClick={() => removeItem(it.id)} className="p-2.5 rounded-xl bg-[#FBEDEA]">
                    <Trash2 size={16} className="text-owe" />
                  </button>
                </div>
                <div className="flex items-center gap-3 mb-2.5">
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted">Qty</span>
                    <input type="number" min={1} value={it.quantity}
                      onChange={(e) => updateItem(it.id, { quantity: Math.max(1, Number(e.target.value) || 1) })}
                      className="w-14 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted">Discount</span>
                    <input inputMode="decimal" value={it.discount} placeholder="0.00"
                      onChange={(e) => updateItem(it.id, { discount: e.target.value })}
                      className="w-20 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  </div>
                  {Number(it.discount) > 0 && (
                    <span className="text-[11px] text-accent font-medium">
                      → {money(Math.max(0, (Number(it.price) || 0) - Number(it.discount)))}
                    </span>
                  )}
                </div>
                <div className="flex gap-1.5 mb-2.5">
                  {CATEGORIES.map((c) => (
                    <button key={c} onClick={() => updateItem(it.id, { category: c })}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.category === c ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {c}
                    </button>
                  ))}
                </div>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Shared by</p>
                <div className="flex flex-wrap gap-1.5">
                  <button onClick={() => setItemPeople(it.id, people.map((p) => p.id))}
                    className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.length === people.length && people.length > 0 ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                    Everyone
                  </button>
                  {groups.map((g) => (
                    <button key={g.id} onClick={() => setItemPeople(it.id, g.memberIds)}
                      className="px-3.5 py-2 rounded-full text-[13px] font-medium border bg-[#F0EDE1] text-[#5B5748] border-line">
                      {g.name}
                    </button>
                  ))}
                  {people.map((p) => (
                    <button key={p.id} onClick={() => togglePerson(it.id, p.id)}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {p.name}
                    </button>
                  ))}
                </div>

                {it.personIds.length > 1 && (
                  <div className="mt-3 pt-3 border-t border-[#EDE9DC]">
                    <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Split</p>
                    <div className="flex gap-1.5 mb-3">
                      {(["even", "shares", "exact", "percent"] as const).map((t) => (
                        <button key={t} onClick={() => setSplitType(it.id, t)}
                          className={`px-2.5 py-1.5 rounded-full text-[11px] font-medium border ${it.splitType === t ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                          {t === "even" ? "Evenly" : t === "shares" ? "Shares" : t === "exact" ? "Exact $" : "%"}
                        </button>
                      ))}
                    </div>

                    {it.splitType === "even" && (
                      <p className="text-[11px] text-muted">
                        {money(Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0)) / it.personIds.length)} each · {it.personIds.length} people
                      </p>
                    )}

                    {it.splitType === "shares" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const units = it.personUnits[pid] ?? 1;
                          const totalUnits = it.personIds.reduce((s, id) => s + (it.personUnits[id] ?? 1), 0);
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const share = effectivePrice * (units / totalUnits);
                          return (
                            <div key={pid} className="flex items-center justify-between">
                              <span className="text-[13px] text-[#3A382F]">{person?.name}</span>
                              <div className="flex items-center gap-2">
                                <button onClick={() => setWeight(it.id, pid, Math.max(0, units - 1))} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">−</button>
                                <span className="w-5 text-center text-[13px] font-medium">{units}</span>
                                <button onClick={() => setWeight(it.id, pid, units + 1)} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">+</button>
                                <span className="w-16 text-right font-mono text-[12px] text-muted">{money(share)}</span>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    )}

                    {it.splitType === "exact" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const amt = it.personUnits[pid] ?? 0;
                          return (
                            <div key={pid} className="flex items-center justify-between gap-2">
                              <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                              <input inputMode="decimal" value={amt || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                placeholder="0.00" className="w-20 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                            </div>
                          );
                        })}
                        {(() => {
                          const sum = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const diff = Math.round((effectivePrice - sum) * 100) / 100;
                          return (
                            <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                              {Math.abs(diff) < 0.01 ? "Matches item price ✓" : diff > 0 ? `${money(diff)} unassigned` : `${money(Math.abs(diff))} over`}
                            </p>
                          );
                        })()}
                      </div>
                    )}

                    {it.splitType === "percent" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const pct = it.personUnits[pid] ?? 0;
                          return (
                            <div key={pid} className="flex items-center justify-between gap-2">
                              <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                              <div className="flex items-center gap-1">
                                <input inputMode="decimal" value={pct || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                  placeholder="0" className="w-14 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                                <span className="text-[12px] text-muted">%</span>
                              </div>
                            </div>
                          );
                        })}
                        {(() => {
                          const sum = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const diff = Math.round((100 - sum) * 100) / 100;
                          return (
                            <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                              {Math.abs(diff) < 0.01 ? "Totals 100% ✓" : diff > 0 ? `${diff}% unassigned` : `${Math.abs(diff)}% over`}
                            </p>
                          );
                        })()}
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>

          <button onClick={addItem} className="w-full mt-3 rounded-xl border-2 border-dashed border-line py-3 flex items-center justify-center gap-1.5 text-[13px] font-semibold text-accent">
            <Plus size={16} /> Add item
          </button>

          <div className="flex items-center justify-between mt-5 mb-6">
            <span className="text-[13px] text-muted">Items total</span>
            <span className="font-mono text-[15px] font-semibold text-ink">{money(itemsSum)}</span>
          </div>

          <button onClick={() => setPhase("review")} disabled={items.filter((it) => it.name.trim() && Number(it.price) > 0).length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>
      )}

      {phase === "review" && (
        <div className="px-5 pt-4 animate-page-in">
          {splitMode === "even" ? (
            <div className="bg-white rounded-xl border border-line p-4 mb-4">
              <div className="flex justify-between text-[14px] font-semibold"><span>Total</span><span className="font-mono">{money(draftReceipt.total)}</span></div>
            </div>
          ) : (
            <div className="bg-white rounded-xl border border-line p-4 mb-4">
              <div className="flex justify-between text-[13px] mb-1"><span className="text-muted">Receipt total</span><span className="font-mono text-ink">{money(draftReceipt.total)}</span></div>
              <div className="flex justify-between text-[13px] mb-1"><span className="text-muted">Calculated total</span><span className="font-mono text-ink">{money(calculatedTotal)}</span></div>
              <div className={`flex justify-between text-[13px] items-center ${Math.abs(totalDifference) < 0.01 ? "text-accent" : "text-owe"}`}>
                <span>Difference</span>
                <span className="font-mono flex items-center gap-1">
                  {money(Math.abs(totalDifference))}
                  {Math.abs(totalDifference) < 0.01 ? <CheckCircle2 size={14} /> : <AlertTriangle size={14} />}
                </span>
              </div>
            </div>
          )}

          {splitMode === "itemized" && (
            <div className="flex gap-1.5 mb-5">
              <button onClick={() => setTaxTipMethod("proportional")}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "proportional" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                Tax/tip proportional
              </button>
              <button onClick={() => setTaxTipMethod("equal")}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "equal" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                Split equally
              </button>
            </div>
          )}

          <div className="space-y-2.5 mb-4">
            {Object.entries(shares).map(([pid, s]: any) => {
              const person = people.find((p) => p.id === pid);
              return (
                <div key={pid} className="bg-white rounded-xl border border-line p-3.5">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[14px] font-semibold text-ink">{person?.name}</span>
                    <span className="font-mono text-[15px] font-semibold text-ink">{money(s.total)}</span>
                  </div>
                  {s.food > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Food</span><span className="font-mono">{money(s.food)}</span></p>}
                  {s.drinks > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Drinks</span><span className="font-mono">{money(s.drinks)}</span></p>}
                  {s.other > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Other</span><span className="font-mono">{money(s.other)}</span></p>}
                  <p className="text-[13px] text-[#3A382F] flex justify-between py-1"><span>Tax, tip &amp; discount</span><span className="font-mono">{money(s.taxTip)}</span></p>
                </div>
              );
            })}
          </div>

          {unassignedItems.length > 0 && (
            <div className="rounded-xl bg-[#FBF3E6] border border-[#EEDDB8] px-4 py-3 text-[13px] text-[#7A5E24] mb-4">
              Not assigned yet: {unassignedItems.map((it) => it.name).join(", ")}
            </div>
          )}

          <div className={`rounded-xl px-4 py-3 mb-6 flex items-center justify-between text-[13px] font-medium ${Math.abs(unassigned) < 0.01 ? "bg-[#EFF7F3] text-[#1F7A5C]" : "bg-[#FBEDEA] text-owe"}`}>
            <span>{Math.abs(unassigned) < 0.01 ? "Fully assigned" : "Unassigned amount"}</span>
            <span className="font-mono flex items-center gap-1">
              {Math.abs(unassigned) < 0.01 ? <CheckCircle2 size={14} /> : money(unassigned)}
            </span>
          </div>

          <button onClick={save} disabled={saving} className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            {saving ? "Saving…" : "Save changes"}
          </button>
        </div>
      )}
    </div>
  );
}
