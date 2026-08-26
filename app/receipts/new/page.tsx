"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Camera, Plus, Trash2, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { computeReceiptShares } from "@/lib/split";
import { Category, Person, TaxTipMethod } from "@/lib/types";

const CATEGORIES: Category[] = ["Food", "Drinks", "Other"];

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

function compressImage(file: File, maxW = 900, quality = 0.72): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("read failed"));
    reader.onload = () => {
      const img = new Image();
      img.onload = () => {
        const scale = Math.min(1, maxW / img.width);
        const w = Math.round(img.width * scale);
        const h = Math.round(img.height * scale);
        const canvas = document.createElement("canvas");
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext("2d")!;
        ctx.drawImage(img, 0, 0, w, h);
        canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("toBlob failed"))), "image/jpeg", quality);
      };
      img.onerror = () => reject(new Error("decode failed"));
      img.src = reader.result as string;
    };
    reader.readAsDataURL(file);
  });
}

interface DraftItem {
  id: string;
  name: string;
  price: string;
  category: Category;
  personIds: string[];
}

export default function AddReceiptPage() {
  const router = useRouter();
  const supabase = createClient();

  const [step, setStep] = useState(1);
  const [people, setPeople] = useState<Person[]>([]);
  const [merchant, setMerchant] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [subtotal, setSubtotal] = useState("");
  const [tax, setTax] = useState("");
  const [tip, setTip] = useState("");
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [items, setItems] = useState<DraftItem[]>([]);
  const [taxTipMethod, setTaxTipMethod] = useState<TaxTipMethod>("proportional");
  const [newPersonName, setNewPersonName] = useState("");
  const [saving, setSaving] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    supabase.from("people").select("*").order("name").then(({ data }) => setPeople(data ?? []));
  }, []);

  const itemsSum = items.reduce((s, it) => s + (Number(it.price) || 0), 0);

  async function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setImageFile(file);
    setImagePreview(URL.createObjectURL(file));
  }

  function addItem() {
    setItems([...items, { id: crypto.randomUUID(), name: "", price: "", category: "Food", personIds: [] }]);
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

  async function addPerson() {
    if (!newPersonName.trim()) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    const { data } = await supabase
      .from("people")
      .insert({ user_id: user.id, name: newPersonName.trim() })
      .select()
      .single();
    if (data) setPeople([...people, data]);
    setNewPersonName("");
  }

  const validItems = items.filter((it) => it.name.trim() && Number(it.price) > 0);
  const draftReceipt = {
    merchant: merchant.trim() || "Untitled receipt",
    date,
    subtotal: Number(subtotal) || itemsSum,
    tax: Number(tax) || 0,
    tip: Number(tip) || 0,
    total: (Number(subtotal) || itemsSum) + (Number(tax) || 0) + (Number(tip) || 0),
    items: validItems.map((it) => ({ ...it, price: Number(it.price) })),
    tax_tip_method: taxTipMethod,
  };
  const shares = computeReceiptShares(draftReceipt as any);

  async function save() {
    setSaving(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;

    const { data: receipt, error } = await supabase
      .from("receipts")
      .insert({
        user_id: user.id,
        merchant: draftReceipt.merchant,
        date: draftReceipt.date,
        subtotal: draftReceipt.subtotal,
        tax: draftReceipt.tax,
        tip: draftReceipt.tip,
        total: draftReceipt.total,
        tax_tip_method: taxTipMethod,
      })
      .select()
      .single();

    if (error || !receipt) {
      setSaving(false);
      return;
    }

    if (imageFile) {
      try {
        const compressed = await compressImage(imageFile);
        const path = `${user.id}/${receipt.id}.jpg`;
        await supabase.storage.from("receipts").upload(path, compressed, { contentType: "image/jpeg" });
        await supabase.from("receipts").update({ image_path: path }).eq("id", receipt.id);
      } catch (e) {
        console.error("image upload failed", e);
      }
    }

    for (const item of validItems) {
      const { data: savedItem } = await supabase
        .from("receipt_items")
        .insert({ receipt_id: receipt.id, name: item.name, price: Number(item.price), category: item.category })
        .select()
        .single();
      if (savedItem && item.personIds.length) {
        await supabase
          .from("item_splits")
          .insert(item.personIds.map((personId) => ({ item_id: savedItem.id, person_id: personId })));
      }
    }

    router.push(`/receipts/${receipt.id}`);
    router.refresh();
  }

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <button onClick={() => (step === 1 ? router.push("/") : setStep(step - 1))} className="text-[13px] text-muted">
          Back
        </button>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink">
          {step === 1 ? "New Receipt" : step === 2 ? "Items" : "Review Split"}
        </h1>
        <button onClick={() => router.push("/")} className="p-1">
          <X size={18} className="text-muted" />
        </button>
      </div>

      {step === 1 && (
        <div className="px-5 pt-4">
          <input ref={fileRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={handleFile} />
          <button
            onClick={() => fileRef.current?.click()}
            className="w-full rounded-2xl border-2 border-dashed border-line bg-white flex flex-col items-center justify-center py-8 mb-5"
          >
            {imagePreview ? (
              <img src={imagePreview} alt="Receipt" className="max-h-56 rounded-lg object-contain" />
            ) : (
              <>
                <Camera size={26} className="text-accent mb-2" />
                <span className="text-[13px] font-medium text-ink">Take or upload a photo</span>
                <span className="text-[11px] text-muted mt-0.5">Optional — you can enter items manually</span>
              </>
            )}
          </button>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Merchant</p>
          <input value={merchant} onChange={(e) => setMerchant(e.target.value)} placeholder="e.g. Shabuya"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Date</p>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <div className="grid grid-cols-3 gap-2 mb-6">
            {[
              ["Subtotal", subtotal, setSubtotal],
              ["Tax", tax, setTax],
              ["Tip", tip, setTip],
            ].map(([label, val, setter]: any) => (
              <div key={label}>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">{label}</p>
                <input inputMode="decimal" value={val} onChange={(e) => setter(e.target.value)} placeholder="0.00"
                  className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40" />
              </div>
            ))}
          </div>

          <button onClick={() => setStep(2)} className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6">
            Continue to items
          </button>
        </div>
      )}

      {step === 2 && (
        <div className="px-5 pt-4">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-4">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

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
                  {people.map((p) => (
                    <button key={p.id} onClick={() => togglePerson(it.id, p.id)}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {p.name}
                    </button>
                  ))}
                </div>
                {it.personIds.length > 1 && Number(it.price) > 0 && (
                  <p className="text-[11px] text-muted mt-2">{money(Number(it.price) / it.personIds.length)} each · {it.personIds.length} people</p>
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

          <button onClick={() => setStep(3)} disabled={validItems.length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>
      )}

      {step === 3 && (
        <div className="px-5 pt-4">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Tax &amp; tip method</p>
          <div className="flex gap-1.5 mb-5">
            <button onClick={() => setTaxTipMethod("proportional")}
              className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "proportional" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Proportional
            </button>
            <button onClick={() => setTaxTipMethod("equal")}
              className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "equal" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Split equally
            </button>
          </div>

          <div className="space-y-2.5 mb-6">
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
                  <p className="text-[13px] text-[#3A382F] flex justify-between py-1"><span>Tax & tip</span><span className="font-mono">{money(s.taxTip)}</span></p>
                </div>
              );
            })}
          </div>

          <button onClick={save} disabled={saving} className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            {saving ? "Saving…" : "Save receipt"}
          </button>
        </div>
      )}
    </div>
  );
}
