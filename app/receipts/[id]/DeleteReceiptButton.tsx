"use client";

import { useRouter } from "next/navigation";
import { Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

export default function DeleteReceiptButton({ receiptId, imagePath }: { receiptId: string; imagePath: string | null }) {
  const router = useRouter();
  const supabase = createClient();

  async function handleDelete() {
    if (!confirm("Delete this receipt? This can't be undone.")) return;
    if (imagePath) await supabase.storage.from("receipts").remove([imagePath]);
    await supabase.from("receipts").delete().eq("id", receiptId);
    router.push("/receipts");
    router.refresh();
  }

  return (
    <button onClick={handleDelete} className="p-1">
      <Trash2 size={17} className="text-owe" />
    </button>
  );
}
