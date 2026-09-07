export function splitName(fullName: string): { first_name: string; last_name: string } {
  const trimmed = fullName.trim();
  const idx = trimmed.indexOf(" ");
  if (idx === -1) return { first_name: trimmed, last_name: "" };
  return { first_name: trimmed.slice(0, idx), last_name: trimmed.slice(idx + 1).trim() };
}
