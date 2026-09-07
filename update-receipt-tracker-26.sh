#!/bin/bash
set -e
echo "Applying: short share links, Additional Tip, cover-for-someone-else, and full Splitwise-style split options (Evenly/Shares/Exact/%/Adjustment) for both items AND whole-bill mode..."
mkdir -p "app/friend/[slug]" "app/api/friend/[slug]"
rm -rf "app/friend/[id]" "app/api/friend/[id]"

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
  share_slug: string;
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
  additional_tip: number;
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

mkdir -p $(dirname 'lib/split.ts')
cat > 'lib/split.ts' << 'FILEEOF'
import { Payment, Receipt } from "./types";

export interface PersonShare {
  food: number;
  drinks: number;
  other: number;
  itemSubtotal: number;
  taxTip: number;
  total: number;
}

/**
 * Resolves "Adjustment" mode into the same weighted-dollar representation used
 * everywhere else: baseline = (price - sum of adjustments) / N, split evenly,
 * then each person's flat +/- adjustment is layered on top. The result always
 * sums to exactly the item price, by construction — no reconciliation needed.
 */
export function resolveAdjustments<
  T extends { price: number; personIds: string[]; personUnits?: Record<string, number>; splitType?: string }
>(items: T[]): T[] {
  return items.map((item) => {
    if (item.splitType !== "adjustment") return item;
    const n = item.personIds.length;
    if (n === 0) return item;
    const adjustments = item.personUnits || {};
    const sumAdjustments = item.personIds.reduce((s, pid) => s + (adjustments[pid] ?? 0), 0);
    const baseline = (item.price - sumAdjustments) / n;
    const resolved: Record<string, number> = {};
    for (const pid of item.personIds) {
      resolved[pid] = baseline + (adjustments[pid] ?? 0);
    }
    return { ...item, personUnits: resolved };
  });
}

/**
 * Follows a chain of "covered by" relationships to the final person who actually
 * pays (e.g. if A is covered by B, and B is covered by C, A resolves to C).
 * Stops at the first cycle it detects rather than looping forever.
 */
function resolveCoverageRoot(personId: string, coverage: Record<string, string>): string {
  let current = personId;
  const seen = new Set<string>();
  while (coverage[current] && !seen.has(current)) {
    seen.add(current);
    current = coverage[current];
  }
  return current;
}

/**
 * Reassigns item shares from a covered person to whoever is covering them, merging
 * weights when both already share the same item. Used at receipt-save time so a
 * "Trung is covering Emi's tab" choice becomes a real, permanent reassignment for
 * this one receipt — Emi remains a fully separate person for every other receipt.
 */
export function applyItemCoverage<T extends { personIds: string[]; personUnits?: Record<string, number> }>(
  items: T[],
  coverage: Record<string, string>
): T[] {
  if (Object.keys(coverage).length === 0) return items;
  return items.map((item) => {
    const newPersonIds: string[] = [];
    const newPersonUnits: Record<string, number> = {};
    for (const pid of item.personIds) {
      const root = resolveCoverageRoot(pid, coverage);
      const weight = item.personUnits?.[pid] ?? 1;
      if (!newPersonIds.includes(root)) newPersonIds.push(root);
      newPersonUnits[root] = (newPersonUnits[root] ?? 0) + weight;
    }
    return { ...item, personIds: newPersonIds, personUnits: newPersonUnits };
  });
}

/** Per-person breakdown of a single receipt: item costs + their share of tax/tip. */
export function computeReceiptShares(receipt: Receipt): Record<string, PersonShare> {
  const shares: Record<string, PersonShare> = {};
  const ensure = (pid: string) => {
    if (!shares[pid]) {
      shares[pid] = { food: 0, drinks: 0, other: 0, itemSubtotal: 0, taxTip: 0, total: 0 };
    }
    return shares[pid];
  };

  if (receipt.split_mode === "even") {
    // Whole-bill mode: split the actual total across whoever's in, directly —
    // no dependency on subtotal/tax/tip being filled in separately. Respects
    // per-person weighting (Shares/Exact/%/Adjustment) if set, otherwise
    // divides purely evenly.
    const item = (receipt.items ?? [])[0];
    const people = item?.personIds ?? [];
    if (people.length > 0) {
      const unitsMap = item?.personUnits || {};
      const totalUnits = people.reduce((sum, pid) => sum + (unitsMap[pid] ?? 1), 0) || people.length;
      people.forEach((pid) => {
        const units = unitsMap[pid] ?? 1;
        const share = (Number(receipt.total) || 0) * (units / totalUnits);
        const s = ensure(pid);
        s.other = share;
        s.itemSubtotal = share;
        s.total = share;
      });
    }
  } else {
    let itemsTotal = 0;
    for (const item of receipt.items ?? []) {
      const people = item.personIds ?? [];
      if (people.length === 0) continue;
      const effectivePrice = Math.max(0, (Number(item.price) || 0) - (Number(item.discount) || 0));
      const unitsMap = item.personUnits || {};
      const totalUnits = people.reduce((sum, pid) => sum + (unitsMap[pid] ?? 1), 0) || people.length;
      itemsTotal += effectivePrice;
      for (const pid of people) {
        const units = unitsMap[pid] ?? 1;
        const per = effectivePrice * (units / totalUnits);
        const s = ensure(pid);
        s.itemSubtotal += per;
        if (item.category === "Food") s.food += per;
        else if (item.category === "Drinks") s.drinks += per;
        else s.other += per;
      }
    }

    const taxTip = (Number(receipt.tax) || 0) + (Number(receipt.tip) || 0) + (Number(receipt.additional_tip) || 0) - (Number(receipt.discount) || 0);
    const participantIds = Object.keys(shares);

    if (receipt.tax_tip_method === "equal" && participantIds.length > 0) {
      const each = taxTip / participantIds.length;
      participantIds.forEach((pid) => (shares[pid].taxTip = each));
    } else {
      participantIds.forEach((pid) => {
        const portion = itemsTotal > 0 ? shares[pid].itemSubtotal / itemsTotal : 0;
        shares[pid].taxTip = portion * taxTip;
      });
    }

    participantIds.forEach((pid) => {
      shares[pid].total = shares[pid].itemSubtotal + shares[pid].taxTip;
    });
  }

  const participantIds = Object.keys(shares);

  // Penny-exact reconciliation: independently rounding each person's share to
  // cents can leave the totals off by a cent or two from the true sum. Fix that
  // using the "largest remainder" method — the fairest way to hand out the
  // leftover pennies — so the amounts you'd actually collect always add up exactly.
  if (participantIds.length > 0) {
    const rawTotal = participantIds.reduce((s, pid) => s + shares[pid].total, 0);
    const targetCents = Math.round(rawTotal * 100);
    const roundedCents: Record<string, number> = {};
    participantIds.forEach((pid) => (roundedCents[pid] = Math.round(shares[pid].total * 100)));
    let diff = targetCents - participantIds.reduce((s, pid) => s + roundedCents[pid], 0);

    if (diff !== 0) {
      const order = [...participantIds].sort((a, b) => {
        const remA = shares[a].total * 100 - Math.floor(shares[a].total * 100);
        const remB = shares[b].total * 100 - Math.floor(shares[b].total * 100);
        return diff > 0 ? remB - remA : remA - remB;
      });
      let i = 0;
      while (diff !== 0 && i < order.length * 4) {
        const pid = order[i % order.length];
        roundedCents[pid] += diff > 0 ? 1 : -1;
        diff += diff > 0 ? -1 : 1;
        i++;
      }
    }

    participantIds.forEach((pid) => (shares[pid].total = roundedCents[pid] / 100));
  }

  return shares;
}

export interface PersonAllocation {
  personReceipts: { receipt: Receipt; owed: number }[];
  remainingMap: Record<string, number>;
  paidMap: Record<string, number>;
  totalOwed: number;
  totalPaid: number;
  totalRemaining: number;
}

/**
 * Allocates a person's payments (some linked to a specific receipt, some general)
 * across their receipts, oldest first, to work out what's still outstanding.
 */
export function allocatePersonPayments(
  personId: string,
  receipts: Receipt[],
  payments: Payment[]
): PersonAllocation {
  const personReceipts = receipts
    .map((r) => {
      const shares = computeReceiptShares(r);
      const owed = shares[personId]?.total ?? 0;
      return owed > 0 ? { receipt: r, owed } : null;
    })
    .filter((x): x is { receipt: Receipt; owed: number } => x !== null)
    .sort((a, b) => (a.receipt.date < b.receipt.date ? -1 : 1));

  const remainingMap: Record<string, number> = {};
  personReceipts.forEach(({ receipt, owed }) => (remainingMap[receipt.id] = owed));

  const personPayments = payments.filter((p) => p.person_id === personId);

  let generalPool = 0;
  personPayments.forEach((p) => {
    if (p.receipt_id && remainingMap[p.receipt_id] !== undefined) {
      remainingMap[p.receipt_id] = Math.max(0, remainingMap[p.receipt_id] - p.amount);
    } else {
      generalPool += p.amount;
    }
  });

  for (const { receipt } of personReceipts) {
    if (generalPool <= 0) break;
    const bal = remainingMap[receipt.id];
    const take = Math.min(bal, generalPool);
    remainingMap[receipt.id] = bal - take;
    generalPool -= take;
  }

  const paidMap: Record<string, number> = {};
  personReceipts.forEach(({ receipt, owed }) => {
    paidMap[receipt.id] = owed - remainingMap[receipt.id];
  });

  const totalOwed = personReceipts.reduce((s, r) => s + r.owed, 0);
  const totalPaid = personPayments.reduce((s, p) => s + p.amount, 0);
  const totalRemaining = personReceipts.reduce((s, r) => s + remainingMap[r.receipt.id], 0);

  return { personReceipts, remainingMap, paidMap, totalOwed, totalPaid, totalRemaining };
}
FILEEOF

mkdir -p $(dirname 'lib/__tests__/split.test.ts')
cat > 'lib/__tests__/split.test.ts' << 'FILEEOF'
import { describe, it, expect } from "vitest";
import { computeReceiptShares, allocatePersonPayments, applyItemCoverage, resolveAdjustments } from "../split";
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

describe("resolveAdjustments — 'By adjustment' split mode", () => {
  it("splits evenly as a baseline when no one has an adjustment", () => {
    const items = resolveAdjustments([
      { price: 90, personIds: ["a", "b", "c"], personUnits: {}, splitType: "adjustment" },
    ]);
    expect(items[0].personUnits).toEqual({ a: 30, b: 30, c: 30 });
  });

  it("gives someone a flat bump on top of the baseline, and reduces everyone else's baseline to compensate", () => {
    // $90 for 3 people, but Sarah gets a flat +$15 for a pricier entrée
    const items = resolveAdjustments([
      { price: 90, personIds: ["sarah", "b", "c"], personUnits: { sarah: 15 }, splitType: "adjustment" },
    ]);
    // baseline = (90 - 15) / 3 = 25; sarah = 25 + 15 = 40; b = c = 25
    expect(items[0].personUnits!.sarah).toBeCloseTo(40);
    expect(items[0].personUnits!.b).toBeCloseTo(25);
    expect(items[0].personUnits!.c).toBeCloseTo(25);
  });

  it("always sums exactly to the item price, regardless of how many adjustments are set", () => {
    const items = resolveAdjustments([
      { price: 200, personIds: ["a", "b", "c", "d"], personUnits: { a: 20, b: -10 }, splitType: "adjustment" },
    ]);
    const sum = Object.values(items[0].personUnits!).reduce((s, v) => s + v, 0);
    expect(sum).toBeCloseTo(200);
  });

  it("leaves non-adjustment items completely untouched", () => {
    const items = resolveAdjustments([{ price: 50, personIds: ["a", "b"], personUnits: { a: 2, b: 1 }, splitType: "shares" }]);
    expect(items[0].personUnits).toEqual({ a: 2, b: 1 });
  });

  it("combines correctly with the rest of the split math via computeReceiptShares", () => {
    const r = {
      id: "r1", user_id: "u1", merchant: "Test", date: "2026-01-01",
      subtotal: 90, tax: 0, tip: 0, additional_tip: 0, discount: 0, total: 90,
      tax_tip_method: "proportional" as const, split_mode: "itemized" as const,
      category: null, image_path: null, image_mime: null,
      items: resolveAdjustments([
        { id: "i1", receipt_id: "r1", name: "Dinner", price: 90, quantity: 1, discount: 0, category: "Food" as const, personIds: ["sarah", "b", "c"], personUnits: { sarah: 15 }, splitType: "adjustment" },
      ]),
    };
    const shares = computeReceiptShares(r);
    expect(shares.sarah.total).toBeCloseTo(40);
    expect(shares.b.total).toBeCloseTo(25);
    expect(shares.c.total).toBeCloseTo(25);
  });
});

