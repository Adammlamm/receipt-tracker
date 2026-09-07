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
