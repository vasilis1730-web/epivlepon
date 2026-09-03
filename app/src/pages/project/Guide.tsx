import { useState } from 'react'
import { useParams } from 'react-router-dom'
import { useQuery } from '@/hooks/useQuery'
import { useToast } from '@/hooks/useToast'
import * as api from '@/lib/api'
import { RuleViolation } from '@/lib/store'
import {
  Badge, BlockerList, Button, CheckIcon, Field, LegalRef, LockIcon,
  Modal, Spinner, Textarea,
} from '@/components/ui'
import { GenerateButton, hasTemplate } from '@/components/DocumentGenerator'
import { DOCS_BY_STAGE, STAGES_BY_CODE, TASKS_BY_STAGE } from '@/lib/catalogue'
import { PARTY, PHASE, RECURRENCE, STAGE_STATUS } from '@/lib/labels'
import { cx, date, daysUntil, relativeDays } from '@/lib/format'
import type { Blocker, ProjectStage, ProjectStageTask, StagePhase } from '@/lib/types'

export default function Guide() {
  const { projectId = '' } = useParams()
  const toast = useToast()
  const [openCode, setOpenCode] = useState<string | null>(null)
  const [phaseFilter, setPhaseFilter] = useState<StagePhase | 'all'>('all')
  const [overrideFor, setOverrideFor] = useState<{ stage: ProjectStage; blockers: Blocker[] } | null>(null)
  const [overrideReason, setOverrideReason] = useState('')

  const { data, loading } = useQuery(async () => {
    const [stages, profile] = await Promise.all([api.getStages(projectId), api.getProfile()])
    const detail = await Promise.all(
      stages.map(async s => ({
        stage: s,
        blockers: await api.getStageBlockers(s.id),
        tasks: await api.getStageTasks(s.id),
      })),
    )
    return { detail, profile }
  }, [projectId])

  if (loading || !data) return <Spinner />

  const phases = (Object.keys(PHASE) as StagePhase[]).filter(ph =>
    data.detail.some(d => STAGES_BY_CODE.get(d.stage.stage_code)?.phase === ph),
  )

  async function complete(stage: ProjectStage, blockers: Blocker[]) {
    try {
      await api.completeStage(stage.id)
      toast.push('success', 'Το στάδιο ολοκληρώθηκε', STAGES_BY_CODE.get(stage.stage_code)?.title)
    } catch (e) {
      if (e instanceof RuleViolation) {
        setOverrideFor({ stage, blockers: e.blockers })
      } else {
        setOverrideFor({ stage, blockers })
        toast.push('error', 'Η ενέργεια απορρίφθηκε', e instanceof Error ? e.message : undefined)
      }
    }
  }

  async function confirmOverride() {
    if (!overrideFor || overrideReason.trim().length < 10) return
    try {
      await api.completeStage(overrideFor.stage.id, {
        reason: overrideReason.trim(), profileId: data!.profile.id,
      })
      toast.push('info', 'Καταχωρήθηκε παράκαμψη',
        'Η ενέργεια καταγράφηκε στο μητρώο ελέγχου (audit log) με την αιτιολόγησή σας.')
      setOverrideFor(null)
      setOverrideReason('')
    } catch (e) {
      toast.push('error', 'Αποτυχία', e instanceof Error ? e.message : undefined)
    }
  }

  return (
    <div className="space-y-4">
      <header>
        <div className="label-xs">Απόλυτος οδηγός επίβλεψης</div>
        <h1 className="mt-1 font-serif text-2xl font-bold">Στάδια & σημεία ελέγχου</h1>
        <p className="mt-1 max-w-3xl text-sm text-ink2">
          Κάθε στάδιο κλείνει μόνο όταν ικανοποιηθούν τα προαπαιτούμενα στάδια, οι
          υποχρεωτικές ενέργειες, τα υποχρεωτικά έγγραφα και ο ειδικός νομικός κανόνας του.
        </p>
      </header>

      <div className="flex flex-wrap items-center gap-2">
        <span className="label-xs">Φάση</span>
        <FilterChip active={phaseFilter === 'all'} onClick={() => setPhaseFilter('all')}>Όλες</FilterChip>
        {phases.map(ph => (
          <FilterChip key={ph} active={phaseFilter === ph} onClick={() => setPhaseFilter(ph)}>
            {PHASE[ph].key} {PHASE[ph].name}
          </FilterChip>
        ))}
      </div>

      {phases.filter(ph => phaseFilter === 'all' || phaseFilter === ph).map(ph => {
        const items = data.detail.filter(d => STAGES_BY_CODE.get(d.stage.stage_code)?.phase === ph)
        return (
          <section key={ph}>
            <div className="flex items-baseline gap-3 border-b-2 border-ink pb-2">
              <span className="font-mono text-xs text-accent">{PHASE[ph].key}</span>
              <h2 className="font-serif text-lg font-semibold">{PHASE[ph].name}</h2>
              <span className="ml-auto font-mono text-2xs text-ink3">{items.length} στάδια</span>
            </div>
            <div>
              {items.map(({ stage, blockers, tasks }) => (
                <StageRow
                  key={stage.id}
                  stage={stage}
                  blockers={blockers}
                  tasks={tasks}
                  open={openCode === stage.stage_code}
                  onToggle={() => setOpenCode(openCode === stage.stage_code ? null : stage.stage_code)}
                  onComplete={() => complete(stage, blockers)}
                  onStart={async () => {
                    try { await api.startStage(stage.id) } catch (e) {
                      toast.push('error', 'Δεν μπορεί να ξεκινήσει',
                        e instanceof RuleViolation ? e.blockers.map(b => '• ' + b.message).join('\n') : undefined)
                    }
                  }}
                  onToggleTask={async (t, done) => { await api.toggleStageTask(t.id, done) }}
                />
              ))}
            </div>
          </section>
        )
      })}

      <Modal
        open={Boolean(overrideFor)}
        onClose={() => { setOverrideFor(null); setOverrideReason('') }}
        title="Το στάδιο δεν μπορεί να κλείσει"
        wide
        footer={
          <>
            <Button onClick={() => { setOverrideFor(null); setOverrideReason('') }}>Άκυρο</Button>
            <Button
              variant="danger"
              disabled={overrideReason.trim().length < 10}
              onClick={confirmOverride}
            >
              Παράκαμψη με αιτιολόγηση
            </Button>
          </>
        }
      >
        <p className="mb-3 text-sm text-ink2">
          Το σύστημα απέρριψε τη μετάβαση. Εκκρεμούν τα εξής:
        </p>
        <BlockerList blockers={overrideFor?.blockers.filter(b => b.severity === 'hard') ?? []} />
        <div className="mt-5 rounded border border-brass bg-brass-soft/50 p-3">
          <p className="text-xs text-ink2">
            Η παράκαμψη επιτρέπεται μόνο στον Προϊστάμενο της Διευθύνουσας Υπηρεσίας ή στην
            Προϊσταμένη Αρχή, καταγράφεται ανεξίτηλα στο μητρώο ελέγχου και συνεπάγεται
            προσωπική ευθύνη.
          </p>
          <div className="mt-3">
            <Field label="Αιτιολόγηση παράκαμψης" hint="Τουλάχιστον 10 χαρακτήρες.">
              <Textarea
                value={overrideReason}
                onChange={e => setOverrideReason(e.target.value)}
                placeholder="π.χ. Το έγγραφο τηρείται σε φυσικό αρχείο με αρ. πρωτ. …"
              />
            </Field>
          </div>
        </div>
      </Modal>
    </div>
  )
}

