#!/bin/bash
set -e
echo "Applying receipt-tracker updates..."
mkdir -p app/api/scan-receipt app/groups

mkdir -p $(dirname 'app/api/scan-receipt/route.ts')
cat > 'app/api/scan-receipt/route.ts' << 'FILEEOF'
import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const maxDuration = 30;

const SYSTEM_PROMPT = `You read restaurant/store receipts from photos and extract structured data.
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
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      { error: "Receipt scanning isn't configured yet (missing ANTHROPIC_API_KEY)." },
      { status: 500 }
    );
  }

  const { imageBase64, mediaType } = await request.json();
  if (!imageBase64) {
    return NextResponse.json({ error: "No image provided." }, { status: 400 });
  }

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
            content: [
              {
                type: "image",
                source: { type: "base64", media_type: mediaType || "image/jpeg", data: imageBase64 },
              },
              { type: "text", text: "Extract this receipt into the JSON shape described." },
            ],
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
    const parsed = JSON.parse(cleaned);
    return NextResponse.json(parsed);
  } catch (err) {
    console.error("scan-receipt error:", err);
    return NextResponse.json({ error: "Receipt scan failed. Try entering it manually." }, { status: 500 });
  }
}
FILEEOF

mkdir -p $(dirname 'app/groups/page.tsx')
cat > 'app/groups/page.tsx' << 'FILEEOF'
import { loadPeople, loadGroups } from "@/lib/data";
import BottomNav from "@/components/BottomNav";
import GroupsManager from "./GroupsManager";

export default async function GroupsPage() {
  const [people, groups] = await Promise.all([loadPeople(), loadGroups()]);

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <h1 className="font-semibold text-[15px] text-ink flex-1">Groups</h1>
      </div>
      <div className="px-5 pt-4 pb-8">
        <p className="text-[13px] text-muted mb-4">
          Groups let you assign a whole table or crowd to an item in one tap — like "Drinkers" or "Table 2".
        </p>
        <GroupsManager people={people} initialGroups={groups} />
      </div>
      <BottomNav />
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/groups/GroupsManager.tsx')
cat > 'app/groups/GroupsManager.tsx' << 'FILEEOF'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Plus, X, Pencil, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Person, Group } from "@/lib/types";

export default function GroupsManager({ people, initialGroups }: { people: Person[]; initialGroups: Group[] }) {
  const [groups, setGroups] = useState(initialGroups);
  const [creating, setCreating] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [memberIds, setMemberIds] = useState<string[]>([]);
  const router = useRouter();
  const supabase = createClient();

  function startCreate() {
    setCreating(true);
    setEditingId(null);
    setName("");
    setMemberIds([]);
  }

  function startEdit(g: Group) {
    setEditingId(g.id);
    setCreating(false);
    setName(g.name);
    setMemberIds(g.memberIds);
  }

  function toggleMember(id: string) {
    setMemberIds((cur) => (cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id]));
  }

  async function save() {
    if (!name.trim()) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;

    if (editingId) {
      await supabase.from("groups").update({ name: name.trim() }).eq("id", editingId);
      await supabase.from("group_members").delete().eq("group_id", editingId);
      if (memberIds.length) {
        await supabase.from("group_members").insert(memberIds.map((person_id) => ({ group_id: editingId, person_id })));
      }
    } else {
      const { data: group } = await supabase.from("groups").insert({ user_id: user.id, name: name.trim() }).select().single();
      if (group && memberIds.length) {
        await supabase.from("group_members").insert(memberIds.map((person_id) => ({ group_id: group.id, person_id })));
      }
    }

    setCreating(false);
    setEditingId(null);
    router.refresh();
    const { data: freshGroups } = await supabase.from("groups").select("*").order("name");
    const { data: freshMembers } = await supabase.from("group_members").select("*");
    setGroups(
      (freshGroups ?? []).map((g) => ({
        ...g,
        memberIds: (freshMembers ?? []).filter((m) => m.group_id === g.id).map((m) => m.person_id),
      }))
    );
  }

  async function remove(id: string) {
    if (!confirm("Delete this group?")) return;
    await supabase.from("groups").delete().eq("id", id);
    setGroups(groups.filter((g) => g.id !== id));
  }

  const editorOpen = creating || editingId !== null;

  return (
    <div>
      {!editorOpen && (
        <button
          onClick={startCreate}
          className="w-full rounded-xl border-2 border-dashed border-line py-3 flex items-center justify-center gap-1.5 text-[13px] font-semibold text-accent mb-4"
        >
          <Plus size={16} /> New group
        </button>
      )}

      {editorOpen && (
        <div className="bg-white rounded-xl border border-line p-3.5 mb-4">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Group name, e.g. Drinkers"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-3"
          />
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Members</p>
          <div className="flex flex-wrap gap-1.5 mb-3">
            {people.map((p) => (
              <button
                key={p.id}
                onClick={() => toggleMember(p.id)}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
                  memberIds.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
                }`}
              >
                {p.name}
              </button>
            ))}
            {people.length === 0 && <p className="text-[13px] text-muted">Add people first, from the People tab.</p>}
          </div>
          <div className="flex gap-2">
            <button onClick={save} className="flex-1 rounded-xl bg-accent text-white font-semibold py-2.5 text-[14px]">
              Save group
            </button>
            <button
              onClick={() => {
                setCreating(false);
                setEditingId(null);
              }}
              className="px-4 rounded-xl bg-[#F0EDE1] text-[#5B5748] font-semibold py-2.5 text-[14px]"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      <div className="space-y-2">
        {groups.map((g) => (
          <div key={g.id} className="bg-white rounded-xl border border-line px-4 py-3 flex items-center gap-3">
            <div className="flex-1 min-w-0">
              <p className="text-[14px] font-medium text-ink">{g.name}</p>
              <p className="text-[12px] text-muted truncate">
                {g.memberIds.map((id) => people.find((p) => p.id === id)?.name).filter(Boolean).join(", ") || "No members"}
              </p>
            </div>
            <button onClick={() => startEdit(g)} className="p-2 rounded-full active:bg-[#F5F3EC]">
              <Pencil size={15} className="text-muted" />
            </button>
            <button onClick={() => remove(g.id)} className="p-2 rounded-full active:bg-[#FBEDEA]">
              <Trash2 size={15} className="text-owe" />
            </button>
          </div>
        ))}
        {groups.length === 0 && !editorOpen && <p className="text-[13px] text-muted py-2">No groups yet.</p>}
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/receipts/new/page.tsx')
cat > 'app/receipts/new/page.tsx' << 'FILEEOF'
"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Camera, Plus, Trash2, X, Sparkles, Loader2, CheckCircle2, AlertTriangle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { computeReceiptShares } from "@/lib/split";
import { Category, Person, Group, TaxTipMethod } from "@/lib/types";

