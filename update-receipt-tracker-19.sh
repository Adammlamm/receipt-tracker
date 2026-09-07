#!/bin/bash
set -e
echo "Applying: friend page overhaul (balance, receipts, pay-back links, Cash App)..."
mkdir -p "app/friend/[id]" "app/api/friend/[id]"

mkdir -p $(dirname 'lib/types.ts')
cat > 'lib/types.ts' << 'FILEEOF'
export type Category = "Food" | "Drinks" | "Other";
export type TaxTipMethod = "proportional" | "equal";
export type PaymentMethod = "Venmo" | "Zelle" | "Apple Cash" | "Cash App" | "Cash" | "PayPal" | "Other";

export type ReceiptCategory = "Dining" | "Trips" | "Roommates/Home" | "Transportation" | "Other";

export interface Person {
  id: string;
  user_id: string;
  name: string;
  is_self: boolean;
  preferred_payment_method: PaymentMethod | null;
  payment_handle: string | null;
  phone_number: string | null;
  created_at: string;
}

export interface ReceiptItem {
  id: string;
  receipt_id: string;
  name: string;
  price: number;
  quantity: number;
  discount: number;
  category: Category;
  personIds: string[]; // hydrated from item_splits
  personUnits?: Record<string, number>; // portion weight per person, defaults to 1 each
}

export interface Group {
  id: string;
  user_id: string;
  name: string;
  memberIds: string[];
}

export interface Receipt {
  id: string;
  user_id: string;
  merchant: string;
  date: string; // ISO date
  subtotal: number;
  tax: number;
  tip: number;
  discount: number;
  total: number;
  tax_tip_method: TaxTipMethod;
  split_mode: "itemized" | "even";
  category: ReceiptCategory | null;
  image_path: string | null;
  image_mime: string | null;
  items: ReceiptItem[];
}

export interface Payment {
  id: string;
  user_id: string;
  person_id: string;
  receipt_id: string | null;
  amount: number;
  payment_date: string;
  payment_method: PaymentMethod;
}
FILEEOF

mkdir -p $(dirname 'lib/paymentLinks.ts')
cat > 'lib/paymentLinks.ts' << 'FILEEOF'
import { PaymentMethod } from "./types";

/**
 * Builds a pre-filled payment link for the methods that support it (Venmo, PayPal,
 * Cash App). Returns null for methods with no universal web link (Zelle is bank-specific
 * with no cross-bank URL scheme; Apple Cash has no public link at all) — the UI should
 * fall back to showing the handle to copy for those.
 */
export function buildPaymentLink(method: PaymentMethod, handle: string, amount: number, note: string): string | null {
  const clean = handle.trim().replace(/^[@$]/, "");
  if (!clean || amount <= 0) return null;
  const amt = amount.toFixed(2);

  switch (method) {
    case "Venmo":
      return `https://venmo.com/${encodeURIComponent(clean)}?txn=pay&amount=${amt}&note=${encodeURIComponent(note)}`;
    case "PayPal":
      return `https://paypal.me/${encodeURIComponent(clean)}/${amt}`;
    case "Cash App":
      return `https://cash.app/$${encodeURIComponent(clean)}/${amt}`;
    default:
      return null;
  }
}

export function supportsPaymentLink(method: PaymentMethod | null): boolean {
  return method === "Venmo" || method === "PayPal" || method === "Cash App";
}
FILEEOF

mkdir -p $(dirname 'lib/supabase/service.ts')
cat > 'lib/supabase/service.ts' << 'FILEEOF'
import { createClient as createSupabaseClient } from "@supabase/supabase-js";

/**
 * Service-role client — bypasses row-level security entirely.
 * ONLY import this from server-side code (Route Handlers), never from
 * a "use client" component. It's what lets the public /friend page compute
 * a specific person's balance without giving anonymous visitors broad
 * database access.
 */
export function createServiceClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );
}
FILEEOF

