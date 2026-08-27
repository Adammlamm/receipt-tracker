import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const maxDuration = 30;

// Belt-and-suspenders limits, independent of the site-wide middleware:
const ALLOWED_MEDIA_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);
const MAX_BYTES = 8 * 1024 * 1024; // 8MB
const DAILY_SCAN_LIMIT = 40; // generous for personal use, cheap insurance against runaway/abusive calls

const SYSTEM_PROMPT = `You read restaurant/store receipts from photos or PDFs and extract structured data.
Return ONLY valid JSON, no prose, no markdown fences, matching exactly this shape:

{
  "merchant": string,
  "date": string | null,       // YYYY-MM-DD if you can read it, else null
  "items": [
    { "name": string, "quantity": number, "unit_price": number, "category": "Food" | "Drinks" | "Other" }
  ],
  "subtotal": number | null,
  "tax": number | null,
  "tip": number | null,
  "discount": number | null,   // positive number representing amount subtracted, 0 if none
  "total": number | null
}

Rules:
- "unit_price" is the price for ONE unit of that item (if the receipt shows a line total for multiple quantity, divide it).
- Guess "category" per item: alcohol/beer/wine/cocktails -> "Drinks", soda/coffee/juice/water are also "Drinks", entrees/appetizers/sides -> "Food", anything else (fees, misc) -> "Other".
- If a value truly isn't visible on the receipt, use null rather than guessing.
- Do not include currency symbols in numbers.
- Respond with raw JSON only.`;

export async function POST(request: Request) {
  // 1. Require a genuine authenticated session, checked here directly rather than
  // trusting only the site-wide middleware — defense in depth.
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Please sign in to scan receipts." }, { status: 401 });
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      { error: "Receipt scanning isn't configured yet (missing ANTHROPIC_API_KEY)." },
      { status: 500 }
    );
  }

  const { imageBase64, mediaType } = await request.json();
  if (!imageBase64) {
    return NextResponse.json({ error: "No file provided." }, { status: 400 });
  }

  // 2. Only accept the file types we actually know how to send to the scanner.
  if (!ALLOWED_MEDIA_TYPES.has(mediaType)) {
    return NextResponse.json({ error: "Unsupported file type. Use a JPEG, PNG, WebP, or PDF." }, { status: 415 });
  }

  // 3. Guard against unexpectedly huge uploads (base64 is ~4/3 the size of the raw file).
  const approxBytes = (imageBase64.length * 3) / 4;
  if (approxBytes > MAX_BYTES + 2 * 1024 * 1024) {
    return NextResponse.json({ error: "That file is too large to scan (max ~8MB). Try a smaller photo or lighter PDF." }, { status: 413 });
  }

  // 4. Cap scans per account per day — cheap insurance against a compromised
  // session or a bug quietly running up API costs.
  const today = new Date().toISOString().slice(0, 10);
  const { data: usage } = await supabase
    .from("scan_usage")
    .select("count")
    .eq("user_id", user.id)
    .eq("day", today)
    .maybeSingle();

  if ((usage?.count ?? 0) >= DAILY_SCAN_LIMIT) {
    return NextResponse.json(
      { error: "You've hit today's scan limit. Enter this receipt manually, or try again tomorrow." },
      { status: 429 }
    );
  }

  await supabase
    .from("scan_usage")
    .upsert({ user_id: user.id, day: today, count: (usage?.count ?? 0) + 1 }, { onConflict: "user_id,day" });

  const isPdf = mediaType === "application/pdf";
  const contentBlock = isPdf
    ? { type: "document", source: { type: "base64", media_type: "application/pdf", data: imageBase64 } }
    : { type: "image", source: { type: "base64", media_type: mediaType, data: imageBase64 } };

  try {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 2000,
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: [contentBlock, { type: "text", text: "Extract this receipt into the JSON shape described." }],
          },
        ],
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error("Anthropic API error:", errText);
      return NextResponse.json({ error: "Receipt scan failed. Try entering it manually." }, { status: 502 });
    }

    const data = await res.json();
    const textBlock = data.content?.find((b: any) => b.type === "text");
    if (!textBlock) {
      return NextResponse.json({ error: "Couldn't read a response from the scanner." }, { status: 502 });
    }

    const cleaned = textBlock.text.replace(/```json|```/g, "").trim();
    let parsed;
    try {
      parsed = JSON.parse(cleaned);
    } catch {
      // The model didn't return valid JSON (e.g. it was refused, or the file wasn't a receipt) —
      // fail safely rather than passing unstructured text back to the client.
      return NextResponse.json({ error: "Couldn't read this as a receipt. Try entering it manually." }, { status: 422 });
    }
    return NextResponse.json(parsed);
  } catch (err) {
    console.error("scan-receipt error:", err);
    return NextResponse.json({ error: "Receipt scan failed. Try entering it manually." }, { status: 500 });
  }
}
