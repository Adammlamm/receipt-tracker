import Link from "next/link";
import { CreditCard } from "lucide-react";
import { loadPeople, loadReceipts, loadPayments } from "@/lib/data";
import BottomNav from "@/components/BottomNav";
import EmptyState from "@/components/EmptyState";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}
function fmtDate(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export default async function PaymentsPage() {
  const [people, receipts, payments] = await Promise.all([loadPeople(), loadReceipts(), loadPayments()]);
  const nameFor = (id: string) => people.find((p) => p.id === id)?.name ?? "—";
  const merchantFor = (id: string | null) => receipts.find((r) => r.id === id)?.merchant;

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <h1 className="font-semibold text-[15px] text-ink flex-1">Payments</h1>
        <Link href="/payments/new" className="text-accent text-[13px] font-semibold">
          + Add
        </Link>
      </div>

      <div className="px-5 pt-4 space-y-2">
        {payments.length === 0 && (
          <EmptyState icon={CreditCard} title="No payments yet" body="Record one once someone pays you back." />
        )}
        {payments.map((p) => (
          <div key={p.id} className="bg-white rounded-xl border border-line px-4 py-3 flex items-center gap-3">
            <div className="flex-1 min-w-0">
              <p className="text-[14px] font-medium text-ink truncate">{nameFor(p.person_id)}</p>
              <p className="text-[12px] text-muted truncate">
                {p.payment_method} · {fmtDate(p.payment_date)}
                {p.receipt_id && merchantFor(p.receipt_id) ? ` · ${merchantFor(p.receipt_id)}` : ""}
              </p>
            </div>
            <span className="font-mono text-[14px] font-semibold text-accent">+{money(p.amount)}</span>
          </div>
        ))}
      </div>

      <BottomNav />
    </div>
  );
}
