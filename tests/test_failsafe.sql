-- =====================================================================
-- ΔΟΚΙΜΕΣ ΟΡΘΟΤΗΤΑΣ (fail-safe & νομικοί κανόνες)
-- Εκτελείται με: psql -d epivlepsi_test -f tests/test_failsafe.sql
-- =====================================================================
\set ON_ERROR_STOP off
\timing off

begin;

-- ------------------------------------------------------------------
-- ΔΕΔΟΜΕΝΑ ΔΟΚΙΜΗΣ
-- ------------------------------------------------------------------
insert into organizations (id, name, unit)
values ('11111111-1111-1111-1111-111111111111','Δήμος Ρόδου','Δ/νση Τεχνικών Έργων & Υποδομών');

-- Τα profiles συνδέονται με ξένο κλειδί στο auth.users (migration 0015),
-- άρα οι δοκιμαστικοί χρήστες δημιουργούνται πρώτα εκεί.
insert into auth.users (id, email, aud, role)
values ('22222222-2222-2222-2222-222222222222','epivl@test.gr','authenticated','authenticated'),
       ('33333333-3333-3333-3333-333333333333','proist@test.gr','authenticated','authenticated')
on conflict (id) do nothing;

insert into profiles (id, org_id, full_name, email, specialty) values
 ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','Επιβλέπων Μηχανικός','epivl@test.gr','ΠΕ Μηχανολόγος Μηχανικός'),
 ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111','Προϊστάμενος Δ.Υ.','proist@test.gr','ΠΕ Πολιτικός Μηχανικός')
on conflict (id) do update set full_name = excluded.full_name, specialty = excluded.specialty;

insert into org_roles (profile_id, org_id, role) values
 ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','epivlepon'),
 ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111','proistamenos_dy');

insert into contractors (id, org_id, name, afm, email)
values ('44444444-4444-4444-4444-444444444444','11111111-1111-1111-1111-111111111111',
        'ΤΕΧΝΙΚΗ Α.Ε.','123456789','anadoxos@test.gr');

insert into projects (id, org_id, code, title, category, study_budget_net, estimated_value_net)
values ('55555555-5555-5555-5555-555555555555','11111111-1111-1111-1111-111111111111',
        'ΕΡΓ-2026-001','Ανακατασκευή οδοστρωμάτων Δ.Ε. Ρόδου','odopoiia', 500000, 500000);

insert into contracts (project_id, contractor_id, contract_no, signed_at,
        discount_pct, works_value_net, ge_oe_amount, contingency_pct, contingency_amount,
        initial_value_net, estimated_guarantee_base,
        total_duration_days, original_end_date, current_end_date, works_start_deadline)
values ('55555555-5555-5555-5555-555555555555','44444444-4444-4444-4444-444444444444',
        '1234/2026','2026-01-15',
        35.00, 250000, 45000, 15.00, 44250,
        339250, 339250,
        365, '2027-01-15','2027-01-15','2026-02-14');

insert into project_assignments (project_id, profile_id, role, decision_no, decision_date) values
 ('55555555-5555-5555-5555-555555555555','22222222-2222-2222-2222-222222222222','epivlepon','Α.Π. 100','2026-01-20'),
 ('55555555-5555-5555-5555-555555555555','33333333-3333-3333-3333-333333333333','proistamenos_dy','Α.Π. 100','2026-01-20');

insert into budget_versions (id, project_id, version_no, label, is_current, total_net)
values ('66666666-6666-6666-6666-666666666666','55555555-5555-5555-5555-555555555555',0,'Αρχική Σύμβαση',true,339250);

insert into budget_items (project_id, version_id, line_no, item_code, description, unit,
        work_group_id, unit_price, quantity)
select '55555555-5555-5555-5555-555555555555','66666666-6666-6666-6666-666666666666',
       n, 'ΝΕΤ ΟΔΟ-'||n, 'Άρθρο δοκιμής '||n, 'm3',
       (select id from work_groups where category='odopoiia' and code='A'),
       10.0, 5000
from generate_series(1,4) n;

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 1 — Δημιουργία ροής 36 σταδίων και κλείδωμα'
\echo '=============================================================='
select app.instantiate_workflow('55555555-5555-5555-5555-555555555555') as stages_created;

select count(*) filter (where status='available') as available,
       count(*) filter (where status='locked')    as locked,
       count(*)                                   as total
from project_stages where project_id='55555555-5555-5555-5555-555555555555';

