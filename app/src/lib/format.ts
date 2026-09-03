const EUR = new Intl.NumberFormat('el-GR', {
  style: 'currency', currency: 'EUR', maximumFractionDigits: 2,
})
const NUM = new Intl.NumberFormat('el-GR', { maximumFractionDigits: 2 })
const NUM4 = new Intl.NumberFormat('el-GR', { maximumFractionDigits: 4 })
const DATE = new Intl.DateTimeFormat('el-GR', { day: '2-digit', month: '2-digit', year: 'numeric' })
const DATE_LONG = new Intl.DateTimeFormat('el-GR', { day: 'numeric', month: 'long', year: 'numeric' })

export const eur = (n: number | null | undefined) => (n == null ? '—' : EUR.format(n))
export const num = (n: number | null | undefined) => (n == null ? '—' : NUM.format(n))
export const qty = (n: number | null | undefined) => (n == null ? '—' : NUM4.format(n))
export const pct = (n: number | null | undefined, digits = 2) =>
  n == null ? '—' : `${NUM.format(Number(n.toFixed(digits)))}%`

export const date = (d: string | null | undefined) =>
  !d ? '—' : DATE.format(new Date(d + (d.length === 10 ? 'T00:00:00' : '')))

export const dateLong = (d: string | null | undefined) =>
  !d ? '—' : DATE_LONG.format(new Date(d + (d.length === 10 ? 'T00:00:00' : '')))

export const today = () => new Date().toISOString().slice(0, 10)

export function addDays(iso: string, days: number): string {
  const d = new Date(iso + 'T00:00:00')
  d.setDate(d.getDate() + days)
  return d.toISOString().slice(0, 10)
}

export function addMonths(iso: string, months: number): string {
  const d = new Date(iso + 'T00:00:00')
  d.setMonth(d.getMonth() + months)
  return d.toISOString().slice(0, 10)
}

/** Ημέρες που απομένουν έως την ημερομηνία (αρνητικές = εκπρόθεσμο). */
export function daysUntil(iso: string | null | undefined, from = today()): number | null {
  if (!iso) return null
  const a = new Date(from + 'T00:00:00').getTime()
  const b = new Date(iso + 'T00:00:00').getTime()
  return Math.round((b - a) / 86_400_000)
}

export function alertLevel(days: number | null): 'ok' | 'warning' | 'critical' | 'overdue' | 'none' {
  if (days == null) return 'none'
  if (days < 0) return 'overdue'
  if (days <= 5) return 'critical'
  if (days <= 15) return 'warning'
  return 'ok'
}

/** «σε 12 ημέρες» / «πριν 3 ημέρες» / «σήμερα» */
export function relativeDays(days: number | null): string {
  if (days == null) return '—'
  if (days === 0) return 'σήμερα'
  if (days === 1) return 'αύριο'
  if (days === -1) return 'χθες'
  return days > 0 ? `σε ${days} ημέρες` : `εκπρόθεσμο ${Math.abs(days)} ημέρες`
}

/** Εργάσιμες ημέρες μεταξύ δύο ημερομηνιών (Δευτ.-Παρ.). */
export function workingDaysBetween(fromIso: string, toIso: string): string[] {
  const out: string[] = []
  const d = new Date(fromIso + 'T00:00:00')
  const end = new Date(toIso + 'T00:00:00')
  while (d <= end) {
    const dow = d.getDay()
    if (dow !== 0 && dow !== 6) out.push(d.toISOString().slice(0, 10))
    d.setDate(d.getDate() + 1)
  }
  return out
}

export const cx = (...parts: (string | false | null | undefined)[]) =>
  parts.filter(Boolean).join(' ')
