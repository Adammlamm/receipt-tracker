import Link from "next/link";
import { Receipt as ReceiptIcon, ChevronRight } from "lucide-react";
import { loadReceipts } from "@/lib/data";
import BottomNav from "@/components/BottomNav";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}
function fmtDate(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export default async function ReceiptsPage() {
  const receipts = await loadReceipts();

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <h1 className="font-semibold text-[15px] text-ink flex-1">Receipts</h1>
      </div>

      <div className="px-5 pt-4 space-y-2">
        {receipts.length === 0 && <p className="text-[13px] text-muted py-3">No receipts yet.</p>}
        {receipts.map((r) => (
          <Link key={r.id} href={`/receipts/${r.id}`} className="w-full bg-white rounded-xl border border-line px-4 py-3 flex items-center gap-3">
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

      <BottomNav />
    </div>
  );
}
