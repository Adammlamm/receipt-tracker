"use client";

import { useMemo, useState } from "react";
import { Users } from "lucide-react";
import PersonRow from "./PersonRow";
import EmptyState from "@/components/EmptyState";
import { Person } from "@/lib/types";

type SortMode = "balance" | "first" | "last";

interface BalanceRow {
  person: Person;
  totalRemaining: number;
}

export default function PeopleList({ balances }: { balances: BalanceRow[] }) {
  const [sortMode, setSortMode] = useState<SortMode>("balance");

  const sorted = useMemo(() => {
    const self = balances.filter((b) => b.person.is_self);
    const rest = balances.filter((b) => !b.person.is_self);

    rest.sort((a, b) => {
      if (sortMode === "balance") return b.totalRemaining - a.totalRemaining;
      if (sortMode === "first") {
        return (a.person.first_name || a.person.name).localeCompare(b.person.first_name || b.person.name);
      }
      // last name — people with no last name sort to the end
      const aLast = a.person.last_name || "";
      const bLast = b.person.last_name || "";
      if (!aLast && !bLast) return (a.person.first_name || a.person.name).localeCompare(b.person.first_name || b.person.name);
      if (!aLast) return 1;
      if (!bLast) return -1;
      return aLast.localeCompare(bLast);
    });

    return [...self, ...rest];
  }, [balances, sortMode]);

  return (
    <div>
      {balances.length > 1 && (
        <div className="flex gap-1.5 mb-3">
          {([
            ["balance", "Balance"],
            ["first", "First name"],
            ["last", "Last name"],
          ] as [SortMode, string][]).map(([mode, label]) => (
            <button
              key={mode}
              onClick={() => setSortMode(mode)}
              className={`px-3 py-1.5 rounded-full text-[12px] font-medium border ${sortMode === mode ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}
            >
              {label}
            </button>
          ))}
        </div>
      )}

      <div className="space-y-2">
        {sorted.length === 0 && (
          <EmptyState icon={Users} title="No people yet" body="Add the people you usually split with above." />
        )}
        {sorted.map(({ person, totalRemaining }) => (
          <PersonRow key={person.id} person={person} totalRemaining={totalRemaining} />
        ))}
      </div>
    </div>
  );
}