\echo '--- Το στάδιο Ι.Φ.Ε. ΔΕΝ πρέπει να έχει δημιουργηθεί (επίβλεψη υπηρεσιακή) ---'
select count(*) as ife_stages from project_stages
where project_id='55555555-5555-5555-5555-555555555555' and stage_code='S01B_IFE';

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 2 — FAIL-SAFE: απόπειρα κλεισίματος σταδίου με εκκρεμότητες'
\echo '=============================================================='
\echo '--- Αναμένεται ΣΦΑΛΜΑ: το S10 (έναρξη εργασιών) απαιτεί χρονοδιάγραμμα & ΣΑΥ/ΦΑΥ ---'
savepoint sp1;
update project_stages set status='completed'
where project_id='55555555-5555-5555-5555-555555555555' and stage_code='S10_EGKATASTASH';
rollback to savepoint sp1;

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 3 — Εμπόδια σταδίου S06 (χρονοδιάγραμμα)'
\echo '=============================================================='
select b.code, b.severity, b.legal_ref, left(b.message, 95) as message
from project_stages ps, app.stage_blockers(ps.id) b
where ps.project_id='55555555-5555-5555-5555-555555555555'
  and ps.stage_code='S06_XRONODIAGRAMMA';

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 4 — ΜΕΙΩΣΗ ΕΓΓΥΗΣΗΣ 70% ΧΩΡΙΣ εγκεκριμένη τελική επιμέτρηση'
\echo '=============================================================='
insert into guarantees (id, project_id, gtype, issuer, guarantee_no, issued_at,
                        original_amount, current_amount, pct_of_contract)
values ('77777777-7777-7777-7777-777777777777','55555555-5555-5555-5555-555555555555',
        'kalis_ektelesis','ΤΜΕΔΕ','ΕΕ-2026-001','2026-01-10', 16962.50, 16962.50, 5.000);

\echo '--- Αναμένεται ΣΦΑΛΜΑ (άρθρο 72 §14β) ---'
savepoint sp2;
insert into guarantee_events (guarantee_id, event_type, amount_before, amount_after,
                              trigger_event, decision_date, reduction_pct)
values ('77777777-7777-7777-7777-777777777777','meiosi_70', 16962.50, 5088.75,
        'egkrisi_telikis_epimetrisis', current_date, 70.000);
rollback to savepoint sp2;

\echo '--- Τώρα με ΕΓΚΕΚΡΙΜΕΝΗ τελική επιμέτρηση: αναμένεται ΕΠΙΤΥΧΙΑ ---'
insert into final_measurement (project_id, completion_date, submitted_at,
                               supervisor_report_at, approved_at)
values ('55555555-5555-5555-5555-555555555555','2026-12-20','2027-01-10','2027-02-10','2027-03-10');

insert into guarantee_events (guarantee_id, event_type, amount_before, amount_after,
                              trigger_event, decision_date, reduction_pct)
values ('77777777-7777-7777-7777-777777777777','meiosi_70', 16962.50, 5088.75,
        'egkrisi_telikis_epimetrisis', current_date, 70.000);

select guarantee_no, original_amount, current_amount, status from guarantees
where project_id='55555555-5555-5555-5555-555555555555';

\echo '--- Απόπειρα ΟΛΙΚΗΣ αποδέσμευσης χωρίς παραλαβή: αναμένεται ΣΦΑΛΜΑ ---'
savepoint sp3;
insert into guarantee_events (guarantee_id, event_type, amount_before, amount_after,
                              trigger_event, decision_date)
values ('77777777-7777-7777-7777-777777777777','apodesmevsi', 5088.75, 0,
        'egkrisi_paralavis', current_date);
rollback to savepoint sp3;

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 5 — ΟΡΙΑ ΑΠΕ (άρθρο 156)'
\echo '=============================================================='
\echo '--- 5α. Υπέρβαση 50% της αρχικής σύμβασης ---'
insert into ape (id, project_id, serial_no, atype, reason, drafted_at,
                 initial_contract_value, new_total_value, contractor_signature)
values ('88888888-8888-8888-8888-888888888888','55555555-5555-5555-5555-555555555555',
        1,'me_apravlepta','Δοκιμή υπέρβασης ορίου','2026-06-01',
        339250, 550000, 'anepifylakta');

select b.code, b.legal_ref, left(b.message,110) as message
from app.ape_validation('88888888-8888-8888-8888-888888888888') b;

\echo '--- Αναμένεται ΣΦΑΛΜΑ κατά την έγκριση ---'
savepoint sp4;
update ape set status='approved' where id='88888888-8888-8888-8888-888888888888';
rollback to savepoint sp4;