mkdir -p $(dirname 'lib/__tests__/split.test.ts')
cat > 'lib/__tests__/split.test.ts' << 'FILEEOF'
import { describe, it, expect } from "vitest";
import { computeReceiptShares, allocatePersonPayments } from "../split";
import { buildPaymentLink, supportsPaymentLink } from "../paymentLinks";
import type { Receipt, ReceiptItem, Payment } from "../types";

/** Minimal item factory so each test only states what it cares about. */
function item(overrides: Partial<ReceiptItem> & { personIds: string[] }): ReceiptItem {
  return {
    id: overrides.id ?? "item-1",
    receipt_id: "receipt-1",
    name: overrides.name ?? "Item",
    price: overrides.price ?? 0,
    quantity: overrides.quantity ?? 1,
    discount: overrides.discount ?? 0,
    category: overrides.category ?? "Food",
    personIds: overrides.personIds,
    personUnits: overrides.personUnits,
  };
}

/** Minimal receipt factory. */
function receipt(overrides: Partial<Receipt> & { items: ReceiptItem[] }): Receipt {
  return {
    id: overrides.id ?? "receipt-1",
    user_id: "user-1",
    merchant: overrides.merchant ?? "Test Merchant",
    date: overrides.date ?? "2026-01-01",
    subtotal: overrides.subtotal ?? 0,
    tax: overrides.tax ?? 0,
    tip: overrides.tip ?? 0,
    discount: overrides.discount ?? 0,
    total: overrides.total ?? 0,
    tax_tip_method: overrides.tax_tip_method ?? "proportional",
    split_mode: overrides.split_mode ?? "itemized",
    category: overrides.category ?? null,
    image_path: null,
    image_mime: null,
    items: overrides.items,
  };
}

function sumTotals(shares: Record<string, { total: number }>) {
  return Math.round(Object.values(shares).reduce((s, x) => s + x.total, 0) * 100) / 100;
}

