"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Plus, Check } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

export default function AddPersonForm() {
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);
  const router = useRouter();
  const supabase = createClient();

  async function submit() {
    if (!name.trim()) return;
    setSaving(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    await supabase.from("people").insert({ user_id: user.id, name: name.trim() });
    setName("");
    setSaving(false);
    router.refresh();
  }

  return (
    <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2">
      <input
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Add a person…"
        className="flex-1 text-[14px] outline-none px-1.5"
        onKeyDown={(e) => e.key === "Enter" && submit()}
      />
      <button
        onClick={submit}
        disabled={saving}
        className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold flex items-center gap-1"
      >
        {saving ? <Check size={14} /> : <Plus size={14} />} Add
      </button>
    </div>
  );
}
