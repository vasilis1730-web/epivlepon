-- =====================================================================
-- 0022_create_project_rpc.sql — Έναρξη επίβλεψης νέου έργου
-- ---------------------------------------------------------------------
-- Μία και μόνη συναλλαγή που δημιουργεί:
--   ανάδοχο → έργο → σύμβαση → ορισμούς επίβλεψης → εγγύηση →
--   ολόκληρη τη ροή των 36 σταδίων του οδηγού.
--
-- Γιατί σε μία RPC και όχι με πέντε κλήσεις από τον browser: αν
-- αποτύχει το τέταρτο βήμα, τα τρία πρώτα έχουν ήδη γραφτεί και το
-- μητρώο μένει με μισοτελειωμένο έργο. Εδώ ή γίνονται όλα ή κανένα.
--
-- ΑΡΜΟΔΙΟΤΗΤΑ: το έργο το ανοίγει η Διευθύνουσα Υπηρεσία, η οποία
-- ορίζει και τον επιβλέποντα (άρθρο 136 §2 ν. 4412/2016). Ο επιβλέπων
-- δεν αυτο-ορίζεται· γι' αυτό απαιτείται ρόλος υπηρεσιακής εμβέλειας.
-- =====================================================================

-- ---- 1. Κατάλογοι για τις λίστες επιλογής της φόρμας ----------------
-- Τα profiles έχουν ήδη policy «ίδιος φορέας → ορατό», όμως το
-- front-end χρειάζεται και τους ρόλους καθενός για να προτείνει σωστά.
create or replace function public.org_people()
returns table (id uuid, full_name text, email text, specialty text,
               grade text, registry_no text, roles text[])
language sql
stable
security definer
set search_path = public, app
as $$
  select p.id, p.full_name, p.email, p.specialty, p.grade, p.registry_no,
         coalesce(array_agg(r.role::text order by r.role)
                    filter (where r.role is not null), '{}')
    from public.profiles p
    left join public.org_roles r
           on r.profile_id = p.id
          and (r.valid_to is null or r.valid_to >= current_date)
   where p.org_id = app.my_org()
     and p.is_active
   group by p.id, p.full_name, p.email, p.specialty, p.grade, p.registry_no
   order by p.full_name;
$$;

comment on function public.org_people() is
  'Το ενεργό προσωπικό του φορέα του καλούντος, με τους υπηρεσιακούς του ρόλους.';

