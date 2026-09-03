import { NavLink, useParams } from 'react-router-dom'
import { useState, type ReactNode } from 'react'
import { cx } from '@/lib/format'
import { DEMO_MODE } from '@/lib/supabase'
import { Badge } from './ui'

const NAV = [
  { to: '', label: 'Επισκόπηση', end: true },
  { to: 'odigos', label: 'Οδηγός σταδίων' },
  { to: 'prothesmies', label: 'Προθεσμίες' },
  { to: 'imerologio', label: 'Ημερολόγιο' },
  { to: 'afaneis', label: 'Αφανείς εργασίες' },
  { to: 'epimetriseis', label: 'Επιμετρήσεις' },
  { to: 'logariasmoi', label: 'Λογαριασμοί' },
  { to: 'ape', label: 'ΑΠΕ' },
  { to: 'eggyiseis', label: 'Εγγυήσεις' },
  { to: 'peraiosi', label: 'Περαίωση & παραλαβή' },
  { to: 'eggrafa', label: 'Έγγραφα' },
]

export function AppShell({
  children, org, user, projectTitle, projectCode,
}: {
  children: ReactNode
  org: { name: string; unit: string } | undefined
  user: { full_name: string; specialty: string | null } | undefined
  projectTitle?: string
  projectCode?: string
}) {
  const { projectId } = useParams()
  const [dark, setDark] = useState(() => document.documentElement.classList.contains('dark'))
  const [navOpen, setNavOpen] = useState(false)

  function toggleTheme() {
    const next = !dark
    setDark(next)
    document.documentElement.classList.toggle('dark', next)
    localStorage.setItem('theme', next ? 'dark' : 'light')
  }

  return (
    <div className="flex min-h-full flex-col">
      <header className="sticky top-0 z-30 border-b border-rule bg-surface/95 backdrop-blur">
        <div className="mx-auto flex max-w-[1400px] items-center gap-3 px-4 py-2.5">
          <NavLink to="/" className="flex items-baseline gap-2 font-serif text-lg font-bold tracking-tight">
            Επίβλεψη <span className="text-accent">4412</span>
          </NavLink>
          {org && (
            <span className="hidden truncate text-xs text-ink3 md:inline">
              {org.name} · {org.unit}
            </span>
          )}
          <div className="ml-auto flex items-center gap-2">
            {DEMO_MODE && <Badge tone="brass">λειτουργία επίδειξης</Badge>}
            {user && (
              <span className="hidden text-xs text-ink2 sm:inline">
                {user.full_name}
                {user.specialty && <span className="text-ink3"> · {user.specialty}</span>}
              </span>
            )}
            <button
              onClick={toggleTheme}
              className="rounded border border-rule2 px-2 py-1 text-xs text-ink2 hover:text-accent"
              aria-label={dark ? 'Φωτεινό θέμα' : 'Σκοτεινό θέμα'}
            >
              {dark ? '☾' : '☀'}
            </button>
          </div>
        </div>
      </header>

      <div className="mx-auto flex w-full max-w-[1400px] flex-1 gap-0 px-0 sm:px-4">
        {projectId && (
          <>
            <button
              className="m-3 self-start rounded border border-rule2 px-2 py-1 text-xs lg:hidden"
              onClick={() => setNavOpen(o => !o)}
            >
              ☰ Ενότητες
            </button>
            <nav
              className={cx(
                'w-60 shrink-0 border-r border-rule py-4 pr-3 lg:block',
                navOpen ? 'block' : 'hidden',
              )}
            >
              {projectCode && (
                <div className="mb-3 px-3">
                  <div className="font-mono text-2xs text-ink3">{projectCode}</div>
                  <div className="mt-0.5 font-serif text-sm font-semibold leading-snug">{projectTitle}</div>
                </div>
              )}
              <ul className="space-y-0.5">
                {NAV.map(n => (
                  <li key={n.to || 'root'}>
                    <NavLink
                      to={`/erga/${projectId}/${n.to}`.replace(/\/$/, '')}
                      end={n.end}
                      onClick={() => setNavOpen(false)}
                      className={({ isActive }) =>
                        cx(
                          'block rounded-r border-l-2 px-3 py-1.5 text-sm',
                          isActive
                            ? 'border-l-accent bg-accent-soft font-semibold text-accent'
                            : 'border-l-transparent text-ink2 hover:border-l-rule2 hover:text-ink',
                        )
                      }
                    >
                      {n.label}
                    </NavLink>
                  </li>
                ))}
              </ul>
              <div className="mt-5 border-t border-rule px-3 pt-3">
                <NavLink to="/" className="text-xs text-ink3 hover:text-accent">
                  ← Όλα τα έργα
                </NavLink>
              </div>
            </nav>
          </>
        )}
        <main className="min-w-0 flex-1 px-4 py-5 sm:px-6">{children}</main>
      </div>

      <footer className="border-t border-rule px-4 py-4 text-center text-xs text-ink3">
        Οι έλεγχοι εφαρμόζονται σύμφωνα με τον ν. 4412/2016 (Βιβλίο Ι, Μέρος Β΄), όπως ισχύει
        μετά τον ν. 4782/2021.
      </footer>
    </div>
  )
}
