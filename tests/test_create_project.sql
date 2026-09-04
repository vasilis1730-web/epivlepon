-- =====================================================================
-- Έλεγχος της public.create_project_full() — έναρξη επίβλεψης έργου
-- Εκτελείται σε καθαρή τοπική εγκατάσταση (βλ. tests/supabase_stubs.sql).
-- =====================================================================
\set ON_ERROR_STOP off
\pset format unaligned
\pset tuples_only on

\set epiv   '''00000000-0000-0000-0000-00000000e001'''
\set proist '''00000000-0000-0000-0000-00000000e002'''

create or replace function pg_temp.as_user(p uuid) returns void
language sql as $$ select set_config('request.jwt.claim.sub', p::text, false)::void $$;

create or replace function pg_temp.try(label text, sql text) returns void
language plpgsql as $$
begin
  execute sql;
  raise notice '❌ %  — πέρασε ενώ έπρεπε να απορριφθεί', label;
exception when others then
  raise notice '✔ %  → %', label, left(sqlerrm, 110);
end $$;

-- Ωφέλιμο φορτίο δοκιμής -------------------------------------------------
create or replace function pg_temp.payload(p_code text, p_cont numeric default 15)
returns jsonb language sql as $$
  select jsonb_build_object(
    'project', jsonb_build_object(
      'code', p_code,
      'title', 'Ασφαλτοστρώσεις οδών Δ.Ε. Καλλιθέας',
      'category', 'odopoiia',
      'funding_source', 'ΣΑΤΑ 2026',
      'ka_budget_code', '30.7333.0021',
      'location', 'Δ.Ε. Καλλιθέας, Ρόδος'),
    'contractor', jsonb_build_object(
      'name', 'ΤΕΧΝΙΚΗ ΡΟΔΟΥ Α.Τ.Ε.', 'afm', '094512367',
      'doy', 'ΡΟΔΟΥ', 'email', 'info@texnikirodou.example',
      'legal_rep_name', 'Ιωάννης Καραγιάννης'),
    'contract', jsonb_build_object(
      'contract_no', 'ΔΡ-2026/031-ΣΥΜ',
      'signed_at', '2026-03-02',
      'budget_works_net', 400000,
      'discount_pct', 25.50,
      'ge_oe_pct', 18,
      'contingency_pct', p_cont,
      'revision_amount', 0,
      'total_duration_days', 300,
      'schedule_submit_days', 15,
      'maintenance_months', 15,
      'diary_mode', 'imerisio',
      'diary_penalty_per_day', 150),
    'assignments', jsonb_build_object(
      'epivlepon', '00000000-0000-0000-0000-00000000e001',
      'proistamenos_dy', '00000000-0000-0000-0000-00000000e002',
      'decision_no', '1245/2026', 'decision_date', '2026-03-04',
      'decision_ada', 'ΨΞΚ4ΩΛΖ-Β7Δ'),
    'guarantee', jsonb_build_object(
      'issuer', 'Τράπεζα Πειραιώς', 'guarantee_no', 'e-ΕΓΓ-2026/8841',
      'issued_at', '2026-02-24', 'original_amount', 18000)
  );
$$;

\echo ''
\echo '── 1. Ο επιβλέπων ΔΕΝ ανοίγει έργο (άρθρο 136 §2) ───────────────'
select pg_temp.as_user(:epiv::uuid);
select pg_temp.try('Επιβλέπων → δημιουργία έργου',
  $$select public.create_project_full(pg_temp.payload('ΤΕΣΤ-01'))$$);

\echo ''
\echo '── 2. Ο Προϊστάμενος Δ.Υ. ανοίγει το έργο ───────────────────────'
select pg_temp.as_user(:proist::uuid);
select 'Αποτέλεσμα: ' || jsonb_pretty(public.create_project_full(pg_temp.payload('ΤΕΣΤ-01')));

\echo ''
\echo '── 3. Έλεγχοι εγκυρότητας ───────────────────────────────────────'
select pg_temp.try('Διπλός κωδικός έργου',
  $$select public.create_project_full(pg_temp.payload('ΤΕΣΤ-01'))$$);
