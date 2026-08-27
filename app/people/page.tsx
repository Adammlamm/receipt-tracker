import Link from "next/link";
import { Users2, Users } from "lucide-react";
import { loadPeople, loadReceipts, loadPayments } from "@/lib/data";
import { allocatePersonPayments } from "@/lib/split";
import BottomNav from "@/components/BottomNav";
import AddPersonForm from "./AddPersonForm";
import PersonRow from "./PersonRow";
import EmptyState from "@/components/EmptyState";

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

      {people.length > 0 && !people.some((p) => p.is_self) && (
        <div className="px-5 pt-4">
          <div className="rounded-xl bg-[#FBF3E6] border border-[#EEDDB8] px-4 py-3 text-[13px] text-[#7A5E24]">
            <p className="font-semibold mb-1">Which one is you?</p>
            <p>Tap the <span className="inline-block px-1.5 py-0.5 rounded bg-white border border-[#EEDDB8] text-[11px] font-semibold align-middle mx-0.5">This is me</span> button next to your name below so your own share doesn't show up as money you owe yourself.</p>
          </div>
        </div>
      )}

      <div className="px-5 pt-4 space-y-2">
        {balances.length === 0 && (
          <EmptyState icon={Users} title="No people yet" body="Add the people you usually split with above." />
        )}
        {balances.map(({ person, totalRemaining }) => (
          <PersonRow key={person.id} person={person} totalRemaining={totalRemaining} />
        ))}
      </div>

      <BottomNav />
    </div>
  );
}