const CATEGORIES: Category[] = ["Food", "Drinks", "Other"];

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

function compressImage(file: File, maxW = 1200, quality = 0.78): Promise<{ blob: Blob; dataUrl: string }> {
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
        const dataUrl = canvas.toDataURL("image/jpeg", quality);
        canvas.toBlob(
          (blob) => (blob ? resolve({ blob, dataUrl }) : reject(new Error("toBlob failed"))),
          "image/jpeg",
          quality
        );
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

type Phase = "capture" | "basics" | "participants" | "items" | "review";

export default function AddReceiptPage() {
  const router = useRouter();
  const supabase = createClient();

  const [phase, setPhase] = useState<Phase>("capture");
  const [people, setPeople] = useState<Person[]>([]);
  const [groups, setGroups] = useState<Group[]>([]);
  const [merchant, setMerchant] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [subtotal, setSubtotal] = useState("");
  const [tax, setTax] = useState("");
  const [tip, setTip] = useState("");
  const [discount, setDiscount] = useState("");
  const [total, setTotal] = useState("");
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [items, setItems] = useState<DraftItem[]>([]);
  const [taxTipMethod, setTaxTipMethod] = useState<TaxTipMethod>("proportional");
  const [splitMode, setSplitMode] = useState<"itemized" | "even">("itemized");
  const [evenParticipants, setEvenParticipants] = useState<string[]>([]);
  const [newPersonName, setNewPersonName] = useState("");
  const [saving, setSaving] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    supabase.from("people").select("*").order("name").then(({ data }) => setPeople(data ?? []));
    (async () => {
      const { data: g } = await supabase.from("groups").select("*").order("name");
      const { data: m } = await supabase.from("group_members").select("*");
      setGroups(
        (g ?? []).map((grp) => ({ ...grp, memberIds: (m ?? []).filter((x) => x.group_id === grp.id).map((x) => x.person_id) }))
      );
    })();
  }, []);

  const itemsSum = items.reduce((s, it) => s + (Number(it.price) || 0), 0);

  async function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setImageFile(file);
    setScanError(null);

    try {
      const { dataUrl } = await compressImage(file);
      setImagePreview(dataUrl);
      setScanning(true);
      const base64 = dataUrl.split(",")[1];
      const res = await fetch("/api/scan-receipt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ imageBase64: base64, mediaType: "image/jpeg" }),
      });
      const parsed = await res.json();
      if (!res.ok) {
        setScanError(parsed.error || "Couldn't read this receipt automatically — enter it manually below.");
      } else {
        setMerchant(parsed.merchant || "");
        if (parsed.date) setDate(parsed.date);
        if (parsed.subtotal != null) setSubtotal(String(parsed.subtotal));
        if (parsed.tax != null) setTax(String(parsed.tax));
        if (parsed.tip != null) setTip(String(parsed.tip));
        if (parsed.discount != null) setDiscount(String(parsed.discount));
        if (parsed.total != null) setTotal(String(parsed.total));
        if (Array.isArray(parsed.items)) {
          setItems(
            parsed.items.map((it: any) => ({
              id: crypto.randomUUID(),
              name: it.quantity && it.quantity > 1 ? `${it.quantity} × ${it.name}` : it.name,
              price: String((Number(it.unit_price) || 0) * (Number(it.quantity) || 1)),
              category: (["Food", "Drinks", "Other"].includes(it.category) ? it.category : "Food") as Category,
              personIds: [],
            }))
          );
        }
      }
    } catch (err) {
      console.error(err);
      setScanError("Couldn't read this receipt automatically — enter it manually below.");
    } finally {
      setScanning(false);
    }
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
            price: Number(subtotal) || 0,
            category: "Other" as Category,
            personIds: evenParticipants,
          },
        ]
      : items.filter((it) => it.name.trim() && Number(it.price) > 0).map((it) => ({ ...it, price: Number(it.price) }));

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

    const { data: receipt, error } = await supabase
      .from("receipts")
      .insert({
        user_id: user.id,
        merchant: draftReceipt.merchant,
        date: draftReceipt.date,
        subtotal: draftReceipt.subtotal,
        tax: draftReceipt.tax,
        tip: draftReceipt.tip,
        discount: draftReceipt.discount,
        total: draftReceipt.total,
        tax_tip_method: taxTipMethod,
        split_mode: splitMode,
      })
      .select()
      .single();

    if (error || !receipt) {
      setSaving(false);
      return;
    }

    if (imageFile) {
      try {
        const { blob } = await compressImage(imageFile);
        const path = `${user.id}/${receipt.id}.jpg`;
        await supabase.storage.from("receipts").upload(path, blob, { contentType: "image/jpeg" });
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
        await supabase.from("item_splits").insert(item.personIds.map((personId) => ({ item_id: savedItem.id, person_id: personId })));
      }
    }

    router.push(`/receipts/${receipt.id}`);
    router.refresh();
  }

  function backFrom(p: Phase) {
    if (p === "basics") setPhase("capture");
    else if (p === "participants") setPhase("basics");
    else if (p === "items") setPhase("basics");
    else if (p === "review") setPhase(splitMode === "even" ? "participants" : "items");
  }

  const titles: Record<Phase, string> = {
    capture: "Scan Receipt",
    basics: "Receipt Details",
    participants: "Who's In?",
    items: "Items",
    review: "Review & Split",
  };

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <button onClick={() => (phase === "capture" ? router.push("/") : backFrom(phase))} className="text-[13px] text-muted">
          Back
        </button>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink">{titles[phase]}</h1>
        <button onClick={() => router.push("/")} className="p-1">
          <X size={18} className="text-muted" />
        </button>
      </div>

      {phase === "capture" && (
        <div className="px-5 pt-4">
          <input ref={fileRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={handleFile} />
          <button
            onClick={() => fileRef.current?.click()}
            disabled={scanning}
            className="w-full rounded-2xl border-2 border-dashed border-line bg-white flex flex-col items-center justify-center py-10 mb-4"
          >
            {imagePreview ? (
              <img src={imagePreview} alt="Receipt" className="max-h-56 rounded-lg object-contain" />
            ) : (
              <>
                <Camera size={28} className="text-accent mb-2" />
                <span className="text-[14px] font-medium text-ink">Take or upload a photo</span>
                <span className="text-[11px] text-muted mt-0.5">We'll read it automatically</span>
              </>
            )}
          </button>

          {scanning && (
            <div className="flex items-center justify-center gap-2 text-[13px] text-accent mb-4">
              <Loader2 size={16} className="animate-spin" />
              Reading your receipt…
            </div>
          )}

          {scanError && (
            <div className="rounded-xl bg-[#FBF3E6] border border-[#EEDDB8] px-4 py-3 text-[13px] text-[#7A5E24] mb-4">
              {scanError}
            </div>
          )}

          {!scanning && (merchant || items.length > 0) && (
            <div className="rounded-xl bg-[#EFF7F3] border border-[#CFE8DC] px-4 py-3 text-[13px] text-[#1F7A5C] mb-4 flex items-center gap-2">
              <Sparkles size={15} /> Scanned — review the details on the next screen.
            </div>
          )}

          <button
            onClick={() => setPhase("basics")}
            disabled={scanning}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-3 disabled:opacity-40"
          >
            {merchant || items.length > 0 ? "Continue" : "Enter manually instead"}
          </button>
        </div>
      )}

      {phase === "basics" && (
        <div className="px-5 pt-4">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Merchant</p>
          <input value={merchant} onChange={(e) => setMerchant(e.target.value)} placeholder="e.g. King Pocha"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Date</p>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <div className="grid grid-cols-2 gap-2 mb-4">
            {[
              ["Subtotal", subtotal, setSubtotal],
              ["Tax", tax, setTax],
              ["Tip", tip, setTip],
              ["Discount", discount, setDiscount],
            ].map(([label, val, setter]: any) => (
              <div key={label}>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">{label}</p>
                <input inputMode="decimal" value={val} onChange={(e) => setter(e.target.value)} placeholder="0.00"
                  className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40" />
              </div>
            ))}
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Total</p>
          <input inputMode="decimal" value={total} onChange={(e) => setTotal(e.target.value)} placeholder="0.00"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-6" />

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
        <div className="px-5 pt-4">
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
        <div className="px-5 pt-4">
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

          <button onClick={() => setPhase("review")} disabled={items.filter((it) => it.name.trim() && Number(it.price) > 0).length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>
      )}

      {phase === "review" && (
        <div className="px-5 pt-4">
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
            {saving ? "Saving…" : "Save receipt"}
          </button>
        </div>
      )}
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/receipts/[id]/page.tsx')
cat > 'app/receipts/[id]/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { loadPeople, loadReceipt, receiptImageUrl } from "@/lib/data";
import { computeReceiptShares } from "@/lib/split";
import DeleteReceiptButton from "./DeleteReceiptButton";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}
function fmtDate(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export default async function ReceiptDetailPage({ params }: { params: { id: string } }) {
  const [receipt, people] = await Promise.all([loadReceipt(params.id), loadPeople()]);
  if (!receipt) return <p className="p-5 text-muted text-sm">This receipt was removed.</p>;

  const imageUrl = await receiptImageUrl(receipt.image_path);
  const shares = computeReceiptShares(receipt);
  const nameFor = (id: string) => people.find((p) => p.id === id)?.name ?? "—";

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Link href="/receipts" className="text-[13px] text-muted">Back</Link>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink truncate px-2">{receipt.merchant}</h1>
        <DeleteReceiptButton receiptId={receipt.id} imagePath={receipt.image_path} />
      </div>

      <div className="px-5 pt-4">
        {imageUrl && <img src={imageUrl} alt="Receipt" className="w-full rounded-xl mb-4 border border-line" />}
        <p className="text-[12px] text-muted mb-4">{fmtDate(receipt.date)}</p>

        <div className="bg-white rounded-xl border border-line p-4 mb-5">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Items</p>
          {receipt.items.map((it) => (
            <div key={it.id} className="py-1.5">
              <div className="flex justify-between text-[14px] text-[#3A382F]">
                <span>{it.name}</span>
                <span className="font-mono">{money(it.price)}</span>
              </div>
              <p className="text-[11px] text-[#A29C8B]">{it.category} · {it.personIds.map(nameFor).join(", ")}</p>
            </div>
          ))}
          <div className="border-t border-[#EDE9DC] mt-2 pt-2 space-y-1">
            <div className="flex justify-between text-[14px]"><span>Subtotal</span><span className="font-mono">{money(receipt.subtotal)}</span></div>
            <div className="flex justify-between text-[14px]"><span>Tax</span><span className="font-mono">{money(receipt.tax)}</span></div>
            <div className="flex justify-between text-[14px]"><span>Tip</span><span className="font-mono">{money(receipt.tip)}</span></div>
            {receipt.discount > 0 && <div className="flex justify-between text-[14px] text-accent"><span>Discount</span><span className="font-mono">-{money(receipt.discount)}</span></div>}
            <div className="flex justify-between text-[14px] font-semibold"><span>Total</span><span className="font-mono">{money(receipt.total)}</span></div>
          </div>
        </div>

        <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Who owes what</p>
        <div className="space-y-2 mb-8">
          {Object.entries(shares).map(([pid, s]) => (
            <Link key={pid} href={`/people/${pid}`} className="w-full bg-white rounded-xl border border-line px-4 py-3 flex items-center justify-between">
              <span className="text-[14px] font-medium text-ink">{nameFor(pid)}</span>
              <span className="font-mono text-[14px] font-semibold text-ink">{money(s.total)}</span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/people/page.tsx')
cat > 'app/people/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { ChevronRight, Users2 } from "lucide-react";
import { loadPeople, loadReceipts, loadPayments } from "@/lib/data";
import { allocatePersonPayments } from "@/lib/split";
import BottomNav from "@/components/BottomNav";
import AddPersonForm from "./AddPersonForm";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

export default async function PeoplePage() {
  const [people, receipts, payments] = await Promise.all([loadPeople(), loadReceipts(), loadPayments()]);
  const balances = people
    .map((p) => ({ person: p, ...allocatePersonPayments(p.id, receipts, payments) }))
    .sort((a, b) => b.totalRemaining - a.totalRemaining);

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <h1 className="font-semibold text-[15px] text-ink flex-1">People</h1>
        <Link href="/groups" className="flex items-center gap-1 text-accent text-[13px] font-semibold">
          <Users2 size={15} /> Groups
        </Link>
      </div>

      <div className="px-5 pt-4">
        <AddPersonForm />
      </div>

      <div className="px-5 pt-4 space-y-2">
        {balances.length === 0 && <p className="text-[13px] text-muted py-3">No people yet.</p>}
        {balances.map(({ person, totalRemaining }) => (
          <Link
            key={person.id}
            href={`/people/${person.id}`}
            className="w-full bg-white rounded-xl border border-line px-4 py-3 flex items-center gap-3"
          >
            <div className="flex-1 min-w-0">
              <p className="text-[14px] font-medium text-ink">{person.name}</p>
              <p className="text-[12px] text-muted">{totalRemaining > 0.005 ? "Owes you" : "Settled up"}</p>
            </div>
            <span className={`font-mono text-[14px] font-semibold ${totalRemaining > 0.005 ? "text-owe" : "text-muted"}`}>
              {money(totalRemaining)}
            </span>
            <ChevronRight size={16} className="text-[#C7C1AF]" />
          </Link>
        ))}
      </div>

      <BottomNav />
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'lib/types.ts')
cat > 'lib/types.ts' << 'FILEEOF'
export type Category = "Food" | "Drinks" | "Other";
export type TaxTipMethod = "proportional" | "equal";
export type PaymentMethod = "Venmo" | "Zelle" | "Apple Cash" | "Cash" | "PayPal" | "Other";

export interface Person {
  id: string;
  user_id: string;
  name: string;
  created_at: string;
}

export interface ReceiptItem {
  id: string;
  receipt_id: string;
  name: string;
  price: number;
  category: Category;
  personIds: string[]; // hydrated from item_splits
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
  image_path: string | null;
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

mkdir -p $(dirname 'lib/data.ts')
cat > 'lib/data.ts' << 'FILEEOF'
import { createClient } from "@/lib/supabase/server";
import { Person, Receipt, Payment, Group } from "@/lib/types";

export async function loadGroups(): Promise<Group[]> {
  const supabase = createClient();
  const { data: groups } = await supabase.from("groups").select("*").order("name");
  if (!groups || groups.length === 0) return [];

  const { data: members } = await supabase
    .from("group_members")
    .select("*")
    .in("group_id", groups.map((g) => g.id));

  return groups.map((g) => ({
    ...g,
    memberIds: (members ?? []).filter((m) => m.group_id === g.id).map((m) => m.person_id),
  }));
}

export async function loadPeople(): Promise<Person[]> {
  const supabase = createClient();
  const { data } = await supabase.from("people").select("*").order("name");
  return data ?? [];
}

export async function loadPayments(): Promise<Payment[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from("payments")
    .select("*")
    .order("payment_date", { ascending: false });
  return data ?? [];
}

/** Fetches all receipts for the signed-in user, each hydrated with items + who split them. */
export async function loadReceipts(): Promise<Receipt[]> {
  const supabase = createClient();

  const { data: receipts } = await supabase
    .from("receipts")
    .select("*")
    .order("date", { ascending: false });

  if (!receipts || receipts.length === 0) return [];

  const receiptIds = receipts.map((r) => r.id);

  const { data: items } = await supabase
    .from("receipt_items")
    .select("*")
    .in("receipt_id", receiptIds);

  const itemIds = (items ?? []).map((i) => i.id);

  const { data: splits } = itemIds.length
    ? await supabase.from("item_splits").select("*").in("item_id", itemIds)
    : { data: [] };

  return receipts.map((r) => ({
    ...r,
    items: (items ?? [])
      .filter((i) => i.receipt_id === r.id)
      .map((i) => ({
        ...i,
        personIds: (splits ?? []).filter((s) => s.item_id === i.id).map((s) => s.person_id),
      })),
  }));
}

export async function loadReceipt(id: string): Promise<Receipt | null> {
  const supabase = createClient();
  const { data: receipt } = await supabase.from("receipts").select("*").eq("id", id).single();
  if (!receipt) return null;

  const { data: items } = await supabase.from("receipt_items").select("*").eq("receipt_id", id);
  const itemIds = (items ?? []).map((i) => i.id);
  const { data: splits } = itemIds.length
    ? await supabase.from("item_splits").select("*").in("item_id", itemIds)
    : { data: [] };

  return {
    ...receipt,
    items: (items ?? []).map((i) => ({
      ...i,
      personIds: (splits ?? []).filter((s) => s.item_id === i.id).map((s) => s.person_id),
    })),
  };
}

/** The "receipts" storage bucket is private, so image URLs must be signed. */
export async function receiptImageUrl(path: string | null): Promise<string | null> {
  if (!path) return null;
  const supabase = createClient();
  const { data } = await supabase.storage.from("receipts").createSignedUrl(path, 60 * 60);
  return data?.signedUrl ?? null;
}
FILEEOF

mkdir -p $(dirname 'lib/split.ts')
cat > 'lib/split.ts' << 'FILEEOF'
import { Payment, Receipt } from "./types";

export interface PersonShare {
  food: number;
  drinks: number;
  other: number;
  itemSubtotal: number;
  taxTip: number;
  total: number;
}

/** Per-person breakdown of a single receipt: item costs + their share of tax/tip. */
export function computeReceiptShares(receipt: Receipt): Record<string, PersonShare> {
  const shares: Record<string, PersonShare> = {};
  const ensure = (pid: string) => {
    if (!shares[pid]) {
      shares[pid] = { food: 0, drinks: 0, other: 0, itemSubtotal: 0, taxTip: 0, total: 0 };
    }
    return shares[pid];
  };

  let itemsTotal = 0;
  for (const item of receipt.items ?? []) {
    const people = item.personIds ?? [];
    if (people.length === 0) continue;
    const per = item.price / people.length;
    itemsTotal += item.price;
    for (const pid of people) {
      const s = ensure(pid);
      s.itemSubtotal += per;
      if (item.category === "Food") s.food += per;
      else if (item.category === "Drinks") s.drinks += per;
      else s.other += per;
    }
  }

  const taxTip = (Number(receipt.tax) || 0) + (Number(receipt.tip) || 0) - (Number(receipt.discount) || 0);
  const participantIds = Object.keys(shares);

  if (receipt.tax_tip_method === "equal" && participantIds.length > 0) {
    const each = taxTip / participantIds.length;
    participantIds.forEach((pid) => (shares[pid].taxTip = each));
  } else {
    participantIds.forEach((pid) => {
      const portion = itemsTotal > 0 ? shares[pid].itemSubtotal / itemsTotal : 0;
      shares[pid].taxTip = portion * taxTip;
    });
  }

  participantIds.forEach((pid) => {
    shares[pid].total = shares[pid].itemSubtotal + shares[pid].taxTip;
  });

  return shares;
}

export interface PersonAllocation {
  personReceipts: { receipt: Receipt; owed: number }[];
  remainingMap: Record<string, number>;
  paidMap: Record<string, number>;
  totalOwed: number;
  totalPaid: number;
  totalRemaining: number;
}

/**
 * Allocates a person's payments (some linked to a specific receipt, some general)
 * across their receipts, oldest first, to work out what's still outstanding.
 */
export function allocatePersonPayments(
  personId: string,
  receipts: Receipt[],
  payments: Payment[]
): PersonAllocation {
  const personReceipts = receipts
    .map((r) => {
      const shares = computeReceiptShares(r);
      const owed = shares[personId]?.total ?? 0;
      return owed > 0 ? { receipt: r, owed } : null;
    })
    .filter((x): x is { receipt: Receipt; owed: number } => x !== null)
    .sort((a, b) => (a.receipt.date < b.receipt.date ? -1 : 1));

  const remainingMap: Record<string, number> = {};
  personReceipts.forEach(({ receipt, owed }) => (remainingMap[receipt.id] = owed));

  const personPayments = payments.filter((p) => p.person_id === personId);

  let generalPool = 0;
  personPayments.forEach((p) => {
    if (p.receipt_id && remainingMap[p.receipt_id] !== undefined) {
      remainingMap[p.receipt_id] = Math.max(0, remainingMap[p.receipt_id] - p.amount);
    } else {
      generalPool += p.amount;
    }
  });

  for (const { receipt } of personReceipts) {
    if (generalPool <= 0) break;
    const bal = remainingMap[receipt.id];
    const take = Math.min(bal, generalPool);
    remainingMap[receipt.id] = bal - take;
    generalPool -= take;
  }

  const paidMap: Record<string, number> = {};
  personReceipts.forEach(({ receipt, owed }) => {
    paidMap[receipt.id] = owed - remainingMap[receipt.id];
  });

  const totalOwed = personReceipts.reduce((s, r) => s + r.owed, 0);
  const totalPaid = personPayments.reduce((s, p) => s + p.amount, 0);
  const totalRemaining = personReceipts.reduce((s, r) => s + remainingMap[r.receipt.id], 0);

  return { personReceipts, remainingMap, paidMap, totalOwed, totalPaid, totalRemaining };
}
FILEEOF

echo "All files updated."
echo "Now run: git add . && git commit -m \"Add AI scanning, groups, reconciliation\" && git push"
