import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode, SelectHTMLAttributes, TextareaHTMLAttributes } from 'react'
import { useEffect, useRef } from 'react'
import { cx } from '@/lib/format'
import { formatLegalRef } from '@/lib/labels'
import { LEGAL_BY_ID } from '@/lib/catalogue'
import type { Blocker } from '@/lib/types'

/* ------------------------------ Button ---------------------------- */
type Variant = 'primary' | 'secondary' | 'ghost' | 'danger'

export function Button({
  variant = 'secondary', className, ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  return (
    <button
      {...props}
      className={cx(
        'inline-flex items-center justify-center gap-2 rounded border px-3 py-1.5 text-sm font-medium',
        'transition-colors disabled:cursor-not-allowed disabled:opacity-45',
        variant === 'primary' && 'border-accent bg-accent text-paper hover:brightness-110',
        variant === 'secondary' && 'border-rule2 bg-surface text-ink hover:border-accent hover:text-accent',
        variant === 'ghost' && 'border-transparent bg-transparent text-ink2 hover:text-accent',
        variant === 'danger' && 'border-oxide bg-oxide-soft text-oxide hover:brightness-105',
        className,
      )}
    />
  )
}

/* ------------------------------- Card ----------------------------- */
export function Card({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <section className={cx('rounded border border-rule bg-surface', className)}>{children}</section>
  )
}

export function CardHeader({
  title, subtitle, right, legalRef,
}: { title: string; subtitle?: ReactNode; right?: ReactNode; legalRef?: string | null }) {
  return (
    <header className="flex flex-wrap items-start justify-between gap-3 border-b border-rule px-4 py-3">
      <div className="min-w-0">
        <h2 className="font-serif text-base font-semibold leading-tight">{title}</h2>
        {subtitle && <p className="mt-0.5 text-xs text-ink2">{subtitle}</p>}
        {legalRef && <div className="mt-1"><LegalRef id={legalRef} /></div>}
      </div>
      {right && <div className="flex shrink-0 items-center gap-2">{right}</div>}
    </header>
  )
}

/* ------------------------------ Badge ----------------------------- */
type Tone = 'neutral' | 'accent' | 'brass' | 'oxide' | 'muted'

export function Badge({
  children, tone = 'neutral', className,
}: { children: ReactNode; tone?: Tone; className?: string }) {
  return (
    <span
      className={cx(
        'inline-flex items-center gap-1 whitespace-nowrap rounded border px-1.5 py-0.5 font-mono text-2xs',
        tone === 'neutral' && 'border-rule2 bg-raised text-ink2',
        tone === 'accent' && 'border-accent bg-accent-soft text-accent',
        tone === 'brass' && 'border-brass bg-brass-soft text-brass',
        tone === 'oxide' && 'border-oxide bg-oxide-soft text-oxide',
        tone === 'muted' && 'border-transparent bg-transparent text-ink3',
        className,
      )}
    >
      {children}
    </span>
  )
}

/* --------------------------- Legal reference ---------------------- */
export function LegalRef({ id, className }: { id: string | null | undefined; className?: string }) {
  if (!id) return null
  const meta = LEGAL_BY_ID.get(id)
  return (
    <span
      title={meta ? `${meta.law} — ${meta.title}` : undefined}
      className={cx('inline-flex items-center gap-1 font-mono text-2xs text-brass', className)}
    >
      <svg width="10" height="10" viewBox="0 0 16 16" aria-hidden="true" className="shrink-0">
        <path d="M3 2h7l3 3v9H3z" fill="none" stroke="currentColor" strokeWidth="1.4" />
        <path d="M9.5 2v3.5H13" fill="none" stroke="currentColor" strokeWidth="1.4" />
      </svg>
      {formatLegalRef(id)}
    </span>
  )
}

/* --------------------------- Blocker list ------------------------- */
export function BlockerList({ blockers, dense }: { blockers: Blocker[]; dense?: boolean }) {
  if (blockers.length === 0) {
    return (
      <p className="flex items-center gap-2 text-sm text-accent">
        <CheckIcon /> Δεν εκκρεμεί κανένα εμπόδιο.
      </p>
    )
  }
  return (
    <ul className={cx('space-y-2', dense && 'space-y-1.5')}>
      {blockers.map(b => (
        <li
          key={b.code}
          className={cx(
            'flex gap-2 rounded border-l-2 py-1 pl-3 pr-2 text-sm',
            b.severity === 'hard'
              ? 'border-l-oxide bg-oxide-soft/40 text-ink'
              : 'border-l-brass bg-brass-soft/40 text-ink2',
          )}
        >
          <span className="min-w-0 flex-1">
            {b.message}
            {b.legal_ref && <> <LegalRef id={b.legal_ref} className="ml-1" /></>}
          </span>
        </li>
      ))}
    </ul>
  )
}

/* ------------------------------ Table ----------------------------- */
export function Table({ children, minWidth = 640 }: { children: ReactNode; minWidth?: number }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-sm" style={{ minWidth }}>{children}</table>
    </div>
  )
}

