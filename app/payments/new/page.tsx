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
      setPeople(p ?? []);
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
        <h1 className="font-semibold text-[15px] text-ink">Record Payment</h1>
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
        className="w-full
