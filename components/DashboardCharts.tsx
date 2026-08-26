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
