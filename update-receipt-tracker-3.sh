#!/bin/bash
set -e
echo "Applying: You/self exclusion, back buttons, receipt editing..."
mkdir -p "app/receipts/[id]/edit"

cat > 'lib/types.ts' << 'FILEEOF'
export type Category = "Food" | "Drinks" | "Other";
export type TaxTipMethod = "proportional" | "equal";
export type PaymentMethod = "Venmo" | "Zelle" | "Apple Cash" | "Cash" | "PayPal" | "Other";

export interface Person {
  id: string;
  user_id: string;
  name: string;
  is_self: boolean;
  created_at: string;
}

export interface ReceiptItem {
  id: string;
  receipt_id: string;
  name: string;
  price: number;
  quantity: number;
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

cat > 'app/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { Receipt as ReceiptIcon, ChevronRight } from "lucide-react";
import { loadPeople, loadReceipts, loadPayments } from "@/lib/data";
import { allocatePersonPayments } from "@/lib/split";
import BottomNav from "@/components/BottomNav";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}
function fmtDate(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export default async function HomePage() {
  const [people, receipts, payments] = await Promise.all([loadPeople(), loadReceipts(), loadPayments()]);

  const balances = people.filter((p) => !p.is_self).map((p) => allocatePersonPayments(p.id, receipts, payments));
  const totalOutstanding = balances.reduce((s, b) => s + b.totalRemaining, 0);
  const peopleOwing = balances.filter((b) => b.totalRemaining > 0.005).length;

  const recentReceipts = [...receipts].slice(0, 4);
  const nameFor = (id: string) => people.find((p) => p.id === id)?.name ?? "—";
  const recentPayments = [...payments].slice(0, 4);

  return (
    <div>
      <div className="px-5 pt-6 pb-2">
        <p className="text-[12px] font-semibold tracking-widest uppercase text-muted">Owed to you</p>
        <p className="font-mono text-[42px] font-semibold text-ink leading-tight mt-1">{money(totalOutstanding)}</p>
        <p className="text-[13px] text-muted mt-1">
          {peopleOwing === 0 ? "Everyone's settled up" : `${peopleOwing} people with a balance`}
        </p>
      </div>

      <div className="px-5 mt-6">
        <h2 className="text-[13px] font-semibold text-ink mb-2">Recent receipts</h2>
        {recentReceipts.length === 0 ? (
          <div className="bg-white rounded-2xl border border-dashed border-line px-5 py-8 text-center">
            <p className="text-[14px] font-semibold text-ink">No receipts yet</p>
            <Link href="/receipts/new" className="mt-3 inline-block text-[13px] font-semibold text-accent">
              + Add Receipt
            </Link>
          </div>
        ) : (
          <div className="space-y-2">
            {recentReceipts.map((r) => (
              <Link
                key={r.id}
                href={`/receipts/${r.id}`}
                className="w-full bg-white rounded-xl border border-line px-4 py-3 flex items-center gap-3"
              >
                <div className="w-10 h-10 rounded-lg bg-[#F0EDE1] flex items-center justify-center shrink-0">
                  <ReceiptIcon size={18} className="text-accent" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-[14px] font-medium text-ink truncate">{r.merchant}</p>
                  <p className="text-[12px] text-muted">{fmtDate(r.date)} · {r.items.length} items</p>
                </div>
                <span className="font-mono text-[14px] font-semibold text-ink">{money(r.total)}</span>
                <ChevronRight size={16} className="text-[#C7C1AF]" />
              </Link>
            ))}
          </div>
        )}
      </div>

      <div className="px-5 mt-7">
        <h2 className="text-[13px] font-semibold text-ink mb-2">Recent payments</h2>
        {recentPayments.length === 0 ? (
          <p className="text-[13px] text-muted py-3">No payments recorded yet.</p>
        ) : (
          <div className="space-y-2">
            {recentPayments.map((p) => (
              <div key={p.id} className="bg-white rounded-xl border border-line px-4 py-3 flex items-center gap-3">
                <div className="flex-1 min-w-0">
                  <p className="text-[14px] font-medium text-ink truncate">{nameFor(p.person_id)}</p>
                  <p className="text-[12px] text-muted">{p.payment_method} · {fmtDate(p.payment_date)}</p>
                </div>
                <span className="font-mono text-[14px] font-semibold text-accent">+{money(p.amount)}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      <BottomNav />
    </div>
  );
}
FILEEOF

cat > 'app/people/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { Users2 } from "lucide-react";
import { loadPeople, loadReceipts, loadPayments } from "@/lib/data";
import { allocatePersonPayments } from "@/lib/split";
import BottomNav from "@/components/BottomNav";
import AddPersonForm from "./AddPersonForm";
import PersonRow from "./PersonRow";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

export default async function PeoplePage() {
  const [people, receipts, payments] = await Promise.all([loadPeople(), loadReceipts(), loadPayments()]);
  const balances = people
    .map((p) => ({ person: p, ...allocatePersonPayments(p.id, receipts, payments) }))
    .sort((a, b) => (a.person.is_self ? -1 : b.person.is_self ? 1 : b.totalRemaining - a.totalRemaining));

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
          <PersonRow key={person.id} person={person} totalRemaining={totalRemaining} />
        ))}
      </div>

      <BottomNav />
    </div>
  );
}
FILEEOF

cat > 'app/people/PersonRow.tsx' << 'FILEEOF'
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
FILEEOF

cat > 'app/people/[id]/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { loadPeople, loadReceipts, loadPayments } from "@/lib/data";
import { allocatePersonPayments } from "@/lib/split";
import BottomNav from "@/components/BottomNav";

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

cat > 'app/payments/new/page.tsx' << 'FILEEOF'
"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { allocatePersonPayments } from "@/lib/split";
import { Person, Receipt, Payment, PaymentMethod } from "@/lib/types";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash", "PayPal", "Other"];

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

export default function RecordPaymentPage() {
  return (
    <Suspense fallback={null}>
      <RecordPaymentForm />
    </Suspense>
  );
}

function RecordPaymentForm() {
  const router = useRouter();
  const params = useSearchParams();
  const supabase = createClient();

  const [people, setPeople] = useState<Person[]>([]);
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [personId, setPersonId] = useState(params.get("personId") ?? "");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [method, setMethod] = useState<PaymentMethod>("Venmo");
  const [receiptId, setReceiptId] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    (async () => {
      const { data: p } = await supabase.from("people").select("*").order("name");
      const { data: pay } = await supabase.from("payments").select("*");
      const { data: r } = await supabase.from("receipts").select("*");
      const { data: items } = await supabase.from("receipt_items").select("*");
      const { data: splits } = await supabase.from("item_splits").select("*");
      setPeople((p ?? []).filter((person: any) => !person.is_self));
      setPayments(pay ?? []);
      setReceipts(
        (r ?? []).map((rec: any) => ({
          ...rec,
          items: (items ?? [])
            .filter((i: any) => i.receipt_id === rec.id)
            .map((i: any) => ({
              ...i,
              personIds: (splits ?? []).filter((s: any) => s.item_id === i.id).map((s: any) => s.person_id),
            })),
        }))
      );
      if (!personId && p && p[0]) setPersonId(p[0].id);
    })();
  }, []);

  const balance = useMemo(
    () => (personId ? allocatePersonPayments(personId, receipts, payments) : null),
    [personId, receipts, payments]
  );
  const receiptsWithBalance = (balance?.personReceipts ?? []).filter(
    (pr) => balance!.remainingMap[pr.receipt.id] > 0.005
  );

  async function save() {
    setSaving(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    await supabase.from("payments").insert({
      user_id: user.id,
      person_id: personId,
      amount: Number(amount),
      payment_date: date,
      payment_method: method,
      receipt_id: receiptId || null,
    });
    router.push("/payments");
    router.refresh();
  }

  return (
    <div className="px-5 pt-4">
      <div className="h-14 -mx-5 px-5 flex items-center border-b border-line mb-4">
        <button onClick={() => router.back()} className="text-[13px] text-muted">Back</button>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink pr-8">Record Payment</h1>
      </div>

      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Person</p>
      <div className="flex flex-wrap gap-1.5 mb-4">
        {people.map((p) => (
          <button
            key={p.id}
            onClick={() => {
              setPersonId(p.id);
              setReceiptId("");
            }}
            className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
              personId === p.id ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
            }`}
          >
            {p.name}
          </button>
        ))}
      </div>

      {balance && <p className="text-[12px] text-muted -mt-2 mb-4">Currently owes {money(balance.totalRemaining)}</p>}

      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Amount</p>
      <input
        inputMode="decimal"
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        placeholder="0.00"
        className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4"
      />

      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Date</p>
      <input
        type="date"
        value={date}
        onChange={(e) => setDate(e.target.value)}
        className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4"
      />

      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Payment method</p>
      <div className="flex flex-wrap gap-1.5 mb-4">
        {METHODS.map((m) => (
          <button
            key={m}
            onClick={() => setMethod(m)}
            className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
              method === m ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
            }`}
          >
            {m}
          </button>
        ))}
      </div>

      {receiptsWithBalance.length > 0 && (
        <>
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">
            Apply to a specific receipt (optional)
          </p>
          <div className="flex flex-wrap gap-1.5 mb-5">
            <button
              onClick={() => setReceiptId("")}
              className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
                receiptId === "" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
              }`}
            >
              General payment
            </button>
            {receiptsWithBalance.map(({ receipt }) => (
              <button
                key={receipt.id}
                onClick={() => setReceiptId(receipt.id)}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
                  receiptId === receipt.id ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
                }`}
              >
                {receipt.merchant}
              </button>
            ))}
          </div>
        </>
      )}

      <button
        onClick={save}
        disabled={!personId || !(Number(amount) > 0) || saving}
        className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-8 disabled:opacity-40"
      >
        Save payment
      </button>
    </div>
  );
}
FILEEOF

