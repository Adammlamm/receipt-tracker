import { NextResponse } from "next/server";

export const runtime = "nodejs";
export const maxDuration = 30;

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

  const isPdf = mediaType === "application/pdf";
  const contentBlock = isPdf
    ? { type: "document", source: { type: "base64", media_type: "application/pdf", data: imageBase64 } }
    : { type: "image", source: { type: "base64", media_type: mediaType || "image/jpeg", data: imageBase64 } };

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
    const parsed = JSON.parse(cleaned);
    return NextResponse.json(parsed);
  } catch (err) {
    console.error("scan-receipt error:", err);
    return NextResponse.json({ error: "Receipt scan failed. Try entering it manually." }, { status: 500 });
  }
}