describe("computeReceiptShares — itemized mode", () => {
  it("splits a single item evenly among its people", () => {
    const r = receipt({
      subtotal: 20,
      total: 20,
      items: [item({ price: 20, personIds: ["a", "b"] })],
    });
    const shares = computeReceiptShares(r);
    expect(shares.a.total).toBeCloseTo(10);
    expect(shares.b.total).toBeCloseTo(10);
  });

  it("allocates tax/tip proportionally to what each person ordered", () => {
    const r = receipt({
      subtotal: 30,
      tax: 3,
      tip: 6,
      total: 39,
      tax_tip_method: "proportional",
      items: [
        item({ id: "i1", price: 20, personIds: ["a"], category: "Food" }),
        item({ id: "i2", price: 10, personIds: ["b"], category: "Food" }),
      ],
    });
    const shares = computeReceiptShares(r);
    // a ordered 2/3 of the food, so should get 2/3 of the $9 tax+tip
    expect(shares.a.total).toBeCloseTo(20 + 6, 2);
    expect(shares.b.total).toBeCloseTo(10 + 3, 2);
    expect(sumTotals(shares)).toBeCloseTo(39, 2);
  });

  it("splits tax/tip equally when tax_tip_method is 'equal', regardless of what each person ordered", () => {
    const r = receipt({
      subtotal: 30,
      tax: 3,
      tip: 6,
      total: 39,
      tax_tip_method: "equal",
      items: [
        item({ id: "i1", price: 20, personIds: ["a"] }),
        item({ id: "i2", price: 10, personIds: ["b"] }),
      ],
    });
    const shares = computeReceiptShares(r);
    // tax+tip = $9, split equally two ways = $4.50 each, regardless of who ordered what
    expect(shares.a.taxTip).toBeCloseTo(4.5, 2);
    expect(shares.b.taxTip).toBeCloseTo(4.5, 2);
  });

  it("splits a shared item's cost by category (food/drinks/other)", () => {
    const r = receipt({
      subtotal: 30,
      total: 30,
      items: [
        item({ id: "i1", price: 20, personIds: ["a"], category: "Food" }),
        item({ id: "i2", price: 10, personIds: ["a"], category: "Drinks" }),
      ],
    });
    const shares = computeReceiptShares(r);
    expect(shares.a.food).toBeCloseTo(20);
    expect(shares.a.drinks).toBeCloseTo(10);
    expect(shares.a.other).toBeCloseTo(0);
  });

  it("weights a shared item by personUnits (the 'Shares' split mode)", () => {
    // e.g. 6 sojus: Lucy had 2, everyone else (4 people) had 1 each
    const r = receipt({
      subtotal: 90,
      total: 90,
      items: [
        item({
          price: 90,
          personIds: ["lucy", "a", "b", "c"],
          personUnits: { lucy: 2, a: 1, b: 1, c: 1 },
        }),
      ],
    });
    const shares = computeReceiptShares(r);
    expect(shares.lucy.total).toBeCloseTo(36); // 2/5 of 90
    expect(shares.a.total).toBeCloseTo(18); // 1/5 of 90
  });

  it("applies an item-level discount only to the people sharing that item (BOGO scenario)", () => {
    const r = receipt({
      subtotal: 40,
      total: 40,
      items: [
        // BOGO on this dish only benefits the two people who shared it
        item({ id: "i1", price: 20, discount: 10, personIds: ["a", "b"] }),
        // untouched item for a third person
        item({ id: "i2", price: 20, personIds: ["c"] }),
      ],
    });
    const shares = computeReceiptShares(r);
    expect(shares.a.total).toBeCloseTo(5); // (20-10)/2
    expect(shares.b.total).toBeCloseTo(5);
    expect(shares.c.total).toBeCloseTo(20); // untouched
  });

  it("subtracts a receipt-level discount proportionally, like tax/tip", () => {
    const r = receipt({
      subtotal: 100,
      discount: 20,
      total: 80,
      items: [
        item({ id: "i1", price: 60, personIds: ["a"] }),
        item({ id: "i2", price: 40, personIds: ["b"] }),
      ],
    });
    const shares = computeReceiptShares(r);
    expect(shares.a.total).toBeCloseTo(60 - 12); // a ordered 60% of subtotal -> 60% of the $20 discount
    expect(shares.b.total).toBeCloseTo(40 - 8);
    expect(sumTotals(shares)).toBeCloseTo(80, 2);
  });

  it("returns nothing for items with no one assigned yet", () => {
    const r = receipt({ items: [item({ price: 20, personIds: [] })] });
    expect(Object.keys(computeReceiptShares(r))).toHaveLength(0);
  });
});

describe("computeReceiptShares — whole-bill-evenly mode", () => {
  it("divides the receipt total evenly, independent of subtotal/tax/tip fields", () => {
    // Regression test: this mode used to divide `subtotal` instead of `total`,
    // so a receipt with only Total filled in (no Subtotal) split everyone to $0.
    const r = receipt({
      subtotal: 0,
      tax: 0,
      tip: 0,
      total: 217.18,
      split_mode: "even",
      items: [item({ price: 0, personIds: ["a", "b", "c", "d", "e", "f", "g"] })],
    });
    const shares = computeReceiptShares(r);
    expect(Object.keys(shares)).toHaveLength(7);
    expect(sumTotals(shares)).toBeCloseTo(217.18, 2);
    // every share should be close to 217.18/7 ≈ 31.03
    for (const pid of Object.keys(shares)) {
      expect(shares[pid].total).toBeGreaterThan(31);
      expect(shares[pid].total).toBeLessThan(31.1);
    }
  });

  it("splits evenly with a clean total", () => {
    const r = receipt({
      total: 100,
      split_mode: "even",
      items: [item({ personIds: ["a", "b", "c", "d"] })],
    });
    const shares = computeReceiptShares(r);
    expect(shares.a.total).toBe(25);
    expect(shares.b.total).toBe(25);
    expect(shares.c.total).toBe(25);
    expect(shares.d.total).toBe(25);
  });
});

