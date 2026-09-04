-- =====================================================================
-- Migration 0025 : Ομάδες εργασιών του ΕΡΓΟΥ
-- =====================================================================
-- Οι «ομάδες εργασιών» δεν είναι παγκόσμιος κατάλογος: τις ορίζει η ΜΕΛΕΤΗ
-- κάθε έργου και αριθμούνται 1, 2, 3 ... με τίτλους που περιγράφουν το
-- συγκεκριμένο αντικείμενο — «1 ΧΩΜΑΤΟΥΡΓΙΚΑ / 2 ΣΚΥΡΟΔΕΜΑΤΑ»,
-- «1 ΚΑΘΑΙΡΕΣΕΙΣ ΣΚΥΡΟΔΕΜΑΤΑ / 2 ΣΚΥΡΟΔΕΜΑΤΑ ΟΠΛΙΣΜΟΙ»,
-- «1 ΔΑΣΟΤΕΧΝΙΚΑ / 2 ΕΡΓΑ ΑΠΟΚΑΤΑΣΤΑΣΕΩΝ ΚΑΙ ΠΡΟΣΤΑΣΙΑΣ». Έτσι ακριβώς
-- εμφανίζονται στους εγκεκριμένους προϋπολογισμούς και ΑΠΕ της Δ/νσης.
--
-- Η Υ.Α. ΔΝΣγ/οικ.38107/ΦΝ 466/2017 ορίζει το ΕΠΙΤΡΕΠΤΟ σύνολο ανά κατηγορία
-- έργου. Ο πίνακας που είχε μπει στο 0013 ως καθολικός κατάλογος παραμένει
-- ΕΝΔΕΙΚΤΙΚΗ πρόταση (project_id is null) και δεν δεσμεύει καμία μελέτη.
--
-- Χωρίς σωστές ομάδες ο έλεγχος του ορίου 20% ανά ομάδα (άρθρο 156 §3γ) δεν
-- ελέγχει τίποτε — γι' αυτό το 0025 κλείνει και δύο τρύπες:
--   (α) το UI επέβαλλε επιλογή από επινοημένο κατάλογο, οπότε ο πραγματικός
--       προϋπολογισμός δεν μπορούσε να καταχωρηθεί όπως είναι·
--   (β) γραμμή ΑΠΕ χωρίς ομάδα έμενε ΕΚΤΟΣ του ελέγχου (inner join) και
--       περνούσε αθόρυβα.
-- ---------------------------------------------------------------------

alter table public.work_groups
  add column if not exists project_id uuid
    references public.projects(id) on delete cascade;

comment on column public.work_groups.project_id is
  'NULL = ενδεικτικός κατάλογος ανά κατηγορία έργου. '
  'Συμπληρωμένο = η ομάδα ορίστηκε από τη μελέτη του συγκεκριμένου έργου.';

-- Ο παλιός περιορισμός δεν χωράει δύο έργα με ομάδα «1»· τον αντικαθιστούμε
-- με δύο μερικά μοναδικά ευρετήρια.
alter table public.work_groups drop constraint if exists work_groups_category_code_key;

create unique index if not exists work_groups_catalogue_uidx
  on public.work_groups (category, code) where project_id is null;

create unique index if not exists work_groups_project_uidx
  on public.work_groups (project_id, code) where project_id is not null;

create index if not exists work_groups_project_idx
  on public.work_groups (project_id) where project_id is not null;

-- ---------------------------------------------------------------------
-- 25.1 RLS — τον κατάλογο τον διαβάζουν όλοι· τις ομάδες ενός έργου τις
--      ορίζει όποιος μπορεί να το επιβλέψει (ΔΥ / επιβλέπων).
--      Ο καθολικός κατάλογος μένει αμετάβλητος από την εφαρμογή.
-- ---------------------------------------------------------------------
drop policy if exists work_groups_ins on public.work_groups;
create policy work_groups_ins on public.work_groups for insert
  with check (project_id is not null and app.can_supervise(project_id));

drop policy if exists work_groups_upd on public.work_groups;
create policy work_groups_upd on public.work_groups for update
  using (project_id is not null and app.can_supervise(project_id))
  with check (project_id is not null and app.can_supervise(project_id));

