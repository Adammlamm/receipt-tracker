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