describe("computeReceiptShares — penny-exact reconciliation", () => {
  it("always sums exactly to the total, even when it doesn't divide evenly", () => {
    // $10 split 3 ways = $3.333... each — a classic rounding trap
    const r = receipt({
      subtotal: 10,
      total: 10,
      items: [item({ price: 10, personIds: ["a", "b", "c"] })],
    });
    const shares = computeReceiptShares(r);
    expect(sumTotals(shares)).toBe(10);
    // each share should be 3.33 or 3.34, never anything else
    for (const pid of Object.keys(shares)) {
      expect([3.33, 3.34]).toContain(shares[pid].total);
    }
  });

  it("sums exactly across a large, awkward group and total", () => {
    const people = Array.from({ length: 11 }, (_, i) => `p${i}`);
    const r = receipt({
      subtotal: 137.77,
      total: 137.77,
      items: [item({ price: 137.77, personIds: people })],
    });
    const shares = computeReceiptShares(r);
    expect(sumTotals(shares)).toBe(137.77);
  });
});

describe("allocatePersonPayments", () => {
  const baseReceipt = receipt({
    id: "r1",
    date: "2026-01-01",
    subtotal: 100,
    total: 100,
    items: [item({ price: 100, personIds: ["a"] })],
  });

  function payment(overrides: Partial<Payment>): Payment {
    return {
      id: overrides.id ?? "p1",
      user_id: "user-1",
      person_id: overrides.person_id ?? "a",
      receipt_id: overrides.receipt_id ?? null,
      amount: overrides.amount ?? 0,
      payment_date: overrides.payment_date ?? "2026-01-02",
      payment_method: overrides.payment_method ?? "Venmo",
    };
  }

  it("shows the full amount owed when no payments have been made", () => {
    const alloc = allocatePersonPayments("a", [baseReceipt], []);
    expect(alloc.totalOwed).toBe(100);
    expect(alloc.totalRemaining).toBe(100);
    expect(alloc.totalPaid).toBe(0);
  });

  it("zeroes out the balance on a full payment", () => {
    const alloc = allocatePersonPayments("a", [baseReceipt], [payment({ amount: 100 })]);
    expect(alloc.totalRemaining).toBe(0);
    expect(alloc.totalPaid).toBe(100);
  });

  it("reduces the balance correctly on a partial payment", () => {
    const alloc = allocatePersonPayments("a", [baseReceipt], [payment({ amount: 40 })]);
    expect(alloc.totalRemaining).toBe(60);
  });

  it("applies a payment linked to a specific receipt only to that receipt", () => {
    const r2 = receipt({ id: "r2", date: "2026-01-05", subtotal: 50, total: 50, items: [item({ price: 50, personIds: ["a"] })] });
    const alloc = allocatePersonPayments("a", [baseReceipt, r2], [payment({ amount: 100, receipt_id: "r1" })]);
    expect(alloc.remainingMap.r1).toBe(0);
    expect(alloc.remainingMap.r2).toBe(50);
  });

  it("applies an unlinked (general) payment oldest-receipt-first", () => {
    const older = receipt({ id: "old", date: "2026-01-01", subtotal: 30, total: 30, items: [item({ price: 30, personIds: ["a"] })] });
    const newer = receipt({ id: "new", date: "2026-02-01", subtotal: 50, total: 50, items: [item({ price: 50, personIds: ["a"] })] });
    // $40 general payment: should fully cover the $30 older receipt, then $10 toward the newer one
    const alloc = allocatePersonPayments("a", [newer, older], [payment({ amount: 40 })]);
    expect(alloc.remainingMap.old).toBe(0);
    expect(alloc.remainingMap.new).toBe(40);
  });

  it("never reports a negative remaining balance from an overpayment", () => {
    const alloc = allocatePersonPayments("a", [baseReceipt], [payment({ amount: 150 })]);
    expect(alloc.remainingMap.r1).toBe(0);
  });
});