export function Th({ children, align = 'start', className }: {
  children?: ReactNode; align?: 'start' | 'end' | 'center'; className?: string
}) {
  return (
    <th
      className={cx(
        'border-b border-rule2 px-3 py-2 font-mono text-2xs font-normal uppercase tracking-[0.1em] text-ink3',
        align === 'end' && 'text-right', align === 'center' && 'text-center',
        align === 'start' && 'text-left', className,
      )}
    >
      {children}
    </th>
  )
}

export function Td({ children, align = 'start', className }: {
  children?: ReactNode; align?: 'start' | 'end' | 'center'; className?: string
}) {
  return (
    <td
      className={cx(
        'border-b border-rule px-3 py-2 align-top',
        align === 'end' && 'text-right tnum', align === 'center' && 'text-center',
        className,
      )}
    >
      {children}
    </td>
  )
}

/* ------------------------------ Fields ---------------------------- */
export function Field({ label, hint, children, legalRef }: {
  label: string; hint?: string; children: ReactNode; legalRef?: string
}) {
  return (
    <label className="block">
      <span className="label-xs mb-1 flex items-center gap-2">
        {label}
        {legalRef && <LegalRef id={legalRef} />}
      </span>
      {children}
      {hint && <span className="mt-1 block text-xs text-ink3">{hint}</span>}
    </label>
  )
}

const inputCls =
  'w-full rounded border border-rule2 bg-paper px-2.5 py-1.5 text-sm text-ink placeholder:text-ink3'

export const Input = (p: InputHTMLAttributes<HTMLInputElement>) => (
  <input {...p} className={cx(inputCls, p.className)} />
)
export const Textarea = (p: TextareaHTMLAttributes<HTMLTextAreaElement>) => (
  <textarea {...p} className={cx(inputCls, 'min-h-[80px]', p.className)} />
)
export const Select = (p: SelectHTMLAttributes<HTMLSelectElement>) => (
  <select {...p} className={cx(inputCls, p.className)} />
)

/* ------------------------------ Modal ----------------------------- */
export function Modal({
  open, onClose, title, children, footer, wide,
}: {
  open: boolean; onClose: () => void; title: string
  children: ReactNode; footer?: ReactNode; wide?: boolean
}) {
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', onKey)
    ref.current?.focus()
    return () => document.removeEventListener('keydown', onKey)
  }, [open, onClose])

  if (!open) return null
  return (
    <div className="fixed inset-0 z-40 flex items-start justify-center overflow-y-auto bg-ink/40 p-4 sm:p-8">
      <div
        ref={ref}
        tabIndex={-1}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className={cx(
          'w-full rounded border border-rule2 bg-surface shadow-pop',
          wide ? 'max-w-3xl' : 'max-w-xl',
        )}
      >
        <header className="flex items-center justify-between border-b border-rule px-4 py-3">
          <h2 className="font-serif text-base font-semibold">{title}</h2>
          <Button variant="ghost" onClick={onClose} aria-label="Κλείσιμο">✕</Button>
        </header>
        <div className="max-h-[65vh] overflow-y-auto px-4 py-4">{children}</div>
        {footer && (
          <footer className="flex flex-wrap justify-end gap-2 border-t border-rule px-4 py-3">{footer}</footer>
        )}
      </div>
    </div>
  )
}

/* ----------------------------- Misc ------------------------------- */
export function EmptyState({ title, detail }: { title: string; detail?: string }) {
  return (
    <div className="px-4 py-10 text-center">
      <p className="font-serif text-base text-ink2">{title}</p>
      {detail && <p className="mx-auto mt-1 max-w-md text-sm text-ink3">{detail}</p>}
    </div>
  )
}

export function Spinner({ label = 'Φόρτωση…' }: { label?: string }) {
  return <p className="px-4 py-8 text-center text-sm text-ink3">{label}</p>
}

export function CheckIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden="true" className="shrink-0">
      <path d="M3 8.5l3.2 3.2L13 5" fill="none" stroke="currentColor" strokeWidth="2"
        strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export function LockIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 16 16" aria-hidden="true" className="shrink-0">
      <rect x="3" y="7" width="10" height="7" rx="1.2" fill="none" stroke="currentColor" strokeWidth="1.5" />
      <path d="M5.5 7V5a2.5 2.5 0 015 0v2" fill="none" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  )
}

/** Οριζόντια μπάρα προόδου με ένδειξη ορίου. */
export function Meter({
  value, max, limit, tone = 'accent',
}: { value: number; max: number; limit?: number; tone?: 'accent' | 'brass' | 'oxide' }) {
  const pctVal = max > 0 ? Math.min(100, (value / max) * 100) : 0
  const pctLimit = limit != null && max > 0 ? Math.min(100, (limit / max) * 100) : null
  return (
    <div className="relative h-2 w-full overflow-hidden rounded-full bg-raised">
      <div
        className={cx(
          'h-full rounded-full',
          tone === 'accent' && 'bg-accent',
          tone === 'brass' && 'bg-brass',
          tone === 'oxide' && 'bg-oxide',
        )}
        style={{ width: `${pctVal}%` }}
      />
      {pctLimit != null && (
        <div className="absolute inset-y-0 w-px bg-oxide" style={{ left: `${pctLimit}%` }} aria-hidden="true" />
      )}
    </div>
  )
}
