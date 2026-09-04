-- =====================================================================
-- 0020_demo_seed.sql — Επιδεικτικά δεδομένα (ΠΡΟΑΙΡΕΤΙΚΟ)
-- ---------------------------------------------------------------------
-- Δημιουργεί δύο χρήστες, ένα πλήρες έργο του Δήμου Ρόδου και όλες τις
-- συνοδευτικές εγγραφές, ώστε να δοκιμαστεί άμεσα η ροή και η παραγωγή
-- εγγράφων. ΔΕΝ πρέπει να εφαρμοστεί σε παραγωγική βάση.
--
--   epivlepon@dimosrodou.demo    / Epivlepsi!2026   (επιβλέπων)
--   proistamenos@dimosrodou.demo / Epivlepsi!2026   (προϊστάμενος Δ.Υ.)
-- =====================================================================

do $$
declare
  v_org        uuid := '00000000-0000-0000-0000-0000000000d1';
  v_epiv       uuid := '00000000-0000-0000-0000-00000000e001';
  v_proi       uuid := '00000000-0000-0000-0000-00000000e002';
  v_project    uuid := '00000000-0000-0000-0000-0000000000a1';
  v_contractor uuid := '00000000-0000-0000-0000-0000000000c1';
  v_contract   uuid := '00000000-0000-0000-0000-0000000000b1';
  v_bver       uuid := '00000000-0000-0000-0000-0000000000f1';
  v_meas       uuid := '00000000-0000-0000-0000-000000000101';
  v_hwn        uuid := '00000000-0000-0000-0000-000000000111';
  v_guar       uuid := '00000000-0000-0000-0000-000000000121';
  v_sched      uuid := '00000000-0000-0000-0000-000000000131';
  v_bi         uuid;
  v_pw         text := extensions.crypt('Epivlepsi!2026', extensions.gen_salt('bf'));
