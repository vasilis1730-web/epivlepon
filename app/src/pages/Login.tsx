import { useState } from 'react'
import * as api from '@/lib/api'
import { Button, Card, Field, Input } from '@/components/ui'

export default function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      await api.signIn(email, password)
      window.location.reload()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Αποτυχία σύνδεσης.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-paper px-4">
      <Card className="w-full max-w-sm p-6">
        <h1 className="font-serif text-2xl font-bold">
          Επίβλεψη <span className="text-accent">4412</span>
        </h1>
        <p className="mt-1 text-sm text-ink2">
          Σύστημα Ελέγχου Επίβλεψης Δημοσίων Έργων
        </p>

        <form onSubmit={submit} className="mt-6 space-y-4">
          <Field label="Ηλεκτρονικό ταχυδρομείο">
            <Input type="email" value={email} required autoComplete="username"
              onChange={e => setEmail(e.target.value)} />
          </Field>
          <Field label="Κωδικός">
            <Input type="password" value={password} required autoComplete="current-password"
              onChange={e => setPassword(e.target.value)} />
          </Field>
          {error && (
            <p className="rounded border border-oxide bg-oxide-soft px-3 py-2 text-sm text-ink">{error}</p>
          )}
          <Button type="submit" variant="primary" className="w-full" disabled={busy}>
            {busy ? 'Σύνδεση…' : 'Σύνδεση'}
          </Button>
        </form>

        <p className="mt-5 border-t border-rule pt-4 text-xs text-ink3">
          Χωρίς ρυθμίσεις Supabase, η εφαρμογή εκκινεί σε λειτουργία επίδειξης με
          δοκιμαστικά δεδομένα. Δείτε το <code className="font-mono">.env.example</code>.
        </p>
      </Card>
    </div>
  )
}
