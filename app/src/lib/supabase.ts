import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined
const forceDemo = import.meta.env.VITE_DEMO === '1'

/**
 * ΛΕΙΤΟΥΡΓΙΑ ΕΠΙΔΕΙΞΗΣ
 * Χωρίς μεταβλητές περιβάλλοντος, η εφαρμογή τρέχει με ενσωματωμένα
 * δοκιμαστικά δεδομένα ώστε να είναι άμεσα εκτελέσιμη (`npm run dev`).
 * Με τη συμπλήρωση του .env.local συνδέεται στο πραγματικό Supabase.
 */
export const DEMO_MODE = forceDemo || !url || !key

export const supabase: SupabaseClient | null = DEMO_MODE
  ? null
  : createClient(url!, key!, {
      auth: { persistSession: true, autoRefreshToken: true },
    })

export function requireClient(): SupabaseClient {
  if (!supabase) {
    throw new Error(
      'Η εφαρμογή εκτελείται σε λειτουργία επίδειξης. ' +
        'Συμπληρώστε VITE_SUPABASE_URL και VITE_SUPABASE_ANON_KEY στο .env.local.',
    )
  }
  return supabase
}
