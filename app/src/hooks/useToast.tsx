import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'
import { cx } from '@/lib/format'

type ToastKind = 'success' | 'error' | 'info'
interface Toast { id: number; kind: ToastKind; title: string; detail?: string }

const Ctx = createContext<{
  push: (kind: ToastKind, title: string, detail?: string) => void
}>({ push: () => {} })

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Toast[]>([])

  const push = useCallback((kind: ToastKind, title: string, detail?: string) => {
    const id = Date.now() + Math.random()
    setItems(prev => [...prev, { id, kind, title, detail }])
    window.setTimeout(() => setItems(prev => prev.filter(t => t.id !== id)), 7000)
  }, [])

  const value = useMemo(() => ({ push }), [push])

  return (
    <Ctx.Provider value={value}>
      {children}
      <div className="pointer-events-none fixed bottom-4 right-4 z-50 flex w-[min(28rem,calc(100vw-2rem))] flex-col gap-2">
        {items.map(t => (
          <div
            key={t.id}
            role="status"
            className={cx(
              'pointer-events-auto rounded border p-3 shadow-pop',
              t.kind === 'error' && 'border-oxide bg-oxide-soft text-ink',
              t.kind === 'success' && 'border-accent bg-accent-soft text-ink',
              t.kind === 'info' && 'border-rule2 bg-surface text-ink',
            )}
          >
            <div className="text-sm font-semibold">{t.title}</div>
            {t.detail && <div className="mt-1 whitespace-pre-line text-xs text-ink2">{t.detail}</div>}
          </div>
        ))}
      </div>
    </Ctx.Provider>
  )
}

export const useToast = () => useContext(Ctx)
