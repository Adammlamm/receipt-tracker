#!/bin/bash
set -e
echo "Applying: customizable reminder message template with placeholders..."

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
  first_name: string | null;
  last_name: string | null;
  is_self: boolean;
  preferred_payment_method: PaymentMethod | null;
  payment_handle: string | null;
  phone_number: string | null;
  reminder_template: string | null;
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

export const DEFAULT_REMINDER_TEMPLATE_WITH_METHOD =
  "Hi {name}! Just a reminder — you owe {amount} for {receipt}. You can send it via {method}: {handle}. Details: {link}";
export const DEFAULT_REMINDER_TEMPLATE_NO_METHOD =
  "Hi {name}! Just a reminder — you owe {amount} for {receipt}. Details: {link}";

export const REMINDER_PLACEHOLDERS = [
  { key: "{name}", label: "Their first name" },
  { key: "{amount}", label: "Total they owe" },
  { key: "{receipt}", label: "Which receipt(s)" },
  { key: "{method}", label: "Your payment method (e.g. Venmo)" },
  { key: "{handle}", label: "Your handle for that method" },
  { key: "{their_method}", label: "The payment app they said they prefer" },
  { key: "{link}", label: "Link to their personal balance page" },
] as const;

/**
 * Builds a pre-filled text message reminding someone what they owe, using either a
 * custom template (with {placeholder} substitution) or a smart default that omits
 * the payment-method sentence entirely when you haven't set one.
 * Uses both `?body=` and `&body=` since Android and iOS read different ones —
 * including both is the documented way to cover both without detecting the platform.
 */
export function buildReminderSmsLink(params: {
  phone: string;
  friendFirstName: string;
  totalRemaining: number;
  receiptSummary: string; // e.g. "King Pocha (Jul 10)" or "3 receipts"
  ownerMethod: PaymentMethod | null;
  ownerHandle: string | null;
  friendPreferredMethod?: PaymentMethod | null;
  friendLink: string;
  template?: string | null;
}): string {
  const { phone, friendFirstName, totalRemaining, receiptSummary, ownerMethod, ownerHandle, friendPreferredMethod, friendLink, template } = params;
  const amount = totalRemaining.toLocaleString("en-US", { style: "currency", currency: "USD" });

  const effectiveTemplate =
    template?.trim() || (ownerMethod && ownerHandle ? DEFAULT_REMINDER_TEMPLATE_WITH_METHOD : DEFAULT_REMINDER_TEMPLATE_NO_METHOD);

  const message = effectiveTemplate
    .replaceAll("{name}", friendFirstName)
    .replaceAll("{amount}", amount)
    .replaceAll("{receipt}", receiptSummary)
    .replaceAll("{method}", ownerMethod ?? "")
    .replaceAll("{handle}", ownerHandle ?? "")
    .replaceAll("{their_method}", friendPreferredMethod ?? "")
    .replaceAll("{link}", friendLink);

  const digitsOnly = phone.replace(/[^\d+]/g, "");
  const cleanPhone = digitsOnly.length === 10 ? `+1${digitsOnly}` : digitsOnly;
  const encoded = encodeURIComponent(message);
  return `sms:${cleanPhone}?body=${encoded}&body=${encoded}`;
}
FILEEOF

mkdir -p $(dirname 'lib/__tests__/split.test.ts')
cat > 'lib/__tests__/split.test.ts' << 'FILEEOF'
import { describe, it, expect } from "vitest";
import { computeReceiptShares, allocatePersonPayments } from "../split";
import { buildPaymentLink, supportsPaymentLink, buildReminderSmsLink } from "../paymentLinks";
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

