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

  const balances = people.map((p) => allocatePersonPayments(p.id, receipts, payments));
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
