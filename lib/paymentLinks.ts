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