\echo '--- 5β. Επί έλασσον > 20% ανά ομάδα εργασιών ---'
insert into ape (id, project_id, serial_no, atype, reason, drafted_at,
                 initial_contract_value, new_total_value, contractor_signature)
values ('99999999-9999-9999-9999-999999999999','55555555-5555-5555-5555-555555555555',
        2,'me_epi_elasson','Δοκιμή επί έλασσον','2026-07-01',
        339250, 339250, 'anepifylakta');

insert into ape_lines (ape_id, work_group_id, item_code, description, unit,
                       unit_price, qty_initial, qty_new, funding_source)
values ('99999999-9999-9999-9999-999999999999',
        (select id from work_groups where category='odopoiia' and code='1'),
        'ΝΕΤ ΟΔΟ-1','Μείωση ποσοτήτων','m3', 10.0, 5000, 1000, 'epi_elasson');

select b.code, b.legal_ref, left(b.message,110) as message
from app.ape_validation('99999999-9999-9999-9999-999999999999') b;

\echo '--- 5γ. Γραμμή ΑΠΕ ΧΩΡΙΣ ομάδα εργασιών ---'
\echo '--- Χωρίς ομάδα το όριο 20% δεν ελέγχεται· η γραμμή δεν περνά αθόρυβα ---'
savepoint sp_nogroup;
insert into ape_lines (ape_id, work_group_id, item_code, description, unit,
                       unit_price, qty_initial, qty_new, funding_source)
values ('99999999-9999-9999-9999-999999999999', null,
        'ΝΕΤ ΟΔΟ-9','Γραμμή χωρίς ομάδα','m3', 10.0, 100, 50, 'epi_elasson');

select b.code, b.legal_ref, left(b.message,110) as message
from app.ape_validation('99999999-9999-9999-9999-999999999999') b
where b.code = 'APE_LINE_NO_GROUP';
rollback to savepoint sp_nogroup;

\echo '=============================================================='
\echo 'ΔΟΚΗ 6 — ΑΦΑΝΕΙΣ ΕΡΓΑΣΙΕΣ: 3ήμερη προθεσμία & φωτογραφίες'
\echo '=============================================================='
insert into hidden_work_notices (id, project_id, serial_no, work_description, location,
        declaration_at, invitation_sent_at, truth_declaration)
values ('aaaaaaaa-0000-0000-0000-000000000001','55555555-5555-5555-5555-555555555555',
        1,'Θεμελίωση φρεατίου','Χ.Θ. 0+250','2026-03-01','2026-03-01', true);

select serial_no, invitation_sent_at, inspection_due,
       (inspection_due - invitation_sent_at) as days_allowed
from hidden_work_notices where id='aaaaaaaa-0000-0000-0000-000000000001';

\echo '--- Αναμένεται ΣΦΑΛΜΑ: έλεγχος αφανών χωρίς φωτογραφική τεκμηρίωση ---'
savepoint sp5;
update hidden_work_notices set inspected_at='2026-03-03'
where id='aaaaaaaa-0000-0000-0000-000000000001';
rollback to savepoint sp5;

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 7 — Κανόνας δειγματοληψίας άρθρου 151 §3'
\echo '=============================================================='
insert into measurements (project_id, mtype, serial_no, submitted_at, truth_declaration, status)
select '55555555-5555-5555-5555-555555555555','tmimatiki', n,
       date '2026-03-01' + (n*30), true, 'submitted'
from generate_series(1,6) n;
select 6 as ypovlithisses, public.required_audit_count('55555555-5555-5555-5555-555555555555') as apaitoumenoi_elegxoi;

insert into measurements (project_id, mtype, serial_no, submitted_at, truth_declaration, status)
select '55555555-5555-5555-5555-555555555555','tmimatiki', n,
       date '2026-03-01' + (n*30), true, 'submitted'
from generate_series(7,20) n;
select 20 as ypovlithisses, public.required_audit_count('55555555-5555-5555-5555-555555555555') as apaitoumenoi_elegxoi;

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 8 — Αυτόματος υπολογισμός προθεσμιών'
\echo '=============================================================='
select serial_no, submitted_at, approval_due, (approval_due - submitted_at) as imeres
from measurements where project_id='55555555-5555-5555-5555-555555555555' and serial_no=1;

select completion_date, contractor_due, supervisor_report_due, approval_due,
       penalty_months, penalty_amount
from final_measurement where project_id='55555555-5555-5555-5555-555555555555';

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 9 — Λογαριασμός χωρίς εγκεκριμένη επιμέτρηση'
\echo '=============================================================='
insert into payment_certificates (id, project_id, ptype, serial_no, submitted_at,
        gross_cumulative, previous_certified, status)
