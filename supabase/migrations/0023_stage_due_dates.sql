-- =====================================================================
-- 0023_stage_due_dates.sql — Διόρθωση αφετηρίας των προθεσμιών σταδίου
-- ---------------------------------------------------------------------
-- ΤΟ ΠΡΟΒΛΗΜΑ
-- Η app.compute_stage_due() αναγνώριζε τρεις μόνο αφετηρίες και για κάθε
-- άλλη έπεφτε σιωπηλά στην ημερομηνία υπογραφής της σύμβασης. Έτσι στάδια
-- που κατά τον νόμο μετρούν από γεγονός που ΔΕΝ έχει ακόμη επέλθει —
-- υποβολή εγγράφου, κοινοποίηση πράξης, Βεβαίωση Περάτωσης, λήξη
-- συντήρησης — έπαιρναν ημερομηνία 10 ή 30 ημερών από την υπογραφή και
-- εμφανίζονταν ως ΕΚΠΡΟΘΕΣΜΑ σε έργο που μόλις ξεκίνησε.
--
-- Ένας επιβλέπων που βλέπει «Έκδοση Βεβαίωσης Περάτωσης — εκπρόθεσμο 145
-- ημέρες» σε έργο υπό εκτέλεση μαθαίνει να αγνοεί τις ειδοποιήσεις. Ένα
-- σύστημα ελέγχου που παράγει ψευδείς συναγερμούς είναι χειρότερο από
-- κανένα.
--
-- Η ΔΙΟΡΘΩΣΗ
-- Η προθεσμία υπολογίζεται μόνο όταν υπάρχει η αφετηρία της. Αλλιώς
-- επιστρέφεται NULL: το στάδιο απλώς δεν έχει ακόμη προθεσμία.
--
--   ypografi_symvasis   → ημερομηνία υπογραφής                (147 §2)
--   enarxi_ergasion     → προθεσμία έναρξης εργασιών          (145 §2)
--   lixi_prothesmias    → τρέχουσα λήξη συνολικής προθεσμίας  (147 §1)
--   bebaiosi_peratosis  → έκδοση Βεβαίωσης Περάτωσης          (168 §2)
--   lixi_syntirisis     → λήξη υποχρεωτικής συντήρησης        (171)
--   ypovoli_eggrafou    ┐ ανά έγγραφο/γεγονός: οι προθεσμίες αυτές
--   koinopoiisi_praxis  ├ τηρούνται στην ίδια την εγγραφή (approval_due,
--   custom              ┘ inspection_due, decision_due) — όχι στο στάδιο.
-- =====================================================================

create or replace function app.compute_stage_due(p_project_id uuid, p_stage_code text)
returns date
language plpgsql
stable
set search_path = public, app
as $$
declare
  s      public.workflow_stages%rowtype;
  v_base date;
begin
  select * into s from public.workflow_stages where code = p_stage_code;
  if not found then return null; end if;
  if s.deadline_days is null and s.deadline_months is null then return null; end if;

  case s.deadline_basis
    when 'ypografi_symvasis' then
      select c.signed_at into v_base from public.contracts c where c.project_id = p_project_id;

    when 'enarxi_ergasion' then
      select c.works_start_deadline into v_base from public.contracts c where c.project_id = p_project_id;

    when 'lixi_prothesmias' then
      select c.current_end_date into v_base from public.contracts c where c.project_id = p_project_id;

    when 'bebaiosi_peratosis' then
      -- Άρθρο 168 §2: μετρά από την έκδοση της Βεβαίωσης — ή από τον χρόνο
      -- που αυτή τεκμαίρεται εκδοθείσα μετά την όχληση του αναδόχου.
      select coalesce(cm.certificate_issued_at,
                      case when cm.deemed_issued then cm.certificate_due end)
        into v_base
        from public.completions cm where cm.project_id = p_project_id;

    when 'lixi_syntirisis' then
      -- Άρθρο 171: η παραλαβή μετρά από τη λήξη του χρόνου συντήρησης.
      select mp.ends_on into v_base
        from public.maintenance_periods mp
       where mp.project_id = p_project_id
       order by mp.ends_on desc nulls last limit 1;

    else
      -- ypovoli_eggrafou / koinopoiisi_praxis / custom: η αφετηρία είναι
      -- συγκεκριμένο έγγραφο ή πράξη. Χωρίς αυτό δεν υπάρχει προθεσμία —
      -- και δεν επινοούμε καμία.
      v_base := null;
  end case;

  if v_base is null then return null; end if;

  if s.deadline_months is not null then
    v_base := v_base + (s.deadline_months || ' months')::interval;
  end if;
  if s.deadline_days is not null then
    v_base := v_base + s.deadline_days;
  end if;
  return v_base;
