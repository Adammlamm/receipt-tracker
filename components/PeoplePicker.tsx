"use client";

import { useState } from "react";
import { X, Search, Check } from "lucide-react";
import { Person, Group } from "@/lib/types";

export default function PeoplePicker({
  isOpen,
  onClose,
  people,
  groups,
  selectedIds,
  onToggle,
  onSetAll,
  title = "Who shared this?",
}: {
  isOpen: boolean;
  onClose: () => void;
  people: Person[];
  groups: Group[];
  selectedIds: string[];
  onToggle: (personId: string) => void;
  onSetAll: (ids: string[]) => void;
  title?: string;
}) {
  const [query, setQuery] = useState("");
  if (!isOpen) return null;

  const filtered = people.filter((p) => p.name.toLowerCase().includes(query.toLowerCase()));

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center">
      <div className="absolute inset-0 bg-black/30" onClick={onClose} />
      <div className="relative w-full max-w-md bg-paper rounded-t-2xl max-h-[85vh] flex flex-col">
        <div className="flex items-center justify-between px-5 py-4 border-b border-line shrink-0">
          <h2 className="text-[15px] font-semibold text-ink">{title}</h2>
          <button onClick={onClose} className="p-1">
            <X size={18} className="text-muted" />
          </button>
        </div>

        <div className="px-5 pt-3 shrink-0">
          <div className="relative mb-3">
            <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search people…"
              className="w-full rounded-xl border border-line bg-white pl-9 pr-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40"
            />
          </div>

          <div className="flex flex-wrap gap-1.5 mb-3">
            <button onClick={() => onSetAll([])} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-owe border-line">
              Unselect all
            </button>
            {people.some((p) => p.is_self) && (
              <button
                onClick={() => onSetAll([people.find((p) => p.is_self)!.id])}
                className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line"
              >
                Just me
              </button>
            )}
            <button onClick={() => onSetAll(people.map((p) => p.id))} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
              Everyone
            </button>
            {groups.map((g) => (
              <button key={g.id} onClick={() => onSetAll(g.memberIds)} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-[#F0EDE1] text-[#5B5748] border-line">
                {g.name}
              </button>
            ))}
          </div>
        </div>

        <div className="flex-1 overflow-y-auto px-5 pb-3">
          {filtered.length === 0 && <p className="text-[13px] text-muted text-center py-6">No matches.</p>}
          <div className="space-y-1">
            {filtered.map((p) => {
              const checked = selectedIds.includes(p.id);
              return (
                <button key={p.id} onClick={() => onToggle(p.id)} className="w-full flex items-center justify-between px-3 py-3 rounded-xl active:bg-white">
                  <span className="text-[14px] text-ink flex items-center gap-1.5">
                    {p.name}
                    {p.is_self && <span className="text-[10px] font-semibold text-accent bg-[#EFF7F3] px-1.5 py-0.5 rounded-full">YOU</span>}
                  </span>
                  <div className={`w-5 h-5 rounded-full border flex items-center justify-center shrink-0 ${checked ? "bg-accent border-accent" : "border-line bg-white"}`}>
                    {checked && <Check size={13} className="text-white" />}
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        <div className="px-5 py-4 border-t border-line shrink-0" style={{ paddingBottom: "max(1rem, env(safe-area-inset-bottom))" }}>
          <button onClick={onClose} className="w-full rounded-xl bg-accent text-white font-semibold py-3 text-[14px]">
            Done{selectedIds.length > 0 ? ` (${selectedIds.length} selected)` : ""}
          </button>
        </div>
      </div>
    </div>
  );
}
