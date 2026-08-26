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
