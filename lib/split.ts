import { Payment, Receipt } from "./types";

export interface PersonShare {
  food: number;
  drinks: number;
  other: number;
  itemSubtotal: number;
  taxTip: number;
  total: number;
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

  let itemsTotal = 0;
  for (const item of receipt.items ?? []) {
    const people = item.personIds ?? [];
    if (people.length === 0) continue;
    const per = item.price / people.length;
    itemsTotal += item.price;
    for (const pid of people) {
      const s = ensure(pid);
      s.itemSubtotal += per;
      if (item.category === "Food") s.food += per;
      else if (item.category === "Drinks") s.drinks += per;
      else s.other += per;
    }
  }

  const taxTip = (Number(receipt.tax) || 0) + (Number(receipt.tip) || 0) - (Number(receipt.discount) || 0);
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
