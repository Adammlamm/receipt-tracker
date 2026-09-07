"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { CheckCircle2, Receipt } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { PaymentMethod } from "@/lib/types";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash", "PayPal", "Other"];

export default function FriendPage() {
  const params = useParams();
  const personId = params.id as string;
  const supabase = createClient();

  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [name, setName] = useState("");
  const [method, setMethod] = useState<PaymentMethod | null>(null);
  const [handle, setHandle] = useState("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    (async () => {
      const { data, error } = await supabase.rpc("get_person_public_info", { p_id: personId });
      const row = Array.isArray(data) ? data[0] : data;
      if (error || !row) {
        setNotFound(true);
      } else {
        setName(row.name);
        setMethod(row.preferred_payment_method ?? null);
        setHandle(row.payment_handle ?? "");
      }
      setLoading(false);
    })();
  }, [personId]);

  async function save() {
    setSaving(true);
    const { error } = await supabase.rpc("update_person_payment_info", {
      p_id: personId,
      p_method: method,
      p_handle: handle.trim() || null,
    });
    setSaving(false);
    if (!error) setSaved(true);
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-paper flex items-center justify-center">
        <p className="text-[13px] text-muted">Loading…</p>
      </div>
    );
  }

  if (notFound) {
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

  return (
    <div className="min-h-screen bg-paper">
      <div className="max-w-md mx-auto px-6 pt-10 pb-10">
        <div className="w-11 h-11 rounded-full bg-[#EFF7F3] flex items-center justify-center mb-4">
          <Receipt size={20} className="text-accent" />
        </div>
        <h1 className="text-[19px] font-semibold text-ink mb-1">Hi {name} 👋</h1>
        <p className="text-[13px] text-muted mb-6">
          Let them know how you'd like to get paid back when it's time to settle up.
        </p>

        {saved ? (
          <div className="bg-white rounded-xl border border-line p-5 flex items-start gap-3">
            <CheckCircle2 size={20} className="text-accent shrink-0 mt-0.5" />
            <div>
              <p className="text-[14px] font-semibold text-ink">Saved</p>
              <p className="text-[13px] text-muted mt-0.5">Your payment info is all set. You can close this page.</p>
            </div>
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-line p-4">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Preferred payment method</p>
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
            <button
              onClick={save}
              disabled={saving}
              className="w-full rounded-xl bg-accent text-white font-semibold py-3 text-[14px] disabled:opacity-40"
            >
              {saving ? "Saving…" : "Save"}
            </button>
          </div>
        )}

        <p className="text-[11px] text-[#B4AEA0] text-center mt-8">Receipt Tracker</p>
      </div>
    </div>
  );
}