/* ------------------------------------------------------------------ */

function StageRow({
  stage, blockers, tasks, open, onToggle, onComplete, onStart, onToggleTask,
}: {
  stage: ProjectStage
  blockers: Blocker[]
  tasks: ProjectStageTask[]
  open: boolean
  onToggle: () => void
  onComplete: () => void
  onStart: () => void
  onToggleTask: (t: ProjectStageTask, done: boolean) => Promise<void>
}) {
  const def = STAGES_BY_CODE.get(stage.stage_code)
  if (!def) return null
  const hard = blockers.filter(b => b.severity === 'hard')
  const soft = blockers.filter(b => b.severity === 'soft')
  const days = daysUntil(stage.due_date)
  const done = ['completed', 'overdue', 'not_applicable'].includes(stage.status)
  const catalogueTasks = TASKS_BY_STAGE[stage.stage_code] ?? []
  const catalogueDocs = DOCS_BY_STAGE[stage.stage_code] ?? []

  return (
    <div className="border-b border-rule">
      <button
        onClick={onToggle}
        aria-expanded={open}
        className="grid w-full grid-cols-[2.5rem_1fr_auto] items-start gap-3 px-1 py-3 text-left hover:bg-surface"
      >
        <span className="pt-0.5 text-right font-mono text-xs text-ink3 tnum">
          {String(def.ordinal).padStart(2, '0')}
        </span>
        <span className="min-w-0">
          <span className="flex flex-wrap items-center gap-2">
            <span className={cx('text-[15px] font-semibold leading-snug', done && 'text-ink2')}>
              {def.title}
            </span>
            <StatusPill status={stage.status} hard={hard.length} />
          </span>
          <span className="mt-1.5 flex flex-wrap items-center gap-1.5">
            <Badge tone="accent">{PARTY[def.responsible]}</Badge>
            {def.approver && def.approver !== def.responsible && (
              <Badge tone="muted">εγκρίνει: {PARTY[def.approver]}</Badge>
            )}
            {stage.due_date && (
              <Badge tone={done ? 'muted' : days != null && days < 0 ? 'oxide' : 'brass'}>
                {date(stage.due_date)}
                {!done && <> · {relativeDays(days)}</>}
              </Badge>
            )}
            {def.tacit_approval && <Badge tone="oxide">σιωπηρή έγκριση</Badge>}
            {def.recurrence !== 'once' && <Badge tone="muted">{RECURRENCE[def.recurrence]}</Badge>}
            <LegalRef id={def.legal_ref_id} />
          </span>
        </span>
        <span className="whitespace-nowrap pt-0.5 text-right font-mono text-2xs text-ink3 tnum">
          {stage.tasks_done}/{stage.tasks_total} ενέργειες
          {hard.length > 0 && (
            <span className="ml-2 text-oxide">
              {hard.length} {hard.length === 1 ? 'εμπόδιο' : 'εμπόδια'}
            </span>
          )}
        </span>
      </button>

      {open && (
        <div className="grid gap-5 pb-5 pl-1 pr-1 sm:pl-14">
          <p className="max-w-3xl text-sm text-ink2">{def.purpose}</p>

          {def.risk_note && (
            <div className="max-w-3xl border-l-2 border-oxide pl-3">
              <div className="label-xs text-oxide">Τι διακυβεύεται</div>
              <p className="mt-0.5 text-sm text-ink2">{def.risk_note}</p>
            </div>
          )}

          {def.tacit_effect && (
            <div className="max-w-3xl rounded border border-brass bg-brass-soft/40 px-3 py-2">
              <div className="label-xs text-brass">Σιωπηρή έγκριση</div>
              <p className="mt-0.5 text-sm text-ink2">{def.tacit_effect}</p>
            </div>
          )}

          <div className="grid gap-5 lg:grid-cols-2">
            <div>
              <div className="label-xs mb-2">Λίστα ελέγχου — διαχωρισμός ρόλων</div>
              <ul className="space-y-1.5">
                {catalogueTasks.map(t => {
                  const inst = tasks.find(x => x.stage_task_id === t.id)
                  const checked = inst?.is_done ?? false
                  return (
                    <li key={t.id} className="flex items-start gap-2 text-sm">
                      <input
                        type="checkbox"
                        checked={checked}
                        disabled={!inst}
                        onChange={e => inst && onToggleTask(inst, e.target.checked)}
                        className="mt-1 h-3.5 w-3.5 shrink-0 accent-[rgb(var(--c-accent))]"
                        aria-label={t.title}
                      />
                      <span className={cx('min-w-0', checked && 'text-ink3 line-through')}>
                        <span className="font-medium text-accent">{PARTY[t.party]}:</span>{' '}
                        {t.title}
                        {!t.is_mandatory && <span className="ml-1 font-mono text-2xs text-ink3">προαιρετικό</span>}
                        {t.detail && <span className="mt-0.5 block text-xs text-ink3">{t.detail}</span>}
                        <LegalRef id={t.legal_ref_id} className="ml-0 mt-0.5 block" />
                      </span>
                    </li>
                  )
                })}
              </ul>
            </div>

            <div className="space-y-4">
              {catalogueDocs.length > 0 && (
                <div>
                  <div className="label-xs mb-2">Υποχρεωτικά έγγραφα</div>
                  <ul className="space-y-1">
                    {catalogueDocs.map(d => (
                      <li key={d.doc_code} className="flex items-baseline gap-2 text-sm">
                        <span className="font-mono text-2xs text-ink3">{d.doc_code}</span>
                        <span className="min-w-0 flex-1">
                          {d.title}
                          <span className="ml-1 text-xs text-ink3">— {PARTY[d.produced_by]}</span>
                        </span>
                        {hasTemplate(d.doc_code) && (
                          <GenerateButton
                            target={{
                              projectId: stage.project_id,
                              docCode: d.doc_code,
                              projectStageId: stage.id,
                            }}
                          />
                        )}
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              <div>
                <div className="label-xs mb-2">Έλεγχος fail-safe</div>
                <BlockerList blockers={[...hard, ...soft]} dense />
              </div>

              {def.prerequisites?.length > 0 && (
                <p className="text-xs text-ink3">
                  Προαπαιτούμενα:{' '}
                  <span className="font-mono text-ink2">{def.prerequisites.join(' · ')}</span>
                </p>
              )}

              {!done && (
                <div className="flex flex-wrap gap-2 pt-1">
                  {stage.status === 'available' && (
                    <Button onClick={onStart}>Έναρξη σταδίου</Button>
                  )}
                  <Button
                    variant={hard.length === 0 ? 'primary' : 'secondary'}
                    onClick={onComplete}
                  >
                    {hard.length === 0 ? 'Ολοκλήρωση σταδίου' : 'Απόπειρα ολοκλήρωσης'}
                  </Button>
                </div>
              )}

              {stage.override_reason && (
                <p className="rounded border border-brass bg-brass-soft/40 px-3 py-2 text-xs text-ink2">
                  <strong>Παράκαμψη:</strong> {stage.override_reason}
                </p>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function StatusPill({ status, hard }: { status: ProjectStage['status']; hard: number }) {
  const tone =
    status === 'completed' ? 'accent'
      : status === 'overdue' ? 'oxide'
        : status === 'locked' ? 'muted'
          : hard > 0 ? 'brass' : 'neutral'
  return (
    <Badge tone={tone as 'accent' | 'oxide' | 'muted' | 'brass' | 'neutral'}>
      {status === 'completed' && <CheckIcon />}
      {status === 'locked' && <LockIcon />}
      {STAGE_STATUS[status]}
    </Badge>
  )
}

function FilterChip({ active, onClick, children }: {
  active: boolean; onClick: () => void; children: React.ReactNode
}) {
  return (
    <button
      onClick={onClick}
      aria-pressed={active}
      className={cx(
        'rounded-full border px-3 py-1 text-xs font-medium',
        active ? 'border-accent bg-accent text-paper' : 'border-rule2 bg-surface text-ink2 hover:text-accent',
      )}
    >
      {children}
    </button>
  )
}