select pg_temp.try('Απρόβλεπτα 12% (επιτρεπτά μόνο 9% ή 15%)',
  $$select public.create_project_full(pg_temp.payload('ΤΕΣΤ-02', 12))$$);
select pg_temp.try('Μηδενική προθεσμία',
  $$select public.create_project_full(
      jsonb_set(pg_temp.payload('ΤΕΣΤ-03'), '{contract,total_duration_days}', '0'))$$);
select pg_temp.try('Χωρίς επιβλέποντα',
  $$select public.create_project_full(
      jsonb_set(pg_temp.payload('ΤΕΣΤ-04'), '{assignments,epivlepon}', '""'))$$);

\echo ''
\echo '── 4. Οικονομικά μεγέθη ─────────────────────────────────────────'
select format(
  E'Δαπάνη εργασιών μελέτης 400.000,00 · έκπτωση 25,50%%\n'
  '  εργασίες μετά την έκπτωση : %s  (αναμ. 298000.00)\n'
  '  ΓΕ & ΟΕ 18%%              : %s  (αναμ. 53640.00)\n'
  '  απρόβλεπτα 15%%           : %s  (αναμ. 52746.00)\n'
  '  αρχική συμβατική αξία     : %s  (αναμ. 404386.00)\n'
  '  με ΦΠΑ 24%%               : %s',
  c.works_value_net, c.ge_oe_amount, c.contingency_amount,
  c.initial_value_net, c.total_with_vat)
  from public.contracts c join public.projects p on p.id=c.project_id
 where p.code='ΤΕΣΤ-01';

\echo ''
\echo '── 5. Προθεσμίες (άρθρο 147 §2 και §4) ──────────────────────────'
select format('υπογραφή %s · λήξη %s (300 ημ.) · οριακή %s (+150 ημ.)',
              c.signed_at, c.original_end_date, c.oriaki_end_date)
  from public.contracts c join public.projects p on p.id=c.project_id
 where p.code='ΤΕΣΤ-01';

\echo ''
\echo '── 6. Τι δημιουργήθηκε ──────────────────────────────────────────'
select format('στάδια οδηγού: %s · εργασίες σταδίων: %s · ορισμοί: %s · εγγυήσεις: %s',
  (select count(*) from public.project_stages ps join public.projects p on p.id=ps.project_id where p.code='ΤΕΣΤ-01'),
  (select count(*) from public.project_stage_tasks t join public.project_stages ps on ps.id=t.project_stage_id
     join public.projects p on p.id=ps.project_id where p.code='ΤΕΣΤ-01'),
  (select count(*) from public.project_assignments a join public.projects p on p.id=a.project_id where p.code='ΤΕΣΤ-01'),
  (select count(*) from public.guarantees g join public.projects p on p.id=g.project_id where p.code='ΤΕΣΤ-01'));

select 'ρόλοι ορισμού: ' || string_agg(a.role::text, ', ' order by a.role::text)
  from public.project_assignments a join public.projects p on p.id=a.project_id
 where p.code='ΤΕΣΤ-01';

select 'πρώτα διαθέσιμα στάδια: ' || string_agg(ps.stage_code, ', ' order by ps.stage_code)
  from public.project_stages ps join public.projects p on p.id=ps.project_id
 where p.code='ΤΕΣΤ-01' and ps.status='available';

\echo ''
\echo '── 7. Ο ορισθείς επιβλέπων βλέπει πλέον το έργο του ─────────────'
select pg_temp.as_user(:epiv::uuid);
select format('can_read_project: %s · can_supervise: %s · can_approve: %s (αναμ. t/t/f)',
              app.can_read_project(p.id), app.can_supervise(p.id), app.can_approve(p.id))
  from public.projects p where p.code='ΤΕΣΤ-01';

set role authenticated;
select 'ορατά έργα μέσω RLS: ' || string_agg(code, ', ' order by code) from public.projects;
reset role;

\echo ''
\echo '── 8. Κατάλογος προσωπικού για τη φόρμα ─────────────────────────'
select pg_temp.as_user(:proist::uuid);
select format('%s — %s [%s]', full_name, coalesce(specialty,'—'),
              coalesce(array_to_string(roles, ','), ''))
  from public.org_people();
