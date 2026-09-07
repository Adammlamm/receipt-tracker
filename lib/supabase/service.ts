import { createClient as createSupabaseClient } from "@supabase/supabase-js";

/**
 * Service-role client — bypasses row-level security entirely.
 * ONLY import this from server-side code (Route Handlers), never from
 * a "use client" component. It's what lets the public /friend page compute
 * a specific person's balance without giving anonymous visitors broad
 * database access.
 */
export function createServiceClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );
}