-- ---- 2. Η δημιουργία -------------------------------------------------
create or replace function public.create_project_full(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_org         uuid := app.my_org();
  v_me          uuid := app.uid();
  j_project     jsonb := payload -> 'project';
  j_contractor  jsonb := payload -> 'contractor';
  j_contract    jsonb := payload -> 'contract';
  j_assign      jsonb := payload -> 'assignments';
  j_guarantee   jsonb := payload -> 'guarantee';

  v_contractor  uuid;
  v_project     uuid;
  v_code        text;
  v_signed      date;
  v_days        integer;
  v_orig_end    date;
  v_oriaki      date;

  v_budget_works numeric;   -- δαπάνη εργασιών κατά τη μελέτη, χωρίς ΓΕ&ΟΕ
  v_discount     numeric;
  v_geoe_pct     numeric;
  v_cont_pct     numeric;
  v_revision     numeric;
  v_works        numeric;   -- μετά την έκπτωση
  v_geoe         numeric;
  v_cont         numeric;
  v_initial      numeric;
  v_study_total  numeric;

  v_epivlepon   uuid;
  v_proistam    uuid;
  v_helper      uuid;
  v_stages      integer;
  v_guarantee   uuid;
begin
  ------------------------------------------------------------------
  -- 2.1 Αρμοδιότητα
  ------------------------------------------------------------------
  if v_me is null then
    raise exception 'Δεν υπάρχει ενεργή συνεδρία.';
  end if;
  if v_org is null then
    raise exception 'Ο λογαριασμός σας δεν έχει συνδεθεί με φορέα. Απευθυνθείτε στον διαχειριστή.';
  end if;
  if not app.is_service_wide() then
    raise exception 'Η δημιουργία έργου ανήκει στη Διευθύνουσα Υπηρεσία, η οποία ορίζει και '
                    'τον επιβλέποντα (άρθρο 136 §2 ν. 4412/2016). Ο λογαριασμός σας δεν φέρει '
                    'ρόλο υπηρεσιακής εμβέλειας.';
  end if;

  ------------------------------------------------------------------
  -- 2.2 Ανάδοχος — υπάρχων ή νέος
  ------------------------------------------------------------------
  v_contractor := nullif(j_contractor ->> 'id', '')::uuid;

  if v_contractor is null then
    -- Ίδιο ΑΦΜ στον ίδιο φορέα σημαίνει ίδιος ανάδοχος: ενημερώνουμε
    -- αντί να σκάσουμε στο μοναδικό ευρετήριο.
    insert into public.contractors
      (org_id, name, legal_form, afm, doy, gemi, meep_mieedde,
       legal_rep_name, legal_rep_afm, address, email, phone, is_joint_venture)
    values
      (v_org,
       j_contractor ->> 'name',
       nullif(j_contractor ->> 'legal_form', ''),
       j_contractor ->> 'afm',
       nullif(j_contractor ->> 'doy', ''),
       nullif(j_contractor ->> 'gemi', ''),
       nullif(j_contractor ->> 'meep_mieedde', ''),
       nullif(j_contractor ->> 'legal_rep_name', ''),
       nullif(j_contractor ->> 'legal_rep_afm', ''),
       nullif(j_contractor ->> 'address', ''),
       j_contractor ->> 'email',
       nullif(j_contractor ->> 'phone', ''),
       coalesce((j_contractor ->> 'is_joint_venture')::boolean, false))
    on conflict (org_id, afm) do update
       set name           = excluded.name,
           email          = excluded.email,
           phone          = coalesce(excluded.phone, public.contractors.phone),
           legal_rep_name = coalesce(excluded.legal_rep_name, public.contractors.legal_rep_name)
    returning id into v_contractor;
  else
    perform 1 from public.contractors
     where id = v_contractor and org_id = v_org;
    if not found then
      raise exception 'Ο ανάδοχος που επιλέξατε δεν ανήκει στον φορέα σας.';
    end if;
  end if;

  ------------------------------------------------------------------
  -- 2.3 Οικονομικά μεγέθη — υπολογίζονται εδώ, όχι στον browser
  ------------------------------------------------------------------
  v_budget_works := (j_contract ->> 'budget_works_net')::numeric;
  v_discount     := coalesce((j_contract ->> 'discount_pct')::numeric, 0);
  v_geoe_pct     := coalesce((j_contract ->> 'ge_oe_pct')::numeric, 18);
  v_cont_pct     := coalesce((j_contract ->> 'contingency_pct')::numeric, 15);
  v_revision     := coalesce((j_contract ->> 'revision_amount')::numeric, 0);

  if v_budget_works is null or v_budget_works <= 0 then
    raise exception 'Η δαπάνη εργασιών του προϋπολογισμού μελέτης πρέπει να είναι θετική.';
  end if;
  if v_cont_pct not in (9, 15) then
    raise exception 'Το ποσοστό απροβλέπτων ορίζεται σε 9%% για έργα ίσα ή άνω των ορίων '
                    'του άρθρου 5 και σε 15%% για τα μικρότερα (άρθρο 156 §3β ν. 4412/2016).';
  end if;

  v_works   := round(v_budget_works * (1 - v_discount / 100), 2);
  v_geoe    := round(v_works * v_geoe_pct / 100, 2);
  v_cont    := round((v_works + v_geoe) * v_cont_pct / 100, 2);
  v_initial := round(v_works + v_geoe + v_cont + v_revision, 2);

  -- Προϋπολογισμός μελέτης: τα ίδια μεγέθη χωρίς την έκπτωση.
  v_study_total := round(
      v_budget_works
    + v_budget_works * v_geoe_pct / 100
    + (v_budget_works + v_budget_works * v_geoe_pct / 100) * v_cont_pct / 100
    + v_revision, 2);

  ------------------------------------------------------------------
  -- 2.4 Προθεσμίες (άρθρο 147)
  ------------------------------------------------------------------
  v_signed := (j_contract ->> 'signed_at')::date;
  v_days   := (j_contract ->> 'total_duration_days')::integer;

  if v_signed is null then raise exception 'Λείπει η ημερομηνία υπογραφής της σύμβασης.'; end if;
  if v_days is null or v_days <= 0 then
    raise exception 'Η συνολική προθεσμία πρέπει να είναι θετικός αριθμός ημερών (άρθρο 147 §1).';
  end if;

  -- §2: οι προθεσμίες αρχίζουν από την υπογραφή της σύμβασης.
  v_orig_end := v_signed + v_days;
  -- §4: οριακή προθεσμία = το ήμισυ της αρχικής, όχι λιγότερο από 3 μήνες.
  v_oriaki   := v_orig_end + greatest((v_days / 2)::integer, 90);

  ------------------------------------------------------------------
  -- 2.5 Έργο
  ------------------------------------------------------------------
  v_code := trim(j_project ->> 'code');
  if v_code is null or v_code = '' then
    raise exception 'Ο κωδικός του έργου είναι υποχρεωτικός.';
  end if;
  if exists (select 1 from public.projects
              where org_id = v_org and code = v_code) then
    raise exception 'Υπάρχει ήδη έργο με κωδικό «%» στον φορέα σας.', v_code;
  end if;

  insert into public.projects
    (org_id, code, title, category, cpv, ka_budget_code, funding_source, mis_code,
     study_budget_net, estimated_value_net, vat_rate,
     tender_publication_at, adam_tender, award_decision_ada, location, created_by)
  values
    (v_org, v_code,
     j_project ->> 'title',
     (j_project ->> 'category')::public.project_category,
     nullif(j_project ->> 'cpv', ''),
     nullif(j_project ->> 'ka_budget_code', ''),
     nullif(j_project ->> 'funding_source', ''),
     nullif(j_project ->> 'mis_code', ''),
     coalesce(nullif(j_project ->> 'study_budget_net', '')::numeric, v_study_total),
     coalesce(nullif(j_project ->> 'estimated_value_net', '')::numeric, v_study_total),
     coalesce((j_project ->> 'vat_rate')::numeric, 24),
     nullif(j_project ->> 'tender_publication_at', '')::date,
     nullif(j_project ->> 'adam_tender', ''),
     nullif(j_project ->> 'award_decision_ada', ''),
     nullif(j_project ->> 'location', ''),
     v_me)
  returning id into v_project;

  ------------------------------------------------------------------
  -- 2.6 Ορισμοί επίβλεψης — ΠΡΙΝ από τη σύμβαση, ώστε ο επιβλέπων να
  --     βλέπει το έργο του από την πρώτη στιγμή (άρθρο 136 §2).
  ------------------------------------------------------------------
  v_epivlepon := nullif(j_assign ->> 'epivlepon', '')::uuid;
  v_proistam  := nullif(j_assign ->> 'proistamenos_dy', '')::uuid;

  if v_epivlepon is null then
    raise exception 'Πρέπει να οριστεί επιβλέπων μηχανικός (άρθρο 136 §2 ν. 4412/2016).';
  end if;
  perform 1 from public.profiles where id = v_epivlepon and org_id = v_org;
  if not found then
    raise exception 'Ο επιβλέπων που επιλέξατε δεν ανήκει στον φορέα σας.';
  end if;

  insert into public.project_assignments
    (project_id, profile_id, role, is_coordinator, duties,
     decision_no, decision_ada, decision_date, valid_from, legal_ref_id)
  values
    (v_project, v_epivlepon, 'epivlepon',
     coalesce((j_assign ->> 'epivlepon_is_coordinator')::boolean, false),
     nullif(j_assign ->> 'duties', ''),
     nullif(j_assign ->> 'decision_no', ''),
     nullif(j_assign ->> 'decision_ada', ''),
     nullif(j_assign ->> 'decision_date', '')::date,
     coalesce(nullif(j_assign ->> 'decision_date', '')::date, v_signed),
     'N4412/136/2');

  -- Βοηθοί επιβλέποντες (προαιρετικά, ίδια απόφαση ορισμού)
  for v_helper in
    select value::uuid
      from jsonb_array_elements_text(coalesce(j_assign -> 'voithoi', '[]'::jsonb))
     where value <> ''
  loop
    if exists (select 1 from public.profiles where id = v_helper and org_id = v_org)
       and v_helper <> v_epivlepon then
      insert into public.project_assignments
        (project_id, profile_id, role, decision_no, decision_ada, decision_date,
         valid_from, legal_ref_id)
      values
        (v_project, v_helper, 'voithos_epivlepon',
         nullif(j_assign ->> 'decision_no', ''),
         nullif(j_assign ->> 'decision_ada', ''),
         nullif(j_assign ->> 'decision_date', '')::date,
         coalesce(nullif(j_assign ->> 'decision_date', '')::date, v_signed),
         'N4412/136/2');
    end if;
  end loop;

  -- Προϊστάμενος Διευθύνουσας Υπηρεσίας
  if v_proistam is not null
     and exists (select 1 from public.profiles where id = v_proistam and org_id = v_org) then
    insert into public.project_assignments
      (project_id, profile_id, role, valid_from, legal_ref_id)
    values (v_project, v_proistam, 'proistamenos_dy', v_signed, 'N4412/136');
  end if;

  -- Ο ανάδοχος ως συμβαλλόμενο μέρος του έργου
  insert into public.project_assignments
    (project_id, contractor_id, role, valid_from, legal_ref_id)
  values (v_project, v_contractor, 'anadochos', v_signed, 'N4412/138');

  ------------------------------------------------------------------
  -- 2.7 Σύμβαση
  ------------------------------------------------------------------
  insert into public.contracts
    (project_id, contractor_id, regime, supervision_mode,
     contract_no, signed_at, adam_contract, ada_contract,
     discount_pct, works_value_net, ge_oe_pct, ge_oe_amount,
     contingency_pct, contingency_amount, revision_amount, initial_value_net,
     estimated_guarantee_base, vat_rate,
     total_duration_days, works_start_deadline, schedule_submit_days,
     original_end_date, current_end_date, oriaki_end_date,
     maintenance_months, has_prim_clause, daily_penalty_basis,
     diary_mode, diary_penalty_per_day, status)
  values
    (v_project, v_contractor,
     coalesce((j_contract ->> 'regime')::public.contract_regime, 'n4412_meta_n4782'),
     coalesce((j_contract ->> 'supervision_mode')::public.supervision_mode, 'ypiresiaki'),
     j_contract ->> 'contract_no',
     v_signed,
     nullif(j_contract ->> 'adam_contract', ''),
     nullif(j_contract ->> 'ada_contract', ''),
     v_discount, v_works, v_geoe_pct, v_geoe,
     v_cont_pct, v_cont, v_revision, v_initial,
     v_initial, coalesce((j_contract ->> 'vat_rate')::numeric, 24),
     v_days,
     nullif(j_contract ->> 'works_start_deadline', '')::date,
     coalesce((j_contract ->> 'schedule_submit_days')::integer, 15),
     v_orig_end, v_orig_end, v_oriaki,
     coalesce((j_contract ->> 'maintenance_months')::integer, 15),
     coalesce((j_contract ->> 'has_prim_clause')::boolean, false),
     nullif(j_contract ->> 'daily_penalty_basis', '')::numeric,
     coalesce((j_contract ->> 'diary_mode')::public.diary_mode, 'imerisio'),
     coalesce((j_contract ->> 'diary_penalty_per_day')::numeric, 100),
     'active');

  ------------------------------------------------------------------
  -- 2.8 Εγγύηση καλής εκτέλεσης (άρθρο 72 §4) — προαιρετική εδώ:
  --     αν δεν έχει κατατεθεί ακόμη, καταχωρίζεται εκκρεμής ώστε το
  --     στάδιο εγκατάστασης να μπλοκάρει μέχρι να προσκομιστεί.
  ------------------------------------------------------------------
  if j_guarantee is not null and jsonb_typeof(j_guarantee) = 'object'
     and coalesce(j_guarantee ->> 'guarantee_no', '') <> '' then
    insert into public.guarantees
      (project_id, gtype, issuer, guarantee_no, issued_at, valid_to,
       original_amount, current_amount, pct_of_contract, status, legal_ref_id)
    values
      (v_project, 'kalis_ektelesis',
       j_guarantee ->> 'issuer',
       j_guarantee ->> 'guarantee_no',
       coalesce(nullif(j_guarantee ->> 'issued_at', '')::date, v_signed),
       nullif(j_guarantee ->> 'valid_to', '')::date,
       (j_guarantee ->> 'original_amount')::numeric,
       (j_guarantee ->> 'original_amount')::numeric,
       round((j_guarantee ->> 'original_amount')::numeric / nullif(v_initial, 0) * 100, 3),
       'energi', 'N4412/72/4')
    returning id into v_guarantee;
  end if;

  ------------------------------------------------------------------
  -- 2.9 Η ροή του οδηγού
  ------------------------------------------------------------------
  v_stages := app.instantiate_workflow(v_project);

  return jsonb_build_object(
    'project_id',      v_project,
    'contractor_id',   v_contractor,
    'guarantee_id',    v_guarantee,
    'stages_created',  v_stages,
    'code',            v_code,
    'oikonomika', jsonb_build_object(
      'works_value_net',     v_works,
      'ge_oe_amount',        v_geoe,
      'contingency_amount',  v_cont,
      'initial_value_net',   v_initial,
      'study_budget_net',    v_study_total),
    'prothesmies', jsonb_build_object(
      'signed_at',         v_signed,
      'original_end_date', v_orig_end,
      'oriaki_end_date',   v_oriaki)
  );
end $$;

comment on function public.create_project_full(jsonb) is
  'Ατομική δημιουργία έργου: ανάδοχος, έργο, ορισμοί επίβλεψης (136 §2), σύμβαση, '
  'εγγύηση (72 §4) και στιγμιότυπο ροής 36 σταδίων. Απαιτεί ρόλο υπηρεσιακής εμβέλειας.';

revoke all on function public.create_project_full(jsonb) from public, anon;
revoke all on function public.org_people()             from public, anon;
grant execute on function public.create_project_full(jsonb) to authenticated, service_role;
grant execute on function public.org_people()               to authenticated, service_role;