values ('bbbbbbbb-0000-0000-0000-000000000001','55555555-5555-5555-5555-555555555555',
        'tmimatikos',1,'2026-04-01', 50000, 0, 'submitted');

select b.code, b.legal_ref, left(b.message,100) as message
from app.payment_validation('bbbbbbbb-0000-0000-0000-000000000001') b;

select serial_no, submitted_at, approval_due, retentions_amount, net_payable, vat_amount
from payment_certificates where id='bbbbbbbb-0000-0000-0000-000000000001';

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 10 — Βεβαίωση Περάτωσης → αυτόματο άνοιγμα συντήρησης/παραλαβής'
\echo '=============================================================='
insert into completions (project_id, approved_completion_date, contractor_declared_at,
        supervisor_report_at, tests_completed)
values ('55555555-5555-5555-5555-555555555555','2026-12-20','2026-12-18','2027-01-05',true);

update completions set certificate_issued_at='2027-01-12', actual_completion_date='2026-12-20'
where project_id='55555555-5555-5555-5555-555555555555';

select certificate_due, certificate_issued_at from completions
where project_id='55555555-5555-5555-5555-555555555555';

select months, starts_on, ends_on from maintenance_periods
where project_id='55555555-5555-5555-5555-555555555555';

select maintenance_end, deadline_3m, status from acceptances
where project_id='55555555-5555-5555-5555-555555555555';

select ckind, must_appoint_by from committees
where project_id='55555555-5555-5555-5555-555555555555';

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 11 — Πίνακας ελέγχου & οικονομική εικόνα'
\echo '=============================================================='
select ordinal, stage_code, status, hard_blockers, tasks_done||'/'||tasks_total as ergasies
from v_stage_board where project_id='55555555-5555-5555-5555-555555555555'
order by ordinal limit 12;

select initial_value_net, limit_50pct, limit_savings_10pct, contingency_amount,
       guarantees_active, days_to_deadline
from v_project_financials where project_id='55555555-5555-5555-5555-555555555555';

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 12 — Audit trail'
\echo '=============================================================='
select table_name, action, count(*) from audit_log
group by 1,2 order by 1,2;

\echo '=============================================================='
\echo 'ΔΟΚΙΜΗ 13 — RLS: τι φτάνει σε χρήστη χωρίς υπηρεσιακό ρόλο'
\echo '=============================================================='
\echo '--- 13α. Κάθε πίνακας με RLS διαβάζεται ΧΩΡΙΣ σφάλμα policy ---'
\echo '--- (αμοιβαία αναδρομή στα documents ματαίωνε ΟΛΟ το ερώτημα) ---'
do $$
declare r record; n bigint; bad text := '';
begin
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000e002', true);
  set local role authenticated;
  for r in select tablename from pg_tables
           where schemaname='public' and rowsecurity order by 1 loop
    begin
      execute format('select count(*) from public.%I', r.tablename) into n;
    exception when others then
      bad := bad || r.tablename || ' (' || sqlerrm || '); ';
    end;
  end loop;
  reset role;
  if bad <> '' then
    raise exception 'Πίνακες που δεν διαβάζονται: %', bad;
  end if;
  raise notice 'όλοι οι πίνακες με RLS διαβάζονται καθαρά';
end $$;

\echo '--- 13β. Εγγραφή εκτός λίστας δεν αποκτά προφίλ ---'
insert into auth.users (id, email, confirmation_token, recovery_token,
                        email_change_token_new, email_change)
values ('cccccccc-cccc-cccc-cccc-cccccccccccc','xenos@example.com','','','','');

select count(*) as profil_agnostou from public.profiles
where id='cccccccc-cccc-cccc-cccc-cccccccccccc';

\echo '--- 13γ. Ο άγνωστος δεν βλέπει ούτε προσωπικό ούτε φορέα ---'
do $$
declare v_prof bigint; v_org bigint; v_proj bigint;
begin
  perform set_config('request.jwt.claim.sub','cccccccc-cccc-cccc-cccc-cccccccccccc', true);
  set local role authenticated;
  select count(*) into v_prof from public.profiles;
  select count(*) into v_org  from public.organizations;
  select count(*) into v_proj from public.projects;
  reset role;
  if v_prof <> 0 or v_org <> 0 or v_proj <> 0 then
    raise exception 'Διαρροή: προφίλ=% φορείς=% έργα=%', v_prof, v_org, v_proj;
  end if;
  raise notice 'ο άγνωστος βλέπει 0 προφίλ, 0 φορείς, 0 έργα';
end $$;

rollback;
