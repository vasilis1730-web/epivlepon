import { useCallback, useEffect, useState, useSyncExternalStore } from 'react'
import { getVersion, subscribe } from '@/lib/store'

/** Παρακολουθεί τις μεταβολές της τοπικής μνήμης (λειτουργία επίδειξης). */
export function useStoreVersion(): number {
  return useSyncExternalStore(
    cb => { const un = subscribe(cb); return () => { un() } },
    getVersion,
    getVersion,
  )
}

export interface QueryState<T> {
  data: T | undefined
  loading: boolean
  error: string | null
  reload: () => void
}

/**
 * Ελαφρύ hook ανάκτησης δεδομένων. Επανεκτελείται όταν αλλάξουν οι
 * εξαρτήσεις ή η κατάσταση της τοπικής μνήμης.
 */
export function useQuery<T>(fn: () => Promise<T>, deps: unknown[] = []): QueryState<T> {
  const version = useStoreVersion()
  const [data, setData] = useState<T>()
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [tick, setTick] = useState(0)

  const reload = useCallback(() => setTick(t => t + 1), [])

  useEffect(() => {
    let alive = true
    setLoading(true)
    fn()
      .then(res => { if (alive) { setData(res); setError(null) } })
      .catch((e: unknown) => { if (alive) setError(e instanceof Error ? e.message : String(e)) })
      .finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, version, tick])

  return { data, loading, error, reload }
}
