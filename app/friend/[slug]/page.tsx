"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { CheckCircle2, Receipt, Copy, ExternalLink, ChevronDown, ChevronUp } from "lucide-react";
import { PaymentMethod } from "@/lib/types";
import { buildPaymentLink, supportsPaymentLink } from "@/lib/paymentLinks";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash App", "Cash", "PayPal", "Other"];

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}
function fmtDate(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

interface ReceiptRow {
  id: string;
  merchant: string;
  date: string;
  category: string | null;
  owed: number;
  paid: number;
  remaining: number;
  items: { name: string; category: string }[];
  notes: string | null;
}

interface FriendInfo {
  name: string;
  first_name: string | null;
  last_name: string | null;
  preferred_payment_method: PaymentMethod | null;
  payment_handle: string | null;
  phone_number: string | null;
  totalOwed: number;
  totalPaid: number;
  totalRemaining: number;
  receipts: ReceiptRow[];
  owner: { name: string; preferred_payment_method: PaymentMethod | null; payment_handle: string | null } | null;
}

export default function FriendPage() {
  const params = useParams();
  const slug = params.slug as string;

  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [info, setInfo] = useState<FriendInfo | null>(null);

  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [method, setMethod] = useState<PaymentMethod | null>(null);
  const [handle, setHandle] = useState("");
  const [phone, setPhone] = useState("");
  const [payAmount, setPayAmount] = useState("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [showReceipts, setShowReceipts] = useState(false);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    (async () => {
      try {
        const res = await fetch(`/api/friend/${slug}`);
        if (!res.ok) {
          setNotFound(true);
        } else {
          const data: FriendInfo = await res.json();
          setInfo(data);
          setFirstName(data.first_name || data.name);
          setLastName(data.last_name || "");
          setMethod(data.preferred_payment_method);
          setHandle(data.payment_handle ?? "");
          setPhone(data.phone_number ?? "");
          setPayAmount(data.totalRemaining > 0 ? data.totalRemaining.toFixed(2) : "");
        }
      } catch {
        setNotFound(true);
      } finally {
        setLoading(false);
      }
    })();
  }, [slug]);

  async function save() {
    setSaving(true);
    try {
      const res = await fetch(`/api/friend/${slug}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          first_name: firstName.trim() || undefined,
          last_name: lastName.trim(),
          preferred_payment_method: method,
          payment_handle: handle.trim() || null,
          phone_number: phone.trim() || null,
        }),
      });
      if (res.ok) setSaved(true);
    } finally {
      setSaving(false);
    }
  }

  async function copyHandle(text: string) {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {}
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-paper flex items-center justify-center">
        <p className="text-[13px] text-muted">Loading…</p>
      </div>
    );
  }

  if (notFound || !info) {
    return (
      <div className="min-h-screen bg-paper flex items-center justify-center px-6">
        <div className="text-center max-w-sm">
          <div className="w-12 h-12 rounded-full bg-[#F0EDE1] flex items-center justify-center mx-auto mb-4">
            <Receipt size={22} className="text-muted" />
          </div>
          <h1 className="text-[17px] font-semibold text-ink mb-1.5">Link not found</h1>
          <p className="text-[13px] text-muted">This link doesn't look right — ask whoever sent it for a fresh one.</p>
        </div>
      </div>
    );
  }

  const owner = info.owner;
  const ownerLink =
    owner?.preferred_payment_method && owner.payment_handle && supportsPaymentLink(owner.preferred_payment_method)
      ? buildPaymentLink(owner.preferred_payment_method, owner.payment_handle, Number(payAmount) || 0, `Receipt Tracker`)
      : null;

  return (
    <div className="min-h-screen bg-paper">
      <div className="max-w-md mx-auto px-6 pt-10 pb-10">
        <div className="w-11 h-11 rounded-full bg-[#EFF7F3] flex items-center justify-center mb-4">
          <Receipt size={20} className="text-accent" />
        </div>
        <h1 className="text-[19px] font-semibold text-ink mb-1">Hi {info.name} 👋</h1>
        <p className="text-[13px] text-muted mb-5">Here's what you owe, and a quick way to add your info or pay back.</p>

        {/* Balance summary */}
        <div className="bg-white rounded-xl border border-line p-4 mb-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1">You owe</p>
          <p className={`font-mono text-[28px] font-semibold ${info.totalRemaining > 0.005 ? "text-owe" : "text-accent"}`}>
            {money(info.totalRemaining)}
          </p>
          {info.totalPaid > 0 && (
            <p className="text-[12px] text-muted mt-1">{money(info.totalPaid)} already paid</p>
          )}
        </div>

        {/* Pay now */}
        {info.totalRemaining > 0.005 && owner?.preferred_payment_method && owner.payment_handle && (
          <div className="bg-white rounded-xl border border-line p-4 mb-3">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">
              Pay {owner.name} back via {owner.preferred_payment_method}
            </p>
            <div className="flex items-center gap-2 mb-3">
              <span className="text-[14px] text-muted">$</span>
              <input
                inputMode="decimal"
                value={payAmount}
                onChange={(e) => setPayAmount(e.target.value)}
                className="flex-1 rounded-lg border border-line bg-white px-3 py-2 text-[14px] outline-none focus:ring-2 focus:ring-accent/40"
              />
            </div>
            {ownerLink ? (
              <a
                href={ownerLink}
                target="_blank"
                rel="noopener noreferrer"
                className="w-full flex items-center justify-center gap-1.5 rounded-xl bg-accent text-white font-semibold py-3 text-[14px]"
              >
                <ExternalLink size={15} /> Pay {money(Number(payAmount) || 0)} via {owner.preferred_payment_method}
              </a>
            ) : (
              <button
                onClick={() => copyHandle(owner.payment_handle!)}
                className="w-full flex items-center justify-center gap-1.5 rounded-xl border border-line bg-white text-ink font-semibold py-3 text-[14px]"
              >
                <Copy size={15} />
                {copied ? "Copied!" : `Copy ${owner.name}'s ${owner.preferred_payment_method} info`}
              </button>
            )}
            {!ownerLink && (
              <p className="text-[11px] text-muted mt-2 text-center">
                {owner.preferred_payment_method} doesn't support pre-filled links — copy their info above and send it from your own {owner.preferred_payment_method} app.
              </p>
            )}
          </div>
        )}

        {/* Receipts */}
        {info.receipts.length > 0 && (
          <div className="bg-white rounded-xl border border-line mb-3 overflow-hidden">
            <button
              onClick={() => setShowReceipts(!showReceipts)}
              className="w-full flex items-center justify-between px-4 py-3"
            >
              <span className="text-[13px] font-semibold text-ink">
                {info.receipts.length} receipt{info.receipts.length === 1 ? "" : "s"}
              </span>
              {showReceipts ? <ChevronUp size={16} className="text-muted" /> : <ChevronDown size={16} className="text-muted" />}
            </button>
            {showReceipts && (
              <div className="border-t border-[#EDE9DC]">
                {info.receipts.map((r) => (
                  <div key={r.id} className="px-4 py-3 border-b border-[#EDE9DC] last:border-b-0">
                    <div className="flex items-center justify-between mb-0.5">
                      <span className="text-[13px] font-medium text-ink">{r.merchant}</span>
                      <span className="font-mono text-[13px] font-semibold text-ink">{money(r.owed)}</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-[11px] text-muted">{fmtDate(r.date)} · {r.items.map((i) => i.name).join(", ")}</span>
                      <span className={`text-[11px] font-medium ${r.remaining > 0.005 ? "text-owe" : "text-accent"}`}>
                        {r.remaining > 0.005 ? `${money(r.remaining)} due` : "Paid"}
                      </span>
                    </div>
                    {r.notes && (
                      <p className="text-[11px] text-[#7A5E24] bg-[#FBF3E6] rounded-lg px-2.5 py-1.5 mt-1.5">{r.notes}</p>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Edit info */}
        {saved ? (
          <div className="bg-white rounded-xl border border-line p-5 flex items-start gap-3">
            <CheckCircle2 size={20} className="text-accent shrink-0 mt-0.5" />
            <div>
              <p className="text-[14px] font-semibold text-ink">Saved</p>
              <p className="text-[13px] text-muted mt-0.5">Your info is all set. You can close this page.</p>
            </div>
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-line p-4">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Your name</p>
            <div className="flex gap-2 mb-4">
              <input
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                placeholder="First name"
                className="flex-1 rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40"
              />
              <input
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                placeholder="Last name"
                className="flex-1 rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40"
              />
            </div>

            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Your preferred payment method</p>
            <div className="flex flex-wrap gap-1.5 mb-3">
              {METHODS.map((m) => (
                <button
                  key={m}
                  onClick={() => setMethod(method === m ? null : m)}
                  className={`px-3 py-1.5 rounded-full text-[12px] font-medium border ${method === m ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}
                >
                  {m}
                </button>
              ))}
            </div>
            {method && method !== "Cash" && (
              <input
                value={handle}
                onChange={(e) => setHandle(e.target.value)}
                placeholder={method === "Venmo" ? "@venmo-username" : `${method} username or phone`}
                className="w-full rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40 mb-4"
              />
            )}
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Phone number (optional)</p>
            <input
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              type="tel"
              placeholder="(555) 555-5555"
              className="w-full rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40 mb-4"
            />
            <button
              onClick={save}
              disabled={saving}
              className="w-full rounded-xl bg-accent text-white font-semibold py-3 text-[14px] disabled:opacity-40"
            >
              {saving ? "Saving…" : "Save my info"}
            </button>
          </div>
        )}

        <p className="text-[11px] text-[#B4AEA0] text-center mt-8">Receipt Tracker</p>
      </div>
    </div>
  );
}
