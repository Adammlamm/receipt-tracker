#!/bin/bash
set -e
echo "Applying: Dashboard (charts) as the new Home tab..."

mkdir -p $(dirname 'package.json')
cat > 'package.json' << 'FILEEOF'
{
  "name": "receipt-tracker",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "@supabase/ssr": "^0.5.2",
    "@supabase/supabase-js": "^2.45.4",
    "lucide-react": "^0.383.0",
    "next": "14.2.5",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "recharts": "^2.15.4"
  },
  "devDependencies": {
    "@types/node": "^20.14.2",
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "autoprefixer": "^10.4.19",
    "postcss": "^8.4.38",
    "tailwindcss": "^3.4.4",
    "typescript": "^5.5.2"
  }
}
FILEEOF

mkdir -p $(dirname 'components/DashboardCharts.tsx')
cat > 'components/DashboardCharts.tsx' << 'FILEEOF'
"use client";

import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, CartesianGrid } from "recharts";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

const PIE_COLORS = ["#1F7A5C", "#C1443A", "#D4A24C", "#5B7DB1", "#8A6BAF", "#A29C8B"];

export function OwedBarChart({ data }: { data: { name: string; amount: number }[] }) {
  if (data.length === 0) {
    return <p className="text-[13px] text-muted py-6 text-center">Everyone's settled up — nothing outstanding.</p>;
  }
  return (
    <ResponsiveContainer width="100%" height={Math.max(140, data.length * 44)}>
      <BarChart data={data} layout="vertical" margin={{ top: 0, right: 24, left: 0, bottom: 0 }}>
        <XAxis type="number" hide />
        <YAxis type="category" dataKey="name" width={70} tick={{ fontSize: 12, fill: "#5B5748" }} axisLine={false} tickLine={false} />
        <Tooltip formatter={(v: number) => money(v)} contentStyle={{ fontSize: 12, borderRadius: 8, border: "1px solid #E7E3D8" }} />
        <Bar dataKey="amount" fill="#C1443A" radius={[0, 6, 6, 0]} barSize={22} />
      </BarChart>
    </ResponsiveContainer>
  );
}

export function CategoryPieChart({ data }: { data: { name: string; value: number }[] }) {
  if (data.length === 0) {
    return <p className="text-[13px] text-muted py-6 text-center">No receipts yet.</p>;
  }
  return (
    <div>
      <ResponsiveContainer width="100%" height={200}>
        <PieChart>
          <Pie data={data} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={45} outerRadius={75} paddingAngle={2}>
            {data.map((_, i) => (
              <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
            ))}
          </Pie>
          <Tooltip formatter={(v: number) => money(v)} contentStyle={{ fontSize: 12, borderRadius: 8, border: "1px solid #E7E3D8" }} />
        </PieChart>
      </ResponsiveContainer>
      <div className="flex flex-wrap gap-x-4 gap-y-1.5 justify-center mt-2">
        {data.map((d, i) => (
          <div key={d.name} className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full" style={{ background: PIE_COLORS[i % PIE_COLORS.length] }} />
            <span className="text-[11px] text-muted">{d.name}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export function MonthlyTrendChart({ data }: { data: { month: string; total: number }[] }) {
  if (data.length === 0) {
    return <p className="text-[13px] text-muted py-6 text-center">No receipts yet.</p>;
  }
  return (
    <ResponsiveContainer width="100%" height={180}>
      <BarChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#EDE9DC" vertical={false} />
        <XAxis dataKey="month" tick={{ fontSize: 11, fill: "#8A8578" }} axisLine={false} tickLine={false} />
        <YAxis hide />
        <Tooltip formatter={(v: number) => money(v)} contentStyle={{ fontSize: 12, borderRadius: 8, border: "1px solid #E7E3D8" }} />
        <Bar dataKey="total" fill="#1F7A5C" radius={[6, 6, 0, 0]} barSize={22} />
      </BarChart>
    </ResponsiveContainer>
  );
}
FILEEOF

mkdir -p $(dirname 'app/page.tsx')
cat > 'app/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { Receipt as ReceiptIcon, ChevronRight } from "lucide-react";
import { loadPeople, loadReceipts, loadPayments } from "@/lib/data";
import { allocatePersonPayments } from "@/lib/split";
import BottomNav from "@/components/BottomNav";
import { OwedBarChart, CategoryPieChart, MonthlyTrendChart } from "@/components/DashboardCharts";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}
function fmtDate(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export default async function HomePage() {
  const [people, receipts, payments] = await Promise.all([loadPeople(), loadReceipts(), loadPayments()]);

  const balances = people
    .filter((p) => !p.is_self)
    .map((p) => ({ person: p, ...allocatePersonPayments(p.id, receipts, payments) }));
  const totalOutstanding = balances.reduce((s, b) => s + b.totalRemaining, 0);
  const peopleOwing = balances.filter((b) => b.totalRemaining > 0.005).length;

  const owedData = balances
    .filter((b) => b.totalRemaining > 0.005)
    .sort((a, b) => b.totalRemaining - a.totalRemaining)
    .map((b) => ({ name: b.person.name, amount: b.totalRemaining }));

  const categoryTotals: Record<string, number> = {};
  for (const r of receipts) {
    const cat = r.category || "Uncategorized";
    categoryTotals[cat] = (categoryTotals[cat] || 0) + r.total;
  }
  const categoryData = Object.entries(categoryTotals)
    .map(([name, value]) => ({ name, value }))
    .sort((a, b) => b.value - a.value);

  const monthMap: Record<string, { label: string; total: number }> = {};
  for (const r of receipts) {
    const d = new Date(r.date + "T00:00:00");
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    const label = d.toLocaleDateString("en-US", { month: "short" });
    if (!monthMap[key]) monthMap[key] = { label, total: 0 };
    monthMap[key].total += r.total;
  }
  const monthlyData = Object.entries(monthMap)
    .sort(([a], [b]) => a.localeCompare(b))
    .slice(-6)
    .map(([, v]) => ({ month: v.label, total: v.total }));

  const totalFronted = receipts.reduce((s, r) => s + r.total, 0);

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
        <h2 className="text-[13px] font-semibold text-ink mb-2">Who owes you</h2>
        <div className="bg-white rounded-xl border border-line p-3">
          <OwedBarChart data={owedData} />
        </div>
      </div>

      <div className="px-5 mt-7">
        <h2 className="text-[13px] font-semibold text-ink mb-1">Spending patterns</h2>
        <p className="text-[12px] text-muted mb-3">
          You've fronted {money(totalFronted)} across {receipts.length} receipt{receipts.length === 1 ? "" : "s"}.
        </p>
        <div className="space-y-3">
          <div className="bg-white rounded-xl border border-line p-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1 px-1">By category</p>
            <CategoryPieChart data={categoryData} />
          </div>
          <div className="bg-white rounded-xl border border-line p-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1 px-1">By month</p>
            <MonthlyTrendChart data={monthlyData} />
          </div>
        </div>
      </div>

      <div className="px-5 mt-7">
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
FILEEOF

echo "Files updated. Installing new dependency (recharts)..."
npm install
echo "Done. Now run: git add . && git commit -m \"Add dashboard with charts as new Home tab\" && git push"
