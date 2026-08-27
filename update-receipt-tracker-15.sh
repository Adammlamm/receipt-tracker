#!/bin/bash
set -e
echo "Applying: app icon (checkmark), loading skeletons, transitions, polished empty states..."
mkdir -p public/icons "app/receipts/[id]" "app/people/[id]"

mkdir -p $(dirname 'public/icons/icon-512.png')
base64 -d > 'public/icons/icon-512.png' << 'B64EOF'
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
B64EOF

mkdir -p $(dirname 'public/icons/icon-192.png')
base64 -d > 'public/icons/icon-192.png' << 'B64EOF'
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
B64EOF

mkdir -p $(dirname 'public/icons/apple-touch-icon.png')
base64 -d > 'public/icons/apple-touch-icon.png' << 'B64EOF'
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
B64EOF

mkdir -p $(dirname 'public/favicon.png')
base64 -d > 'public/favicon.png' << 'B64EOF'
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAAsTAAALEwEAmpwYAAAB1ElEQVRYhWOQr4r5P5CYYdQB8qNRUDWaCGMIZhXXCWX/mzcv+t+2dQkYL1gz7/+6KR1w+cnz+v8vWDv/f/8miBqQWpf+UupkQ8OWjP/vPr39/+vnNxT87fvn/9Xr54AxiI0u/+nDm/9JxbH/jUvCKXNAyMwmDMOJxecLMv4fdLH63x3mRr4DwmY2k+2AC4WZYAeAMK6QYKCHA/a7WP9XL48eOAes8LGnfRQ8fPUEnPJXntyD4YCOcBqngZfvX/936iv9r1wT///AjbMYDshM9KGeA758/YTC//jlw/+A6XX/Fapj/y8/sRtrFHjlBFPHAU/ePv+vUZ/0v3P7cnhZkDC/E1IY7V2LNQ0ccLH6r10WRR0HfPv2+X/U7FawePu2pf8LV00Ds+s3zseZCNd421FWEIWhRcGnLx/+R0IdAcJZyyb+//HjK04H9Ia6UtcBv6COSFzQ9T9pYff/r99Q0wS6A/ISvKnvgF8klAN+2UED6wD90siBc8CR0hy8ZhPlAEpqw9U1+bRrD/wigL+/f/2/MC+ScgfIV8X8d+4v+9+9Y8X/yfvW4cTT9q79v3jH6v+btiz/v2v53P+NVRn/FYkwm4EYB9ASM4w6QH40CqoGNhECAH6yp9jIp+wmAAAAAElFTkSuQmCC
B64EOF

mkdir -p $(dirname 'app/layout.tsx')
cat > 'app/layout.tsx' << 'FILEEOF'
import type { Metadata, Viewport } from "next";
import "./globals.css";
import PageTransition from "@/components/PageTransition";

export const metadata: Metadata = {
  title: "Receipt Tracker",
  description: "Split receipts and track who owes you.",
  manifest: "/manifest.json",
  icons: {
    icon: "/favicon.png",
    apple: "/icons/apple-touch-icon.png",
  },
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "Receipts",
  },
  openGraph: {
    title: "Receipt Tracker",
    description: "Split receipts and track who owes you.",
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#1F7A5C",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="font-sans text-ink">
        <div className="max-w-md mx-auto min-h-screen pb-24 relative">
          <PageTransition>{children}</PageTransition>
        </div>
      </body>
    </html>
  );
}
FILEEOF

mkdir -p $(dirname 'app/globals.css')
cat > 'app/globals.css' << 'FILEEOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

html, body {
  background: #FAF9F6;
}

.dotted-row {
  border-bottom: 1px dotted #D8D3C4;
}

