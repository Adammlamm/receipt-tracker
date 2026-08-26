"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Home, Receipt, Users, CreditCard, Plus } from "lucide-react";

const TABS = [
  { href: "/", label: "Home", icon: Home },
  { href: "/receipts", label: "Receipts", icon: Receipt },
  { href: "/people", label: "People", icon: Users },
  { href: "/payments", label: "Payments", icon: CreditCard },
];

export default function BottomNav() {
  const pathname = usePathname();

  return (
    <>
      <Link
        href="/receipts/new"
        className="fixed bottom-20 right-5 max-w-md mx-auto rounded-full bg-accent text-white shadow-lg shadow-accent/30 px-5 py-3.5 flex items-center gap-2 font-semibold text-sm z-30"
        style={{ right: "max(1.25rem, calc((100vw - 28rem) / 2 + 1.25rem))" }}
      >
        <Plus size={18} /> Add Receipt
      </Link>

      <nav className="fixed bottom-0 left-0 right-0 bg-white/95 backdrop-blur border-t border-line z-30">
        <div className="max-w-md mx-auto grid grid-cols-4">
          {TABS.map(({ href, label, icon: Icon }) => {
            const active = pathname === href;
            return (
              <Link key={href} href={href} className="flex flex-col items-center gap-0.5 py-2.5">
                <Icon size={21} className={active ? "text-accent" : "text-muted"} strokeWidth={active ? 2.4 : 2} />
                <span className={`text-[10px] font-medium ${active ? "text-accent" : "text-muted"}`}>{label}</span>
              </Link>
            );
          })}
        </div>
      </nav>
    </>
  );
}
