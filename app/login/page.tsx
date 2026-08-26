"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const supabase = createClient();

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    });
    if (error) setError(error.message);
    else setSent(true);
  }

  return (
    <div className="min-h-screen bg-paper flex items-center justify-center px-6">
      <div className="w-full max-w-sm">
        <h1 className="text-2xl font-semibold text-ink mb-1">Receipt Tracker</h1>
        <p className="text-sm text-muted mb-6">Sign in with a magic link — no password needed.</p>

        {sent ? (
          <p className="text-sm text-accent bg-white border border-line rounded-xl p-4">
            Check {email} for a sign-in link.
          </p>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-3">
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40"
            />
            <button
              type="submit"
              className="w-full rounded-xl bg-accent text-white font-semibold py-3.5"
            >
              Send magic link
            </button>
            {error && <p className="text-sm text-owe">{error}</p>}
          </form>
        )}
      </div>
    </div>
  );
}