@keyframes page-in {
  from {
    opacity: 0;
    transform: translateY(6px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.animate-page-in {
  animation: page-in 220ms ease-out;
}

/* Subtle press feedback so taps feel responsive rather than static */
button:active {
  transform: scale(0.98);
}
FILEEOF

mkdir -p $(dirname 'components/PageTransition.tsx')
cat > 'components/PageTransition.tsx' << 'FILEEOF'
"use client";

import { usePathname } from "next/navigation";

export default function PageTransition({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  return (
    <div key={pathname} className="animate-page-in">
      {children}
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'components/Skeleton.tsx')
cat > 'components/Skeleton.tsx' << 'FILEEOF'
export default function Skeleton({ className = "" }: { className?: string }) {
  return <div className={`animate-pulse bg-[#EFEBDD] rounded-lg ${className}`} />;
}
FILEEOF

mkdir -p $(dirname 'components/EmptyState.tsx')
cat > 'components/EmptyState.tsx' << 'FILEEOF'
import { LucideIcon } from "lucide-react";

export default function EmptyState({
  icon: Icon,
  title,
  body,
}: {
  icon: LucideIcon;
  title: string;
  body?: string;
}) {
  return (
    <div className="bg-white rounded-2xl border border-dashed border-line px-5 py-10 text-center">
      <div className="w-11 h-11 rounded-full bg-[#F0EDE1] flex items-center justify-center mx-auto mb-3">
        <Icon size={20} className="text-muted" />
      </div>
      <p className="text-[14px] font-semibold text-ink">{title}</p>
      {body && <p className="text-[13px] text-muted mt-1">{body}</p>}
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/loading.tsx')
cat > 'app/loading.tsx' << 'FILEEOF'
import Skeleton from "@/components/Skeleton";

export default function Loading() {
  return (
    <div>
      <div className="px-5 pt-6 pb-2">
        <Skeleton className="h-3 w-24 mb-2" />
        <Skeleton className="h-10 w-40 mb-2" />
        <Skeleton className="h-3 w-32" />
      </div>
      <div className="px-5 mt-6">
        <Skeleton className="h-3 w-20 mb-2" />
        <Skeleton className="h-32 w-full rounded-xl" />
      </div>
      <div className="px-5 mt-7 space-y-3">
        <Skeleton className="h-3 w-28 mb-1" />
        <Skeleton className="h-40 w-full rounded-xl" />
        <Skeleton className="h-32 w-full rounded-xl" />
      </div>
      <div className="px-5 mt-7 space-y-2">
        <Skeleton className="h-3 w-32 mb-2" />
        <Skeleton className="h-16 w-full rounded-xl" />
        <Skeleton className="h-16 w-full rounded-xl" />
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/receipts/loading.tsx')
cat > 'app/receipts/loading.tsx' << 'FILEEOF'
import Skeleton from "@/components/Skeleton";

export default function Loading() {
  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Skeleton className="h-4 w-24" />
      </div>
      <div className="px-5 pt-4 space-y-2">
        {[0, 1, 2, 3].map((i) => (
          <Skeleton key={i} className="h-16 w-full rounded-xl" />
        ))}
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/people/loading.tsx')
cat > 'app/people/loading.tsx' << 'FILEEOF'
import Skeleton from "@/components/Skeleton";

export default function Loading() {
  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Skeleton className="h-4 w-20" />
      </div>
      <div className="px-5 pt-4">
        <Skeleton className="h-12 w-full rounded-xl mb-4" />
        <div className="space-y-2">
          {[0, 1, 2, 3, 4].map((i) => (
            <Skeleton key={i} className="h-16 w-full rounded-xl" />
          ))}
        </div>
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/payments/loading.tsx')
cat > 'app/payments/loading.tsx' << 'FILEEOF'
import Skeleton from "@/components/Skeleton";

export default function Loading() {
  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Skeleton className="h-4 w-24" />
      </div>
      <div className="px-5 pt-4 space-y-2">
        {[0, 1, 2, 3].map((i) => (
          <Skeleton key={i} className="h-16 w-full rounded-xl" />
        ))}
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/receipts/[id]/loading.tsx')
cat > 'app/receipts/[id]/loading.tsx' << 'FILEEOF'
import Skeleton from "@/components/Skeleton";

export default function Loading() {
  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Skeleton className="h-4 w-16" />
      </div>
      <div className="px-5 pt-4">
        <Skeleton className="h-48 w-full rounded-xl mb-4" />
        <Skeleton className="h-3 w-20 mb-4" />
        <Skeleton className="h-56 w-full rounded-xl mb-5" />
        <Skeleton className="h-3 w-28 mb-2" />
        <div className="space-y-2">
          <Skeleton className="h-14 w-full rounded-xl" />
          <Skeleton className="h-14 w-full rounded-xl" />
        </div>
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/people/[id]/loading.tsx')
cat > 'app/people/[id]/loading.tsx' << 'FILEEOF'
import Skeleton from "@/components/Skeleton";

export default function Loading() {
  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Skeleton className="h-4 w-16" />
      </div>
      <div className="px-5 pt-5">
        <Skeleton className="h-3 w-28 mb-2" />
        <Skeleton className="h-8 w-32 mb-6" />
        <Skeleton className="h-12 w-full rounded-xl mb-7" />
        <Skeleton className="h-3 w-20 mb-2" />
        <div className="space-y-2">
          <Skeleton className="h-14 w-full rounded-xl" />
          <Skeleton className="h-14 w-full rounded-xl" />
        </div>
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/receipts/page.tsx')
cat > 'app/receipts/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { Receipt as ReceiptIcon, ChevronRight } from "lucide-react";
import { loadReceipts } from "@/lib/data";
import BottomNav from "@/components/BottomNav";
import EmptyState from "@/components/EmptyState";

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
        {receipts.length === 0 && (
          <EmptyState icon={ReceiptIcon} title="No receipts yet" body="Tap Add Receipt to get started." />
        )}
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
FILEEOF

mkdir -p $(dirname 'app/payments/page.tsx')
cat > 'app/payments/page.tsx' << 'FILEEOF'
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
FILEEOF

mkdir -p $(dirname 'app/people/page.tsx')
cat > 'app/people/page.tsx' << 'FILEEOF'
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
FILEEOF

mkdir -p $(dirname 'app/groups/GroupsManager.tsx')
cat > 'app/groups/GroupsManager.tsx' << 'FILEEOF'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Plus, X, Pencil, Trash2, Users2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Person, Group } from "@/lib/types";
import EmptyState from "@/components/EmptyState";

export default function GroupsManager({ people, initialGroups }: { people: Person[]; initialGroups: Group[] }) {
  const [groups, setGroups] = useState(initialGroups);
  const [creating, setCreating] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [memberIds, setMemberIds] = useState<string[]>([]);
  const router = useRouter();
  const supabase = createClient();

  function startCreate() {
    setCreating(true);
    setEditingId(null);
    setName("");
    setMemberIds([]);
  }

  function startEdit(g: Group) {
    setEditingId(g.id);
    setCreating(false);
    setName(g.name);
    setMemberIds(g.memberIds);
  }

  function toggleMember(id: string) {
    setMemberIds((cur) => (cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id]));
  }

  async function save() {
    if (!name.trim()) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;

    if (editingId) {
      await supabase.from("groups").update({ name: name.trim() }).eq("id", editingId);
      await supabase.from("group_members").delete().eq("group_id", editingId);
      if (memberIds.length) {
        await supabase.from("group_members").insert(memberIds.map((person_id) => ({ group_id: editingId, person_id })));
      }
    } else {
      const { data: group } = await supabase.from("groups").insert({ user_id: user.id, name: name.trim() }).select().single();
      if (group && memberIds.length) {
        await supabase.from("group_members").insert(memberIds.map((person_id) => ({ group_id: group.id, person_id })));
      }
    }

    setCreating(false);
    setEditingId(null);
    router.refresh();
    const { data: freshGroups } = await supabase.from("groups").select("*").order("name");
    const { data: freshMembers } = await supabase.from("group_members").select("*");
    setGroups(
      (freshGroups ?? []).map((g) => ({
        ...g,
        memberIds: (freshMembers ?? []).filter((m) => m.group_id === g.id).map((m) => m.person_id),
      }))
    );
  }

  async function remove(id: string) {
    if (!confirm("Delete this group?")) return;
    await supabase.from("groups").delete().eq("id", id);
    setGroups(groups.filter((g) => g.id !== id));
  }

  const editorOpen = creating || editingId !== null;

  return (
    <div>
      {!editorOpen && (
        <button
          onClick={startCreate}
          className="w-full rounded-xl border-2 border-dashed border-line py-3 flex items-center justify-center gap-1.5 text-[13px] font-semibold text-accent mb-4"
        >
          <Plus size={16} /> New group
        </button>
      )}

      {editorOpen && (
        <div className="bg-white rounded-xl border border-line p-3.5 mb-4">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Group name, e.g. Drinkers"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-3"
          />
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Members</p>
          <div className="flex flex-wrap gap-1.5 mb-3">
            {people.map((p) => (
              <button
                key={p.id}
                onClick={() => toggleMember(p.id)}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
                  memberIds.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
                }`}
              >
                {p.name}
              </button>
            ))}
            {people.length === 0 && <p className="text-[13px] text-muted">Add people first, from the People tab.</p>}
          </div>
          <div className="flex gap-2">
            <button onClick={save} className="flex-1 rounded-xl bg-accent text-white font-semibold py-2.5 text-[14px]">
              Save group
            </button>
            <button
              onClick={() => {
                setCreating(false);
                setEditingId(null);
              }}
              className="px-4 rounded-xl bg-[#F0EDE1] text-[#5B5748] font-semibold py-2.5 text-[14px]"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      <div className="space-y-2">
        {groups.map((g) => (
          <div key={g.id} className="bg-white rounded-xl border border-line px-4 py-3 flex items-center gap-3">
            <div className="flex-1 min-w-0">
              <p className="text-[14px] font-medium text-ink">{g.name}</p>
              <p className="text-[12px] text-muted truncate">
                {g.memberIds.map((id) => people.find((p) => p.id === id)?.name).filter(Boolean).join(", ") || "No members"}
              </p>
            </div>
            <button onClick={() => startEdit(g)} className="p-2 rounded-full active:bg-[#F5F3EC]">
              <Pencil size={15} className="text-muted" />
            </button>
            <button onClick={() => remove(g.id)} className="p-2 rounded-full active:bg-[#FBEDEA]">
              <Trash2 size={15} className="text-owe" />
            </button>
          </div>
        ))}
        {groups.length === 0 && !editorOpen && (
          <EmptyState icon={Users2} title="No groups yet" body="Create one for a table, a trip, or your regular crew." />
        )}
      </div>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/receipts/new/page.tsx')
cat > 'app/receipts/new/page.tsx' << 'FILEEOF'
"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Camera, Plus, Trash2, X, Sparkles, Loader2, CheckCircle2, AlertTriangle, FileText } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { computeReceiptShares } from "@/lib/split";
import { Category, Person, Group, TaxTipMethod, ReceiptCategory } from "@/lib/types";

const CATEGORIES: Category[] = ["Food", "Drinks", "Other"];
const RECEIPT_CATEGORIES: ReceiptCategory[] = ["Dining", "Trips", "Roommates/Home", "Transportation", "Other"];
const DRAFT_KEY = "receipt-draft-v1";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

function compressImage(file: File, maxW = 1200, quality = 0.78): Promise<{ blob: Blob; dataUrl: string }> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("read failed"));
    reader.onload = () => {
      const img = new Image();
      img.onload = () => {
        const scale = Math.min(1, maxW / img.width);
        const w = Math.round(img.width * scale);
        const h = Math.round(img.height * scale);
        const canvas = document.createElement("canvas");
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext("2d")!;
        ctx.drawImage(img, 0, 0, w, h);
        const dataUrl = canvas.toDataURL("image/jpeg", quality);
        canvas.toBlob(
          (blob) => (blob ? resolve({ blob, dataUrl }) : reject(new Error("toBlob failed"))),
          "image/jpeg",
          quality
        );
      };
      img.onerror = () => reject(new Error("decode failed"));
      img.src = reader.result as string;
    };
    reader.readAsDataURL(file);
  });
}

/** PDFs can't go through canvas compression — just read them as-is. */
function readFileAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("read failed"));
    reader.onload = () => resolve(reader.result as string);
    reader.readAsDataURL(file);
  });
}

interface DraftItem {
  id: string;
  name: string;
  price: string;
  discount: string;
  quantity: number;
  category: Category;
  personIds: string[];
  personUnits: Record<string, number>;
  splitType: "even" | "shares" | "exact" | "percent";
}

type Phase = "capture" | "basics" | "participants" | "items" | "review";

export default function AddReceiptPage() {
  const router = useRouter();
  const supabase = createClient();

  const [phase, setPhase] = useState<Phase>("capture");
  const [people, setPeople] = useState<Person[]>([]);
  const [groups, setGroups] = useState<Group[]>([]);
  const [merchant, setMerchant] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [subtotal, setSubtotal] = useState("");
  const [tax, setTax] = useState("");
  const [tip, setTip] = useState("");
  const [discount, setDiscount] = useState("");
  const [total, setTotal] = useState("");
  const [selectedTipPct, setSelectedTipPct] = useState<number | null>(null);
  const [receiptCategory, setReceiptCategory] = useState<ReceiptCategory | null>(null);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [isPdf, setIsPdf] = useState(false);
  const [items, setItems] = useState<DraftItem[]>([]);
  const [taxTipMethod, setTaxTipMethod] = useState<TaxTipMethod>("proportional");
  const [splitMode, setSplitMode] = useState<"itemized" | "even">("itemized");
  const [evenParticipants, setEvenParticipants] = useState<string[]>([]);
  const [newPersonName, setNewPersonName] = useState("");
  const [saving, setSaving] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    supabase.from("people").select("*").order("name").then(({ data }) => setPeople(data ?? []));
    (async () => {
      const { data: g } = await supabase.from("groups").select("*").order("name");
      const { data: m } = await supabase.from("group_members").select("*");
      setGroups(
        (g ?? []).map((grp) => ({ ...grp, memberIds: (m ?? []).filter((x) => x.group_id === grp.id).map((x) => x.person_id) }))
      );
    })();
  }, []);

  // Draft protection: if a receipt was left unfinished (dropped connection, backgrounded app),
  // offer to resume it. Images aren't restorable this way, only the entered numbers/items.
  useEffect(() => {
    try {
      const saved = localStorage.getItem(DRAFT_KEY);
      if (!saved) return;
      const draft = JSON.parse(saved);
      const hasContent = draft.merchant || (draft.items && draft.items.length > 0) || Number(draft.subtotal) > 0;
      if (!hasContent) {
        localStorage.removeItem(DRAFT_KEY);
        return;
      }
      if (confirm("You have an unfinished receipt from earlier — resume where you left off?")) {
        if (draft.phase && draft.phase !== "capture") setPhase(draft.phase);
        setMerchant(draft.merchant ?? "");
        setDate(draft.date ?? new Date().toISOString().slice(0, 10));
        setSubtotal(draft.subtotal ?? "");
        setTax(draft.tax ?? "");
        setTip(draft.tip ?? "");
        setDiscount(draft.discount ?? "");
        setTotal(draft.total ?? "");
        setReceiptCategory(draft.receiptCategory ?? null);
        setItems(draft.items ?? []);
        setTaxTipMethod(draft.taxTipMethod ?? "proportional");
        setSplitMode(draft.splitMode ?? "itemized");
        setEvenParticipants(draft.evenParticipants ?? []);
      } else {
        localStorage.removeItem(DRAFT_KEY);
      }
    } catch (e) {
      console.error("draft resume failed", e);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Autosave the draft as it changes (image/file state intentionally excluded — not restorable).
  useEffect(() => {
    try {
      const hasContent = merchant || items.length > 0 || Number(subtotal) > 0;
      if (!hasContent) return;
      const draft = { phase, merchant, date, subtotal, tax, tip, discount, total, receiptCategory, items, taxTipMethod, splitMode, evenParticipants };
      localStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
    } catch (e) {
      // storage unavailable/full — draft protection just won't work this session, not fatal
    }
  }, [phase, merchant, date, subtotal, tax, tip, discount, total, receiptCategory, items, taxTipMethod, splitMode, evenParticipants]);

  const itemsSum = items.reduce((s, it) => s + Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0)), 0);

  async function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 8 * 1024 * 1024) {
      setScanError("That file is too large (max 8MB) — try a smaller photo or a lighter PDF, or enter it manually.");
      return;
    }
    setImageFile(file);
    setScanError(null);
    const fileIsPdf = file.type === "application/pdf";
    setIsPdf(fileIsPdf);

    try {
      let dataUrl: string;
      if (fileIsPdf) {
        dataUrl = await readFileAsDataUrl(file);
        setImagePreview(null); // no visual preview for PDFs, we show a file chip instead
      } else {
        const compressed = await compressImage(file);
        dataUrl = compressed.dataUrl;
        setImagePreview(dataUrl);
      }
      setScanning(true);
      const base64 = dataUrl.split(",")[1];
      const res = await fetch("/api/scan-receipt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ imageBase64: base64, mediaType: fileIsPdf ? "application/pdf" : "image/jpeg" }),
      });
      const parsed = await res.json();
      if (!res.ok) {
        setScanError(parsed.error || "Couldn't read this receipt automatically — enter it manually below.");
      } else {
        setMerchant(parsed.merchant || "");
        if (parsed.date) setDate(parsed.date);
        if (parsed.subtotal != null) setSubtotal(String(parsed.subtotal));
        if (parsed.tax != null) setTax(String(parsed.tax));
        if (parsed.tip != null) setTip(String(parsed.tip));
        if (parsed.discount != null) setDiscount(String(parsed.discount));
        if (parsed.total != null) setTotal(String(parsed.total));
        if (Array.isArray(parsed.items)) {
          setItems(
            parsed.items.map((it: any) => ({
              id: crypto.randomUUID(),
              name: it.quantity && it.quantity > 1 ? `${it.quantity} × ${it.name}` : it.name,
              price: String((Number(it.unit_price) || 0) * (Number(it.quantity) || 1)),
              discount: "",
              quantity: Number(it.quantity) || 1,
              category: (["Food", "Drinks", "Other"].includes(it.category) ? it.category : "Food") as Category,
              personIds: [],
              personUnits: {},
              splitType: "even" as const,
            }))
          );
        }
      }
    } catch (err) {
      console.error(err);
      setScanError("Couldn't read this receipt automatically — enter it manually below.");
    } finally {
      setScanning(false);
    }
  }

  function addItem() {
    setItems([...items, { id: crypto.randomUUID(), name: "", price: "", discount: "", quantity: 1, category: "Food", personIds: [], personUnits: {}, splitType: "even" }]);
  }
  function updateItem(id: string, patch: Partial<DraftItem>) {
    setItems(items.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  }
  function removeItem(id: string) {
    setItems(items.filter((it) => it.id !== id));
  }
  function togglePerson(itemId: string, personId: string) {
    setItems(
      items.map((it) => {
        if (it.id !== itemId) return it;
        const has = it.personIds.includes(personId);
        return { ...it, personIds: has ? it.personIds.filter((id) => id !== personId) : [...it.personIds, personId] };
      })
    );
  }
  function setItemPeople(itemId: string, ids: string[]) {
    setItems(items.map((it) => (it.id === itemId ? { ...it, personIds: ids } : it)));
  }
  function setSplitType(itemId: string, type: DraftItem["splitType"]) {
    setItems(
      items.map((it) => {
        if (it.id !== itemId) return it;
        const count = it.personIds.length || 1;
        const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
        let personUnits: Record<string, number> = {};
        if (type === "shares") personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, 1]));
        else if (type === "exact") {
          const each = Math.round((effectivePrice / count) * 100) / 100;
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, each]));
        } else if (type === "percent") {
          const each = Math.round((100 / count) * 100) / 100;
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, each]));
        }
        return { ...it, splitType: type, personUnits };
      })
    );
  }
  function setWeight(itemId: string, personId: string, value: number) {
    setItems(
      items.map((it) => (it.id === itemId ? { ...it, personUnits: { ...it.personUnits, [personId]: Math.max(0, value) } } : it))
    );
  }
  function assignCategoryToEveryone(category: Category) {
    const everyone = people.map((p) => p.id);
    setItems(items.map((it) => (it.category === category ? { ...it, personIds: everyone } : it)));
  }
  function assignCategoryToGroup(category: Category, group: Group) {
    setItems(items.map((it) => (it.category === category ? { ...it, personIds: group.memberIds } : it)));
  }

  async function addPerson() {
    if (!newPersonName.trim()) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    const { data } = await supabase.from("people").insert({ user_id: user.id, name: newPersonName.trim() }).select().single();
    if (data) setPeople([...people, data]);
    setNewPersonName("");
  }

  const validItems =
    splitMode === "even"
      ? [
          {
            id: "even-split",
            name: "Whole bill",
            price:
              Number(total) ||
              (Number(subtotal) || 0) + (Number(tax) || 0) + (Number(tip) || 0) - (Number(discount) || 0),
            discount: 0,
            quantity: 1,
            category: "Other" as Category,
            personIds: evenParticipants,
            personUnits: {} as Record<string, number>,
            splitType: "even" as const,
          },
        ]
      : items
          .filter((it) => it.name.trim() && Number(it.price) > 0)
          .map((it) => ({ ...it, price: Number(it.price), discount: Number(it.discount) || 0 }));

  const draftReceipt = {
    merchant: merchant.trim() || "Untitled receipt",
    date,
    subtotal: Number(subtotal) || itemsSum,
    tax: Number(tax) || 0,
    tip: Number(tip) || 0,
    discount: Number(discount) || 0,
    total: Number(total) || (Number(subtotal) || itemsSum) + (Number(tax) || 0) + (Number(tip) || 0) - (Number(discount) || 0),
    items: validItems,
    tax_tip_method: taxTipMethod,
    split_mode: splitMode,
  };
  const shares = computeReceiptShares(draftReceipt as any);

  // Reconciliation
  const calculatedTotal =
    draftReceipt.subtotal + draftReceipt.tax + draftReceipt.tip - draftReceipt.discount;
  const totalDifference = Math.round((draftReceipt.total - calculatedTotal) * 100) / 100;
  const assignedTotal = Object.values(shares).reduce((s: number, sh: any) => s + sh.total, 0);
  const unassigned = Math.round((draftReceipt.total - assignedTotal) * 100) / 100;
  const unassignedItems = splitMode === "itemized" ? validItems.filter((it) => it.personIds.length === 0) : [];

  async function save() {
    setSaving(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;

    const { data: possibleDupes } = await supabase
      .from("receipts")
      .select("merchant, date, total")
      .eq("merchant", draftReceipt.merchant)
      .eq("date", draftReceipt.date);
    const dupe = (possibleDupes ?? []).find((d) => Math.abs(d.total - draftReceipt.total) < 0.01);
    if (dupe) {
      const proceed = confirm(
        `This looks like it might already be saved — ${dupe.merchant} on ${dupe.date} for ${money(dupe.total)}. Save it anyway?`
      );
      if (!proceed) {
        setSaving(false);
        return;
      }
    }

    const { data: receipt, error } = await supabase
      .from("receipts")
      .insert({
        user_id: user.id,
        merchant: draftReceipt.merchant,
        date: draftReceipt.date,
        subtotal: draftReceipt.subtotal,
        tax: draftReceipt.tax,
        tip: draftReceipt.tip,
        discount: draftReceipt.discount,
        total: draftReceipt.total,
        tax_tip_method: taxTipMethod,
        split_mode: splitMode,
        category: receiptCategory,
      })
      .select()
      .single();

    if (error || !receipt) {
      setSaving(false);
      return;
    }

    if (imageFile) {
      try {
        if (isPdf) {
          const path = `${user.id}/${receipt.id}.pdf`;
          await supabase.storage.from("receipts").upload(path, imageFile, { contentType: "application/pdf" });
          await supabase.from("receipts").update({ image_path: path, image_mime: "application/pdf" }).eq("id", receipt.id);
        } else {
          const { blob } = await compressImage(imageFile);
          const path = `${user.id}/${receipt.id}.jpg`;
          await supabase.storage.from("receipts").upload(path, blob, { contentType: "image/jpeg" });
          await supabase.from("receipts").update({ image_path: path, image_mime: "image/jpeg" }).eq("id", receipt.id);
        }
      } catch (e) {
        console.error("image upload failed", e);
      }
    }

    for (const item of validItems) {
      const { data: savedItem } = await supabase
        .from("receipt_items")
        .insert({
          receipt_id: receipt.id,
          name: item.name,
          price: Number(item.price),
          discount: Number(item.discount) || 0,
          category: item.category,
          quantity: item.quantity || 1,
        })
        .select()
        .single();
      if (savedItem && item.personIds.length) {
        await supabase.from("item_splits").insert(
          item.personIds.map((personId) => ({
            item_id: savedItem.id,
            person_id: personId,
            units: item.personUnits?.[personId] ?? 1,
          }))
        );
      }
    }

    try {
      localStorage.removeItem(DRAFT_KEY);
    } catch (e) {}
    router.push(`/receipts/${receipt.id}`);
    router.refresh();
  }

  function backFrom(p: Phase) {
    if (p === "basics") setPhase("capture");
    else if (p === "participants") setPhase("basics");
    else if (p === "items") setPhase("basics");
    else if (p === "review") setPhase(splitMode === "even" ? "participants" : "items");
  }

  const titles: Record<Phase, string> = {
    capture: "Scan Receipt",
    basics: "Receipt Details",
    participants: "Who's In?",
    items: "Items",
    review: "Review & Split",
  };

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <button onClick={() => (phase === "capture" ? router.push("/") : backFrom(phase))} className="text-[13px] text-muted">
          Back
        </button>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink">{titles[phase]}</h1>
        <button onClick={() => router.push("/")} className="p-1">
          <X size={18} className="text-muted" />
        </button>
      </div>

      {phase === "capture" && (
        <div className="px-5 pt-4 animate-page-in">
          <input ref={fileRef} type="file" accept="image/*,application/pdf" className="hidden" onChange={handleFile} />
          <button
            onClick={() => fileRef.current?.click()}
            disabled={scanning}
            className="w-full rounded-2xl border-2 border-dashed border-line bg-white flex flex-col items-center justify-center py-10 mb-4"
          >
            {isPdf && imageFile ? (
              <div className="flex flex-col items-center gap-2">
                <FileText size={28} className="text-accent" />
                <span className="text-[13px] font-medium text-ink">{imageFile.name}</span>
              </div>
            ) : imagePreview ? (
              <img src={imagePreview} alt="Receipt" className="max-h-56 rounded-lg object-contain" />
            ) : (
              <>
                <Camera size={28} className="text-accent mb-2" />
                <span className="text-[14px] font-medium text-ink">Take or upload a photo or PDF</span>
                <span className="text-[11px] text-muted mt-0.5">We'll read it automatically</span>
              </>
            )}
          </button>

          {scanning && (
            <div className="flex items-center justify-center gap-2 text-[13px] text-accent mb-4">
              <Loader2 size={16} className="animate-spin" />
              Reading your receipt…
            </div>
          )}

          {scanError && (
            <div className="rounded-xl bg-[#FBF3E6] border border-[#EEDDB8] px-4 py-3 text-[13px] text-[#7A5E24] mb-4">
              {scanError}
            </div>
          )}

          {!scanning && (merchant || items.length > 0) && (
            <div className="rounded-xl bg-[#EFF7F3] border border-[#CFE8DC] px-4 py-3 text-[13px] text-[#1F7A5C] mb-4 flex items-center gap-2">
              <Sparkles size={15} /> Scanned — review the details on the next screen.
            </div>
          )}

          <button
            onClick={() => setPhase("basics")}
            disabled={scanning}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-3 disabled:opacity-40"
          >
            {merchant || items.length > 0 ? "Continue" : "Enter manually instead"}
          </button>
        </div>
      )}

      {phase === "basics" && (
        <div className="px-5 pt-4 animate-page-in">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Merchant</p>
          <input value={merchant} onChange={(e) => setMerchant(e.target.value)} placeholder="e.g. King Pocha"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Date</p>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <div className="grid grid-cols-2 gap-2 mb-3">
            {[
              ["Subtotal", subtotal, setSubtotal],
              ["Tax", tax, setTax],
              ["Tip", tip, (v: string) => { setTip(v); setSelectedTipPct(null); }],
              ["Discount", discount, setDiscount],
            ].map(([label, val, setter]: any) => (
              <div key={label}>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">{label}</p>
                <input inputMode="decimal" value={val} onChange={(e) => setter(e.target.value)} placeholder="0.00"
                  className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40" />
              </div>
            ))}
          </div>

          {Number(subtotal) > 0 && (
            <div className="mb-4">
              <p className="text-[11px] text-muted mb-1.5">Tip wasn't printed on the receipt? Calculate it:</p>
              <div className="flex gap-1.5">
                {[15, 18, 20, 25].map((pct) => (
                  <button
                    key={pct}
                    onClick={() => {
                      const calcTip = Math.round(((Number(subtotal) + Number(tax || 0)) * pct) / 100 * 100) / 100;
                      setTip(String(calcTip));
                      setSelectedTipPct(pct);
                      const newTotal = Number(subtotal) + Number(tax || 0) + calcTip - Number(discount || 0);
                      setTotal(String(Math.round(newTotal * 100) / 100));
                    }}
                    className={`flex-1 px-2 py-2 rounded-lg text-[13px] font-medium border ${selectedTipPct === pct ? "bg-accent text-white border-accent" : "bg-white text-[#5B5748] border-line"}`}
                  >
                    {pct}%
                  </button>
                ))}
              </div>
            </div>
          )}

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Total</p>
          <input inputMode="decimal" value={total} onChange={(e) => setTotal(e.target.value)} placeholder="0.00"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-1.5" />
          {(Number(subtotal) > 0 || Number(tax) > 0 || Number(tip) > 0) && (
            <button
              onClick={() => {
                const calc = Number(subtotal || 0) + Number(tax || 0) + Number(tip || 0) - Number(discount || 0);
                setTotal(String(Math.round(calc * 100) / 100));
              }}
              className="text-[12px] text-accent font-medium mb-6"
            >
              Use calculated total ({money(Number(subtotal || 0) + Number(tax || 0) + Number(tip || 0) - Number(discount || 0))})
            </button>
          )}
          {!(Number(subtotal) > 0 || Number(tax) > 0 || Number(tip) > 0) && <div className="mb-6" />}

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Category (optional)</p>
          <div className="flex flex-wrap gap-1.5 mb-6">
            {RECEIPT_CATEGORIES.map((c) => (
              <button
                key={c}
                onClick={() => setReceiptCategory(receiptCategory === c ? null : c)}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${receiptCategory === c ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}
              >
                {c}
              </button>
            ))}
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">How do you want to split it?</p>
          <div className="flex gap-1.5 mb-6">
            <button onClick={() => setSplitMode("itemized")}
              className={`flex-1 px-3.5 py-3 rounded-xl text-[13px] font-medium border ${splitMode === "itemized" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              By item
            </button>
            <button onClick={() => setSplitMode("even")}
              className={`flex-1 px-3.5 py-3 rounded-xl text-[13px] font-medium border ${splitMode === "even" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Whole bill, evenly
            </button>
          </div>

          <button
            onClick={() => setPhase(splitMode === "even" ? "participants" : "items")}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6"
          >
            Continue
          </button>
        </div>
      )}

      {phase === "participants" && (
        <div className="px-5 pt-4 animate-page-in">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-4">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Who was there?</p>
          <div className="flex flex-wrap gap-1.5 mb-4">
            <button onClick={() => setEvenParticipants(people.map((p) => p.id))}
              className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${evenParticipants.length === people.length && people.length > 0 ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Everyone
            </button>
            {people.map((p) => (
              <button key={p.id} onClick={() => setEvenParticipants((cur) => cur.includes(p.id) ? cur.filter((x) => x !== p.id) : [...cur, p.id])}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${evenParticipants.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                {p.name}
              </button>
            ))}
          </div>

          {evenParticipants.length > 0 && (
            <p className="text-[13px] text-muted mb-6">
              {money((Number(total) || Number(subtotal) || 0) / evenParticipants.length)} each · {evenParticipants.length} people
            </p>
          )}

          <button onClick={() => setPhase("review")} disabled={evenParticipants.length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>
      )}

      {phase === "items" && (
        <div className="px-5 pt-4 animate-page-in">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-3">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

          {groups.length > 0 && (items.some((it) => it.category === "Food") || items.some((it) => it.category === "Drinks")) && (
            <div className="bg-white rounded-xl border border-line p-3 mb-3">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Quick assign by category</p>
              <div className="flex flex-wrap gap-1.5">
                <button onClick={() => assignCategoryToEveryone("Food")} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
                  🍽️ Food → Everyone
                </button>
                {groups.map((g) => (
                  <button key={g.id} onClick={() => assignCategoryToGroup("Drinks", g)} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
                    🍺 Drinks → {g.name}
                  </button>
                ))}
              </div>
            </div>
          )}

          <div className="space-y-3">
            {items.map((it) => (
              <div key={it.id} className="bg-white rounded-xl border border-line p-3.5">
                <div className="flex gap-2 mb-2.5">
                  <input className="flex-1 rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none" placeholder="Item name"
                    value={it.name} onChange={(e) => updateItem(it.id, { name: e.target.value })} />
                  <input inputMode="decimal" className="w-24 rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none" placeholder="$"
                    value={it.price} onChange={(e) => updateItem(it.id, { price: e.target.value })} />
                  <button onClick={() => removeItem(it.id)} className="p-2.5 rounded-xl bg-[#FBEDEA]">
                    <Trash2 size={16} className="text-owe" />
                  </button>
                </div>
                <div className="flex items-center gap-3 mb-2.5">
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted">Qty</span>
                    <input type="number" min={1} value={it.quantity}
                      onChange={(e) => updateItem(it.id, { quantity: Math.max(1, Number(e.target.value) || 1) })}
                      className="w-14 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted">Discount</span>
                    <input inputMode="decimal" value={it.discount} placeholder="0.00"
                      onChange={(e) => updateItem(it.id, { discount: e.target.value })}
                      className="w-20 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  </div>
                  {Number(it.discount) > 0 && (
                    <span className="text-[11px] text-accent font-medium">
                      → {money(Math.max(0, (Number(it.price) || 0) - Number(it.discount)))}
                    </span>
                  )}
                </div>
                <div className="flex gap-1.5 mb-2.5">
                  {CATEGORIES.map((c) => (
                    <button key={c} onClick={() => updateItem(it.id, { category: c })}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.category === c ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {c}
                    </button>
                  ))}
                </div>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Shared by</p>
                <div className="flex flex-wrap gap-1.5">
                  <button onClick={() => setItemPeople(it.id, people.map((p) => p.id))}
                    className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.length === people.length && people.length > 0 ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                    Everyone
                  </button>
                  {groups.map((g) => (
                    <button key={g.id} onClick={() => setItemPeople(it.id, g.memberIds)}
                      className="px-3.5 py-2 rounded-full text-[13px] font-medium border bg-[#F0EDE1] text-[#5B5748] border-line">
                      {g.name}
                    </button>
                  ))}
                  {people.map((p) => (
                    <button key={p.id} onClick={() => togglePerson(it.id, p.id)}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {p.name}
                    </button>
                  ))}
                </div>

                {it.personIds.length > 1 && (
                  <div className="mt-3 pt-3 border-t border-[#EDE9DC]">
                    <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Split</p>
                    <div className="flex gap-1.5 mb-3">
                      {(["even", "shares", "exact", "percent"] as const).map((t) => (
                        <button key={t} onClick={() => setSplitType(it.id, t)}
                          className={`px-2.5 py-1.5 rounded-full text-[11px] font-medium border ${it.splitType === t ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                          {t === "even" ? "Evenly" : t === "shares" ? "Shares" : t === "exact" ? "Exact $" : "%"}
                        </button>
                      ))}
                    </div>

                    {it.splitType === "even" && (
                      <p className="text-[11px] text-muted">
                        {money(Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0)) / it.personIds.length)} each · {it.personIds.length} people
                      </p>
                    )}

                    {it.splitType === "shares" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const units = it.personUnits[pid] ?? 1;
                          const totalUnits = it.personIds.reduce((s, id) => s + (it.personUnits[id] ?? 1), 0);
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const share = effectivePrice * (units / totalUnits);
                          return (
                            <div key={pid} className="flex items-center justify-between">
                              <span className="text-[13px] text-[#3A382F]">{person?.name}</span>
                              <div className="flex items-center gap-2">
                                <button onClick={() => setWeight(it.id, pid, Math.max(0, units - 1))} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">−</button>
                                <span className="w-5 text-center text-[13px] font-medium">{units}</span>
                                <button onClick={() => setWeight(it.id, pid, units + 1)} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">+</button>
                                <span className="w-16 text-right font-mono text-[12px] text-muted">{money(share)}</span>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    )}

                    {it.splitType === "exact" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const amt = it.personUnits[pid] ?? 0;
                          return (
                            <div key={pid} className="flex items-center justify-between gap-2">
                              <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                              <input inputMode="decimal" value={amt || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                placeholder="0.00" className="w-20 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                            </div>
                          );
                        })}
                        {(() => {
                          const sum = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const diff = Math.round((effectivePrice - sum) * 100) / 100;
                          return (
                            <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                              {Math.abs(diff) < 0.01 ? "Matches item price ✓" : diff > 0 ? `${money(diff)} unassigned` : `${money(Math.abs(diff))} over`}
                            </p>
                          );
                        })()}
                      </div>
                    )}

                    {it.splitType === "percent" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const pct = it.personUnits[pid] ?? 0;
                          return (
                            <div key={pid} className="flex items-center justify-between gap-2">
                              <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                              <div className="flex items-center gap-1">
                                <input inputMode="decimal" value={pct || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                  placeholder="0" className="w-14 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                                <span className="text-[12px] text-muted">%</span>
                              </div>
                            </div>
                          );
                        })}
                        {(() => {
                          const sum = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const diff = Math.round((100 - sum) * 100) / 100;
                          return (
                            <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                              {Math.abs(diff) < 0.01 ? "Totals 100% ✓" : diff > 0 ? `${diff}% unassigned` : `${Math.abs(diff)}% over`}
                            </p>
                          );
                        })()}
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>

          <button onClick={addItem} className="w-full mt-3 rounded-xl border-2 border-dashed border-line py-3 flex items-center justify-center gap-1.5 text-[13px] font-semibold text-accent">
            <Plus size={16} /> Add item
          </button>

          <div className="flex items-center justify-between mt-5 mb-6">
            <span className="text-[13px] text-muted">Items total</span>
            <span className="font-mono text-[15px] font-semibold text-ink">{money(itemsSum)}</span>
          </div>

          <button onClick={() => setPhase("review")} disabled={items.filter((it) => it.name.trim() && Number(it.price) > 0).length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>
      )}

      {phase === "review" && (
        <div className="px-5 pt-4 animate-page-in">
          {splitMode === "even" ? (
            <div className="bg-white rounded-xl border border-line p-4 mb-4">
              <div className="flex justify-between text-[14px] font-semibold"><span>Total</span><span className="font-mono">{money(draftReceipt.total)}</span></div>
            </div>
          ) : (
            <div className="bg-white rounded-xl border border-line p-4 mb-4">
              <div className="flex justify-between text-[13px] mb-1"><span className="text-muted">Receipt total</span><span className="font-mono text-ink">{money(draftReceipt.total)}</span></div>
              <div className="flex justify-between text-[13px] mb-1"><span className="text-muted">Calculated total</span><span className="font-mono text-ink">{money(calculatedTotal)}</span></div>
              <div className={`flex justify-between text-[13px] items-center ${Math.abs(totalDifference) < 0.01 ? "text-accent" : "text-owe"}`}>
                <span>Difference</span>
                <span className="font-mono flex items-center gap-1">
                  {money(Math.abs(totalDifference))}
                  {Math.abs(totalDifference) < 0.01 ? <CheckCircle2 size={14} /> : <AlertTriangle size={14} />}
                </span>
              </div>
            </div>
          )}

          {splitMode === "itemized" && (
            <div className="flex gap-1.5 mb-5">
              <button onClick={() => setTaxTipMethod("proportional")}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "proportional" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                Tax/tip proportional
              </button>
              <button onClick={() => setTaxTipMethod("equal")}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "equal" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                Split equally
              </button>
            </div>
          )}

          <div className="space-y-2.5 mb-4">
            {Object.entries(shares).map(([pid, s]: any) => {
              const person = people.find((p) => p.id === pid);
              return (
                <div key={pid} className="bg-white rounded-xl border border-line p-3.5">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[14px] font-semibold text-ink">{person?.name}</span>
                    <span className="font-mono text-[15px] font-semibold text-ink">{money(s.total)}</span>
                  </div>
                  {s.food > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Food</span><span className="font-mono">{money(s.food)}</span></p>}
                  {s.drinks > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Drinks</span><span className="font-mono">{money(s.drinks)}</span></p>}
                  {s.other > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Other</span><span className="font-mono">{money(s.other)}</span></p>}
                  <p className="text-[13px] text-[#3A382F] flex justify-between py-1"><span>Tax, tip &amp; discount</span><span className="font-mono">{money(s.taxTip)}</span></p>
                </div>
              );
            })}
          </div>

          {unassignedItems.length > 0 && (
            <div className="rounded-xl bg-[#FBF3E6] border border-[#EEDDB8] px-4 py-3 text-[13px] text-[#7A5E24] mb-4">
              Not assigned yet: {unassignedItems.map((it) => it.name).join(", ")}
            </div>
          )}

          <div className={`rounded-xl px-4 py-3 mb-6 flex items-center justify-between text-[13px] font-medium ${Math.abs(unassigned) < 0.01 ? "bg-[#EFF7F3] text-[#1F7A5C]" : "bg-[#FBEDEA] text-owe"}`}>
            <span>{Math.abs(unassigned) < 0.01 ? "Fully assigned" : "Unassigned amount"}</span>
            <span className="font-mono flex items-center gap-1">
              {Math.abs(unassigned) < 0.01 ? <CheckCircle2 size={14} /> : money(unassigned)}
            </span>
          </div>

          <button onClick={save} disabled={saving} className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            {saving ? "Saving…" : "Save receipt"}
          </button>
        </div>
      )}
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/receipts/[id]/edit/page.tsx')
cat > 'app/receipts/[id]/edit/page.tsx' << 'FILEEOF'
"use client";

import { useEffect, useState } from "react";
import { useRouter, useParams } from "next/navigation";
import { Plus, Trash2, X, CheckCircle2, AlertTriangle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { computeReceiptShares } from "@/lib/split";
import { Category, Person, Group, TaxTipMethod, ReceiptCategory } from "@/lib/types";

const CATEGORIES: Category[] = ["Food", "Drinks", "Other"];
const RECEIPT_CATEGORIES: ReceiptCategory[] = ["Dining", "Trips", "Roommates/Home", "Transportation", "Other"];

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

interface DraftItem {
  id: string;
  name: string;
  price: string;
  discount: string;
  quantity: number;
  category: Category;
  personIds: string[];
  personUnits: Record<string, number>;
  splitType: "even" | "shares" | "exact" | "percent";
}

type Phase = "basics" | "participants" | "items" | "review";

export default function EditReceiptPage() {
  const router = useRouter();
  const params = useParams();
  const receiptId = params.id as string;
  const supabase = createClient();

  const [loading, setLoading] = useState(true);
  const [phase, setPhase] = useState<Phase>("basics");
  const [people, setPeople] = useState<Person[]>([]);
  const [groups, setGroups] = useState<Group[]>([]);
  const [merchant, setMerchant] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [subtotal, setSubtotal] = useState("");
  const [tax, setTax] = useState("");
  const [tip, setTip] = useState("");
  const [discount, setDiscount] = useState("");
  const [total, setTotal] = useState("");
  const [selectedTipPct, setSelectedTipPct] = useState<number | null>(null);
  const [receiptCategory, setReceiptCategory] = useState<ReceiptCategory | null>(null);
  const [items, setItems] = useState<DraftItem[]>([]);
  const [taxTipMethod, setTaxTipMethod] = useState<TaxTipMethod>("proportional");
  const [splitMode, setSplitMode] = useState<"itemized" | "even">("itemized");
  const [evenParticipants, setEvenParticipants] = useState<string[]>([]);
  const [newPersonName, setNewPersonName] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    (async () => {
      const { data: p } = await supabase.from("people").select("*").order("name");
      setPeople(p ?? []);
      const { data: g } = await supabase.from("groups").select("*").order("name");
      const { data: m } = await supabase.from("group_members").select("*");
      setGroups(
        (g ?? []).map((grp) => ({ ...grp, memberIds: (m ?? []).filter((x) => x.group_id === grp.id).map((x) => x.person_id) }))
      );

      const { data: receipt } = await supabase.from("receipts").select("*").eq("id", receiptId).single();
      if (!receipt) {
        setLoading(false);
        return;
      }
      setMerchant(receipt.merchant || "");
      setDate(receipt.date || new Date().toISOString().slice(0, 10));
      setSubtotal(String(receipt.subtotal ?? ""));
      setTax(String(receipt.tax ?? ""));
      setTip(String(receipt.tip ?? ""));
      setDiscount(String(receipt.discount ?? ""));
      setTotal(String(receipt.total ?? ""));
      setTaxTipMethod(receipt.tax_tip_method || "proportional");
      setSplitMode(receipt.split_mode || "itemized");
      setReceiptCategory(receipt.category || null);

      const { data: dbItems } = await supabase.from("receipt_items").select("*").eq("receipt_id", receiptId);
      const itemIds = (dbItems ?? []).map((i) => i.id);
      const { data: dbSplits } = itemIds.length
        ? await supabase.from("item_splits").select("*").in("item_id", itemIds)
        : { data: [] };

      if (receipt.split_mode === "even") {
        const evenItem = (dbItems ?? [])[0];
        if (evenItem) {
          const splitsForItem = (dbSplits ?? []).filter((s) => s.item_id === evenItem.id);
          setEvenParticipants(splitsForItem.map((s) => s.person_id));
        }
      } else {
        setItems(
          (dbItems ?? []).map((i) => {
            const splitsForItem = (dbSplits ?? []).filter((s) => s.item_id === i.id);
            const personUnits = Object.fromEntries(splitsForItem.map((s) => [s.person_id, s.units ?? 1]));
            const values = Object.values(personUnits);
            const allSame = values.length > 0 && values.every((v) => v === values[0]);
            return {
              id: i.id,
              name: i.name,
              price: String(i.price),
              discount: i.discount ? String(i.discount) : "",
              quantity: i.quantity || 1,
              category: i.category,
              personIds: splitsForItem.map((s) => s.person_id),
              personUnits,
              splitType: allSame ? "even" : "shares",
            } as DraftItem;
          })
        );
      }
      setLoading(false);
    })();
  }, [receiptId]);

  const itemsSum = items.reduce((s, it) => s + Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0)), 0);

  function addItem() {
    setItems([...items, { id: crypto.randomUUID(), name: "", price: "", discount: "", quantity: 1, category: "Food", personIds: [], personUnits: {}, splitType: "even" }]);
  }
  function updateItem(id: string, patch: Partial<DraftItem>) {
    setItems(items.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  }
  function removeItem(id: string) {
    setItems(items.filter((it) => it.id !== id));
  }
  function togglePerson(itemId: string, personId: string) {
    setItems(
      items.map((it) => {
        if (it.id !== itemId) return it;
        const has = it.personIds.includes(personId);
        return { ...it, personIds: has ? it.personIds.filter((id) => id !== personId) : [...it.personIds, personId] };
      })
    );
  }
  function setItemPeople(itemId: string, ids: string[]) {
    setItems(items.map((it) => (it.id === itemId ? { ...it, personIds: ids } : it)));
  }
  function setSplitType(itemId: string, type: DraftItem["splitType"]) {
    setItems(
      items.map((it) => {
        if (it.id !== itemId) return it;
        const count = it.personIds.length || 1;
        const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
        let personUnits: Record<string, number> = {};
        if (type === "shares") personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, 1]));
        else if (type === "exact") {
          const each = Math.round((effectivePrice / count) * 100) / 100;
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, each]));
        } else if (type === "percent") {
          const each = Math.round((100 / count) * 100) / 100;
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, each]));
        }
        return { ...it, splitType: type, personUnits };
      })
    );
  }
  function setWeight(itemId: string, personId: string, value: number) {
    setItems(
      items.map((it) => (it.id === itemId ? { ...it, personUnits: { ...it.personUnits, [personId]: Math.max(0, value) } } : it))
    );
  }
  function assignCategoryToEveryone(category: Category) {
    const everyone = people.map((p) => p.id);
    setItems(items.map((it) => (it.category === category ? { ...it, personIds: everyone } : it)));
  }
  function assignCategoryToGroup(category: Category, group: Group) {
    setItems(items.map((it) => (it.category === category ? { ...it, personIds: group.memberIds } : it)));
  }

  async function addPerson() {
    if (!newPersonName.trim()) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    const { data } = await supabase.from("people").insert({ user_id: user.id, name: newPersonName.trim() }).select().single();
    if (data) setPeople([...people, data]);
    setNewPersonName("");
  }

  const validItems =
    splitMode === "even"
      ? [
          {
            id: "even-split",
            name: "Whole bill",
            price:
              Number(total) ||
              (Number(subtotal) || 0) + (Number(tax) || 0) + (Number(tip) || 0) - (Number(discount) || 0),
            discount: 0,
            quantity: 1,
            category: "Other" as Category,
            personIds: evenParticipants,
            personUnits: {} as Record<string, number>,
            splitType: "even" as const,
          },
        ]
      : items
          .filter((it) => it.name.trim() && Number(it.price) > 0)
          .map((it) => ({ ...it, price: Number(it.price), discount: Number(it.discount) || 0 }));

  const draftReceipt = {
    merchant: merchant.trim() || "Untitled receipt",
    date,
    subtotal: Number(subtotal) || itemsSum,
    tax: Number(tax) || 0,
    tip: Number(tip) || 0,
    discount: Number(discount) || 0,
    total: Number(total) || (Number(subtotal) || itemsSum) + (Number(tax) || 0) + (Number(tip) || 0) - (Number(discount) || 0),
    items: validItems,
    tax_tip_method: taxTipMethod,
    split_mode: splitMode,
  };
  const shares = computeReceiptShares(draftReceipt as any);

  // Reconciliation
  const calculatedTotal =
    draftReceipt.subtotal + draftReceipt.tax + draftReceipt.tip - draftReceipt.discount;
  const totalDifference = Math.round((draftReceipt.total - calculatedTotal) * 100) / 100;
  const assignedTotal = Object.values(shares).reduce((s: number, sh: any) => s + sh.total, 0);
  const unassigned = Math.round((draftReceipt.total - assignedTotal) * 100) / 100;
  const unassignedItems = splitMode === "itemized" ? validItems.filter((it) => it.personIds.length === 0) : [];

  async function save() {
    setSaving(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;

    const { error } = await supabase
      .from("receipts")
      .update({
        merchant: draftReceipt.merchant,
        date: draftReceipt.date,
        subtotal: draftReceipt.subtotal,
        tax: draftReceipt.tax,
        tip: draftReceipt.tip,
        discount: draftReceipt.discount,
        total: draftReceipt.total,
        tax_tip_method: taxTipMethod,
        split_mode: splitMode,
        category: receiptCategory,
      })
      .eq("id", receiptId);

    if (error) {
      setSaving(false);
      return;
    }

    await supabase.from("receipt_items").delete().eq("receipt_id", receiptId);

    for (const item of validItems) {
      const { data: savedItem } = await supabase
        .from("receipt_items")
        .insert({
          receipt_id: receiptId,
          name: item.name,
          price: Number(item.price),
          discount: Number(item.discount) || 0,
          category: item.category,
          quantity: item.quantity || 1,
        })
        .select()
        .single();
      if (savedItem && item.personIds.length) {
        await supabase.from("item_splits").insert(
          item.personIds.map((personId) => ({
            item_id: savedItem.id,
            person_id: personId,
            units: item.personUnits?.[personId] ?? 1,
          }))
        );
      }
    }

    router.push(`/receipts/${receiptId}`);
    router.refresh();
  }

  function backFrom(p: Phase) {
    if (p === "basics") router.push(`/receipts/${receiptId}`);
    else if (p === "participants") setPhase("basics");
    else if (p === "items") setPhase("basics");
    else if (p === "review") setPhase(splitMode === "even" ? "participants" : "items");
  }

  const titles: Record<Phase, string> = {
    basics: "Edit Receipt",
    participants: "Who's In?",
    items: "Items",
    review: "Review & Split",
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-[13px] text-muted">Loading receipt…</p>
      </div>
    );
  }

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <button onClick={() => backFrom(phase)} className="text-[13px] text-muted">
          Back
        </button>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink">{titles[phase]}</h1>
        <button onClick={() => router.push(`/receipts/${receiptId}`)} className="p-1">
          <X size={18} className="text-muted" />
        </button>
      </div>

      {phase === "basics" && (
        <div className="px-5 pt-4 animate-page-in">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Merchant</p>
          <input value={merchant} onChange={(e) => setMerchant(e.target.value)} placeholder="e.g. King Pocha"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Date</p>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <div className="grid grid-cols-2 gap-2 mb-3">
            {[
              ["Subtotal", subtotal, setSubtotal],
              ["Tax", tax, setTax],
              ["Tip", tip, (v: string) => { setTip(v); setSelectedTipPct(null); }],
              ["Discount", discount, setDiscount],
            ].map(([label, val, setter]: any) => (
              <div key={label}>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">{label}</p>
                <input inputMode="decimal" value={val} onChange={(e) => setter(e.target.value)} placeholder="0.00"
                  className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40" />
              </div>
            ))}
          </div>

          {Number(subtotal) > 0 && (
            <div className="mb-4">
              <p className="text-[11px] text-muted mb-1.5">Tip wasn't printed on the receipt? Calculate it:</p>
              <div className="flex gap-1.5">
                {[15, 18, 20, 25].map((pct) => (
                  <button
                    key={pct}
                    onClick={() => {
                      const calcTip = Math.round(((Number(subtotal) + Number(tax || 0)) * pct) / 100 * 100) / 100;
                      setTip(String(calcTip));
                      setSelectedTipPct(pct);
                      const newTotal = Number(subtotal) + Number(tax || 0) + calcTip - Number(discount || 0);
                      setTotal(String(Math.round(newTotal * 100) / 100));
                    }}
                    className={`flex-1 px-2 py-2 rounded-lg text-[13px] font-medium border ${selectedTipPct === pct ? "bg-accent text-white border-accent" : "bg-white text-[#5B5748] border-line"}`}
                  >
                    {pct}%
                  </button>
                ))}
              </div>
            </div>
          )}

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Total</p>
          <input inputMode="decimal" value={total} onChange={(e) => setTotal(e.target.value)} placeholder="0.00"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-1.5" />
          {(Number(subtotal) > 0 || Number(tax) > 0 || Number(tip) > 0) && (
            <button
              onClick={() => {
                const calc = Number(subtotal || 0) + Number(tax || 0) + Number(tip || 0) - Number(discount || 0);
                setTotal(String(Math.round(calc * 100) / 100));
              }}
              className="text-[12px] text-accent font-medium mb-6"
            >
              Use calculated total ({money(Number(subtotal || 0) + Number(tax || 0) + Number(tip || 0) - Number(discount || 0))})
            </button>
          )}
          {!(Number(subtotal) > 0 || Number(tax) > 0 || Number(tip) > 0) && <div className="mb-6" />}

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Category (optional)</p>
          <div className="flex flex-wrap gap-1.5 mb-6">
            {RECEIPT_CATEGORIES.map((c) => (
              <button
                key={c}
                onClick={() => setReceiptCategory(receiptCategory === c ? null : c)}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${receiptCategory === c ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}
              >
                {c}
              </button>
            ))}
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">How do you want to split it?</p>
          <div className="flex gap-1.5 mb-6">
            <button onClick={() => setSplitMode("itemized")}
              className={`flex-1 px-3.5 py-3 rounded-xl text-[13px] font-medium border ${splitMode === "itemized" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              By item
            </button>
            <button onClick={() => setSplitMode("even")}
              className={`flex-1 px-3.5 py-3 rounded-xl text-[13px] font-medium border ${splitMode === "even" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Whole bill, evenly
            </button>
          </div>

          <button
            onClick={() => setPhase(splitMode === "even" ? "participants" : "items")}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6"
          >
            Continue
          </button>
        </div>
      )}

      {phase === "participants" && (
        <div className="px-5 pt-4 animate-page-in">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-4">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Who was there?</p>
          <div className="flex flex-wrap gap-1.5 mb-4">
            <button onClick={() => setEvenParticipants(people.map((p) => p.id))}
              className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${evenParticipants.length === people.length && people.length > 0 ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Everyone
            </button>
            {people.map((p) => (
              <button key={p.id} onClick={() => setEvenParticipants((cur) => cur.includes(p.id) ? cur.filter((x) => x !== p.id) : [...cur, p.id])}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${evenParticipants.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                {p.name}
              </button>
            ))}
          </div>

          {evenParticipants.length > 0 && (
            <p className="text-[13px] text-muted mb-6">
              {money((Number(total) || Number(subtotal) || 0) / evenParticipants.length)} each · {evenParticipants.length} people
            </p>
          )}

          <button onClick={() => setPhase("review")} disabled={evenParticipants.length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>
      )}

      {phase === "items" && (
        <div className="px-5 pt-4 animate-page-in">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-3">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

          {groups.length > 0 && (items.some((it) => it.category === "Food") || items.some((it) => it.category === "Drinks")) && (
            <div className="bg-white rounded-xl border border-line p-3 mb-3">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Quick assign by category</p>
              <div className="flex flex-wrap gap-1.5">
                <button onClick={() => assignCategoryToEveryone("Food")} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
                  🍽️ Food → Everyone
                </button>
                {groups.map((g) => (
                  <button key={g.id} onClick={() => assignCategoryToGroup("Drinks", g)} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
                    🍺 Drinks → {g.name}
                  </button>
                ))}
              </div>
            </div>
          )}

          <div className="space-y-3">
            {items.map((it) => (
              <div key={it.id} className="bg-white rounded-xl border border-line p-3.5">
                <div className="flex gap-2 mb-2.5">
                  <input className="flex-1 rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none" placeholder="Item name"
                    value={it.name} onChange={(e) => updateItem(it.id, { name: e.target.value })} />
                  <input inputMode="decimal" className="w-24 rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none" placeholder="$"
                    value={it.price} onChange={(e) => updateItem(it.id, { price: e.target.value })} />
                  <button onClick={() => removeItem(it.id)} className="p-2.5 rounded-xl bg-[#FBEDEA]">
                    <Trash2 size={16} className="text-owe" />
                  </button>
                </div>
                <div className="flex items-center gap-3 mb-2.5">
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted">Qty</span>
                    <input type="number" min={1} value={it.quantity}
                      onChange={(e) => updateItem(it.id, { quantity: Math.max(1, Number(e.target.value) || 1) })}
                      className="w-14 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted">Discount</span>
                    <input inputMode="decimal" value={it.discount} placeholder="0.00"
                      onChange={(e) => updateItem(it.id, { discount: e.target.value })}
                      className="w-20 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  </div>
                  {Number(it.discount) > 0 && (
                    <span className="text-[11px] text-accent font-medium">
                      → {money(Math.max(0, (Number(it.price) || 0) - Number(it.discount)))}
                    </span>
                  )}
                </div>
                <div className="flex gap-1.5 mb-2.5">
                  {CATEGORIES.map((c) => (
                    <button key={c} onClick={() => updateItem(it.id, { category: c })}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.category === c ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {c}
                    </button>
                  ))}
                </div>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Shared by</p>
                <div className="flex flex-wrap gap-1.5">
                  <button onClick={() => setItemPeople(it.id, people.map((p) => p.id))}
                    className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.length === people.length && people.length > 0 ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                    Everyone
                  </button>
                  {groups.map((g) => (
                    <button key={g.id} onClick={() => setItemPeople(it.id, g.memberIds)}
                      className="px-3.5 py-2 rounded-full text-[13px] font-medium border bg-[#F0EDE1] text-[#5B5748] border-line">
                      {g.name}
                    </button>
                  ))}
                  {people.map((p) => (
                    <button key={p.id} onClick={() => togglePerson(it.id, p.id)}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {p.name}
                    </button>
                  ))}
                </div>

                {it.personIds.length > 1 && (
                  <div className="mt-3 pt-3 border-t border-[#EDE9DC]">
                    <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Split</p>
                    <div className="flex gap-1.5 mb-3">
                      {(["even", "shares", "exact", "percent"] as const).map((t) => (
                        <button key={t} onClick={() => setSplitType(it.id, t)}
                          className={`px-2.5 py-1.5 rounded-full text-[11px] font-medium border ${it.splitType === t ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                          {t === "even" ? "Evenly" : t === "shares" ? "Shares" : t === "exact" ? "Exact $" : "%"}
                        </button>
                      ))}
                    </div>

                    {it.splitType === "even" && (
                      <p className="text-[11px] text-muted">
                        {money(Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0)) / it.personIds.length)} each · {it.personIds.length} people
                      </p>
                    )}

                    {it.splitType === "shares" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const units = it.personUnits[pid] ?? 1;
                          const totalUnits = it.personIds.reduce((s, id) => s + (it.personUnits[id] ?? 1), 0);
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const share = effectivePrice * (units / totalUnits);
                          return (
                            <div key={pid} className="flex items-center justify-between">
                              <span className="text-[13px] text-[#3A382F]">{person?.name}</span>
                              <div className="flex items-center gap-2">
                                <button onClick={() => setWeight(it.id, pid, Math.max(0, units - 1))} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">−</button>
                                <span className="w-5 text-center text-[13px] font-medium">{units}</span>
                                <button onClick={() => setWeight(it.id, pid, units + 1)} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">+</button>
                                <span className="w-16 text-right font-mono text-[12px] text-muted">{money(share)}</span>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    )}

                    {it.splitType === "exact" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const amt = it.personUnits[pid] ?? 0;
                          return (
                            <div key={pid} className="flex items-center justify-between gap-2">
                              <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                              <input inputMode="decimal" value={amt || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                placeholder="0.00" className="w-20 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                            </div>
                          );
                        })}
                        {(() => {
                          const sum = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const diff = Math.round((effectivePrice - sum) * 100) / 100;
                          return (
                            <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                              {Math.abs(diff) < 0.01 ? "Matches item price ✓" : diff > 0 ? `${money(diff)} unassigned` : `${money(Math.abs(diff))} over`}
                            </p>
                          );
                        })()}
                      </div>
                    )}

                    {it.splitType === "percent" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const pct = it.personUnits[pid] ?? 0;
                          return (
                            <div key={pid} className="flex items-center justify-between gap-2">
                              <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                              <div className="flex items-center gap-1">
                                <input inputMode="decimal" value={pct || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                  placeholder="0" className="w-14 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                                <span className="text-[12px] text-muted">%</span>
                              </div>
                            </div>
                          );
                        })}
                        {(() => {
                          const sum = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const diff = Math.round((100 - sum) * 100) / 100;
                          return (
                            <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                              {Math.abs(diff) < 0.01 ? "Totals 100% ✓" : diff > 0 ? `${diff}% unassigned` : `${Math.abs(diff)}% over`}
                            </p>
                          );
                        })()}
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>

          <button onClick={addItem} className="w-full mt-3 rounded-xl border-2 border-dashed border-line py-3 flex items-center justify-center gap-1.5 text-[13px] font-semibold text-accent">
            <Plus size={16} /> Add item
          </button>

          <div className="flex items-center justify-between mt-5 mb-6">
            <span className="text-[13px] text-muted">Items total</span>
            <span className="font-mono text-[15px] font-semibold text-ink">{money(itemsSum)}</span>
          </div>

          <button onClick={() => setPhase("review")} disabled={items.filter((it) => it.name.trim() && Number(it.price) > 0).length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>
      )}

      {phase === "review" && (
        <div className="px-5 pt-4 animate-page-in">
          {splitMode === "even" ? (
            <div className="bg-white rounded-xl border border-line p-4 mb-4">
              <div className="flex justify-between text-[14px] font-semibold"><span>Total</span><span className="font-mono">{money(draftReceipt.total)}</span></div>
            </div>
          ) : (
            <div className="bg-white rounded-xl border border-line p-4 mb-4">
              <div className="flex justify-between text-[13px] mb-1"><span className="text-muted">Receipt total</span><span className="font-mono text-ink">{money(draftReceipt.total)}</span></div>
              <div className="flex justify-between text-[13px] mb-1"><span className="text-muted">Calculated total</span><span className="font-mono text-ink">{money(calculatedTotal)}</span></div>
              <div className={`flex justify-between text-[13px] items-center ${Math.abs(totalDifference) < 0.01 ? "text-accent" : "text-owe"}`}>
                <span>Difference</span>
                <span className="font-mono flex items-center gap-1">
                  {money(Math.abs(totalDifference))}
                  {Math.abs(totalDifference) < 0.01 ? <CheckCircle2 size={14} /> : <AlertTriangle size={14} />}
                </span>
              </div>
            </div>
          )}

          {splitMode === "itemized" && (
            <div className="flex gap-1.5 mb-5">
              <button onClick={() => setTaxTipMethod("proportional")}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "proportional" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                Tax/tip proportional
              </button>
              <button onClick={() => setTaxTipMethod("equal")}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "equal" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                Split equally
              </button>
            </div>
          )}

          <div className="space-y-2.5 mb-4">
            {Object.entries(shares).map(([pid, s]: any) => {
              const person = people.find((p) => p.id === pid);
              return (
                <div key={pid} className="bg-white rounded-xl border border-line p-3.5">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[14px] font-semibold text-ink">{person?.name}</span>
                    <span className="font-mono text-[15px] font-semibold text-ink">{money(s.total)}</span>
                  </div>
                  {s.food > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Food</span><span className="font-mono">{money(s.food)}</span></p>}
                  {s.drinks > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Drinks</span><span className="font-mono">{money(s.drinks)}</span></p>}
                  {s.other > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Other</span><span className="font-mono">{money(s.other)}</span></p>}
                  <p className="text-[13px] text-[#3A382F] flex justify-between py-1"><span>Tax, tip &amp; discount</span><span className="font-mono">{money(s.taxTip)}</span></p>
                </div>
              );
            })}
          </div>

          {unassignedItems.length > 0 && (
            <div className="rounded-xl bg-[#FBF3E6] border border-[#EEDDB8] px-4 py-3 text-[13px] text-[#7A5E24] mb-4">
              Not assigned yet: {unassignedItems.map((it) => it.name).join(", ")}
            </div>
          )}

          <div className={`rounded-xl px-4 py-3 mb-6 flex items-center justify-between text-[13px] font-medium ${Math.abs(unassigned) < 0.01 ? "bg-[#EFF7F3] text-[#1F7A5C]" : "bg-[#FBEDEA] text-owe"}`}>
            <span>{Math.abs(unassigned) < 0.01 ? "Fully assigned" : "Unassigned amount"}</span>
            <span className="font-mono flex items-center gap-1">
              {Math.abs(unassigned) < 0.01 ? <CheckCircle2 size={14} /> : money(unassigned)}
            </span>
          </div>

          <button onClick={save} disabled={saving} className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            {saving ? "Saving…" : "Save changes"}
          </button>
        </div>
      )}
    </div>
  );
}
FILEEOF

echo "All files updated."
echo "Now run: git add . && git commit -m \"Add app icon, loading skeletons, transitions, polished empty states\" && git push"