describe("buildReminderSmsLink", () => {
  it("includes both body= separators so it works on iOS and Android", () => {
    const url = buildReminderSmsLink({
      phone: "(555) 123-4567",
      friendFirstName: "Joseph",
      totalRemaining: 42.12,
      receiptSummary: "King Pocha (Jul 10)",
      ownerMethod: "Venmo",
      ownerHandle: "@adamlam",
      friendLink: "https://example.com/friend/abc",
    });
    expect(url.startsWith("sms:+15551234567?body=")).toBe(true);
    expect((url.match(/body=/g) || []).length).toBe(2);
  });

  it("strips non-digit characters and adds a US country code for 10-digit numbers", () => {
    const url = buildReminderSmsLink({
      phone: "555.123.4567",
      friendFirstName: "A",
      totalRemaining: 10,
      receiptSummary: "x",
      ownerMethod: null,
      ownerHandle: null,
      friendLink: "https://x.com",
    });
    expect(url.startsWith("sms:+15551234567?")).toBe(true);
  });

  it("mentions the payment method and handle when the owner has one set", () => {
    const url = buildReminderSmsLink({
      phone: "5551234567",
      friendFirstName: "Joseph",
      totalRemaining: 42.12,
      receiptSummary: "King Pocha (Jul 10)",
      ownerMethod: "Venmo",
      ownerHandle: "@adamlam",
      friendLink: "https://example.com/friend/abc",
    });
    const decoded = decodeURIComponent(url);
    expect(decoded).toContain("Venmo");
    expect(decoded).toContain("@adamlam");
    expect(decoded).toContain("$42.12");
  });

  it("omits the payment method sentence when the owner hasn't set one", () => {
    const url = buildReminderSmsLink({
      phone: "5551234567",
      friendFirstName: "Joseph",
      totalRemaining: 42.12,
      receiptSummary: "King Pocha (Jul 10)",
      ownerMethod: null,
      ownerHandle: null,
      friendLink: "https://example.com/friend/abc",
    });
    const decoded = decodeURIComponent(url);
    expect(decoded).not.toContain("send it via");
  });

  it("uses a custom template and substitutes every placeholder", () => {
    const url = buildReminderSmsLink({
      phone: "5551234567",
      friendFirstName: "Joseph",
      totalRemaining: 42.12,
      receiptSummary: "King Pocha (Jul 10)",
      ownerMethod: "Venmo",
      ownerHandle: "@adamlam",
      friendPreferredMethod: "Zelle",
      friendLink: "https://example.com/friend/abc",
      template: "yo {name}, you owe {amount} for {receipt}. hit me on {method} ({handle}) — I know you're usually on {their_method} tho. info: {link}",
    });
    const decoded = decodeURIComponent(url);
    expect(decoded).toContain(
      "yo Joseph, you owe $42.12 for King Pocha (Jul 10). hit me on Venmo (@adamlam) — I know you're usually on Zelle tho. info: https://example.com/friend/abc"
    );
  });

  it("leaves a placeholder as an empty string if the underlying value is missing", () => {
    const url = buildReminderSmsLink({
      phone: "5551234567",
      friendFirstName: "Joseph",
      totalRemaining: 42.12,
      receiptSummary: "x",
      ownerMethod: null,
      ownerHandle: null,
      friendLink: "https://x.com",
      template: "Pay via {method}: {handle}",
    });
    const decoded = decodeURIComponent(url);
    expect(decoded).toContain("Pay via : ");
  });
});
FILEEOF