describe("buildPaymentLink", () => {
  it("builds a Venmo pay link with amount and note", () => {
    const url = buildPaymentLink("Venmo", "@adamlam", 42.5, "Receipt Tracker");
    expect(url).toBe("https://venmo.com/adamlam?txn=pay&amount=42.50&note=Receipt%20Tracker");
  });

  it("builds a PayPal.me link", () => {
    expect(buildPaymentLink("PayPal", "adamlam", 42.5, "x")).toBe("https://paypal.me/adamlam/42.50");
  });

  it("builds a Cash App cashtag link, normalizing a leading $", () => {
    expect(buildPaymentLink("Cash App", "$adamlam", 42.5, "x")).toBe("https://cash.app/$adamlam/42.50");
  });

  it("returns null for methods with no universal payment link", () => {
    expect(buildPaymentLink("Zelle", "adam@email.com", 42.5, "x")).toBeNull();
    expect(buildPaymentLink("Apple Cash", "555-1234", 42.5, "x")).toBeNull();
    expect(buildPaymentLink("Cash", "", 42.5, "x")).toBeNull();
  });

  it("returns null for a zero or negative amount", () => {
    expect(buildPaymentLink("Venmo", "@adamlam", 0, "x")).toBeNull();
  });

  it("reports which methods support pre-filled links", () => {
    expect(supportsPaymentLink("Venmo")).toBe(true);
    expect(supportsPaymentLink("PayPal")).toBe(true);
    expect(supportsPaymentLink("Cash App")).toBe(true);
    expect(supportsPaymentLink("Zelle")).toBe(false);
    expect(supportsPaymentLink("Apple Cash")).toBe(false);
    expect(supportsPaymentLink(null)).toBe(false);
  });
});
FILEEOF

mkdir -p $(dirname 'middleware.ts')
cat > 'middleware.ts' << 'FILEEOF'
import { createServerClient } from "@supabase/ssr";
import type { CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request: { headers: request.headers } });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          response.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          response.cookies.set({ name, value: "", ...options });
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const isAuthRoute = request.nextUrl.pathname.startsWith("/login") ||
    request.nextUrl.pathname.startsWith("/auth") ||
    request.nextUrl.pathname.startsWith("/friend") ||
    request.nextUrl.pathname.startsWith("/api/friend");

  if (!user && !isAuthRoute) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|manifest.json|icons).*)"],
};
FILEEOF

mkdir -p $(dirname 'app/api/friend/[id]/route.ts')
cat > 'app/api/friend/[id]/route.ts' << 'FILEEOF'
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
FILEEOF

mkdir -p $(dirname 'app/friend/[id]/page.tsx')
cat > 'app/friend/[id]/page.tsx' << 'FILEEOF'
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
}

interface FriendInfo {
  name: string;
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
  const personId = params.id as string;

  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [info, setInfo] = useState<FriendInfo | null>(null);

