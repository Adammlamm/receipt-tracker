import { createClient } from "@/lib/supabase/server";
import { Person, Receipt, Payment, Group } from "@/lib/types";

export async function loadGroups(): Promise<Group[]> {
  const supabase = createClient();
  const { data: groups } = await supabase.from("groups").select("*").order("name");
  if (!groups || groups.length === 0) return [];

  const { data: members } = await supabase
    .from("group_members")
    .select("*")
    .in("group_id", groups.map((g) => g.id));

  return groups.map((g) => ({
    ...g,
    memberIds: (members ?? []).filter((m) => m.group_id === g.id).map((m) => m.person_id),
  }));
}

export async function loadPeople(): Promise<Person[]> {
  const supabase = createClient();
  const { data } = await supabase.from("people").select("*").order("name");
  return data ?? [];
}

export async function loadPayments(): Promise<Payment[]> {
  const supabase = createClient();
  const { data } = await supabase
    .from("payments")
    .select("*")
    .order("payment_date", { ascending: false });
  return data ?? [];
}

/** Fetches all receipts for the signed-in user, each hydrated with items + who split them. */
export async function loadReceipts(): Promise<Receipt[]> {
  const supabase = createClient();

  const { data: receipts } = await supabase
    .from("receipts")
    .select("*")
    .order("date", { ascending: false });

  if (!receipts || receipts.length === 0) return [];

  const receiptIds = receipts.map((r) => r.id);

  const { data: items } = await supabase
    .from("receipt_items")
    .select("*")
    .in("receipt_id", receiptIds);

  const itemIds = (items ?? []).map((i) => i.id);

  const { data: splits } = itemIds.length
    ? await supabase.from("item_splits").select("*").in("item_id", itemIds)
    : { data: [] };

  return receipts.map((r) => ({
    ...r,
    items: (items ?? [])
      .filter((i) => i.receipt_id === r.id)
      .map((i) => ({
        ...i,
        personIds: (splits ?? []).filter((s) => s.item_id === i.id).map((s) => s.person_id),
      })),
  }));
}

export async function loadReceipt(id: string): Promise<Receipt | null> {
  const supabase = createClient();
  const { data: receipt } = await supabase.from("receipts").select("*").eq("id", id).single();
  if (!receipt) return null;

  const { data: items } = await supabase.from("receipt_items").select("*").eq("receipt_id", id);
  const itemIds = (items ?? []).map((i) => i.id);
  const { data: splits } = itemIds.length
    ? await supabase.from("item_splits").select("*").in("item_id", itemIds)
    : { data: [] };

  return {
    ...receipt,
    items: (items ?? []).map((i) => ({
      ...i,
      personIds: (splits ?? []).filter((s) => s.item_id === i.id).map((s) => s.person_id),
    })),
  };
}

/** The "receipts" storage bucket is private, so image URLs must be signed. */
export async function receiptImageUrl(path: string | null): Promise<string | null> {
  if (!path) return null;
  const supabase = createClient();
  const { data } = await supabase.storage.from("receipts").createSignedUrl(path, 60 * 60);
  return data?.signedUrl ?? null;
}
