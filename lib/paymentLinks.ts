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