describe("computeReceiptShares — whole-bill mode respects weighting (Shares/Exact/%/Adjustment)", () => {
  it("splits by shares instead of forcing pure equal division when weights are set", () => {
    const r = {
      id: "r1", user_id: "u1", merchant: "Test", date: "2026-01-01",
      subtotal: 0, tax: 0, tip: 0, additional_tip: 0, discount: 0, total: 100,
      tax_tip_method: "proportional" as const, split_mode: "even" as const,
      category: null, image_path: null, image_mime: null,
      items: [{ id: "i1", receipt_id: "r1", name: "Whole bill", price: 100, quantity: 1, discount: 0, category: "Other" as const, personIds: ["a", "b"], personUnits: { a: 3, b: 1 } }],
    };
    const shares = computeReceiptShares(r);
    expect(shares.a.total).toBeCloseTo(75); // 3/4 of 100
    expect(shares.b.total).toBeCloseTo(25); // 1/4 of 100
  });

  it("still splits purely evenly when no weights are set (unchanged default behavior)", () => {
    const r = {
      id: "r1", user_id: "u1", merchant: "Test", date: "2026-01-01",
      subtotal: 0, tax: 0, tip: 0, additional_tip: 0, discount: 0, total: 90,
      tax_tip_method: "proportional" as const, split_mode: "even" as const,
      category: null, image_path: null, image_mime: null,
      items: [{ id: "i1", receipt_id: "r1", name: "Whole bill", price: 90, quantity: 1, discount: 0, category: "Other" as const, personIds: ["a", "b", "c"], personUnits: {} }],
    };
    const shares = computeReceiptShares(r);
    expect(shares.a.total).toBeCloseTo(30);
    expect(shares.b.total).toBeCloseTo(30);
    expect(shares.c.total).toBeCloseTo(30);
  });
});
FILEEOF

mkdir -p $(dirname 'app/friend/[slug]/page.tsx')
cat > 'app/friend/[slug]/page.tsx' << 'FILEEOF'
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
  first_name: string | null;
  last_name: string | null;
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
  const slug = params.slug as string;

  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [info, setInfo] = useState<FriendInfo | null>(null);

  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
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
        const res = await fetch(`/api/friend/${slug}`);
        if (!res.ok) {
          setNotFound(true);
        } else {
          const data: FriendInfo = await res.json();
          setInfo(data);
          setFirstName(data.first_name || data.name);
          setLastName(data.last_name || "");
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
  }, [slug]);

  async function save() {
    setSaving(true);
    try {
      const res = await fetch(`/api/friend/${slug}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          first_name: firstName.trim() || undefined,
          last_name: lastName.trim(),
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
            <div className="flex gap-2 mb-4">
              <input
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                placeholder="First name"
                className="flex-1 rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40"
              />
              <input
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                placeholder="Last name"
                className="flex-1 rounded-lg border border-line bg-white px-3 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-accent/40"
              />
            </div>

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

mkdir -p $(dirname 'app/api/friend/[slug]/route.ts')
cat > 'app/api/friend/[slug]/route.ts' << 'FILEEOF'
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

export async function GET(request: Request, { params }: { params: { slug: string } }) {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({ error: "This feature isn't fully configured yet." }, { status: 500 });
  }
  const supabase = createServiceClient();

  const { data: person } = await supabase.from("people").select("*").eq("share_slug", params.slug).maybeSingle();
  if (!person) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }
  const personId = person.id;

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
    first_name: person.first_name,
    last_name: person.last_name,
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

export async function POST(request: Request, { params }: { params: { slug: string } }) {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({ error: "This feature isn't fully configured yet." }, { status: 500 });
  }
  const supabase = createServiceClient();

  const { data: existing } = await supabase.from("people").select("id").eq("share_slug", params.slug).maybeSingle();
  if (!existing) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }
  const personId = existing.id;

  const body = await request.json();
  // Explicit whitelist — never spread the raw body into an update.
  const update: Record<string, any> = {};
  if (typeof body.first_name === "string" && body.first_name.trim()) {
    const first = body.first_name.trim().slice(0, 100);
    const last = typeof body.last_name === "string" ? body.last_name.trim().slice(0, 100) : "";
    update.first_name = first;
    update.last_name = last;
    update.name = `${first} ${last}`.trim();
  } else if (typeof body.name === "string" && body.name.trim()) {
    update.name = body.name.trim().slice(0, 100);
  }
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
    const url = `${window.location.origin}/friend/${person.share_slug}`;
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
  const friendLink = host ? `https://${host}/friend/${person.share_slug}` : "";

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

mkdir -p $(dirname 'app/receipts/new/page.tsx')
cat > 'app/receipts/new/page.tsx' << 'FILEEOF'
"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Camera, Plus, Trash2, X, Sparkles, Loader2, CheckCircle2, AlertTriangle, FileText } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { computeReceiptShares, applyItemCoverage, resolveAdjustments } from "@/lib/split";
import { Category, Person, Group, TaxTipMethod, ReceiptCategory } from "@/lib/types";
import { splitName } from "@/lib/utils";

const CATEGORIES: Category[] = ["Food", "Drinks", "Other"];
const RECEIPT_CATEGORIES: ReceiptCategory[] = ["Dining", "Trips", "Roommates/Home", "Transportation", "Other"];
const DRAFT_KEY = "receipt-draft-v1";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

function compressImage(file: File, maxW = 1200, quality = 0.78): Promise<{ blob: Blob; dataUrl: string }> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("read failed"));
    reader.onload = () => {
      const img = new Image();
      img.onload = () => {
        const scale = Math.min(1, maxW / img.width);
        const w = Math.round(img.width * scale);
        const h = Math.round(img.height * scale);
        const canvas = document.createElement("canvas");
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext("2d")!;
        ctx.drawImage(img, 0, 0, w, h);
        const dataUrl = canvas.toDataURL("image/jpeg", quality);
        canvas.toBlob(
          (blob) => (blob ? resolve({ blob, dataUrl }) : reject(new Error("toBlob failed"))),
          "image/jpeg",
          quality
        );
      };
      img.onerror = () => reject(new Error("decode failed"));
      img.src = reader.result as string;
    };
    reader.readAsDataURL(file);
  });
}

/** PDFs can't go through canvas compression — just read them as-is. */
function readFileAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("read failed"));
    reader.onload = () => resolve(reader.result as string);
    reader.readAsDataURL(file);
  });
}

interface DraftItem {
  id: string;
  name: string;
  price: string;
  discount: string;
  quantity: number;
  category: Category;
  personIds: string[];
  personUnits: Record<string, number>;
  splitType: "even" | "shares" | "exact" | "percent" | "adjustment";
}

type Phase = "capture" | "basics" | "participants" | "items" | "review";