begin
  -- ---- 1. Χρήστες αυθεντικοποίησης --------------------------------
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    ('00000000-0000-0000-0000-000000000000', v_epiv, 'authenticated', 'authenticated',
     'epivlepon@dimosrodou.demo', v_pw, now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"full_name":"Βασίλειος Διακολιός","specialty":"ΠΕ Μηχανολόγος Μηχανικός"}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-000000000000', v_proi, 'authenticated', 'authenticated',
     'proistamenos@dimosrodou.demo', v_pw, now(),
     '{"provider":"email","providers":["email"]}'::jsonb,
     '{"full_name":"Γεώργιος Παπαδόπουλος","specialty":"Πολιτικός Μηχανικός"}'::jsonb, now(), now())
  on conflict (id) do nothing;

  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values
    (v_epiv::text, v_epiv,
     jsonb_build_object('sub', v_epiv::text, 'email', 'epivlepon@dimosrodou.demo', 'email_verified', true),
     'email', now(), now(), now()),
    (v_proi::text, v_proi,
     jsonb_build_object('sub', v_proi::text, 'email', 'proistamenos@dimosrodou.demo', 'email_verified', true),
     'email', now(), now(), now())
  on conflict (provider, provider_id) do nothing;

  -- ΚΡΙΣΙΜΟ: οι στήλες κειμένου confirmation_token, recovery_token,
  -- email_change_token_new και email_change ΔΕΝ έχουν προεπιλογή. Αν μείνουν
  -- NULL, η υπηρεσία Auth τις διαβάζει σε μη-μηδενίσιμα πεδία και κάθε
  -- σύνδεση αποτυγχάνει με «Database error querying schema». Το GoTrue
  -- αποθηκεύει κενό κείμενο — κάνουμε το ίδιο.
  update auth.users
     set confirmation_token         = coalesce(confirmation_token, ''),
         recovery_token             = coalesce(recovery_token, ''),
         email_change_token_new     = coalesce(email_change_token_new, ''),
         email_change               = coalesce(email_change, ''),
         email_change_token_current = coalesce(email_change_token_current, ''),
         phone_change               = coalesce(phone_change, ''),
         phone_change_token         = coalesce(phone_change_token, ''),
         reauthentication_token     = coalesce(reauthentication_token, '')
   where id in (v_epiv, v_proi);

  -- Το trigger trg_handle_new_user έχει ήδη δημιουργήσει τα profiles·
  -- εδώ μόνο συμπληρώνουμε στοιχεία.
  update public.profiles set grade = 'Α΄', registry_no = 'ΤΕΕ 98765'
   where id = v_epiv;
  update public.profiles set grade = 'Α΄', registry_no = 'ΤΕΕ 45321'
   where id = v_proi;

  insert into public.org_roles (profile_id, org_id, role, decision_ada)
  values (v_proi, v_org, 'proistamenos_dy', 'ΨΞ12ΩΡΤ-Λ4Δ')
  on conflict do nothing;

  -- ---- 2. Ανάδοχος --------------------------------------------------
  insert into public.contractors (id, org_id, name, legal_form, afm, doy, gemi,
                                  meep_mieedde, categories, legal_rep_name, legal_rep_afm,
                                  address, email, phone)
  values (v_contractor, v_org, 'ΤΕΧΝΙΚΗ ΑΙΓΑΙΟΥ Α.Τ.Ε.', 'Α.Ε.', '099887766', 'Ρόδου',
          '123456789000', 'ΜΗ.Ε.Ε.Δ.Ε. 21456', array['ΟΔΟΠΟΙΙΑ','ΟΙΚΟΔΟΜΙΚΑ'],
          'Ιωάννης Καραγιάννης', '045678912',
          'Λεωφ. Ρόδου–Λίνδου 12, 85100 Ρόδος', 'info@texnikiaigaiou.demo', '2241012345')
  on conflict (id) do nothing;

  -- ---- 3. Έργο ------------------------------------------------------
  insert into public.projects (id, org_id, code, title, category, cpv, ka_budget_code,
                               funding_source, study_budget_net, estimated_value_net,
                               tender_publication_at, adam_tender, award_decision_ada,
                               location, created_by)
  values (v_project, v_org, 'ΔΡ-2026/014',
          'Ανακατασκευή οδοστρωμάτων και κατασκευή πεζοδρομίων στη Δ.Ε. Ιαλυσού',
          'odopoiia', '45233120-6', '30.7323.0012',
          'ΣΑΤΑ / Ίδιοι πόροι (Κ.Α. 30.7323.0012)',
          620000.00, 620000.00,
          date '2025-09-15', '25PROC000123456', 'ΨΘ45ΩΡΤ-Ν9Ζ',
          'Δ.Ε. Ιαλυσού, Δήμος Ρόδου', v_proi)
  on conflict (id) do nothing;

  -- ---- 4. Σύμβαση ---------------------------------------------------
  insert into public.contracts (id, project_id, contractor_id, regime, supervision_mode,
                                contract_no, signed_at, adam_contract, ada_contract,
                                discount_pct, works_value_net, ge_oe_pct, ge_oe_amount,
                                contingency_pct, contingency_amount, revision_amount,
                                initial_value_net, vat_rate, total_duration_days,
                                works_start_deadline, schedule_submit_days,
                                original_end_date, current_end_date, maintenance_months,
                                diary_mode, diary_penalty_per_day, daily_penalty_basis)
  values (v_contract, v_project, v_contractor, 'n4412_meta_n4782', 'ypiresiaki',
          'ΔΡ-2026/014-ΣΥΜ', date '2026-01-20', '26SYMV000234567', 'Ω4Κ7ΩΡΤ-Β2Χ',
          32.40, 335664.00, 18.00, 60419.52, 15.00, 59412.53, 0.00,
          455496.05, 24.00, 300,
          date '2026-02-19', 15,
          date '2026-11-16', date '2026-11-16', 15,
          'imerisio', 200.00, 455496.05)
  on conflict (id) do nothing;

  -- ---- 5. Αναθέσεις -------------------------------------------------
  insert into public.project_assignments (project_id, profile_id, role, is_coordinator,
                                          duties, decision_no, decision_ada, decision_date, legal_ref_id)
  values
    (v_project, v_epiv, 'epivlepon', true,
     'Επίβλεψη του συνόλου των εργασιών, τήρηση ημερολογίου, έλεγχος επιμετρήσεων και λογαριασμών.',
     '2145/2026', 'ΨΛ8ΤΩΡΤ-Ξ7Φ', date '2026-01-22', 'N4412/136/2'),
    (v_project, v_proi, 'proistamenos_dy', false,
     'Άσκηση καθηκόντων Διευθύνουσας Υπηρεσίας.',
     '2145/2026', 'ΨΛ8ΤΩΡΤ-Ξ7Φ', date '2026-01-22', 'N4412/136')
  on conflict do nothing;

  insert into public.project_assignments (project_id, contractor_id, role, decision_date, legal_ref_id)
  values (v_project, v_contractor, 'anadochos', date '2026-01-20', 'N4412/138')
  on conflict do nothing;

  -- ---- 6. Προϋπολογισμός --------------------------------------------
  insert into public.budget_versions (id, project_id, version_no, label, is_current, approved_at, total_net)
  values (v_bver, v_project, 0, 'Αρχική σύμβαση', true, date '2026-01-20', 455496.05)
  on conflict (id) do nothing;

  insert into public.budget_items (project_id, version_id, line_no, item_code, description, unit, unit_price, quantity)
  values
    (v_project, v_bver, 1, 'ΟΔΟ Α-2',   'Γενικές εκσκαφές σε έδαφος γαιώδες–ημιβραχώδες', 'm3',   3.20,  4200.000),
    (v_project, v_bver, 2, 'ΟΔΟ Γ-1.2', 'Υπόβαση οδοστρωσίας μεταβλητού πάχους',          'm3',  12.50,  1850.000),
    (v_project, v_bver, 3, 'ΟΔΟ Δ-8.1', 'Ασφαλτική στρώση κυκλοφορίας 5 cm',              'm2',   8.90, 12400.000),
    (v_project, v_bver, 4, 'ΟΙΚ 38.20', 'Χαλύβδινος οπλισμός σκυροδέματος B500C',         'kg',   1.15, 18600.000),
    (v_project, v_bver, 5, 'ΟΔΟ Β-51',  'Πρόχυτα κράσπεδα από σκυρόδεμα',                 'm',   11.40,  2350.000),
    (v_project, v_bver, 6, 'ΟΔΟ Β-52',  'Πλακοστρώσεις πεζοδρομίων με τσιμεντόπλακες',    'm2',  18.70,  3100.000)
  on conflict do nothing;

  -- ---- 7. Χρονοδιάγραμμα -------------------------------------------
  insert into public.schedules (id, project_id, version_no, label, method,
                                submitted_at, approved_at, approved_by, period_granularity)
  values (v_sched, v_project, 0, 'Αρχικό χρονοδιάγραμμα', 'diktyoti_analysi',
          date '2026-02-02', date '2026-02-12', v_proi, 'mina')
  on conflict (id) do nothing;

  -- ---- 8. Πρωτόκολλο αφανών εργασιών (άρθρο 151 παρ. 7) -------------
  insert into public.hidden_work_notices (id, project_id, serial_no, work_description, location,
                                          declaration_at, truth_declaration, invitation_sent_at,
                                          inspected_at, inspected_by, supervisor_report_at,
                                          photos_count, covered_at, status, legal_ref_id)
  values (v_hwn, v_project, 1,
          'Θεμελίωση και εγκιβωτισμός αγωγού ομβρίων Φ600 — εκσκαφή, στρώση έδρασης, οπλισμός και επίχωση',
          'Οδός Ηρακλειδών, Χ.Θ. 0+120 έως 0+265',
          date '2026-03-09', true, date '2026-03-09',
          date '2026-03-11', '00000000-0000-0000-0000-00000000e001', date '2026-03-11',
          14, date '2026-03-13', 'approved', 'N4412/151/7')
  on conflict (id) do nothing;

  -- ---- 9. Αναλυτική επιμέτρηση --------------------------------------
  insert into public.measurements (id, project_id, mtype, serial_no, period_from, period_to,
                                   work_section, truth_declaration, has_drawings,
                                   submitted_at, status, contractual_amount, extra_amount)
  values (v_meas, v_project, 'tmimatiki', 1, date '2026-02-20', date '2026-05-31',
          'Χωματουργικά – οδοστρωσία – ασφαλτικά (Α΄ τμήμα)',
          true, true, date '2026-06-05', 'approved', 0, 0)
  on conflict (id) do nothing;

  for v_bi in
    select id from public.budget_items where version_id = v_bver order by line_no
  loop
    insert into public.measurement_lines (measurement_id, budget_item_id, quantity_period, quantity_cumul, unit_price)
    select v_meas, bi.id, round(bi.quantity * 0.45, 3), round(bi.quantity * 0.45, 3), bi.unit_price
      from public.budget_items bi where bi.id = v_bi
    on conflict do nothing;
  end loop;

  update public.measurements m
     set contractual_amount = coalesce((select sum(ml.quantity_cumul * ml.unit_price)
                                          from public.measurement_lines ml
                                         where ml.measurement_id = m.id), 0)
   where m.id = v_meas;

  -- ---- 10. Εγγυητική καλής εκτέλεσης (άρθρο 72) ---------------------
  insert into public.guarantees (id, project_id, gtype, issuer, guarantee_no, issued_at,
                                 original_amount, current_amount, pct_of_contract, status, legal_ref_id)
  values (v_guar, v_project, 'kalis_ektelesis', 'Τράπεζα Πειραιώς Α.Ε.', 'e-ΕΓΓ/2026/884512',
          date '2026-01-16', 22774.80, 22774.80, 5.00, 'energi', 'N4412/72/4')
  on conflict (id) do nothing;

  -- ---- 11. Στιγμιότυπο ροής εργασιών --------------------------------
  perform app.instantiate_workflow(v_project);
