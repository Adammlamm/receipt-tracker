import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/service";
import { computeReceiptShares, allocatePersonPayments } from "@/lib/split";
import { Receipt, Payment, PaymentMethod } from "@/lib/types";

const ALLOWED_METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash App", "Cash", "PayPal", "Other"];

async function loadOwnerReceiptsAndPayments(supabase: ReturnType<typeof createServiceClient>, userId: string) {
  const { data: receiptsRaw } = await supabase.from("receipts").select("*").eq("user_id", userId);
  const receiptIds = (receiptsRaw ?? []).map((r: any) => r.id);

  const { data: items } = receiptIds.length
    ? await supabase.from("receipt_items").select("*").in("receipt_id", receiptIds)
    : { data: [] };
  const itemIds = (items ?? []).map((i: any) => i.id);

  const { data: splits } = itemIds.length
    ? await supabase.from("item_splits").select("*").in("item_id", itemIds)
    : { data: [] };

  const { data: payments } = await supabase.from("payments").select("*").eq("user_id", userId);

  const receipts: Receipt[] = (receiptsRaw ?? []).map((r: any) => ({
    ...r,
    items: (items ?? [])
      .filter((i: any) => i.receipt_id === r.id)
      .map((i: any) => {
        const itemSplits = (splits ?? []).filter((s: any) => s.item_id === i.id);
        return {
          ...i,
          personIds: itemSplits.map((s: any) => s.person_id),
          personUnits: Object.fromEntries(itemSplits.map((s: any) => [s.person_id, s.units ?? 1])),
        };
      }),
  }));

  return { receipts, payments: (payments ?? []) as Payment[] };
}

export async function GET(request: Request, { params }: { params: { id: string } }) {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({ error: "This feature isn't fully configured yet." }, { status: 500 });
  }
  const supabase = createServiceClient();
  const personId = params.id;

  const { data: person } = await supabase.from("people").select("*").eq("id", personId).maybeSingle();
  if (!person) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  const { data: owner } = await supabase
    .from("people")
    .select("name, preferred_payment_method, payment_handle")
    .eq("user_id", person.user_id)
    .eq("is_self", true)
    .maybeSingle();

  const { receipts, payments } = await loadOwnerReceiptsAndPayments(supabase, person.user_id);
  const alloc = allocatePersonPayments(personId, receipts, payments);

  const receiptDetails = alloc.personReceipts.map(({ receipt, owed }) => {
    const myItems = (receipt.items ?? [])
      .filter((it) => it.personIds.includes(personId))
      .map((it) => ({ name: it.name, category: it.category }));
    return {
      id: receipt.id,
      merchant: receipt.merchant,
      date: receipt.date,
      category: receipt.category,
      owed,
      paid: alloc.paidMap[receipt.id] ?? 0,
      remaining: alloc.remainingMap[receipt.id] ?? 0,
      items: myItems,
    };
  });

  return NextResponse.json({
    name: person.name,
    preferred_payment_method: person.preferred_payment_method,
    payment_handle: person.payment_handle,
    phone_number: person.phone_number,
    totalOwed: alloc.totalOwed,
    totalPaid: alloc.totalPaid,
    totalRemaining: alloc.totalRemaining,
    receipts: receiptDetails,
    owner: owner ?? null,
  });
}

export async function POST(request: Request, { params }: { params: { id: string } }) {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({ error: "This feature isn't fully configured yet." }, { status: 500 });
  }
  const supabase = createServiceClient();
  const personId = params.id;

  const { data: existing } = await supabase.from("people").select("id").eq("id", personId).maybeSingle();
  if (!existing) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  const body = await request.json();
  // Explicit whitelist — never spread the raw body into an update.
  const update: Record<string, any> = {};
  if (typeof body.name === "string" && body.name.trim()) update.name = body.name.trim().slice(0, 100);
  if (body.preferred_payment_method === null || ALLOWED_METHODS.includes(body.preferred_payment_method)) {
    update.preferred_payment_method = body.preferred_payment_method;
  }
  if (typeof body.payment_handle === "string" || body.payment_handle === null) {
    update.payment_handle = body.payment_handle ? String(body.payment_handle).slice(0, 100) : null;
  }
  if (typeof body.phone_number === "string" || body.phone_number === null) {
    update.phone_number = body.phone_number ? String(body.phone_number).slice(0, 30) : null;
  }

  if (Object.keys(update).length === 0) {
    return NextResponse.json({ error: "nothing to update" }, { status: 400 });
  }

  const { error } = await supabase.from("people").update(update).eq("id", personId);
  if (error) {
    return NextResponse.json({ error: "save_failed" }, { status: 500 });
  }
  return NextResponse.json({ ok: true });
}