end $$;

comment on function app.compute_stage_due(uuid, text) is
  'Προθεσμία σταδίου με βάση την αφετηρία που ορίζει ο νόμος. Επιστρέφει NULL όσο '
  'η αφετηρία δεν έχει επέλθει — ποτέ πλασματική ημερομηνία.';

-- ---------------------------------------------------------------------
-- Επανυπολογισμός όταν εμφανιστεί μια αφετηρία
-- ---------------------------------------------------------------------
create or replace function app.recompute_stage_dues(p_project_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
declare v_n integer;
begin
  update public.project_stages ps
     set due_date = app.compute_stage_due(p_project_id, ps.stage_code)
   where ps.project_id = p_project_id
     and ps.status not in ('completed', 'not_applicable')
     and ps.due_date is distinct from app.compute_stage_due(p_project_id, ps.stage_code);
  get diagnostics v_n = row_count;

  -- Ένα στάδιο που είχε χαρακτηριστεί εκπρόθεσμο επειδή έφερε πλασματική
  -- ημερομηνία επιστρέφει στην κανονική του κατάσταση.
  update public.project_stages ps
     set status = 'available'
   where ps.project_id = p_project_id
     and ps.status = 'overdue'
     and (ps.due_date is null or ps.due_date >= current_date);

  return v_n;
end $$;

comment on function app.recompute_stage_dues(uuid) is
  'Επαναϋπολογισμός των προθεσμιών των σταδίων ενός έργου όταν επέλθει νέα αφετηρία '
  '(Βεβαίωση Περάτωσης, έναρξη εργασιών, παράταση, λήξη συντήρησης).';

revoke all on function app.recompute_stage_dues(uuid) from public, anon;

create or replace function app.trg_recompute_stage_dues()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  perform app.recompute_stage_dues(coalesce(new.project_id, old.project_id));
  return null;
end $$;

-- Οι τρεις πίνακες που γεννούν νέες αφετηρίες.
drop trigger if exists trg_dues_completions on public.completions;
create trigger trg_dues_completions
  after insert or update on public.completions
  for each row execute function app.trg_recompute_stage_dues();

drop trigger if exists trg_dues_maintenance on public.maintenance_periods;
create trigger trg_dues_maintenance
  after insert or update on public.maintenance_periods
  for each row execute function app.trg_recompute_stage_dues();

drop trigger if exists trg_dues_contracts on public.contracts;
create trigger trg_dues_contracts
  after update of works_start_deadline, current_end_date, signed_at on public.contracts
  for each row execute function app.trg_recompute_stage_dues();

-- ---------------------------------------------------------------------
-- Διόρθωση των ήδη καταχωρισμένων έργων
-- ---------------------------------------------------------------------
do $fix$
declare r record; v_total integer := 0; v_n integer;
begin
  for r in select id from public.projects loop
    v_n := app.recompute_stage_dues(r.id);
    v_total := v_total + v_n;
  end loop;
  raise notice 'Διορθώθηκαν % προθεσμίες σταδίων σε υπάρχοντα έργα.', v_total;
end $fix$;
