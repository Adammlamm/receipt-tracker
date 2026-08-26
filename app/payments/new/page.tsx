"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { allocatePersonPayments } from "@/lib/split";
import { Person, Receipt, Payment, PaymentMethod } from "@/lib/types";

const METHODS: PaymentMethod[] = ["Venmo", "Zelle", "Apple Cash", "Cash", "PayPal", "Other"];

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