end $$;


-- =====================================================================
-- ΔΕΥΤΕΡΟ ΕΡΓΟ — στη φάση της περαίωσης, ώστε να δοκιμάζονται τα
-- έγγραφα Βεβαίωσης Περάτωσης και Μείωσης Εγγύησης 70%.
-- =====================================================================
do $$
declare
  v_org        uuid := '00000000-0000-0000-0000-0000000000d1';
  v_epiv       uuid := '00000000-0000-0000-0000-00000000e001';
  v_proi       uuid := '00000000-0000-0000-0000-00000000e002';
  v_contractor uuid := '00000000-0000-0000-0000-0000000000c2';
  v_project    uuid := '00000000-0000-0000-0000-0000000000a2';
  v_contract   uuid := '00000000-0000-0000-0000-0000000000b2';
  v_bver       uuid := '00000000-0000-0000-0000-0000000000f2';
  v_meas       uuid := '00000000-0000-0000-0000-000000000102';
  v_guar       uuid := '00000000-0000-0000-0000-000000000122';
begin
  insert into public.contractors (id, org_id, name, legal_form, afm, doy,
                                  meep_mieedde, categories, legal_rep_name,
                                  address, email, phone)
  values (v_contractor, v_org, 'ΔΩΔΕΚΑΝΗΣΟΣ ΚΑΤΑΣΚΕΥΑΣΤΙΚΗ Ο.Ε.', 'Ο.Ε.', '088776655', 'Ρόδου',
          'ΜΗ.Ε.Ε.Δ.Ε. 30871', array['ΟΙΚΟΔΟΜΙΚΑ','ΗΛΕΚΤΡΟΜΗΧΑΝΟΛΟΓΙΚΑ'],
          'Ελένη Σαββίδου', 'Αγίων Αποστόλων 45, 85100 Ρόδος',
          'info@dodekanisos-kat.demo', '2241067890')
  on conflict (id) do nothing;

  insert into public.projects (id, org_id, code, title, category, cpv, ka_budget_code,
                               funding_source, study_budget_net, estimated_value_net,
                               tender_publication_at, award_decision_ada, location, created_by)
  values (v_project, v_org, 'ΔΡ-2025/007',
          'Ενεργειακή αναβάθμιση του 3ου Δημοτικού Σχολείου Ρόδου',
          'oikodomika', '45214210-5', '30.7331.0007',
          'Πρόγραμμα «ΗΛΕΚΤΡΑ» / Ταμείο Ανάκαμψης',
          310000.00, 310000.00, date '2024-11-04', 'ΨΓ73ΩΡΤ-Κ2Λ',
          'Ρόδος, Δ.Ε. Ρόδου', v_proi)
  on conflict (id) do nothing;

  insert into public.contracts (id, project_id, contractor_id, contract_no, signed_at,
                                ada_contract, discount_pct, works_value_net, ge_oe_pct,
                                ge_oe_amount, contingency_pct, contingency_amount,
                                initial_value_net, total_duration_days, works_start_deadline,
                                original_end_date, current_end_date, maintenance_months,
                                diary_mode, diary_penalty_per_day, daily_penalty_basis)
  values (v_contract, v_project, v_contractor, 'ΔΡ-2025/007-ΣΥΜ', date '2025-03-10',
          'ΩΞ92ΩΡΤ-Φ5Θ', 28.15, 178300.00, 18.00, 32094.00, 9.00, 18935.46,
          229329.46, 420, date '2025-04-09',
          date '2026-05-04', date '2026-06-30', 15,
          'imerisio', 150.00, 229329.46)
  on conflict (id) do nothing;

  insert into public.project_assignments (project_id, profile_id, role, is_coordinator,
                                          decision_no, decision_ada, decision_date, legal_ref_id)
  values (v_project, v_epiv, 'epivlepon', true, '1180/2025', 'ΨΩ42ΩΡΤ-Δ8Ψ', date '2025-03-12', 'N4412/136/2'),
         (v_project, v_proi, 'proistamenos_dy', false, '1180/2025', 'ΨΩ42ΩΡΤ-Δ8Ψ', date '2025-03-12', 'N4412/136')
  on conflict do nothing;

  insert into public.project_assignments (project_id, contractor_id, role, decision_date, legal_ref_id)
  values (v_project, v_contractor, 'anadochos', date '2025-03-10', 'N4412/138')
  on conflict do nothing;

  insert into public.budget_versions (id, project_id, version_no, label, is_current, approved_at, total_net)
  values (v_bver, v_project, 0, 'Αρχική σύμβαση', true, date '2025-03-10', 229329.46)
  on conflict (id) do nothing;

  insert into public.budget_items (project_id, version_id, line_no, item_code, description, unit, unit_price, quantity)
  values
    (v_project, v_bver, 1, 'ΟΙΚ 79.55',  'Θερμομόνωση εξωτερικής τοιχοποιίας με σύστημα ETICS', 'm2',  42.00, 1850.000),
    (v_project, v_bver, 2, 'ΟΙΚ 65.17',  'Κουφώματα αλουμινίου με ενεργειακούς υαλοπίνακες',    'm2', 265.00,  310.000),
    (v_project, v_bver, 3, 'ΗΛΜ 60.10',  'Αντλία θερμότητας αέρα–νερού 60 kW',                  'τεμ',9800.00,    2.000),
    (v_project, v_bver, 4, 'ΗΛΜ 62.15',  'Φωτιστικά σώματα LED οροφής',                         'τεμ',  78.00,  240.000)
  on conflict do nothing;

  -- Τελική επιμέτρηση (άρθρο 151 §9) — εγκεκριμένη
  insert into public.measurements (id, project_id, mtype, serial_no, period_from, period_to,
                                   work_section, truth_declaration, has_drawings,
                                   submitted_at, approved_at, approved_by, status,
                                   contractual_amount, extra_amount)
  values (v_meas, v_project, 'teliki', 1, date '2025-04-09', date '2026-05-04',
          'Τελική επιμέτρηση του συνόλου των εργασιών', true, true,
          date '2026-06-02', date '2026-07-28', v_proi, 'approved', 229329.46, 0)
  on conflict (id) do nothing;

  insert into public.measurement_lines (measurement_id, budget_item_id, quantity_period, quantity_cumul, unit_price)
  select v_meas, bi.id, bi.quantity, bi.quantity, bi.unit_price
    from public.budget_items bi where bi.version_id = v_bver
  on conflict do nothing;

  insert into public.final_measurement (project_id, measurement_id, completion_date,
                                        submitted_at, supervisor_report_at, approved_at,
                                        approved_by, approval_ada, prepared_by_service,
                                        penalty_months, penalty_amount, legal_ref_id)
  values (v_project, v_meas, date '2026-05-04',
          date '2026-06-02', date '2026-06-30', date '2026-07-28',
          v_proi, 'ΨΛ55ΩΡΤ-Τ3Β', false, 0, 0, 'N4412/151/9')
  on conflict do nothing;

  -- Βεβαίωση περάτωσης (άρθρο 168)
  insert into public.completions (project_id, approved_completion_date, contractor_declared_at,
                                  supervisor_report_at, tests_completed, defects_found,
                                  certificate_issued_at, certificate_issued_by,
                                  actual_completion_date, legal_ref_id)
  values (v_project, date '2026-06-30', date '2026-05-04', date '2026-05-20',
          true, false, date '2026-05-28', v_proi, date '2026-05-04', 'N4412/168/2')
  on conflict do nothing;

  insert into public.guarantees (id, project_id, gtype, issuer, guarantee_no, issued_at,
                                 original_amount, current_amount, pct_of_contract, status, legal_ref_id)
  values (v_guar, v_project, 'kalis_ektelesis', 'Τράπεζα Eurobank Α.Ε.', 'e-ΕΓΓ/2025/551204',
          date '2025-03-05', 11466.47, 11466.47, 5.00, 'energi', 'N4412/72/4')
  on conflict (id) do nothing;

  perform app.instantiate_workflow(v_project);
end $$;