export default function AddReceiptPage() {
  const router = useRouter();
  const supabase = createClient();

  const [phase, setPhase] = useState<Phase>("capture");
  const [people, setPeople] = useState<Person[]>([]);
  const [groups, setGroups] = useState<Group[]>([]);
  const [merchant, setMerchant] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [subtotal, setSubtotal] = useState("");
  const [tax, setTax] = useState("");
  const [tip, setTip] = useState("");
  const [additionalTip, setAdditionalTip] = useState("");
  const [coverage, setCoverage] = useState<Record<string, string>>({});
  const [discount, setDiscount] = useState("");
  const [total, setTotal] = useState("");
  const [selectedTipPct, setSelectedTipPct] = useState<number | null>(null);
  const [receiptCategory, setReceiptCategory] = useState<ReceiptCategory | null>(null);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [isPdf, setIsPdf] = useState(false);
  const [items, setItems] = useState<DraftItem[]>([]);
  const [taxTipMethod, setTaxTipMethod] = useState<TaxTipMethod>("proportional");
  const [splitMode, setSplitMode] = useState<"itemized" | "even">("itemized");
  const [evenParticipants, setEvenParticipants] = useState<string[]>([]);
  const [evenSplitType, setEvenSplitType] = useState<"even" | "shares" | "exact" | "percent" | "adjustment">("even");
  const [evenPersonUnits, setEvenPersonUnits] = useState<Record<string, number>>({});
  const [newPersonName, setNewPersonName] = useState("");
  const [saving, setSaving] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    supabase.from("people").select("*").order("name").then(({ data }) => setPeople(data ?? []));
    (async () => {
      const { data: g } = await supabase.from("groups").select("*").order("name");
      const { data: m } = await supabase.from("group_members").select("*");
      setGroups(
        (g ?? []).map((grp) => ({ ...grp, memberIds: (m ?? []).filter((x) => x.group_id === grp.id).map((x) => x.person_id) }))
      );
    })();
  }, []);

  // Draft protection: if a receipt was left unfinished (dropped connection, backgrounded app),
  // offer to resume it. Images aren't restorable this way, only the entered numbers/items.
  useEffect(() => {
    try {
      const saved = localStorage.getItem(DRAFT_KEY);
      if (!saved) return;
      const draft = JSON.parse(saved);
      const hasContent = draft.merchant || (draft.items && draft.items.length > 0) || Number(draft.subtotal) > 0;
      if (!hasContent) {
        localStorage.removeItem(DRAFT_KEY);
        return;
      }
      if (confirm("You have an unfinished receipt from earlier — resume where you left off?")) {
        if (draft.phase && draft.phase !== "capture") setPhase(draft.phase);
        setMerchant(draft.merchant ?? "");
        setDate(draft.date ?? new Date().toISOString().slice(0, 10));
        setSubtotal(draft.subtotal ?? "");
        setTax(draft.tax ?? "");
        setTip(draft.tip ?? "");
        setDiscount(draft.discount ?? "");
        setTotal(draft.total ?? "");
        setReceiptCategory(draft.receiptCategory ?? null);
        setItems(draft.items ?? []);
        setTaxTipMethod(draft.taxTipMethod ?? "proportional");
        setSplitMode(draft.splitMode ?? "itemized");
        setEvenParticipants(draft.evenParticipants ?? []);
      } else {
        localStorage.removeItem(DRAFT_KEY);
      }
    } catch (e) {
      console.error("draft resume failed", e);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Autosave the draft as it changes (image/file state intentionally excluded — not restorable).
  useEffect(() => {
    try {
      const hasContent = merchant || items.length > 0 || Number(subtotal) > 0;
      if (!hasContent) return;
      const draft = { phase, merchant, date, subtotal, tax, tip, discount, total, receiptCategory, items, taxTipMethod, splitMode, evenParticipants };
      localStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
    } catch (e) {
      // storage unavailable/full — draft protection just won't work this session, not fatal
    }
  }, [phase, merchant, date, subtotal, tax, tip, discount, total, receiptCategory, items, taxTipMethod, splitMode, evenParticipants]);

  const itemsSum = items.reduce((s, it) => s + Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0)), 0);

  async function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 8 * 1024 * 1024) {
      setScanError("That file is too large (max 8MB) — try a smaller photo or a lighter PDF, or enter it manually.");
      return;
    }
    setImageFile(file);
    setScanError(null);
    const fileIsPdf = file.type === "application/pdf";
    setIsPdf(fileIsPdf);

    try {
      let dataUrl: string;
      if (fileIsPdf) {
        dataUrl = await readFileAsDataUrl(file);
        setImagePreview(null); // no visual preview for PDFs, we show a file chip instead
      } else {
        const compressed = await compressImage(file);
        dataUrl = compressed.dataUrl;
        setImagePreview(dataUrl);
      }
      setScanning(true);
      const base64 = dataUrl.split(",")[1];
      const res = await fetch("/api/scan-receipt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ imageBase64: base64, mediaType: fileIsPdf ? "application/pdf" : "image/jpeg" }),
      });
      const parsed = await res.json();
      if (!res.ok) {
        setScanError(parsed.error || "Couldn't read this receipt automatically — enter it manually below.");
      } else {
        setMerchant(parsed.merchant || "");
        if (parsed.date) setDate(parsed.date);
        if (parsed.subtotal != null) setSubtotal(String(parsed.subtotal));
        if (parsed.tax != null) setTax(String(parsed.tax));
        if (parsed.tip != null) setTip(String(parsed.tip));
        if (parsed.discount != null) setDiscount(String(parsed.discount));
        if (parsed.total != null) setTotal(String(parsed.total));
        if (Array.isArray(parsed.items)) {
          setItems(
            parsed.items.map((it: any) => ({
              id: crypto.randomUUID(),
              name: it.quantity && it.quantity > 1 ? `${it.quantity} × ${it.name}` : it.name,
              price: String((Number(it.unit_price) || 0) * (Number(it.quantity) || 1)),
              discount: "",
              quantity: Number(it.quantity) || 1,
              category: (["Food", "Drinks", "Other"].includes(it.category) ? it.category : "Food") as Category,
              personIds: [],
              personUnits: {},
              splitType: "even" as const,
            }))
          );
        }
      }
    } catch (err) {
      console.error(err);
      setScanError("Couldn't read this receipt automatically — enter it manually below.");
    } finally {
      setScanning(false);
    }
  }

  function addItem() {
    setItems([...items, { id: crypto.randomUUID(), name: "", price: "", discount: "", quantity: 1, category: "Food", personIds: [], personUnits: {}, splitType: "even" }]);
  }
  function updateItem(id: string, patch: Partial<DraftItem>) {
    setItems(items.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  }
  function removeItem(id: string) {
    setItems(items.filter((it) => it.id !== id));
  }
  function togglePerson(itemId: string, personId: string) {
    setItems(
      items.map((it) => {
        if (it.id !== itemId) return it;
        const has = it.personIds.includes(personId);
        return { ...it, personIds: has ? it.personIds.filter((id) => id !== personId) : [...it.personIds, personId] };
      })
    );
  }
  function setItemPeople(itemId: string, ids: string[]) {
    setItems(items.map((it) => (it.id === itemId ? { ...it, personIds: ids } : it)));
  }
  function setSplitType(itemId: string, type: DraftItem["splitType"]) {
    setItems(
      items.map((it) => {
        if (it.id !== itemId) return it;
        const count = it.personIds.length || 1;
        const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
        let personUnits: Record<string, number> = {};
        if (type === "shares") personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, 1]));
        else if (type === "exact") {
          const each = Math.round((effectivePrice / count) * 100) / 100;
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, each]));
        } else if (type === "percent") {
          const each = Math.round((100 / count) * 100) / 100;
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, each]));
        } else if (type === "adjustment") {
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, 0]));
        }
        return { ...it, splitType: type, personUnits };
      })
    );
  }
  function setWeight(itemId: string, personId: string, value: number) {
    setItems(
      items.map((it) => (it.id === itemId ? { ...it, personUnits: { ...it.personUnits, [personId]: Math.max(0, value) } } : it))
    );
  }
  function assignCategoryToEveryone(category: Category) {
    const everyone = people.map((p) => p.id);
    setItems(items.map((it) => (it.category === category ? { ...it, personIds: everyone } : it)));
  }
  function assignCategoryToGroup(category: Category, group: Group) {
    setItems(items.map((it) => (it.category === category ? { ...it, personIds: group.memberIds } : it)));
  }

  async function addPerson() {
    if (!newPersonName.trim()) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    const { first_name, last_name } = splitName(newPersonName);
    const { data } = await supabase.from("people").insert({ user_id: user.id, name: newPersonName.trim(), first_name, last_name }).select().single();
    if (data) setPeople([...people, data]);
    setNewPersonName("");
  }

  const validItems =
    splitMode === "even"
      ? [
          {
            id: "even-split",
            name: "Whole bill",
            price:
              Number(total) ||
              (Number(subtotal) || 0) + (Number(tax) || 0) + (Number(tip) || 0) + (Number(additionalTip) || 0) - (Number(discount) || 0),
            discount: 0,
            quantity: 1,
            category: "Other" as Category,
            personIds: evenParticipants,
            personUnits: evenPersonUnits,
            splitType: evenSplitType,
          },
        ]
      : items
          .filter((it) => it.name.trim() && Number(it.price) > 0)
          .map((it) => ({ ...it, price: Number(it.price), discount: Number(it.discount) || 0 }));

  const rawParticipantIds = Array.from(new Set(validItems.flatMap((it) => it.personIds)));
  const coveredItems = applyItemCoverage(resolveAdjustments(validItems), coverage);

  const draftReceipt = {
    merchant: merchant.trim() || "Untitled receipt",
    date,
    subtotal: Number(subtotal) || itemsSum,
    tax: Number(tax) || 0,
    tip: Number(tip) || 0,
    additional_tip: Number(additionalTip) || 0,
    discount: Number(discount) || 0,
    total: Number(total) || (Number(subtotal) || itemsSum) + (Number(tax) || 0) + (Number(tip) || 0) + (Number(additionalTip) || 0) - (Number(discount) || 0),
    items: coveredItems,
    tax_tip_method: taxTipMethod,
    split_mode: splitMode,
  };
  const shares = computeReceiptShares(draftReceipt as any);

  // Reconciliation
  const calculatedTotal =
    draftReceipt.subtotal + draftReceipt.tax + draftReceipt.tip + draftReceipt.additional_tip - draftReceipt.discount;
  const totalDifference = Math.round((draftReceipt.total - calculatedTotal) * 100) / 100;
  const assignedTotal = Object.values(shares).reduce((s: number, sh: any) => s + sh.total, 0);
  const unassignedCheckTotal = splitMode === "even" ? draftReceipt.total : calculatedTotal;
  const unassigned = Math.round((unassignedCheckTotal - assignedTotal) * 100) / 100;
  const unassignedItems = splitMode === "itemized" ? validItems.filter((it) => it.personIds.length === 0) : [];

  async function save() {
    setSaving(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;

    const { data: possibleDupes } = await supabase
      .from("receipts")
      .select("merchant, date, total")
      .eq("merchant", draftReceipt.merchant)
      .eq("date", draftReceipt.date);
    const dupe = (possibleDupes ?? []).find((d) => Math.abs(d.total - draftReceipt.total) < 0.01);
    if (dupe) {
      const proceed = confirm(
        `This looks like it might already be saved — ${dupe.merchant} on ${dupe.date} for ${money(dupe.total)}. Save it anyway?`
      );
      if (!proceed) {
        setSaving(false);
        return;
      }
    }

    const { data: receipt, error } = await supabase
      .from("receipts")
      .insert({
        user_id: user.id,
        merchant: draftReceipt.merchant,
        date: draftReceipt.date,
        subtotal: draftReceipt.subtotal,
        tax: draftReceipt.tax,
        tip: draftReceipt.tip,
        additional_tip: draftReceipt.additional_tip,
        discount: draftReceipt.discount,
        total: draftReceipt.total,
        tax_tip_method: taxTipMethod,
        split_mode: splitMode,
        category: receiptCategory,
      })
      .select()
      .single();

    if (error || !receipt) {
      setSaving(false);
      return;
    }

    if (imageFile) {
      try {
        if (isPdf) {
          const path = `${user.id}/${receipt.id}.pdf`;
          await supabase.storage.from("receipts").upload(path, imageFile, { contentType: "application/pdf" });
          await supabase.from("receipts").update({ image_path: path, image_mime: "application/pdf" }).eq("id", receipt.id);
        } else {
          const { blob } = await compressImage(imageFile);
          const path = `${user.id}/${receipt.id}.jpg`;
          await supabase.storage.from("receipts").upload(path, blob, { contentType: "image/jpeg" });
          await supabase.from("receipts").update({ image_path: path, image_mime: "image/jpeg" }).eq("id", receipt.id);
        }
      } catch (e) {
        console.error("image upload failed", e);
      }
    }

    for (const item of coveredItems) {
      const { data: savedItem } = await supabase
        .from("receipt_items")
        .insert({
          receipt_id: receipt.id,
          name: item.name,
          price: Number(item.price),
          discount: Number(item.discount) || 0,
          category: item.category,
          quantity: item.quantity || 1,
        })
        .select()
        .single();
      if (savedItem && item.personIds.length) {
        await supabase.from("item_splits").insert(
          item.personIds.map((personId) => ({
            item_id: savedItem.id,
            person_id: personId,
            units: item.personUnits?.[personId] ?? 1,
          }))
        );
      }
    }

    try {
      localStorage.removeItem(DRAFT_KEY);
    } catch (e) {}
    router.push(`/receipts/${receipt.id}`);
    router.refresh();
  }

  function backFrom(p: Phase) {
    if (p === "basics") setPhase("capture");
    else if (p === "participants") setPhase("basics");
    else if (p === "items") setPhase("basics");
    else if (p === "review") setPhase(splitMode === "even" ? "participants" : "items");
  }

  const titles: Record<Phase, string> = {
    capture: "Scan Receipt",
    basics: "Receipt Details",
    participants: "Who's In?",
    items: "Items",
    review: "Review & Split",
  };

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <button onClick={() => (phase === "capture" ? router.push("/") : backFrom(phase))} className="text-[13px] text-muted">
          Back
        </button>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink">{titles[phase]}</h1>
        <button onClick={() => router.push("/")} className="p-1">
          <X size={18} className="text-muted" />
        </button>
      </div>

      {phase === "capture" && (
        <div className="px-5 pt-4 animate-page-in">
          <input ref={fileRef} type="file" accept="image/*,application/pdf" className="hidden" onChange={handleFile} />
          <button
            onClick={() => fileRef.current?.click()}
            disabled={scanning}
            className="w-full rounded-2xl border-2 border-dashed border-line bg-white flex flex-col items-center justify-center py-10 mb-4"
          >
            {isPdf && imageFile ? (
              <div className="flex flex-col items-center gap-2">
                <FileText size={28} className="text-accent" />
                <span className="text-[13px] font-medium text-ink">{imageFile.name}</span>
              </div>
            ) : imagePreview ? (
              <img src={imagePreview} alt="Receipt" className="max-h-56 rounded-lg object-contain" />
            ) : (
              <>
                <Camera size={28} className="text-accent mb-2" />
                <span className="text-[14px] font-medium text-ink">Take or upload a photo or PDF</span>
                <span className="text-[11px] text-muted mt-0.5">We'll read it automatically</span>
              </>
            )}
          </button>

          {scanning && (
            <div className="flex items-center justify-center gap-2 text-[13px] text-accent mb-4">
              <Loader2 size={16} className="animate-spin" />
              Reading your receipt…
            </div>
          )}

          {scanError && (
            <div className="rounded-xl bg-[#FBF3E6] border border-[#EEDDB8] px-4 py-3 text-[13px] text-[#7A5E24] mb-4">
              {scanError}
            </div>
          )}

          {!scanning && (merchant || items.length > 0) && (
            <div className="rounded-xl bg-[#EFF7F3] border border-[#CFE8DC] px-4 py-3 text-[13px] text-[#1F7A5C] mb-4 flex items-center gap-2">
              <Sparkles size={15} /> Scanned — review the details on the next screen.
            </div>
          )}

          <button
            onClick={() => setPhase("basics")}
            disabled={scanning}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-3 disabled:opacity-40"
          >
            {merchant || items.length > 0 ? "Continue" : "Enter manually instead"}
          </button>
        </div>
      )}

      {phase === "basics" && (
        <div className="px-5 pt-4 animate-page-in">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Merchant</p>
          <input value={merchant} onChange={(e) => setMerchant(e.target.value)} placeholder="e.g. King Pocha"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Date</p>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <div className="grid grid-cols-2 gap-2 mb-3">
            {[
              ["Subtotal", subtotal, setSubtotal],
              ["Tax", tax, setTax],
              ["Tip", tip, (v: string) => { setTip(v); setSelectedTipPct(null); }],
              ["Additional tip", additionalTip, setAdditionalTip],
              ["Discount", discount, setDiscount],
            ].map(([label, val, setter]: any) => (
              <div key={label}>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">{label}</p>
                <input inputMode="decimal" value={val} onChange={(e) => setter(e.target.value)} placeholder="0.00"
                  className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40" />
              </div>
            ))}
          </div>

          {Number(subtotal) > 0 && (
            <div className="mb-4">
              <p className="text-[11px] text-muted mb-1.5">Tip wasn't printed on the receipt? Calculate it:</p>
              <div className="flex gap-1.5">
                {[15, 18, 20, 25].map((pct) => (
                  <button
                    key={pct}
                    onClick={() => {
                      const calcTip = Math.round(((Number(subtotal) + Number(tax || 0)) * pct) / 100 * 100) / 100;
                      setTip(String(calcTip));
                      setSelectedTipPct(pct);
                      const newTotal = Number(subtotal) + Number(tax || 0) + calcTip - Number(discount || 0);
                      setTotal(String(Math.round(newTotal * 100) / 100));
                    }}
                    className={`flex-1 px-2 py-2 rounded-lg text-[13px] font-medium border ${selectedTipPct === pct ? "bg-accent text-white border-accent" : "bg-white text-[#5B5748] border-line"}`}
                  >
                    {pct}%
                  </button>
                ))}
              </div>
            </div>
          )}

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Total</p>
          <input inputMode="decimal" value={total} onChange={(e) => setTotal(e.target.value)} placeholder="0.00"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-1.5" />
          {(Number(subtotal) > 0 || Number(tax) > 0 || Number(tip) > 0) && (
            <button
              onClick={() => {
                const calc = Number(subtotal || 0) + Number(tax || 0) + Number(tip || 0) + Number(additionalTip || 0) - Number(discount || 0);
                setTotal(String(Math.round(calc * 100) / 100));
              }}
              className="text-[12px] text-accent font-medium mb-6"
            >
              Use calculated total ({money(Number(subtotal || 0) + Number(tax || 0) + Number(tip || 0) + Number(additionalTip || 0) - Number(discount || 0))})
            </button>
          )}
          {!(Number(subtotal) > 0 || Number(tax) > 0 || Number(tip) > 0) && <div className="mb-6" />}

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Category (optional)</p>
          <div className="flex flex-wrap gap-1.5 mb-6">
            {RECEIPT_CATEGORIES.map((c) => (
              <button
                key={c}
                onClick={() => setReceiptCategory(receiptCategory === c ? null : c)}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${receiptCategory === c ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}
              >
                {c}
              </button>
            ))}
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">How do you want to split it?</p>
          <div className="flex gap-1.5 mb-6">
            <button onClick={() => setSplitMode("itemized")}
              className={`flex-1 px-3.5 py-3 rounded-xl text-[13px] font-medium border ${splitMode === "itemized" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              By item
            </button>
            <button onClick={() => setSplitMode("even")}
              className={`flex-1 px-3.5 py-3 rounded-xl text-[13px] font-medium border ${splitMode === "even" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Whole bill, evenly
            </button>
          </div>

          <button
            onClick={() => setPhase(splitMode === "even" ? "participants" : "items")}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6"
          >
            Continue
          </button>
        </div>
      )}

      {phase === "participants" && (
        <div className="px-5 pt-4 animate-page-in">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-4">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Who was there?</p>
          <div className="flex flex-wrap gap-1.5 mb-4">
            <button onClick={() => setEvenParticipants(people.map((p) => p.id))}
              className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${evenParticipants.length === people.length && people.length > 0 ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Everyone
            </button>
            {people.map((p) => (
              <button key={p.id} onClick={() => setEvenParticipants((cur) => cur.includes(p.id) ? cur.filter((x) => x !== p.id) : [...cur, p.id])}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${evenParticipants.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                {p.name}
              </button>
            ))}
          </div>

          {evenParticipants.length > 0 && (() => {
            const wholeBillTotal = Number(total) || (Number(subtotal) || 0) + (Number(tax) || 0) + (Number(tip) || 0) + (Number(additionalTip) || 0) - (Number(discount) || 0);
            function setEvenType(type: typeof evenSplitType) {
              const count = evenParticipants.length || 1;
              let units: Record<string, number> = {};
              if (type === "shares") units = Object.fromEntries(evenParticipants.map((pid) => [pid, 1]));
              else if (type === "exact") {
                const each = Math.round((wholeBillTotal / count) * 100) / 100;
                units = Object.fromEntries(evenParticipants.map((pid) => [pid, each]));
              } else if (type === "percent") {
                const each = Math.round((100 / count) * 100) / 100;
                units = Object.fromEntries(evenParticipants.map((pid) => [pid, each]));
              } else if (type === "adjustment") {
                units = Object.fromEntries(evenParticipants.map((pid) => [pid, 0]));
              }
              setEvenSplitType(type);
              setEvenPersonUnits(units);
            }
            function setEvenWeight(pid: string, value: number) {
              setEvenPersonUnits((prev) => ({ ...prev, [pid]: Math.max(evenSplitType === "adjustment" ? -Infinity : 0, value) }));
            }
            return (
              <div className="bg-white rounded-xl border border-line p-3.5 mb-6">
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">How should this split?</p>
                <div className="flex flex-wrap gap-1.5 mb-3">
                  {(["even", "shares", "exact", "percent", "adjustment"] as const).map((t) => (
                    <button key={t} onClick={() => setEvenType(t)}
                      className={`px-2.5 py-1.5 rounded-full text-[11px] font-medium border ${evenSplitType === t ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {t === "even" ? "Evenly" : t === "shares" ? "Shares" : t === "exact" ? "Exact $" : t === "percent" ? "%" : "Adjustment"}
                    </button>
                  ))}
                </div>

                {evenSplitType === "even" && (
                  <p className="text-[13px] text-muted">{money(wholeBillTotal / evenParticipants.length)} each · {evenParticipants.length} people</p>
                )}

                {evenSplitType === "shares" && (
                  <div className="space-y-1.5">
                    {evenParticipants.map((pid) => {
                      const person = people.find((p) => p.id === pid);
                      const units = evenPersonUnits[pid] ?? 1;
                      const totalUnits = evenParticipants.reduce((s, id) => s + (evenPersonUnits[id] ?? 1), 0);
                      const share = wholeBillTotal * (units / totalUnits);
                      return (
                        <div key={pid} className="flex items-center justify-between">
                          <span className="text-[13px] text-[#3A382F]">{person?.name}</span>
                          <div className="flex items-center gap-2">
                            <button onClick={() => setEvenWeight(pid, Math.max(0, units - 1))} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">−</button>
                            <span className="w-5 text-center text-[13px] font-medium">{units}</span>
                            <button onClick={() => setEvenWeight(pid, units + 1)} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">+</button>
                            <span className="w-16 text-right font-mono text-[12px] text-muted">{money(share)}</span>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}

                {evenSplitType === "exact" && (
                  <div className="space-y-1.5">
                    {evenParticipants.map((pid) => {
                      const person = people.find((p) => p.id === pid);
                      const amt = evenPersonUnits[pid] ?? 0;
                      return (
                        <div key={pid} className="flex items-center justify-between gap-2">
                          <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                          <input inputMode="decimal" value={amt || ""} onChange={(e) => setEvenWeight(pid, Number(e.target.value) || 0)}
                            placeholder="0.00" className="w-20 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                        </div>
                      );
                    })}
                    {(() => {
                      const sum = evenParticipants.reduce((s, pid) => s + (evenPersonUnits[pid] ?? 0), 0);
                      const diff = Math.round((wholeBillTotal - sum) * 100) / 100;
                      return (
                        <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                          {Math.abs(diff) < 0.01 ? "Matches total ✓" : diff > 0 ? `${money(diff)} unassigned` : `${money(Math.abs(diff))} over`}
                        </p>
                      );
                    })()}
                  </div>
                )}

                {evenSplitType === "percent" && (
                  <div className="space-y-1.5">
                    {evenParticipants.map((pid) => {
                      const person = people.find((p) => p.id === pid);
                      const pct = evenPersonUnits[pid] ?? 0;
                      return (
                        <div key={pid} className="flex items-center justify-between gap-2">
                          <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                          <div className="flex items-center gap-1">
                            <input inputMode="decimal" value={pct || ""} onChange={(e) => setEvenWeight(pid, Number(e.target.value) || 0)}
                              placeholder="0" className="w-14 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                            <span className="text-[12px] text-muted">%</span>
                          </div>
                        </div>
                      );
                    })}
                    {(() => {
                      const sum = evenParticipants.reduce((s, pid) => s + (evenPersonUnits[pid] ?? 0), 0);
                      const diff = Math.round((100 - sum) * 100) / 100;
                      return (
                        <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                          {Math.abs(diff) < 0.01 ? "Totals 100% ✓" : diff > 0 ? `${diff}% unassigned` : `${Math.abs(diff)}% over`}
                        </p>
                      );
                    })()}
                  </div>
                )}

                {evenSplitType === "adjustment" && (() => {
                  const n = evenParticipants.length || 1;
                  const sumAdj = evenParticipants.reduce((s, pid) => s + (evenPersonUnits[pid] ?? 0), 0);
                  const baseline = (wholeBillTotal - sumAdj) / n;
                  return (
                    <div className="space-y-1.5">
                      {evenParticipants.map((pid) => {
                        const person = people.find((p) => p.id === pid);
                        const adj = evenPersonUnits[pid] ?? 0;
                        return (
                          <div key={pid} className="flex items-center justify-between gap-2">
                            <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                            <div className="flex items-center gap-1.5">
                              <span className="text-[11px] text-muted">+/−</span>
                              <input inputMode="decimal" value={adj || ""} onChange={(e) => setEvenWeight(pid, Number(e.target.value) || 0)}
                                placeholder="0.00" className="w-16 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                              <span className="w-16 text-right font-mono text-[12px] text-muted">{money(baseline + adj)}</span>
                            </div>
                          </div>
                        );
                      })}
                      <p className="text-[11px] text-muted mt-1">Base splits evenly; adjustments add or subtract on top.</p>
                    </div>
                  );
                })()}
              </div>
            );
          })()}

          <button onClick={() => setPhase("review")} disabled={evenParticipants.length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>

      )}

      {phase === "items" && (
        <div className="px-5 pt-4 animate-page-in">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-3">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

          {groups.length > 0 && (items.some((it) => it.category === "Food") || items.some((it) => it.category === "Drinks")) && (
            <div className="bg-white rounded-xl border border-line p-3 mb-3">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Quick assign by category</p>
              <div className="flex flex-wrap gap-1.5">
                <button onClick={() => assignCategoryToEveryone("Food")} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
                  🍽️ Food → Everyone
                </button>
                {groups.map((g) => (
                  <button key={g.id} onClick={() => assignCategoryToGroup("Drinks", g)} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
                    🍺 Drinks → {g.name}
                  </button>
                ))}
              </div>
            </div>
          )}

          <div className="space-y-3">
            {items.map((it) => (
              <div key={it.id} className="bg-white rounded-xl border border-line p-3.5">
                <div className="flex gap-2 mb-2.5">
                  <input className="flex-1 rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none" placeholder="Item name"
                    value={it.name} onChange={(e) => updateItem(it.id, { name: e.target.value })} />
                  <input inputMode="decimal" className="w-24 rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none" placeholder="$"
                    value={it.price} onChange={(e) => updateItem(it.id, { price: e.target.value })} />
                  <button onClick={() => removeItem(it.id)} className="p-2.5 rounded-xl bg-[#FBEDEA]">
                    <Trash2 size={16} className="text-owe" />
                  </button>
                </div>
                <div className="flex items-center gap-3 mb-2.5">
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted">Qty</span>
                    <input type="number" min={1} value={it.quantity}
                      onChange={(e) => updateItem(it.id, { quantity: Math.max(1, Number(e.target.value) || 1) })}
                      className="w-14 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted">Discount</span>
                    <input inputMode="decimal" value={it.discount} placeholder="0.00"
                      onChange={(e) => updateItem(it.id, { discount: e.target.value })}
                      className="w-20 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  </div>
                  {Number(it.discount) > 0 && (
                    <span className="text-[11px] text-accent font-medium">
                      → {money(Math.max(0, (Number(it.price) || 0) - Number(it.discount)))}
                    </span>
                  )}
                </div>
                <div className="flex gap-1.5 mb-2.5">
                  {CATEGORIES.map((c) => (
                    <button key={c} onClick={() => updateItem(it.id, { category: c })}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.category === c ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {c}
                    </button>
                  ))}
                </div>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Shared by</p>
                <div className="flex flex-wrap gap-1.5">
                  <button onClick={() => setItemPeople(it.id, people.map((p) => p.id))}
                    className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.length === people.length && people.length > 0 ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                    Everyone
                  </button>
                  {groups.map((g) => (
                    <button key={g.id} onClick={() => setItemPeople(it.id, g.memberIds)}
                      className="px-3.5 py-2 rounded-full text-[13px] font-medium border bg-[#F0EDE1] text-[#5B5748] border-line">
                      {g.name}
                    </button>
                  ))}
                  {people.map((p) => (
                    <button key={p.id} onClick={() => togglePerson(it.id, p.id)}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {p.name}
                    </button>
                  ))}
                </div>

                {it.personIds.length > 1 && (
                  <div className="mt-3 pt-3 border-t border-[#EDE9DC]">
                    <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Split</p>
                    <div className="flex gap-1.5 mb-3">
                      {(["even", "shares", "exact", "percent", "adjustment"] as const).map((t) => (
                        <button key={t} onClick={() => setSplitType(it.id, t)}
                          className={`px-2.5 py-1.5 rounded-full text-[11px] font-medium border ${it.splitType === t ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                          {t === "even" ? "Evenly" : t === "shares" ? "Shares" : t === "exact" ? "Exact $" : t === "percent" ? "%" : "Adjustment"}
                        </button>
                      ))}
                    </div>

                    {it.splitType === "even" && (
                      <p className="text-[11px] text-muted">
                        {money(Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0)) / it.personIds.length)} each · {it.personIds.length} people
                      </p>
                    )}

                    {it.splitType === "shares" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const units = it.personUnits[pid] ?? 1;
                          const totalUnits = it.personIds.reduce((s, id) => s + (it.personUnits[id] ?? 1), 0);
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const share = effectivePrice * (units / totalUnits);
                          return (
                            <div key={pid} className="flex items-center justify-between">
                              <span className="text-[13px] text-[#3A382F]">{person?.name}</span>
                              <div className="flex items-center gap-2">
                                <button onClick={() => setWeight(it.id, pid, Math.max(0, units - 1))} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">−</button>
                                <span className="w-5 text-center text-[13px] font-medium">{units}</span>
                                <button onClick={() => setWeight(it.id, pid, units + 1)} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">+</button>
                                <span className="w-16 text-right font-mono text-[12px] text-muted">{money(share)}</span>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    )}

                    {it.splitType === "exact" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const amt = it.personUnits[pid] ?? 0;
                          return (
                            <div key={pid} className="flex items-center justify-between gap-2">
                              <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                              <input inputMode="decimal" value={amt || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                placeholder="0.00" className="w-20 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                            </div>
                          );
                        })}
                        {(() => {
                          const sum = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const diff = Math.round((effectivePrice - sum) * 100) / 100;
                          return (
                            <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                              {Math.abs(diff) < 0.01 ? "Matches item price ✓" : diff > 0 ? `${money(diff)} unassigned` : `${money(Math.abs(diff))} over`}
                            </p>
                          );
                        })()}
                      </div>
                    )}

                    {it.splitType === "percent" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const pct = it.personUnits[pid] ?? 0;
                          return (
                            <div key={pid} className="flex items-center justify-between gap-2">
                              <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                              <div className="flex items-center gap-1">
                                <input inputMode="decimal" value={pct || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                  placeholder="0" className="w-14 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                                <span className="text-[12px] text-muted">%</span>
                              </div>
                            </div>
                          );
                        })}
                        {(() => {
                          const sum = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const diff = Math.round((100 - sum) * 100) / 100;
                          return (
                            <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                              {Math.abs(diff) < 0.01 ? "Totals 100% ✓" : diff > 0 ? `${diff}% unassigned` : `${Math.abs(diff)}% over`}
                            </p>
                          );
                        })()}
                      </div>
                    )}
                    {it.splitType === "adjustment" && (
                      <div className="space-y-1.5">
                        {(() => {
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const n = it.personIds.length || 1;
                          const sumAdj = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const baseline = (effectivePrice - sumAdj) / n;
                          return it.personIds.map((pid) => {
                            const person = people.find((p) => p.id === pid);
                            const adj = it.personUnits[pid] ?? 0;
                            const finalAmt = baseline + adj;
                            return (
                              <div key={pid} className="flex items-center justify-between gap-2">
                                <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                                <div className="flex items-center gap-1.5">
                                  <span className="text-[11px] text-muted">+/−</span>
                                  <input inputMode="decimal" value={adj || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                    placeholder="0.00" className="w-16 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                                  <span className="w-16 text-right font-mono text-[12px] text-muted">{money(finalAmt)}</span>
                                </div>
                              </div>
                            );
                          });
                        })()}
                        <p className="text-[11px] text-muted mt-1">Base splits evenly; adjustments add or subtract on top.</p>
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>

          <button onClick={addItem} className="w-full mt-3 rounded-xl border-2 border-dashed border-line py-3 flex items-center justify-center gap-1.5 text-[13px] font-semibold text-accent">
            <Plus size={16} /> Add item
          </button>

          <div className="flex items-center justify-between mt-5 mb-6">
            <span className="text-[13px] text-muted">Items total</span>
            <span className="font-mono text-[15px] font-semibold text-ink">{money(itemsSum)}</span>
          </div>

          <button onClick={() => setPhase("review")} disabled={items.filter((it) => it.name.trim() && Number(it.price) > 0).length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>
      )}

      {phase === "review" && (
        <div className="px-5 pt-4 animate-page-in">
          {splitMode === "even" ? (
            <div className="bg-white rounded-xl border border-line p-4 mb-4">
              <div className="flex justify-between text-[14px] font-semibold"><span>Total</span><span className="font-mono">{money(draftReceipt.total)}</span></div>
            </div>
          ) : (
            <div className="bg-white rounded-xl border border-line p-4 mb-4">
              <div className="flex justify-between text-[13px] mb-1"><span className="text-muted">Receipt total</span><span className="font-mono text-ink">{money(draftReceipt.total)}</span></div>
              <div className="flex justify-between text-[13px] mb-1"><span className="text-muted">Calculated total</span><span className="font-mono text-ink">{money(calculatedTotal)}</span></div>
              <div className={`flex justify-between text-[13px] items-center ${Math.abs(totalDifference) < 0.01 ? "text-accent" : "text-owe"}`}>
                <span>Difference</span>
                <span className="font-mono flex items-center gap-1">
                  {money(Math.abs(totalDifference))}
                  {Math.abs(totalDifference) < 0.01 ? <CheckCircle2 size={14} /> : <AlertTriangle size={14} />}
                </span>
              </div>
            </div>
          )}

          {splitMode === "itemized" && (
            <div className="flex gap-1.5 mb-5">
              <button onClick={() => setTaxTipMethod("proportional")}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "proportional" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                Tax/tip proportional
              </button>
              <button onClick={() => setTaxTipMethod("equal")}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "equal" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                Split equally
              </button>
            </div>
          )}

          {rawParticipantIds.length > 1 && (
            <div className="bg-white rounded-xl border border-line p-3.5 mb-4">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1">Anyone covering for someone else?</p>
              <p className="text-[11px] text-muted mb-2.5">Their charge folds into whoever's covering them — just for this receipt.</p>
              <div className="space-y-2">
                {rawParticipantIds.map((pid) => {
                  const person = people.find((p) => p.id === pid);
                  return (
                    <div key={pid} className="flex items-center justify-between gap-2">
                      <span className="text-[13px] text-ink">{person?.name}</span>
                      <select
                        value={coverage[pid] || ""}
                        onChange={(e) => {
                          const next = { ...coverage };
                          if (e.target.value) next[pid] = e.target.value;
                          else delete next[pid];
                          setCoverage(next);
                        }}
                        className="rounded-lg border border-line bg-white px-2 py-1.5 text-[12px] outline-none"
                      >
                        <option value="">Pays their own share</option>
                        {rawParticipantIds
                          .filter((id) => id !== pid)
                          .map((id) => (
                            <option key={id} value={id}>
                              Covered by {people.find((p) => p.id === id)?.name}
                            </option>
                          ))}
                      </select>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          <div className="space-y-2.5 mb-4">
            {Object.entries(shares).map(([pid, s]: any) => {
              const person = people.find((p) => p.id === pid);
              return (
                <div key={pid} className="bg-white rounded-xl border border-line p-3.5">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[14px] font-semibold text-ink">{person?.name}</span>
                    <span className="font-mono text-[15px] font-semibold text-ink">{money(s.total)}</span>
                  </div>
                  {s.food > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Food</span><span className="font-mono">{money(s.food)}</span></p>}
                  {s.drinks > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Drinks</span><span className="font-mono">{money(s.drinks)}</span></p>}
                  {s.other > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Other</span><span className="font-mono">{money(s.other)}</span></p>}
                  <p className="text-[13px] text-[#3A382F] flex justify-between py-1"><span>Tax, tip &amp; discount</span><span className="font-mono">{money(s.taxTip)}</span></p>
                </div>
              );
            })}
          </div>

          {unassignedItems.length > 0 && (
            <div className="rounded-xl bg-[#FBF3E6] border border-[#EEDDB8] px-4 py-3 text-[13px] text-[#7A5E24] mb-4">
              Not assigned yet: {unassignedItems.map((it) => it.name).join(", ")}
            </div>
          )}

          <div className={`rounded-xl px-4 py-3 mb-6 flex items-center justify-between text-[13px] font-medium ${Math.abs(unassigned) < 0.01 ? "bg-[#EFF7F3] text-[#1F7A5C]" : "bg-[#FBEDEA] text-owe"}`}>
            <span>{Math.abs(unassigned) < 0.01 ? "Fully assigned" : "Unassigned amount"}</span>
            <span className="font-mono flex items-center gap-1">
              {Math.abs(unassigned) < 0.01 ? <CheckCircle2 size={14} /> : money(unassigned)}
            </span>
          </div>

          <button onClick={save} disabled={saving} className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            {saving ? "Saving…" : "Save receipt"}
          </button>
        </div>
      )}
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/receipts/[id]/edit/page.tsx')
cat > 'app/receipts/[id]/edit/page.tsx' << 'FILEEOF'
"use client";

import { useEffect, useState } from "react";
import { useRouter, useParams } from "next/navigation";
import { Plus, Trash2, X, CheckCircle2, AlertTriangle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { computeReceiptShares, applyItemCoverage, resolveAdjustments } from "@/lib/split";
import { Category, Person, Group, TaxTipMethod, ReceiptCategory } from "@/lib/types";
import { splitName } from "@/lib/utils";

const CATEGORIES: Category[] = ["Food", "Drinks", "Other"];
const RECEIPT_CATEGORIES: ReceiptCategory[] = ["Dining", "Trips", "Roommates/Home", "Transportation", "Other"];

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}

interface DraftItem {
  id: string;
  name: string;
  price: string;
  discount: string;
  quantity: number;
  category: Category;
  personIds: string[];
  personUnits: Record<string, number>;
  splitType: "even" | "shares" | "exact" | "percent" | "adjustment";
}

type Phase = "basics" | "participants" | "items" | "review";

export default function EditReceiptPage() {
  const router = useRouter();
  const params = useParams();
  const receiptId = params.id as string;
  const supabase = createClient();

  const [loading, setLoading] = useState(true);
  const [phase, setPhase] = useState<Phase>("basics");
  const [people, setPeople] = useState<Person[]>([]);
  const [groups, setGroups] = useState<Group[]>([]);
  const [merchant, setMerchant] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [subtotal, setSubtotal] = useState("");
  const [tax, setTax] = useState("");
  const [tip, setTip] = useState("");
  const [additionalTip, setAdditionalTip] = useState("");
  const [coverage, setCoverage] = useState<Record<string, string>>({});
  const [discount, setDiscount] = useState("");
  const [total, setTotal] = useState("");
  const [selectedTipPct, setSelectedTipPct] = useState<number | null>(null);
  const [receiptCategory, setReceiptCategory] = useState<ReceiptCategory | null>(null);
  const [items, setItems] = useState<DraftItem[]>([]);
  const [taxTipMethod, setTaxTipMethod] = useState<TaxTipMethod>("proportional");
  const [splitMode, setSplitMode] = useState<"itemized" | "even">("itemized");
  const [evenParticipants, setEvenParticipants] = useState<string[]>([]);
  const [evenSplitType, setEvenSplitType] = useState<"even" | "shares" | "exact" | "percent" | "adjustment">("even");
  const [evenPersonUnits, setEvenPersonUnits] = useState<Record<string, number>>({});
  const [newPersonName, setNewPersonName] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    (async () => {
      const { data: p } = await supabase.from("people").select("*").order("name");
      setPeople(p ?? []);
      const { data: g } = await supabase.from("groups").select("*").order("name");
      const { data: m } = await supabase.from("group_members").select("*");
      setGroups(
        (g ?? []).map((grp) => ({ ...grp, memberIds: (m ?? []).filter((x) => x.group_id === grp.id).map((x) => x.person_id) }))
      );

      const { data: receipt } = await supabase.from("receipts").select("*").eq("id", receiptId).single();
      if (!receipt) {
        setLoading(false);
        return;
      }
      setMerchant(receipt.merchant || "");
      setDate(receipt.date || new Date().toISOString().slice(0, 10));
      setSubtotal(String(receipt.subtotal ?? ""));
      setTax(String(receipt.tax ?? ""));
      setTip(String(receipt.tip ?? ""));
      setAdditionalTip(String(receipt.additional_tip ?? ""));
      setDiscount(String(receipt.discount ?? ""));
      setTotal(String(receipt.total ?? ""));
      setTaxTipMethod(receipt.tax_tip_method || "proportional");
      setSplitMode(receipt.split_mode || "itemized");
      setReceiptCategory(receipt.category || null);

      const { data: dbItems } = await supabase.from("receipt_items").select("*").eq("receipt_id", receiptId);
      const itemIds = (dbItems ?? []).map((i) => i.id);
      const { data: dbSplits } = itemIds.length
        ? await supabase.from("item_splits").select("*").in("item_id", itemIds)
        : { data: [] };

      if (receipt.split_mode === "even") {
        const evenItem = (dbItems ?? [])[0];
        if (evenItem) {
          const splitsForItem = (dbSplits ?? []).filter((s) => s.item_id === evenItem.id);
          setEvenParticipants(splitsForItem.map((s) => s.person_id));
          const units = Object.fromEntries(splitsForItem.map((s) => [s.person_id, s.units ?? 1]));
          const values = Object.values(units);
          const allSame = values.length > 0 && values.every((v) => v === values[0]);
          setEvenPersonUnits(units);
          setEvenSplitType(allSame ? "even" : "shares");
        }
      } else {
        setItems(
          (dbItems ?? []).map((i) => {
            const splitsForItem = (dbSplits ?? []).filter((s) => s.item_id === i.id);
            const personUnits = Object.fromEntries(splitsForItem.map((s) => [s.person_id, s.units ?? 1]));
            const values = Object.values(personUnits);
            const allSame = values.length > 0 && values.every((v) => v === values[0]);
            return {
              id: i.id,
              name: i.name,
              price: String(i.price),
              discount: i.discount ? String(i.discount) : "",
              quantity: i.quantity || 1,
              category: i.category,
              personIds: splitsForItem.map((s) => s.person_id),
              personUnits,
              splitType: allSame ? "even" : "shares",
            } as DraftItem;
          })
        );
      }
      setLoading(false);
    })();
  }, [receiptId]);

  const itemsSum = items.reduce((s, it) => s + Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0)), 0);

  function addItem() {
    setItems([...items, { id: crypto.randomUUID(), name: "", price: "", discount: "", quantity: 1, category: "Food", personIds: [], personUnits: {}, splitType: "even" }]);
  }
  function updateItem(id: string, patch: Partial<DraftItem>) {
    setItems(items.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  }
  function removeItem(id: string) {
    setItems(items.filter((it) => it.id !== id));
  }
  function togglePerson(itemId: string, personId: string) {
    setItems(
      items.map((it) => {
        if (it.id !== itemId) return it;
        const has = it.personIds.includes(personId);
        return { ...it, personIds: has ? it.personIds.filter((id) => id !== personId) : [...it.personIds, personId] };
      })
    );
  }
  function setItemPeople(itemId: string, ids: string[]) {
    setItems(items.map((it) => (it.id === itemId ? { ...it, personIds: ids } : it)));
  }
  function setSplitType(itemId: string, type: DraftItem["splitType"]) {
    setItems(
      items.map((it) => {
        if (it.id !== itemId) return it;
        const count = it.personIds.length || 1;
        const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
        let personUnits: Record<string, number> = {};
        if (type === "shares") personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, 1]));
        else if (type === "exact") {
          const each = Math.round((effectivePrice / count) * 100) / 100;
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, each]));
        } else if (type === "percent") {
          const each = Math.round((100 / count) * 100) / 100;
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, each]));
        } else if (type === "adjustment") {
          personUnits = Object.fromEntries(it.personIds.map((pid) => [pid, 0]));
        }
        return { ...it, splitType: type, personUnits };
      })
    );
  }
  function setWeight(itemId: string, personId: string, value: number) {
    setItems(
      items.map((it) => (it.id === itemId ? { ...it, personUnits: { ...it.personUnits, [personId]: Math.max(0, value) } } : it))
    );
  }
  function assignCategoryToEveryone(category: Category) {
    const everyone = people.map((p) => p.id);
    setItems(items.map((it) => (it.category === category ? { ...it, personIds: everyone } : it)));
  }
  function assignCategoryToGroup(category: Category, group: Group) {
    setItems(items.map((it) => (it.category === category ? { ...it, personIds: group.memberIds } : it)));
  }

  async function addPerson() {
    if (!newPersonName.trim()) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;
    const { first_name, last_name } = splitName(newPersonName);
    const { data } = await supabase.from("people").insert({ user_id: user.id, name: newPersonName.trim(), first_name, last_name }).select().single();
    if (data) setPeople([...people, data]);
    setNewPersonName("");
  }

  const validItems =
    splitMode === "even"
      ? [
          {
            id: "even-split",
            name: "Whole bill",
            price:
              Number(total) ||
              (Number(subtotal) || 0) + (Number(tax) || 0) + (Number(tip) || 0) + (Number(additionalTip) || 0) - (Number(discount) || 0),
            discount: 0,
            quantity: 1,
            category: "Other" as Category,
            personIds: evenParticipants,
            personUnits: evenPersonUnits,
            splitType: evenSplitType,
          },
        ]
      : items
          .filter((it) => it.name.trim() && Number(it.price) > 0)
          .map((it) => ({ ...it, price: Number(it.price), discount: Number(it.discount) || 0 }));

  const rawParticipantIds = Array.from(new Set(validItems.flatMap((it) => it.personIds)));
  const coveredItems = applyItemCoverage(resolveAdjustments(validItems), coverage);

  const draftReceipt = {
    merchant: merchant.trim() || "Untitled receipt",
    date,
    subtotal: Number(subtotal) || itemsSum,
    tax: Number(tax) || 0,
    tip: Number(tip) || 0,
    additional_tip: Number(additionalTip) || 0,
    discount: Number(discount) || 0,
    total: Number(total) || (Number(subtotal) || itemsSum) + (Number(tax) || 0) + (Number(tip) || 0) + (Number(additionalTip) || 0) - (Number(discount) || 0),
    items: coveredItems,
    tax_tip_method: taxTipMethod,
    split_mode: splitMode,
  };
  const shares = computeReceiptShares(draftReceipt as any);

  // Reconciliation
  const calculatedTotal =
    draftReceipt.subtotal + draftReceipt.tax + draftReceipt.tip + draftReceipt.additional_tip - draftReceipt.discount;
  const totalDifference = Math.round((draftReceipt.total - calculatedTotal) * 100) / 100;
  const assignedTotal = Object.values(shares).reduce((s: number, sh: any) => s + sh.total, 0);
  const unassignedCheckTotal = splitMode === "even" ? draftReceipt.total : calculatedTotal;
  const unassigned = Math.round((unassignedCheckTotal - assignedTotal) * 100) / 100;
  const unassignedItems = splitMode === "itemized" ? validItems.filter((it) => it.personIds.length === 0) : [];

  async function save() {
    setSaving(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;

    const { error } = await supabase
      .from("receipts")
      .update({
        merchant: draftReceipt.merchant,
        date: draftReceipt.date,
        subtotal: draftReceipt.subtotal,
        tax: draftReceipt.tax,
        tip: draftReceipt.tip,
        additional_tip: draftReceipt.additional_tip,
        discount: draftReceipt.discount,
        total: draftReceipt.total,
        tax_tip_method: taxTipMethod,
        split_mode: splitMode,
        category: receiptCategory,
      })
      .eq("id", receiptId);

    if (error) {
      setSaving(false);
      return;
    }

    await supabase.from("receipt_items").delete().eq("receipt_id", receiptId);

    for (const item of coveredItems) {
      const { data: savedItem } = await supabase
        .from("receipt_items")
        .insert({
          receipt_id: receiptId,
          name: item.name,
          price: Number(item.price),
          discount: Number(item.discount) || 0,
          category: item.category,
          quantity: item.quantity || 1,
        })
        .select()
        .single();
      if (savedItem && item.personIds.length) {
        await supabase.from("item_splits").insert(
          item.personIds.map((personId) => ({
            item_id: savedItem.id,
            person_id: personId,
            units: item.personUnits?.[personId] ?? 1,
          }))
        );
      }
    }

    router.push(`/receipts/${receiptId}`);
    router.refresh();
  }

  function backFrom(p: Phase) {
    if (p === "basics") router.push(`/receipts/${receiptId}`);
    else if (p === "participants") setPhase("basics");
    else if (p === "items") setPhase("basics");
    else if (p === "review") setPhase(splitMode === "even" ? "participants" : "items");
  }

  const titles: Record<Phase, string> = {
    basics: "Edit Receipt",
    participants: "Who's In?",
    items: "Items",
    review: "Review & Split",
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-[13px] text-muted">Loading receipt…</p>
      </div>
    );
  }

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <button onClick={() => backFrom(phase)} className="text-[13px] text-muted">
          Back
        </button>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink">{titles[phase]}</h1>
        <button onClick={() => router.push(`/receipts/${receiptId}`)} className="p-1">
          <X size={18} className="text-muted" />
        </button>
      </div>

      {phase === "basics" && (
        <div className="px-5 pt-4 animate-page-in">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Merchant</p>
          <input value={merchant} onChange={(e) => setMerchant(e.target.value)} placeholder="e.g. King Pocha"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Date</p>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-4" />

          <div className="grid grid-cols-2 gap-2 mb-3">
            {[
              ["Subtotal", subtotal, setSubtotal],
              ["Tax", tax, setTax],
              ["Tip", tip, (v: string) => { setTip(v); setSelectedTipPct(null); }],
              ["Additional tip", additionalTip, setAdditionalTip],
              ["Discount", discount, setDiscount],
            ].map(([label, val, setter]: any) => (
              <div key={label}>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">{label}</p>
                <input inputMode="decimal" value={val} onChange={(e) => setter(e.target.value)} placeholder="0.00"
                  className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40" />
              </div>
            ))}
          </div>

          {Number(subtotal) > 0 && (
            <div className="mb-4">
              <p className="text-[11px] text-muted mb-1.5">Tip wasn't printed on the receipt? Calculate it:</p>
              <div className="flex gap-1.5">
                {[15, 18, 20, 25].map((pct) => (
                  <button
                    key={pct}
                    onClick={() => {
                      const calcTip = Math.round(((Number(subtotal) + Number(tax || 0)) * pct) / 100 * 100) / 100;
                      setTip(String(calcTip));
                      setSelectedTipPct(pct);
                      const newTotal = Number(subtotal) + Number(tax || 0) + calcTip - Number(discount || 0);
                      setTotal(String(Math.round(newTotal * 100) / 100));
                    }}
                    className={`flex-1 px-2 py-2 rounded-lg text-[13px] font-medium border ${selectedTipPct === pct ? "bg-accent text-white border-accent" : "bg-white text-[#5B5748] border-line"}`}
                  >
                    {pct}%
                  </button>
                ))}
              </div>
            </div>
          )}

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Total</p>
          <input inputMode="decimal" value={total} onChange={(e) => setTotal(e.target.value)} placeholder="0.00"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-1.5" />
          {(Number(subtotal) > 0 || Number(tax) > 0 || Number(tip) > 0) && (
            <button
              onClick={() => {
                const calc = Number(subtotal || 0) + Number(tax || 0) + Number(tip || 0) + Number(additionalTip || 0) - Number(discount || 0);
                setTotal(String(Math.round(calc * 100) / 100));
              }}
              className="text-[12px] text-accent font-medium mb-6"
            >
              Use calculated total ({money(Number(subtotal || 0) + Number(tax || 0) + Number(tip || 0) + Number(additionalTip || 0) - Number(discount || 0))})
            </button>
          )}
          {!(Number(subtotal) > 0 || Number(tax) > 0 || Number(tip) > 0) && <div className="mb-6" />}

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Category (optional)</p>
          <div className="flex flex-wrap gap-1.5 mb-6">
            {RECEIPT_CATEGORIES.map((c) => (
              <button
                key={c}
                onClick={() => setReceiptCategory(receiptCategory === c ? null : c)}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${receiptCategory === c ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}
              >
                {c}
              </button>
            ))}
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">How do you want to split it?</p>
          <div className="flex gap-1.5 mb-6">
            <button onClick={() => setSplitMode("itemized")}
              className={`flex-1 px-3.5 py-3 rounded-xl text-[13px] font-medium border ${splitMode === "itemized" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              By item
            </button>
            <button onClick={() => setSplitMode("even")}
              className={`flex-1 px-3.5 py-3 rounded-xl text-[13px] font-medium border ${splitMode === "even" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Whole bill, evenly
            </button>
          </div>

          <button
            onClick={() => setPhase(splitMode === "even" ? "participants" : "items")}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6"
          >
            Continue
          </button>
        </div>
      )}

      {phase === "participants" && (
        <div className="px-5 pt-4 animate-page-in">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-4">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Who was there?</p>
          <div className="flex flex-wrap gap-1.5 mb-4">
            <button onClick={() => setEvenParticipants(people.map((p) => p.id))}
              className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${evenParticipants.length === people.length && people.length > 0 ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
              Everyone
            </button>
            {people.map((p) => (
              <button key={p.id} onClick={() => setEvenParticipants((cur) => cur.includes(p.id) ? cur.filter((x) => x !== p.id) : [...cur, p.id])}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${evenParticipants.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                {p.name}
              </button>
            ))}
          </div>

          {evenParticipants.length > 0 && (() => {
            const wholeBillTotal = Number(total) || (Number(subtotal) || 0) + (Number(tax) || 0) + (Number(tip) || 0) + (Number(additionalTip) || 0) - (Number(discount) || 0);
            function setEvenType(type: typeof evenSplitType) {
              const count = evenParticipants.length || 1;
              let units: Record<string, number> = {};
              if (type === "shares") units = Object.fromEntries(evenParticipants.map((pid) => [pid, 1]));
              else if (type === "exact") {
                const each = Math.round((wholeBillTotal / count) * 100) / 100;
                units = Object.fromEntries(evenParticipants.map((pid) => [pid, each]));
              } else if (type === "percent") {
                const each = Math.round((100 / count) * 100) / 100;
                units = Object.fromEntries(evenParticipants.map((pid) => [pid, each]));
              } else if (type === "adjustment") {
                units = Object.fromEntries(evenParticipants.map((pid) => [pid, 0]));
              }
              setEvenSplitType(type);
              setEvenPersonUnits(units);
            }
            function setEvenWeight(pid: string, value: number) {
              setEvenPersonUnits((prev) => ({ ...prev, [pid]: Math.max(evenSplitType === "adjustment" ? -Infinity : 0, value) }));
            }
            return (
              <div className="bg-white rounded-xl border border-line p-3.5 mb-6">
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">How should this split?</p>
                <div className="flex flex-wrap gap-1.5 mb-3">
                  {(["even", "shares", "exact", "percent", "adjustment"] as const).map((t) => (
                    <button key={t} onClick={() => setEvenType(t)}
                      className={`px-2.5 py-1.5 rounded-full text-[11px] font-medium border ${evenSplitType === t ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {t === "even" ? "Evenly" : t === "shares" ? "Shares" : t === "exact" ? "Exact $" : t === "percent" ? "%" : "Adjustment"}
                    </button>
                  ))}
                </div>

                {evenSplitType === "even" && (
                  <p className="text-[13px] text-muted">{money(wholeBillTotal / evenParticipants.length)} each · {evenParticipants.length} people</p>
                )}

                {evenSplitType === "shares" && (
                  <div className="space-y-1.5">
                    {evenParticipants.map((pid) => {
                      const person = people.find((p) => p.id === pid);
                      const units = evenPersonUnits[pid] ?? 1;
                      const totalUnits = evenParticipants.reduce((s, id) => s + (evenPersonUnits[id] ?? 1), 0);
                      const share = wholeBillTotal * (units / totalUnits);
                      return (
                        <div key={pid} className="flex items-center justify-between">
                          <span className="text-[13px] text-[#3A382F]">{person?.name}</span>
                          <div className="flex items-center gap-2">
                            <button onClick={() => setEvenWeight(pid, Math.max(0, units - 1))} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">−</button>
                            <span className="w-5 text-center text-[13px] font-medium">{units}</span>
                            <button onClick={() => setEvenWeight(pid, units + 1)} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">+</button>
                            <span className="w-16 text-right font-mono text-[12px] text-muted">{money(share)}</span>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}

                {evenSplitType === "exact" && (
                  <div className="space-y-1.5">
                    {evenParticipants.map((pid) => {
                      const person = people.find((p) => p.id === pid);
                      const amt = evenPersonUnits[pid] ?? 0;
                      return (
                        <div key={pid} className="flex items-center justify-between gap-2">
                          <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                          <input inputMode="decimal" value={amt || ""} onChange={(e) => setEvenWeight(pid, Number(e.target.value) || 0)}
                            placeholder="0.00" className="w-20 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                        </div>
                      );
                    })}
                    {(() => {
                      const sum = evenParticipants.reduce((s, pid) => s + (evenPersonUnits[pid] ?? 0), 0);
                      const diff = Math.round((wholeBillTotal - sum) * 100) / 100;
                      return (
                        <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                          {Math.abs(diff) < 0.01 ? "Matches total ✓" : diff > 0 ? `${money(diff)} unassigned` : `${money(Math.abs(diff))} over`}
                        </p>
                      );
                    })()}
                  </div>
                )}

                {evenSplitType === "percent" && (
                  <div className="space-y-1.5">
                    {evenParticipants.map((pid) => {
                      const person = people.find((p) => p.id === pid);
                      const pct = evenPersonUnits[pid] ?? 0;
                      return (
                        <div key={pid} className="flex items-center justify-between gap-2">
                          <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                          <div className="flex items-center gap-1">
                            <input inputMode="decimal" value={pct || ""} onChange={(e) => setEvenWeight(pid, Number(e.target.value) || 0)}
                              placeholder="0" className="w-14 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                            <span className="text-[12px] text-muted">%</span>
                          </div>
                        </div>
                      );
                    })}
                    {(() => {
                      const sum = evenParticipants.reduce((s, pid) => s + (evenPersonUnits[pid] ?? 0), 0);
                      const diff = Math.round((100 - sum) * 100) / 100;
                      return (
                        <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                          {Math.abs(diff) < 0.01 ? "Totals 100% ✓" : diff > 0 ? `${diff}% unassigned` : `${Math.abs(diff)}% over`}
                        </p>
                      );
                    })()}
                  </div>
                )}

                {evenSplitType === "adjustment" && (() => {
                  const n = evenParticipants.length || 1;
                  const sumAdj = evenParticipants.reduce((s, pid) => s + (evenPersonUnits[pid] ?? 0), 0);
                  const baseline = (wholeBillTotal - sumAdj) / n;
                  return (
                    <div className="space-y-1.5">
                      {evenParticipants.map((pid) => {
                        const person = people.find((p) => p.id === pid);
                        const adj = evenPersonUnits[pid] ?? 0;
                        return (
                          <div key={pid} className="flex items-center justify-between gap-2">
                            <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                            <div className="flex items-center gap-1.5">
                              <span className="text-[11px] text-muted">+/−</span>
                              <input inputMode="decimal" value={adj || ""} onChange={(e) => setEvenWeight(pid, Number(e.target.value) || 0)}
                                placeholder="0.00" className="w-16 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                              <span className="w-16 text-right font-mono text-[12px] text-muted">{money(baseline + adj)}</span>
                            </div>
                          </div>
                        );
                      })}
                      <p className="text-[11px] text-muted mt-1">Base splits evenly; adjustments add or subtract on top.</p>
                    </div>
                  );
                })()}
              </div>
            );
          })()}

          <button onClick={() => setPhase("review")} disabled={evenParticipants.length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>

      )}

      {phase === "items" && (
        <div className="px-5 pt-4 animate-page-in">
          <div className="bg-white rounded-xl border border-line p-2.5 flex items-center gap-2 mb-3">
            <input value={newPersonName} onChange={(e) => setNewPersonName(e.target.value)} placeholder="Add a person…"
              className="flex-1 text-[14px] outline-none px-1.5" onKeyDown={(e) => e.key === "Enter" && addPerson()} />
            <button onClick={addPerson} className="px-3 py-1.5 rounded-lg bg-accent text-white text-[13px] font-semibold">Add</button>
          </div>

          {groups.length > 0 && (items.some((it) => it.category === "Food") || items.some((it) => it.category === "Drinks")) && (
            <div className="bg-white rounded-xl border border-line p-3 mb-3">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Quick assign by category</p>
              <div className="flex flex-wrap gap-1.5">
                <button onClick={() => assignCategoryToEveryone("Food")} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
                  🍽️ Food → Everyone
                </button>
                {groups.map((g) => (
                  <button key={g.id} onClick={() => assignCategoryToGroup("Drinks", g)} className="px-3 py-1.5 rounded-full text-[12px] font-medium border bg-white text-[#5B5748] border-line">
                    🍺 Drinks → {g.name}
                  </button>
                ))}
              </div>
            </div>
          )}

          <div className="space-y-3">
            {items.map((it) => (
              <div key={it.id} className="bg-white rounded-xl border border-line p-3.5">
                <div className="flex gap-2 mb-2.5">
                  <input className="flex-1 rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none" placeholder="Item name"
                    value={it.name} onChange={(e) => updateItem(it.id, { name: e.target.value })} />
                  <input inputMode="decimal" className="w-24 rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none" placeholder="$"
                    value={it.price} onChange={(e) => updateItem(it.id, { price: e.target.value })} />
                  <button onClick={() => removeItem(it.id)} className="p-2.5 rounded-xl bg-[#FBEDEA]">
                    <Trash2 size={16} className="text-owe" />
                  </button>
                </div>
                <div className="flex items-center gap-3 mb-2.5">
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted">Qty</span>
                    <input type="number" min={1} value={it.quantity}
                      onChange={(e) => updateItem(it.id, { quantity: Math.max(1, Number(e.target.value) || 1) })}
                      className="w-14 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-muted">Discount</span>
                    <input inputMode="decimal" value={it.discount} placeholder="0.00"
                      onChange={(e) => updateItem(it.id, { discount: e.target.value })}
                      className="w-20 rounded-lg border border-line bg-white px-2 py-1 text-[13px] outline-none" />
                  </div>
                  {Number(it.discount) > 0 && (
                    <span className="text-[11px] text-accent font-medium">
                      → {money(Math.max(0, (Number(it.price) || 0) - Number(it.discount)))}
                    </span>
                  )}
                </div>
                <div className="flex gap-1.5 mb-2.5">
                  {CATEGORIES.map((c) => (
                    <button key={c} onClick={() => updateItem(it.id, { category: c })}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.category === c ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {c}
                    </button>
                  ))}
                </div>
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Shared by</p>
                <div className="flex flex-wrap gap-1.5">
                  <button onClick={() => setItemPeople(it.id, people.map((p) => p.id))}
                    className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.length === people.length && people.length > 0 ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                    Everyone
                  </button>
                  {groups.map((g) => (
                    <button key={g.id} onClick={() => setItemPeople(it.id, g.memberIds)}
                      className="px-3.5 py-2 rounded-full text-[13px] font-medium border bg-[#F0EDE1] text-[#5B5748] border-line">
                      {g.name}
                    </button>
                  ))}
                  {people.map((p) => (
                    <button key={p.id} onClick={() => togglePerson(it.id, p.id)}
                      className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${it.personIds.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                      {p.name}
                    </button>
                  ))}
                </div>

                {it.personIds.length > 1 && (
                  <div className="mt-3 pt-3 border-t border-[#EDE9DC]">
                    <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Split</p>
                    <div className="flex gap-1.5 mb-3">
                      {(["even", "shares", "exact", "percent", "adjustment"] as const).map((t) => (
                        <button key={t} onClick={() => setSplitType(it.id, t)}
                          className={`px-2.5 py-1.5 rounded-full text-[11px] font-medium border ${it.splitType === t ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                          {t === "even" ? "Evenly" : t === "shares" ? "Shares" : t === "exact" ? "Exact $" : t === "percent" ? "%" : "Adjustment"}
                        </button>
                      ))}
                    </div>

                    {it.splitType === "even" && (
                      <p className="text-[11px] text-muted">
                        {money(Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0)) / it.personIds.length)} each · {it.personIds.length} people
                      </p>
                    )}

                    {it.splitType === "shares" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const units = it.personUnits[pid] ?? 1;
                          const totalUnits = it.personIds.reduce((s, id) => s + (it.personUnits[id] ?? 1), 0);
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const share = effectivePrice * (units / totalUnits);
                          return (
                            <div key={pid} className="flex items-center justify-between">
                              <span className="text-[13px] text-[#3A382F]">{person?.name}</span>
                              <div className="flex items-center gap-2">
                                <button onClick={() => setWeight(it.id, pid, Math.max(0, units - 1))} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">−</button>
                                <span className="w-5 text-center text-[13px] font-medium">{units}</span>
                                <button onClick={() => setWeight(it.id, pid, units + 1)} className="w-7 h-7 rounded-full bg-[#F0EDE1] text-[#5B5748] text-[15px] font-semibold">+</button>
                                <span className="w-16 text-right font-mono text-[12px] text-muted">{money(share)}</span>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    )}

                    {it.splitType === "exact" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const amt = it.personUnits[pid] ?? 0;
                          return (
                            <div key={pid} className="flex items-center justify-between gap-2">
                              <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                              <input inputMode="decimal" value={amt || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                placeholder="0.00" className="w-20 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                            </div>
                          );
                        })}
                        {(() => {
                          const sum = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const diff = Math.round((effectivePrice - sum) * 100) / 100;
                          return (
                            <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                              {Math.abs(diff) < 0.01 ? "Matches item price ✓" : diff > 0 ? `${money(diff)} unassigned` : `${money(Math.abs(diff))} over`}
                            </p>
                          );
                        })()}
                      </div>
                    )}

                    {it.splitType === "percent" && (
                      <div className="space-y-1.5">
                        {it.personIds.map((pid) => {
                          const person = people.find((p) => p.id === pid);
                          const pct = it.personUnits[pid] ?? 0;
                          return (
                            <div key={pid} className="flex items-center justify-between gap-2">
                              <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                              <div className="flex items-center gap-1">
                                <input inputMode="decimal" value={pct || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                  placeholder="0" className="w-14 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                                <span className="text-[12px] text-muted">%</span>
                              </div>
                            </div>
                          );
                        })}
                        {(() => {
                          const sum = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const diff = Math.round((100 - sum) * 100) / 100;
                          return (
                            <p className={`text-[11px] mt-1 ${Math.abs(diff) < 0.01 ? "text-accent" : "text-owe"}`}>
                              {Math.abs(diff) < 0.01 ? "Totals 100% ✓" : diff > 0 ? `${diff}% unassigned` : `${Math.abs(diff)}% over`}
                            </p>
                          );
                        })()}
                      </div>
                    )}
                    {it.splitType === "adjustment" && (
                      <div className="space-y-1.5">
                        {(() => {
                          const effectivePrice = Math.max(0, (Number(it.price) || 0) - (Number(it.discount) || 0));
                          const n = it.personIds.length || 1;
                          const sumAdj = it.personIds.reduce((s, pid) => s + (it.personUnits[pid] ?? 0), 0);
                          const baseline = (effectivePrice - sumAdj) / n;
                          return it.personIds.map((pid) => {
                            const person = people.find((p) => p.id === pid);
                            const adj = it.personUnits[pid] ?? 0;
                            const finalAmt = baseline + adj;
                            return (
                              <div key={pid} className="flex items-center justify-between gap-2">
                                <span className="text-[13px] text-[#3A382F] flex-1">{person?.name}</span>
                                <div className="flex items-center gap-1.5">
                                  <span className="text-[11px] text-muted">+/−</span>
                                  <input inputMode="decimal" value={adj || ""} onChange={(e) => setWeight(it.id, pid, Number(e.target.value) || 0)}
                                    placeholder="0.00" className="w-16 rounded-lg border border-line bg-white px-2 py-1.5 text-[13px] text-right outline-none" />
                                  <span className="w-16 text-right font-mono text-[12px] text-muted">{money(finalAmt)}</span>
                                </div>
                              </div>
                            );
                          });
                        })()}
                        <p className="text-[11px] text-muted mt-1">Base splits evenly; adjustments add or subtract on top.</p>
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>

          <button onClick={addItem} className="w-full mt-3 rounded-xl border-2 border-dashed border-line py-3 flex items-center justify-center gap-1.5 text-[13px] font-semibold text-accent">
            <Plus size={16} /> Add item
          </button>

          <div className="flex items-center justify-between mt-5 mb-6">
            <span className="text-[13px] text-muted">Items total</span>
            <span className="font-mono text-[15px] font-semibold text-ink">{money(itemsSum)}</span>
          </div>

          <button onClick={() => setPhase("review")} disabled={items.filter((it) => it.name.trim() && Number(it.price) > 0).length === 0}
            className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            Review split
          </button>
        </div>
      )}

      {phase === "review" && (
        <div className="px-5 pt-4 animate-page-in">
          {splitMode === "even" ? (
            <div className="bg-white rounded-xl border border-line p-4 mb-4">
              <div className="flex justify-between text-[14px] font-semibold"><span>Total</span><span className="font-mono">{money(draftReceipt.total)}</span></div>
            </div>
          ) : (
            <div className="bg-white rounded-xl border border-line p-4 mb-4">
              <div className="flex justify-between text-[13px] mb-1"><span className="text-muted">Receipt total</span><span className="font-mono text-ink">{money(draftReceipt.total)}</span></div>
              <div className="flex justify-between text-[13px] mb-1"><span className="text-muted">Calculated total</span><span className="font-mono text-ink">{money(calculatedTotal)}</span></div>
              <div className={`flex justify-between text-[13px] items-center ${Math.abs(totalDifference) < 0.01 ? "text-accent" : "text-owe"}`}>
                <span>Difference</span>
                <span className="font-mono flex items-center gap-1">
                  {money(Math.abs(totalDifference))}
                  {Math.abs(totalDifference) < 0.01 ? <CheckCircle2 size={14} /> : <AlertTriangle size={14} />}
                </span>
              </div>
            </div>
          )}

          {splitMode === "itemized" && (
            <div className="flex gap-1.5 mb-5">
              <button onClick={() => setTaxTipMethod("proportional")}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "proportional" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                Tax/tip proportional
              </button>
              <button onClick={() => setTaxTipMethod("equal")}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${taxTipMethod === "equal" ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"}`}>
                Split equally
              </button>
            </div>
          )}

          {rawParticipantIds.length > 1 && (
            <div className="bg-white rounded-xl border border-line p-3.5 mb-4">
              <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1">Anyone covering for someone else?</p>
              <p className="text-[11px] text-muted mb-2.5">Their charge folds into whoever's covering them — just for this receipt.</p>
              <div className="space-y-2">
                {rawParticipantIds.map((pid) => {
                  const person = people.find((p) => p.id === pid);
                  return (
                    <div key={pid} className="flex items-center justify-between gap-2">
                      <span className="text-[13px] text-ink">{person?.name}</span>
                      <select
                        value={coverage[pid] || ""}
                        onChange={(e) => {
                          const next = { ...coverage };
                          if (e.target.value) next[pid] = e.target.value;
                          else delete next[pid];
                          setCoverage(next);
                        }}
                        className="rounded-lg border border-line bg-white px-2 py-1.5 text-[12px] outline-none"
                      >
                        <option value="">Pays their own share</option>
                        {rawParticipantIds
                          .filter((id) => id !== pid)
                          .map((id) => (
                            <option key={id} value={id}>
                              Covered by {people.find((p) => p.id === id)?.name}
                            </option>
                          ))}
                      </select>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          <div className="space-y-2.5 mb-4">
            {Object.entries(shares).map(([pid, s]: any) => {
              const person = people.find((p) => p.id === pid);
              return (
                <div key={pid} className="bg-white rounded-xl border border-line p-3.5">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[14px] font-semibold text-ink">{person?.name}</span>
                    <span className="font-mono text-[15px] font-semibold text-ink">{money(s.total)}</span>
                  </div>
                  {s.food > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Food</span><span className="font-mono">{money(s.food)}</span></p>}
                  {s.drinks > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Drinks</span><span className="font-mono">{money(s.drinks)}</span></p>}
                  {s.other > 0 && <p className="text-[13px] text-[#3A382F] flex justify-between dotted-row py-1"><span>Other</span><span className="font-mono">{money(s.other)}</span></p>}
                  <p className="text-[13px] text-[#3A382F] flex justify-between py-1"><span>Tax, tip &amp; discount</span><span className="font-mono">{money(s.taxTip)}</span></p>
                </div>
              );
            })}
          </div>

          {unassignedItems.length > 0 && (
            <div className="rounded-xl bg-[#FBF3E6] border border-[#EEDDB8] px-4 py-3 text-[13px] text-[#7A5E24] mb-4">
              Not assigned yet: {unassignedItems.map((it) => it.name).join(", ")}
            </div>
          )}

          <div className={`rounded-xl px-4 py-3 mb-6 flex items-center justify-between text-[13px] font-medium ${Math.abs(unassigned) < 0.01 ? "bg-[#EFF7F3] text-[#1F7A5C]" : "bg-[#FBEDEA] text-owe"}`}>
            <span>{Math.abs(unassigned) < 0.01 ? "Fully assigned" : "Unassigned amount"}</span>
            <span className="font-mono flex items-center gap-1">
              {Math.abs(unassigned) < 0.01 ? <CheckCircle2 size={14} /> : money(unassigned)}
            </span>
          </div>

          <button onClick={save} disabled={saving} className="w-full rounded-xl bg-accent text-white font-semibold py-3.5 mb-6 disabled:opacity-40">
            {saving ? "Saving…" : "Save changes"}
          </button>
        </div>
      )}
    </div>
  );
}
FILEEOF

mkdir -p $(dirname 'app/receipts/[id]/page.tsx')
cat > 'app/receipts/[id]/page.tsx' << 'FILEEOF'
import Link from "next/link";
import { Pencil, FileText } from "lucide-react";
import { loadPeople, loadReceipt, receiptImageUrl } from "@/lib/data";
import { computeReceiptShares } from "@/lib/split";
import DeleteReceiptButton from "./DeleteReceiptButton";

function money(n: number) {
  return (isFinite(n) ? n : 0).toLocaleString("en-US", { style: "currency", currency: "USD" });
}
function fmtDate(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export default async function ReceiptDetailPage({ params }: { params: { id: string } }) {
  const [receipt, people] = await Promise.all([loadReceipt(params.id), loadPeople()]);
  if (!receipt) return <p className="p-5 text-muted text-sm">This receipt was removed.</p>;

  const imageUrl = await receiptImageUrl(receipt.image_path);
  const shares = computeReceiptShares(receipt);
  const nameFor = (id: string) => people.find((p) => p.id === id)?.name ?? "—";

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Link href="/receipts" className="text-[13px] text-muted">Back</Link>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink truncate px-2">{receipt.merchant}</h1>
        <Link href={`/receipts/${receipt.id}/edit`} className="p-2 -mr-1 rounded-full active:bg-[#F5F3EC]">
          <Pencil size={16} className="text-muted" />
        </Link>
        <DeleteReceiptButton receiptId={receipt.id} imagePath={receipt.image_path} />
      </div>

      <div className="px-5 pt-4">
        {imageUrl && receipt.image_mime === "application/pdf" ? (
          <a
            href={imageUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="w-full rounded-xl mb-4 border border-line bg-white flex items-center gap-3 px-4 py-3"
          >
            <FileText size={20} className="text-accent" />
            <span className="text-[14px] font-medium text-ink">View original PDF</span>
          </a>
        ) : (
          imageUrl && <img src={imageUrl} alt="Receipt" className="w-full rounded-xl mb-4 border border-line" />
        )}
        <p className="text-[12px] text-muted mb-4">{fmtDate(receipt.date)}</p>

        <div className="bg-white rounded-xl border border-line p-4 mb-5">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Items</p>
          {receipt.items.map((it) => (
            <div key={it.id} className="py-1.5">
              <div className="flex justify-between text-[14px] text-[#3A382F]">
                <span>{it.name}</span>
                <span className="font-mono">
                  {it.discount > 0 ? (
                    <>
                      <span className="line-through text-[#B4AEA0] mr-1.5">{money(it.price)}</span>
                      {money(Math.max(0, it.price - it.discount))}
                    </>
                  ) : (
                    money(it.price)
                  )}
                </span>
              </div>
              <p className="text-[11px] text-[#A29C8B]">
                {it.category} · {it.personIds.map(nameFor).join(", ")}
                {it.discount > 0 && <span className="text-accent"> · −{money(it.discount)} discount</span>}
              </p>
            </div>
          ))}
          <div className="border-t border-[#EDE9DC] mt-2 pt-2 space-y-1">
            <div className="flex justify-between text-[14px]"><span>Subtotal</span><span className="font-mono">{money(receipt.subtotal)}</span></div>
            <div className="flex justify-between text-[14px]"><span>Tax</span><span className="font-mono">{money(receipt.tax)}</span></div>
            <div className="flex justify-between text-[14px]"><span>Tip</span><span className="font-mono">{money(receipt.tip)}</span></div>
            {receipt.additional_tip > 0 && <div className="flex justify-between text-[14px]"><span>Additional tip</span><span className="font-mono">{money(receipt.additional_tip)}</span></div>}
            {receipt.discount > 0 && <div className="flex justify-between text-[14px] text-accent"><span>Discount</span><span className="font-mono">-{money(receipt.discount)}</span></div>}
            <div className="flex justify-between text-[14px] font-semibold"><span>Total</span><span className="font-mono">{money(receipt.total)}</span></div>
          </div>
        </div>

        <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-2">Who owes what</p>
        <div className="space-y-2 mb-8">
          {Object.entries(shares).map(([pid, s]) => (
            <Link key={pid} href={`/people/${pid}`} className="w-full bg-white rounded-xl border border-line px-4 py-3 flex items-center justify-between">
              <span className="text-[14px] font-medium text-ink">{nameFor(pid)}</span>
              <span className="font-mono text-[14px] font-semibold text-ink">{money(s.total)}</span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}
FILEEOF

echo "Files updated. Running tests..."
npm test
echo "Now run: git add . && git commit -m \"Add full Splitwise-style split options, short links, Additional Tip, coverage\" && git push"
