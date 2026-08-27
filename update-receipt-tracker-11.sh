#!/bin/bash
set -e
echo "Applying: automated test suite for the split math + CI on every push..."

mkdir -p $(dirname 'package.json')
cat > 'package.json' << 'FILEEOF'
{
  "name": "receipt-tracker",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@supabase/ssr": "^0.5.2",
    "@supabase/supabase-js": "^2.45.4",
    "lucide-react": "^0.383.0",
    "next": "14.2.5",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "recharts": "^2.15.4"
  },
  "devDependencies": {
    "@types/node": "^20.14.2",
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "autoprefixer": "^10.4.19",
    "postcss": "^8.4.38",
    "tailwindcss": "^3.4.4",
    "typescript": "^5.5.2",
    "vitest": "^4.1.11"
  }
}
FILEEOF

mkdir -p $(dirname 'lib/__tests__/split.test.ts')
cat > 'lib/__tests__/split.test.ts' << 'FILEEOF'
import { describe, it, expect } from "vitest";
import { computeReceiptShares, allocatePersonPayments } from "../split";
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
FILEEOF

mkdir -p $(dirname '.github/workflows/test.yml')
cat > '.github/workflows/test.yml' << 'FILEEOF'
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm ci
      - run: npm test
FILEEOF

echo "Files updated. Installing vitest..."
npm install
echo "Running the test suite now..."
npm test
echo "Done. Now run: git add . && git commit -m \"Add automated test suite for split math + CI\" && git push"
