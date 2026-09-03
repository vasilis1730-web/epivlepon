/**
 * Μορφοποίηση τιμών κατά τα ελληνικά διοικητικά πρότυπα.
 */

const EUR = new Intl.NumberFormat('el-GR', {
  style: 'currency', currency: 'EUR', minimumFractionDigits: 2, maximumFractionDigits: 2,
})
const NUM = new Intl.NumberFormat('el-GR', { maximumFractionDigits: 2 })
const QTY = new Intl.NumberFormat('el-GR', { maximumFractionDigits: 4 })
const DATE = new Intl.DateTimeFormat('el-GR', { day: '2-digit', month: '2-digit', year: 'numeric' })
const DATE_LONG = new Intl.DateTimeFormat('el-GR', {
  weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
})

export function toDate(value: unknown): Date | null {
  if (!value) return null
  const s = String(value)
  const d = new Date(s.length === 10 ? `${s}T00:00:00` : s)
  return isNaN(d.getTime()) ? null : d
}

export function formatValue(
  value: unknown,
  dataType = 'text',
  _mask?: string | null,
): string {
  if (value === null || value === undefined || value === '') return '—'

  switch (dataType) {
    case 'currency': {
      const n = Number(value)
      return isNaN(n) ? String(value) : EUR.format(n)
    }
    case 'number': {
      const n = Number(value)
      return isNaN(n) ? String(value) : NUM.format(n)
    }
    case 'quantity': {
      const n = Number(value)
      return isNaN(n) ? String(value) : QTY.format(n)
    }
    case 'date': {
      const d = toDate(value)
      return d ? DATE.format(d) : String(value)
    }
    case 'date_long': {
      const d = toDate(value)
      return d ? DATE_LONG.format(d) : String(value)
    }
    case 'boolean':
      return value ? 'ΝΑΙ' : 'ΟΧΙ'
    default:
      return String(value)
  }
}

/** Αυτόματη επιλογή τύπου όταν δεν δηλώνεται στο template_fields. */
export function inferType(key: string, value: unknown): string {
  if (typeof value === 'number') {
    return /poso|aksia|dapani|timi|synolo|ypoloipo|amount/i.test(key) ? 'currency' : 'number'
  }
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}/.test(value)) return 'date'
  if (typeof value === 'boolean') return 'boolean'
  return 'text'
}

export const escapeHtml = (s: string) =>
  s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!))

/** Ελληνικός τακτικός αριθμός: 1 → 1ος, 2 → 2ος … */
export const ordinal = (n: number) => `${n}ος`

export const todayIso = () => new Date().toISOString().slice(0, 10)

export function addMonths(iso: string, months: number): string {
  const d = new Date(`${iso}T00:00:00`)
  d.setMonth(d.getMonth() + months)
  return d.toISOString().slice(0, 10)
}

export function addDays(iso: string, days: number): string {
  const d = new Date(`${iso}T00:00:00`)
  d.setDate(d.getDate() + days)
  return d.toISOString().slice(0, 10)
}