drop policy if exists work_groups_del on public.work_groups;
create policy work_groups_del on public.work_groups for delete
  using (project_id is not null and app.can_supervise(project_id));

grant insert, update, delete on public.work_groups to authenticated;

-- ---------------------------------------------------------------------
-- 25.2 Γραμμή χωρίς ομάδα = ανέλεγκτη γραμμή (άρθρο 156 §3γ)
-- ---------------------------------------------------------------------
create or replace function app.ape_validation(p_ape_id uuid)
returns setof app.blocker
language plpgsql stable security definer set search_path = public, app as $$
declare
  a               public.ape%rowtype;
  c               public.contracts%rowtype;
  v_cum_increase  numeric;
  v_group         record;
  v_savings_total numeric;
  v_ungrouped     integer;
begin
  select * into a from public.ape where id = p_ape_id;
  if not found then return; end if;
  select * into c from public.contracts where project_id = a.project_id;

  -- (1) Σωρευτικό όριο αύξησης 50% της αξίας της αρχικής σύμβασης (άρθρο 156 §1)
  select coalesce(sum(x.delta_amount), 0) into v_cum_increase
  from public.ape x
  where x.project_id = a.project_id
    and (x.status = 'approved' or x.id = a.id)
    and x.delta_amount > 0;

  if c.initial_value_net > 0
     and v_cum_increase > c.initial_value_net * 0.50 then
    return next ('APE_LIMIT_50',
      format('Υπέρβαση του ανώτατου ορίου 50%%: σωρευτική αύξηση %s € έναντι ορίου %s €.',
             to_char(v_cum_increase,'FM999G999G990D00'),
             to_char(c.initial_value_net*0.50,'FM999G999G990D00')),
      'hard', 'N4412/156/1')::app.blocker;
  end if;

  -- (2) Όριο απροβλέπτων 9% ή 15% (άρθρο 156 §3β)
  if a.contingency_used > c.contingency_amount + 0.005 then
    return next ('APE_CONTINGENCY',
      format('Η χρήση απροβλέπτων (%s €) υπερβαίνει το εγκεκριμένο κονδύλιο %s%% (%s €).',
             to_char(a.contingency_used,'FM999G999G990D00'),
             to_char(c.contingency_pct,'FM990D00'),
             to_char(c.contingency_amount,'FM999G999G990D00')),
      'hard', 'N4412/156/3b')::app.blocker;
  end if;

  -- (3α) Γραμμή χωρίς ομάδα εργασιών = ανέλεγκτη γραμμή.
  --      Ο έλεγχος (3) γίνεται με join στις ομάδες: ό,τι δεν έχει ομάδα
  --      έμενε ΕΚΤΟΣ αθροίσματος και περνούσε αθόρυβα.
  select count(*) into v_ungrouped
  from public.ape_lines al
  where al.ape_id = p_ape_id and al.work_group_id is null;

  if v_ungrouped > 0 then
    return next ('APE_LINE_NO_GROUP',
      case when v_ungrouped = 1
        then 'Μία γραμμή του πίνακα δεν έχει ομάδα εργασιών — σε αυτήν δεν ελέγχεται το όριο 20% των επί έλασσον δαπανών.'
        else format('%s γραμμές του πίνακα δεν έχουν ομάδα εργασιών — σε αυτές δεν ελέγχεται το όριο 20%% των επί έλασσον δαπανών.',
                    v_ungrouped)
      end,
      'hard', 'N4412/156/3c')::app.blocker;
  end if;

  -- (3) Επί έλασσον: ≤ 20% ανά ΟΜΑΔΑ ΕΡΓΑΣΙΩΝ (άρθρο 156 §3γ)
  for v_group in
    select wg.title as group_title,
           sum(case when al.delta_amount < 0 then -al.delta_amount else 0 end) as savings,
           sum(al.amount_initial) as group_initial
    from public.ape_lines al
    join public.work_groups wg on wg.id = al.work_group_id
    where al.ape_id = p_ape_id
    group by wg.title
  loop
    if v_group.group_initial > 0
       and v_group.savings > v_group.group_initial * 0.20 then
      return next ('APE_SAVINGS_GROUP_20',
        format('Ομάδα «%s»: οι επί έλασσον δαπάνες (%s €) υπερβαίνουν το 20%% της συμβατικής δαπάνης της ομάδας (%s €).',
               v_group.group_title,
               to_char(v_group.savings,'FM999G999G990D00'),
               to_char(v_group.group_initial*0.20,'FM999G999G990D00')),
        'hard', 'N4412/156/3c')::app.blocker;
    end if;
  end loop;

  -- (4) Επί έλασσον: ≤ 10% της αξίας της αρχικής σύμβασης (άρθρο 156 §3γ)
  select coalesce(sum(case when al.delta_amount < 0 then -al.delta_amount else 0 end), 0)
    into v_savings_total
  from public.ape_lines al where al.ape_id = p_ape_id;

  if c.initial_value_net > 0
     and v_savings_total > c.initial_value_net * 0.10 then
    return next ('APE_SAVINGS_TOTAL_10',
      format('Οι επί έλασσον δαπάνες (%s €) υπερβαίνουν το 10%% της αξίας της αρχικής σύμβασης (%s €).',
             to_char(v_savings_total,'FM999G999G990D00'),
             to_char(c.initial_value_net*0.10,'FM999G999G990D00')),
      'hard', 'N4412/156/3c')::app.blocker;
  end if;

  -- (5) Απαγόρευση εισαγωγής ΝΕΩΝ άρθρων με χρηματοδότηση από επί έλασσον
  if exists (select 1 from public.ape_lines al
             where al.ape_id = p_ape_id
               and al.is_new_item
               and al.funding_source = 'epi_elasson') then
    return next ('APE_NEW_ITEM_FROM_SAVINGS',
      'Δεν επιτρέπεται η κάλυψη ΝΕΩΝ άρθρων (μη περιλαμβανομένων στην αρχική σύμβαση) από επί έλασσον δαπάνες.',
      'hard', 'N4412/156/3c')::app.blocker;
  end if;

  -- (6) Γνωμοδότηση Τεχνικού Συμβουλίου όπου απαιτείται
  if (a.supplementary_needed or v_savings_total > 0)
     and a.tc_opinion_id is null then
    return next ('APE_TC_OPINION',
      'Απαιτείται γνωμοδότηση Τεχνικού Συμβουλίου (συμπληρωματική σύμβαση ή χρήση επί έλασσον δαπανών).',
      'hard', 'N4412/156/1e')::app.blocker;
  end if;

  -- (7) Υπογραφή/κοινοποίηση στον ανάδοχο
  if a.contractor_signature is null then
    return next ('APE_SIGNATURE',
      'Ο ΑΠΕ δεν έχει υπογραφεί από τον ανάδοχο ούτε έχει κοινοποιηθεί κατ'' άρθρο 143.',
      'soft', 'N4412/156/7')::app.blocker;
  end if;

  -- (8) ΠΚΤΜΝΕ όταν υπάρχουν νέα άρθρα
  if exists (select 1 from public.ape_lines al where al.ape_id = p_ape_id and al.is_new_item)
     and a.new_price_protocol_id is null then
    return next ('APE_PKTMNE_MISSING',
      'Ο ΑΠΕ περιλαμβάνει νέες εργασίες χωρίς συνοδευτικό Π.Κ.Τ.Μ.Ν.Ε.',
      'hard', 'N4412/156/5')::app.blocker;
  end if;
end $$;

comment on function app.ape_validation(uuid) is
  'Ελεγκτής ορίων άρθρου 156 ν.4412/2016: 50% σωρευτική αύξηση, 9%/15% απρόβλεπτα, '
  'γραμμές χωρίς ομάδα εργασιών, 20% ανά ομάδα και 10% συνολικά για επί έλασσον, '
  'απαγόρευση νέων άρθρων από επί έλασσον, γνωμοδότηση Τεχνικού Συμβουλίου, ΠΚΤΜΝΕ.';
