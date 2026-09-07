import { describe, it, expect } from "vitest";
import { computeReceiptShares, allocatePersonPayments, applyItemCoverage } from "../split";
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
    additional_tip: overrides.additional_tip ?? 0,
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

  it("adds additional_tip (cash tip on top of what's printed) into the split, same as the receipt's own tip", () => {
    const r = receipt({
      subtotal: 30,
      tax: 3,
      tip: 6,
      additional_tip: 10, // e.g. extra cash tip not on the printed receipt
      total: 49,
      tax_tip_method: "proportional",
      items: [
        item({ id: "i1", price: 20, personIds: ["a"] }),
        item({ id: "i2", price: 10, personIds: ["b"] }),
      ],
    });
    const shares = computeReceiptShares(r);
    // tax+tip+additional_tip = $19 total pool, split proportionally 2:1 by subtotal
    expect(shares.a.total).toBeCloseTo(20 + (19 * (2 / 3)), 2);
    expect(shares.b.total).toBeCloseTo(10 + (19 * (1 / 3)), 2);
    expect(sumTotals(shares)).toBeCloseTo(49, 2);
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

describe("applyItemCoverage — 'someone is covering someone else' feature", () => {
  it("reassigns a covered person's share entirely to their coverer", () => {
    const items = [{ personIds: ["trung", "emi"], personUnits: undefined }];
    const result = applyItemCoverage(items, { emi: "trung" });
    expect(result[0].personIds).toEqual(["trung"]);
    expect(result[0].personUnits).toEqual({ trung: 2 }); // merged weight: trung's own 1 + emi's 1
  });

  it("leaves items untouched when there's no coverage set", () => {
    const items = [{ personIds: ["a", "b"], personUnits: { a: 1, b: 1 } }];
    const result = applyItemCoverage(items, {});
    expect(result).toBe(items); // same reference — early return, no unnecessary copy
  });

  it("resolves a chain of coverage to the final payer", () => {
    // emi covered by trung, trung covered by tammy -> emi's share should land on tammy
    const items = [{ personIds: ["emi"], personUnits: { emi: 1 } }];
    const result = applyItemCoverage(items, { emi: "trung", trung: "tammy" });
    expect(result[0].personIds).toEqual(["tammy"]);
    expect(result[0].personUnits).toEqual({ tammy: 1 });
  });

  it("doesn't loop forever if coverage forms a cycle", () => {
    const items = [{ personIds: ["a", "b"], personUnits: { a: 1, b: 1 } }];
    // a covered by b, b covered by a — a genuine mistake, but must not hang
    const result = applyItemCoverage(items, { a: "b", b: "a" });
    expect(result[0].personIds.length).toBeGreaterThan(0); // just needs to terminate sanely
  });

  it("only affects the people who actually have coverage set, leaving others alone", () => {
    const items = [{ personIds: ["a", "b", "c"], personUnits: { a: 1, b: 1, c: 1 } }];
    const result = applyItemCoverage(items, { b: "a" });
    expect(result[0].personIds.sort()).toEqual(["a", "c"]);
    expect(result[0].personUnits).toEqual({ a: 2, c: 1 });
  });

  it("combines cleanly with the rest of the split math — the covered person ends up owing nothing", () => {
    const r = {
      id: "r1",
      user_id: "u1",
      merchant: "Test",
      date: "2026-01-01",
      subtotal: 40,
      tax: 0,
      tip: 0,
      additional_tip: 0,
      discount: 0,
      total: 40,
      tax_tip_method: "proportional" as const,
      split_mode: "itemized" as const,
      category: null,
      image_path: null,
      image_mime: null,
      items: applyItemCoverage(
        [{ id: "i1", receipt_id: "r1", name: "Dinner", price: 40, quantity: 1, discount: 0, category: "Food" as const, personIds: ["trung", "emi"], personUnits: undefined }],
        { emi: "trung" }
      ),
    };
    const shares = computeReceiptShares(r);
    expect(shares.emi).toBeUndefined();
    expect(shares.trung.total).toBeCloseTo(40);
  });
});
