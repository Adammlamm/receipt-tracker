"use client";

import { useState } from "react";
import { Download } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { computeReceiptShares, allocatePersonPayments } from "@/lib/split";
import { Person, Receipt, Payment } from "@/lib/types";

function csvEscape(value: string | number) {
  const s = String(value);
  if (s.includes(",") || s.includes('"') || s.includes("\n")) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

function downloadCsv(filename: string, rows: (string | number)[][]) {
  const csv = rows.map((row) => row.map(csvEscape).join(",")).join("\n");
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

async function loadAllData(supabase: ReturnType<typeof createClient>) {
  const { data: people } = await supabase.from("people").select("*").order("name");
  const { data: paymentsRaw } = await supabase.from("payments").select("*");
  const { data: receiptsRaw } = await supabase.from("receipts").select("*").order("date");
  const { data: items } = await supabase.from("receipt_items").select("*");
  const { data: splits } = await supabase.from("item_splits").select("*");

  const receipts: Receipt[] = (receiptsRaw ?? []).map((r: any) => ({
    ...r,
    items: (items ?? [])
      .filter((i: any) => i.receipt_id === r.id)
      .map((i: any) => ({
        ...i,
        personIds: (splits ?? []).filter((s: any) => s.item_id === i.id).map((s: any) => s.person_id),
        personUnits: Object.fromEntries((splits ?? []).filter((s: any) => s.item_id === i.id).map((s: any) => [s.person_id, s.units ?? 1])),
      })),
  }));

  return { people: (people ?? []) as Person[], payments: (paymentsRaw ?? []) as Payment[], receipts };
}

export default function ExportButtons() {
  const supabase = createClient();
  const [busy, setBusy] = useState<"receipts" | "payments" | null>(null);

  async function exportReceipts() {
    setBusy("receipts");
    try {
      const { people, receipts, payments } = await loadAllData(supabase);
      const nameFor = (id: string) => people.find((p) => p.id === id)?.name ?? "Unknown";

      const rows: (string | number)[][] = [
        ["Date", "Merchant", "Category", "Person", "Food", "Drinks", "Other", "Tax/Tip", "Total Owed", "Total Paid", "Remaining"],
      ];

      for (const receipt of receipts) {
        const shares = computeReceiptShares(receipt);
        for (const [personId, share] of Object.entries(shares)) {
          const alloc = allocatePersonPayments(personId, [receipt], payments.filter((p) => p.person_id === personId));
          const paid = alloc.paidMap[receipt.id] ?? 0;
          const remaining = alloc.remainingMap[receipt.id] ?? share.total;
          rows.push([
            receipt.date,
            receipt.merchant,
            receipt.category ?? "Uncategorized",
            nameFor(personId),
            share.food.toFixed(2),
            share.drinks.toFixed(2),
            share.other.toFixed(2),
            share.taxTip.toFixed(2),
            share.total.toFixed(2),
            paid.toFixed(2),
            remaining.toFixed(2),
          ]);
        }
      }

      downloadCsv(`receipt-splits-${new Date().toISOString().slice(0, 10)}.csv`, rows);
    } finally {
      setBusy(null);
    }
  }

  async function exportPayments() {
    setBusy("payments");
    try {
      const { people, receipts, payments } = await loadAllData(supabase);
      const nameFor = (id: string) => people.find((p) => p.id === id)?.name ?? "Unknown";
      const merchantFor = (id: string | null) => (id ? receipts.find((r) => r.id === id)?.merchant ?? "" : "");

      const rows: (string | number)[][] = [["Date", "Person", "Amount", "Method", "Linked Receipt"]];
      for (const p of [...payments].sort((a, b) => (a.payment_date < b.payment_date ? -1 : 1))) {
        rows.push([p.payment_date, nameFor(p.person_id), p.amount.toFixed(2), p.payment_method, merchantFor(p.receipt_id)]);
      }

      downloadCsv(`payment-history-${new Date().toISOString().slice(0, 10)}.csv`, rows);
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="flex gap-2">
      <button
        onClick={exportReceipts}
        disabled={busy !== null}
        className="flex-1 flex items-center justify-center gap-1.5 rounded-xl border border-line bg-white py-2.5 text-[12px] font-semibold text-[#5B5748] disabled:opacity-50"
      >
        <Download size={13} /> {busy === "receipts" ? "Exporting…" : "Receipts CSV"}
      </button>
      <button
        onClick={exportPayments}
        disabled={busy !== null}
        className="flex-1 flex items-center justify-center gap-1.5 rounded-xl border border-line bg-white py-2.5 text-[12px] font-semibold text-[#5B5748] disabled:opacity-50"
      >
        <Download size={13} /> {busy === "payments" ? "Exporting…" : "Payments CSV"}
      </button>
    </div>
  );
}