cat > 'app/groups/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { loadPeople, loadGroups } from "@/lib/data";
import BottomNav from "@/components/BottomNav";
import GroupsManager from "./GroupsManager";

export default async function GroupsPage() {
  const [people, groups] = await Promise.all([loadPeople(), loadGroups()]);

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Link href="/people" className="text-[13px] text-muted">Back</Link>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink pr-8">Groups</h1>
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

cat > 'app/receipts/[id]/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { Pencil } from "lucide-react";
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
        <Link href={`/receipts/${receipt.id}/edit`} className="p-2 -mr-1 rounded-full active:bg-[#F5F3EC]">
          <Pencil size={16} className="text-muted" />
        </Link>
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

cat > 'app/receipts/[id]/edit/page.tsx' << 'FILEEOF'
"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter, useParams } from "next/navigation";
import { Plus, Trash2, X, CheckCircle2, AlertTriangle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { computeReceiptShares } from "@/lib/split";
import { Category, Person, Group, TaxTipMethod } from "@/lib/types";

const CATEGORIES: Category[] = ["Food", "Drinks", "Other"];

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

interface DraftItem {
  id: string;
  name: string;
  price: string;
  quantity: number;
  category: Category;
  personIds: string[];
  personUnits: Record<string, number>;
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
            return {
              id: i.id,
              name: i.name,
              price: String(i.price),
              quantity: i.quantity || 1,
              category: i.category,
              personIds: splitsForItem.map((s) => s.person_id),
              personUnits: Object.fromEntries(splitsForItem.map((s) => [s.person_id, s.units ?? 1])),
            };
          })
        );
      }
      setLoading(false);
    })();
  }, [receiptId]);

  const itemsSum = items.reduce((s, it) => s + (Number(it.price) || 0), 0);

  function addItem() {
    setItems([...items, { id: crypto.randomUUID(), name: "", price: "", quantity: 1, category: "Food", personIds: [], personUnits: {} }]);
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
  function setUnits(itemId: string, personId: string, units: number) {
    setItems(
      items.map((it) =>
        it.id === itemId ? { ...it, personUnits: { ...it.personUnits, [personId]: Math.max(1, units) } } : it
      )
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
            price: Number(subtotal) || 0,
            quantity: 1,
            category: "Other" as Category,
            personIds: evenParticipants,
            personUnits: {} as Record<string, number>,
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
      })
      .eq("id", receiptId);

    if (error) {
      setSaving(false);
      return;
    }

    // Replace items + splits: delete existing (cascades to item_splits), then reinsert current state
    await supabase.from("receipt_items").delete().eq("receipt_id", receiptId);

    for (const item of validItems) {
      const { data: savedItem } = await supabase
        .from("receipt_items")
        .insert({ receipt_id: receiptId, name: item.name, price: Number(item.price), category: item.category, quantity: item.quantity || 1 })
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
        <div className="px-5 pt-4">
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
                      const newTotal = Number(subtotal) + Number(tax || 0) + calcTip - Number(discount || 0);
                      setTotal(String(Math.round(newTotal * 100) / 100));
                    }}
                    className="flex-1 px-2 py-2 rounded-lg text-[13px] font-medium border bg-white text-[#5B5748] border-line"
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
                <div className="flex items-center gap-2 mb-2.5">
                  <span className="text-[11px] text-muted">Qty</span>
                  <input type="number" min={1} value={it.quantity}
                    onChange={(e) => updateItem(it.id, { quantity: Math.max(1, Number(e.target.value) || 1) })}
                    className="w-14 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  {it.quantity > 1 && <span className="text-[11px] text-muted">(uneven split? use Portions below)</span>}
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
                {it.personIds.length > 1 && Number(it.price) > 0 && it.quantity <= 1 && (
                  <p className="text-[11px] text-muted mt-2">{money(Number(it.price) / it.personIds.length)} each · {it.personIds.length} people</p>
                )}
                {it.personIds.length > 1 && it.quantity > 1 && (
                  <div className="mt-3 pt-3 border-t border-[#EDE9DC]">
                    <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">
                      Portions — not everyone had the same amount?
                    </p>
                    <div className="space-y-1.5">
                      {it.personIds.map((pid) => {
                        const person = people.find((p) => p.id === pid);
                        const units = it.personUnits[pid] ?? 1;
                        const totalUnits = it.personIds.reduce((s, id) => s + (it.personUnits[id] ?? 1), 0);
                        const share = Number(it.price) * (units / totalUnits);
                        return (
                          <div key={pid} className="flex items-center justify-between">
                            <span className="text-[13px] text-[#3A382F]">{person?.name}</span>
                            <div className="flex items-center gap-2">
                              <button onClick={() => setUnits(it.id, pid, units - 1)} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">−</button>
                              <span className="w-5 text-center text-[13px] font-medium">{units}</span>
                              <button onClick={() => setUnits(it.id, pid, units + 1)} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">+</button>
                              <span className="w-16 text-right font-mono text-[12px] text-muted">{money(share)}</span>
                            </div>
                          </div>
                        );
                      })}
                    </div>
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
            {saving ? "Saving…" : "Save changes"}
          </button>
        </div>
      )}
    </div>
  );
}
FILEEOF

echo "All files updated."
echo "Now run: git add . && git commit -m \"Add self-exclusion, back buttons, receipt editing\" && git push"