  const [name, setName] = useState("");
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
        const res = await fetch(`/api/friend/${personId}`);
        if (!res.ok) {
          setNotFound(true);
        } else {
          const data: FriendInfo = await res.json();
          setInfo(data);
          setName(data.name);
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
  }, [personId]);

  async function save() {
    setSaving(true);
    try {
      const res = await fetch(`/api/friend/${personId}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: name.trim() || undefined,
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
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40 mb-4"
            />

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
FILEEOF

mkdir -p $(dirname 'app/payments/new/page.tsx')
cat > 'app/payments/new/page.tsx' << 'FILEEOF'
"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { allocatePersonPayments } from "@/lib/split";
import { Person, Receipt, Payment, PaymentMethod } from "@/lib/types";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash App", "Cash", "PayPal", "Other"];

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

export default function RecordPaymentPage() {
  return (
    <Suspense fallback={null}>
      <RecordPaymentForm />
    </Suspense>
  );
}

function RecordPaymentForm() {
  const router = useRouter();
  const params = useSearchParams();
  const supabase = createClient();

  const [people, setPeople] = useState<Person[]>([]);
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [personId, setPersonId] = useState(params.get("personId") ?? "");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [method, setMethod] = useState<PaymentMethod>("Venmo");
  const [receiptId, setReceiptId] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    (async () => {
      const { data: p } = await supabase.from("people").select("*").order("name");
      const { data: pay } = await supabase.from("payments").select("*");
      const { data: r } = await supabase.from("receipts").select("*");
      const { data: items } = await supabase.from("receipt_items").select("*");
      const { data: splits } = await supabase.from("item_splits").select("*");
      setPeople((p ?? []).filter((person: any) => !person.is_self));
      setPayments(pay ?? []);
      setReceipts(
        (r ?? []).map((rec: any) => ({
          ...rec,
          items: (items ?? [])
            .filter((i: any) => i.receipt_id === rec.id)
            .map((i: any) => ({
              ...i,
              personIds: (splits ?? []).filter((s: any) => s.item_id === i.id).map((s: any) => s.person_id),
            })),
        }))
      );
      if (!personId && p && p[0]) setPersonId(p[0].id);
    })();
  }, []);

  const balance = useMemo(
    () => (personId ? allocatePersonPayments(personId, receipts, payments) : null),
    [personId, receipts, payments]
  );
  const receiptsWithBalance = (balance?.personReceipts ?? []).filter(
    (pr) => balance!.remainingMap[pr.receipt.id] > 0.005
  );

  async function save() {
    setSaving(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    await supabase.from("payments").insert({
      user_id: user.id,
      person_id: personId,
      amount: Number(amount),
      payment_date: date,
      payment_method: method,
      receipt_id: receiptId || null,
    });
    router.push("/payments");
    router.refresh();
  }

  return (
    <div className="px-5 pt-4">
      <div className="h-14 -mx-5 px-5 flex items-center border-b border-line mb-4">
        <button onClick={() => router.back()} className="text-[13px] text-muted">Back</button>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink pr-8">Record Payment</h1>
      </div>

      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Person</p>
      <div className="flex flex-wrap gap-1.5 mb-4">
        {people.map((p) => (
          <button
            key={p.id}
            onClick={() => {
              setPersonId(p.id);
              setReceiptId("");
            }}
            className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
              personId === p.id ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
            }`}
          >
            {p.name}
          </button>
        ))}
      </div>

      {balance && <p className="text-[12px] text-muted -mt-2 mb-4">Currently owes {money(balance.totalRemaining)}</p>}

      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Amount</p>
      <input
        inputMode="decimal"
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        placeholder="0.00"
        className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4"
      />

      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Date</p>
      <input
        type="date"
        value={date}
        onChange={(e) => setDate(e.target.value)}
        className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4"
      />

      <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Payment method</p>
      <div className="flex flex-wrap gap-1.5 mb-4">
        {METHODS.map((m) => (
          <button
            key={m}
            onClick={() => setMethod(m)}
            className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
              method === m ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
            }`}
          >
            {m}
          </button>
        ))}
      </div>

      {receiptsWithBalance.length > 0 && (
        <>
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">
            Apply to a specific receipt (optional)
          </p>
          <div className="flex flex-wrap gap-1.5 mb-5">
            <button
              onClick={() => setReceiptId("")}
              className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
                receiptId === "" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
              }`}
            >
              General payment
            </button>
            {receiptsWithBalance.map(({ receipt }) => (
              <button
                key={receipt.id}
                onClick={() => setReceiptId(receipt.id)}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
                  receiptId === receipt.id ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
                }`}
              >
                {receipt.merchant}
              </button>
            ))}
          </div>
        </>
      )}

      <button
        onClick={save}
        disabled={!personId || !(Number(amount) > 0) || saving}
        className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-8 disabled:opacity-40"
      >
        Save payment
      </button>
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/people/[id]/PersonActions.tsx')
cat > 'app/people/[id]/PersonActions.tsx' << 'FILEEOF'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Pencil, Trash2, Check, X, Merge, Share2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Person, PaymentMethod } from "@/lib/types";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash App", "Cash", "PayPal", "Other"];

export default function PersonActions({ person, allPeople }: { person: Person; allPeople: Person[] }) {
  const router = useRouter();
  const supabase = createClient();
  const [editingName, setEditingName] = useState(false);
  const [name, setName] = useState(person.name);
  const [method, setMethod] = useState<PaymentMethod | null>(person.preferred_payment_method);
  const [handle, setHandle] = useState(person.payment_handle || "");
  const [phone, setPhone] = useState(person.phone_number || "");
  const [saving, setSaving] = useState(false);
  const [merging, setMerging] = useState(false);
  const [mergeTargetId, setMergeTargetId] = useState<string>("");
  const [mergeBusy, setMergeBusy] = useState(false);
  const [linkCopied, setLinkCopied] = useState(false);

  const otherPeople = allPeople.filter((p) => p.id !== person.id);

  async function shareLink() {
    const url = `${window.location.origin}/friend/${person.id}`;
    if (navigator.share) {
      try {
        await navigator.share({ title: "Add your payment info", text: `Hey — add your Venmo/Zelle so I know how to pay you back:`, url });
      } catch (e) {
        // user cancelled the share sheet — not an error
      }
    } else {
      await navigator.clipboard.writeText(url);
      setLinkCopied(true);
      setTimeout(() => setLinkCopied(false), 2000);
    }
  }

  async function saveName() {
    if (!name.trim()) return;
    await supabase.from("people").update({ name: name.trim() }).eq("id", person.id);
    setEditingName(false);
    router.refresh();
  }

  async function savePaymentInfo() {
    setSaving(true);
    await supabase.from("people").update({ preferred_payment_method: method, payment_handle: handle.trim() || null, phone_number: phone.trim() || null }).eq("id", person.id);
    setSaving(false);
    router.refresh();
  }

  async function deletePerson() {
    if (!confirm(`Delete ${person.name}? This also removes their item assignments and payment history.`)) return;
    await supabase.from("people").delete().eq("id", person.id);
    router.push("/people");
    router.refresh();
  }

  async function mergeInto() {
    const target = otherPeople.find((p) => p.id === mergeTargetId);
    if (!target) return;
    if (!confirm(`Merge ${person.name} into ${target.name}? All their item assignments and payment history move to ${target.name}, and ${person.name} is removed. This can't be undone.`)) {
      return;
    }
    setMergeBusy(true);
    try {
      // Reassign item_splits, combining shares when both people already had a split on the same item
      // (the (item_id, person_id) unique constraint means we can't just blindly reassign).
      const { data: sourceSplits } = await supabase.from("item_splits").select("*").eq("person_id", person.id);
      for (const split of sourceSplits ?? []) {
        const { data: existing } = await supabase
          .from("item_splits")
          .select("*")
          .eq("item_id", split.item_id)
          .eq("person_id", target.id)
          .maybeSingle();
        if (existing) {
          await supabase
            .from("item_splits")
            .update({ units: (existing.units ?? 1) + (split.units ?? 1) })
            .eq("item_id", split.item_id)
            .eq("person_id", target.id);
          await supabase.from("item_splits").delete().eq("item_id", split.item_id).eq("person_id", person.id);
        } else {
          await supabase.from("item_splits").update({ person_id: target.id }).eq("item_id", split.item_id).eq("person_id", person.id);
        }
      }

      // Reassign payments outright — no collision risk, payments aren't unique per person.
      await supabase.from("payments").update({ person_id: target.id }).eq("person_id", person.id);

      // Reassign group memberships, same collision handling as item_splits.
      const { data: sourceGroups } = await supabase.from("group_members").select("*").eq("person_id", person.id);
      for (const gm of sourceGroups ?? []) {
        const { data: existingGm } = await supabase
          .from("group_members")
          .select("*")
          .eq("group_id", gm.group_id)
          .eq("person_id", target.id)
          .maybeSingle();
        if (!existingGm) {
          await supabase.from("group_members").update({ person_id: target.id }).eq("group_id", gm.group_id).eq("person_id", person.id);
        } else {
          await supabase.from("group_members").delete().eq("group_id", gm.group_id).eq("person_id", person.id);
        }
      }

      await supabase.from("people").delete().eq("id", person.id);
      router.push(`/people/${target.id}`);
      router.refresh();
    } catch (e) {
      console.error("merge failed", e);
      alert("Something went wrong merging — nothing was changed. Try again.");
    } finally {
      setMergeBusy(false);
    }
  }

  return (
    <div className="mb-6">
      <div className="flex items-center gap-2 mb-1 flex-wrap">
        {editingName ? (
          <>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="flex-1 rounded-lg border border-line bg-white px-2.5 py-1.5 text-[14px] outline-none"
              autoFocus
            />
            <button onClick={saveName} className="p-1.5 rounded-full bg-accent text-white"><Check size={14} /></button>
            <button onClick={() => { setEditingName(false); setName(person.name); }} className="p-1.5 rounded-full bg-[#F0EDE1]"><X size={14} className="text-muted" /></button>
          </>
        ) : (
          <>
            <button onClick={() => setEditingName(true)} className="flex items-center gap-1 text-[12px] text-muted">
              <Pencil size={12} /> Rename
            </button>
            <span className="text-[12px] text-[#D8D3C4]">·</span>
            {otherPeople.length > 0 && (
              <>
                <button onClick={() => setMerging(!merging)} className="flex items-center gap-1 text-[12px] text-muted">
                  <Merge size={12} /> Merge into…
                </button>
                <span className="text-[12px] text-[#D8D3C4]">·</span>
              </>
            )}
            <button onClick={deletePerson} className="flex items-center gap-1 text-[12px] text-owe">
              <Trash2 size={12} /> Delete
            </button>
          </>
        )}
      </div>

      {merging && (
        <div className="bg-white rounded-xl border border-line p-3.5 mt-2 mb-1">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">
            Merge {person.name} into…
          </p>
          <div className="flex flex-wrap gap-1.5 mb-3">
            {otherPeople.map((p) => (
              <button
                key={p.id}
                onClick={() => setMergeTargetId(p.id)}
                className={`px-3 py-1.5 rounded-full text-[12px] font-medium border ${mergeTargetId === p.id ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}
              >
                {p.name}
              </button>
            ))}
          </div>
          <button
            onClick={mergeInto}
            disabled={!mergeTargetId || mergeBusy}
            className="text-[12px] font-semibold text-owe disabled:opacity-40"
          >
            {mergeBusy ? "Merging…" : "Merge and delete this person"}
          </button>
        </div>
      )}

      {!person.is_self && (
        <button
          onClick={shareLink}
          className="w-full flex items-center justify-center gap-1.5 rounded-xl border border-line bg-white py-2.5 text-[13px] font-semibold text-accent mt-3"
        >
          <Share2 size={14} /> {linkCopied ? "Link copied!" : `Send ${person.name} a link to add their info`}
        </button>
      )}

      <div className="bg-white rounded-xl border border-line p-3.5 mt-3">
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
            placeholder={method === "Venmo" ? "@venmo-username" : method === "Apple Cash" || method === "Other" ? "Phone or details" : `${method} username or phone`}
            className="w-full rounded-lg border border-line bg-white px-3 py-2 text-[13px] outline-none focus:ring-2 focus:ring-accent/40 mb-3"
          />
        )}
        <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Phone number</p>
        <input
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          type="tel"
          placeholder="(555) 555-5555"
          className="w-full rounded-lg border border-line bg-white px-3 py-2 text-[13px] outline-none focus:ring-2 focus:ring-accent/40 mb-3"
        />
        <button onClick={savePaymentInfo} disabled={saving} className="text-[12px] font-semibold text-accent">
          {saving ? "Saving…" : "Save"}
        </button>
      </div>
    </div>
  );
}
FILEEOF

echo "Files updated. Running tests..."
npm test
echo "Now run: git add . && git commit -m \"Add friend balance view, receipts, pay-back links, Cash App\" && git push"
