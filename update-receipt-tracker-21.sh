#!/bin/bash
set -e
echo "Applying: one-tap text reminder with payment method and amount owed..."

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

/**
 * Builds a pre-filled text message reminding someone what they owe, mentioning
 * how to pay you back, with a link to their own page for full details.
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
  friendLink: string;
}): string {
  const { phone, friendFirstName, totalRemaining, receiptSummary, ownerMethod, ownerHandle, friendLink } = params;
  const amount = totalRemaining.toLocaleString("en-US", { style: "currency", currency: "USD" });

  let message = `Hi ${friendFirstName}! Just a reminder — you owe ${amount} for ${receiptSummary}.`;
  if (ownerMethod && ownerHandle) {
    message += ` You can send it via ${ownerMethod}: ${ownerHandle}.`;
  }
  message += ` Details: ${friendLink}`;

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
          friendLink,
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

echo "Files updated. Running tests..."
npm test
echo "Now run: git add . && git commit -m \"Add text reminder with payment method and amount owed\" && git push"