mkdir -p $(dirname 'app/people/[id]/page.tsx')
cat > 'app/people/[id]/page.tsx' << 'FILEEOF'
import { headers } from "next/headers";
import Link from "next/link";
import { MessageCircle } from "lucide-react";
import { loadPeople, loadReceipts, loadPayments } from "@/lib/data";
import { allocatePersonPayments } from "@/lib/split";
import { buildReminderSmsLink } from "@/lib/paymentLinks";
import BottomNav from "@/components/BottomNav";
import PersonActions from "./PersonActions";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}
function fmtDate(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export default async function PersonDetailPage({ params }: { params: { id: string } }) {
  const [people, receipts, payments] = await Promise.all([loadPeople(), loadReceipts(), loadPayments()]);
  const person = people.find((p) => p.id === params.id);
  if (!person) return <p className="p-5 text-muted text-sm">Person not found.</p>;

  const alloc = allocatePersonPayments(person.id, receipts, payments);
  const { personReceipts, remainingMap, totalRemaining } = alloc;

  const owner = people.find((p) => p.is_self);
  const host = headers().get("host");
  const friendLink = host ? `https://${host}/friend/${person.id}` : "";

  const unpaidReceipts = personReceipts.filter(({ receipt }) => remainingMap[receipt.id] > 0.005);
  const receiptSummary =
    unpaidReceipts.length === 1
      ? `${unpaidReceipts[0].receipt.merchant} (${fmtDate(unpaidReceipts[0].receipt.date)})`
      : `${unpaidReceipts.length} receipts`;

  const reminderLink =
    person.phone_number && totalRemaining > 0.005 && friendLink
      ? buildReminderSmsLink({
          phone: person.phone_number,
          friendFirstName: person.first_name || person.name,
          totalRemaining,
          receiptSummary,
          ownerMethod: owner?.preferred_payment_method ?? null,
          ownerHandle: owner?.payment_handle ?? null,
          friendPreferredMethod: person.preferred_payment_method,
          friendLink,
          template: owner?.reminder_template ?? null,
        })
      : null;

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Link href="/people" className="text-[13px] text-muted">Back</Link>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink truncate px-2">{person.name}</h1>
        <div className="w-9" />
      </div>

      <div className="px-5 pt-5">
        {person.is_self ? (
          <div className="mb-6">
            <span className="text-[11px] font-semibold text-accent bg-[#EFF7F3] px-2 py-1 rounded-full">This is you</span>
            <p className="text-[13px] text-muted mt-2">You don't owe yourself — your share of receipts is already excluded from totals.</p>
          </div>
        ) : (
          <>
            <p className="text-[12px] text-muted">Total outstanding</p>
            <p className={`font-mono text-[26px] font-semibold mb-6 ${totalRemaining > 0.005 ? "text-owe" : "text-accent"}`}>
              {money(totalRemaining)}
            </p>

            <Link
              href={`/payments/new?personId=${person.id}`}
              className="block text-center rounded-xl bg-accent text-white font-semibold py-3.5 mb-3"
            >
              Record payment
            </Link>

            {reminderLink ? (
              <a
                href={reminderLink}
                className="flex items-center justify-center gap-1.5 rounded-xl border border-line bg-white text-ink font-semibold py-3 text-[14px] mb-7"
              >
                <MessageCircle size={16} /> Text {person.first_name || person.name} a reminder
              </a>
            ) : totalRemaining > 0.005 ? (
              <p className="text-[12px] text-muted text-center mb-7">
                Add {person.first_name || person.name}'s phone number below to send a text reminder.
              </p>
            ) : (
              <div className="mb-7" />
            )}
          </>
        )}

        <PersonActions person={person} allPeople={people} />

        <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Receipts</p>
        <div className="space-y-2 mb-8">
          {personReceipts.length === 0 && <p className="text-[13px] text-muted">No receipts yet.</p>}
          {personReceipts.map(({ receipt, owed }) => (
            <Link
              key={receipt.id}
              href={`/receipts/${receipt.id}`}
              className="block bg-white rounded-xl border border-line px-4 py-3"
            >
              <div className="flex items-center justify-between mb-1">
                <span className="text-[14px] font-medium text-ink">{receipt.merchant}</span>
                <span className="font-mono text-[14px] font-semibold text-ink">{money(owed)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-[11px] text-muted">{fmtDate(receipt.date)}</span>
                <span className={`text-[11px] font-medium ${remainingMap[receipt.id] > 0.005 ? "text-owe" : "text-accent"}`}>
                  {remainingMap[receipt.id] > 0.005 ? `${money(remainingMap[receipt.id])} due` : "Paid"}
                </span>
              </div>
            </Link>
          ))}
        </div>
      </div>

      <BottomNav />
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/people/[id]/PersonActions.tsx')
cat > 'app/people/[id]/PersonActions.tsx' << 'FILEEOF'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Pencil, Trash2, Check, X, Merge, Share2, MessageCircle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Person, PaymentMethod } from "@/lib/types";
import { DEFAULT_REMINDER_TEMPLATE_WITH_METHOD, REMINDER_PLACEHOLDERS } from "@/lib/paymentLinks";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash App", "Cash", "PayPal", "Other"];

export default function PersonActions({ person, allPeople }: { person: Person; allPeople: Person[] }) {
  const router = useRouter();
  const supabase = createClient();
  const [editingName, setEditingName] = useState(false);
  const [firstName, setFirstName] = useState(person.first_name || person.name);
  const [lastName, setLastName] = useState(person.last_name || "");
  const [method, setMethod] = useState<PaymentMethod | null>(person.preferred_payment_method);
  const [handle, setHandle] = useState(person.payment_handle || "");
  const [phone, setPhone] = useState(person.phone_number || "");
  const [template, setTemplate] = useState(person.reminder_template || "");
  const [templateSaved, setTemplateSaved] = useState(false);
  const [saving, setSaving] = useState(false);
  const [merging, setMerging] = useState(false);
  const [mergeTargetId, setMergeTargetId] = useState<string>("");
  const [mergeBusy, setMergeBusy] = useState(false);
  const [linkCopied, setLinkCopied] = useState(false);

  const otherPeople = allPeople.filter((p) => p.id !== person.id);

  async function saveTemplate() {
    await supabase.from("people").update({ reminder_template: template.trim() || null }).eq("id", person.id);
    setTemplateSaved(true);
    setTimeout(() => setTemplateSaved(false), 2000);
    router.refresh();
  }

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
    if (!firstName.trim()) return;
    const fullName = `${firstName.trim()} ${lastName.trim()}`.trim();
    await supabase.from("people").update({ name: fullName, first_name: firstName.trim(), last_name: lastName.trim() }).eq("id", person.id);
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
          <div className="w-full bg-white rounded-xl border border-line p-3 mb-1">
            <div className="flex gap-2 mb-2">
              <input
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                placeholder="First name"
                className="flex-1 rounded-lg border border-line px-2.5 py-1.5 text-[14px] outline-none"
                autoFocus
              />
              <input
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                placeholder="Last name"
                className="flex-1 rounded-lg border border-line px-2.5 py-1.5 text-[14px] outline-none"
              />
            </div>
            <div className="flex gap-2">
              <button onClick={saveName} className="flex-1 rounded-lg bg-accent text-white text-[13px] font-semibold py-1.5 flex items-center justify-center gap-1">
                <Check size={14} /> Save
              </button>
              <button
                onClick={() => {
                  setEditingName(false);
                  setFirstName(person.first_name || person.name);
                  setLastName(person.last_name || "");
                }}
                className="px-3 rounded-lg bg-[#F0EDE1] text-[13px] font-semibold"
              >
                <X size={14} className="text-muted" />
              </button>
            </div>
          </div>
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

      {person.is_self && (
        <div className="bg-white rounded-xl border border-line p-3.5 mt-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5 flex items-center gap-1.5">
            <MessageCircle size={12} /> Reminder text message
          </p>
          <p className="text-[11px] text-muted mb-2">Customize the wording — tap a placeholder to add it.</p>
          <textarea
            value={template}
            onChange={(e) => setTemplate(e.target.value)}
            placeholder={DEFAULT_REMINDER_TEMPLATE_WITH_METHOD}
            rows={4}
            className="w-full rounded-lg border border-line bg-white px-3 py-2 text-[13px] outline-none focus:ring-2 focus:ring-accent/40 mb-2"
          />
          <div className="flex flex-wrap gap-1.5 mb-3">
            {REMINDER_PLACEHOLDERS.map((p) => (
              <button
                key={p.key}
                onClick={() => setTemplate((t) => t + (t && !t.endsWith(" ") ? " " : "") + p.key)}
                title={p.label}
                className="px-2.5 py-1 rounded-full text-[11px] font-mono font-medium border bg-[#F0EDE1] text-[#5B5748] border-line"
              >
                {p.key}
              </button>
            ))}
          </div>
          <button onClick={saveTemplate} className="text-[12px] font-semibold text-accent">
            {templateSaved ? "Saved!" : "Save template"}
          </button>
        </div>
      )}
    </div>
  );
}
FILEEOF

echo "Files updated. Running tests..."
npm test
echo "Now run: git add . && git commit -m \"Add customizable reminder message template\" && git push"
