-- ================================================================
-- 0003_live_demo_seed.sql
-- Mitas for Alliance — Live 環境向けデモシード（フィクションのみ）
--
-- 用途: 本番 Supabase 環境でのスモークテスト・15分版デモ
--
-- ⚠️ 本シードは「DEMO」と明確に判別できるフィクションのみを含みます。
--    実在する医療機関・医療従事者・患者情報は一切含みません。
--    本番運用切替時は docs/LIVE_DEMO_SEED_PLAN.md の削除手順で
--    速やかに削除してください。
--
-- 前提:
--   1. Supabase ダッシュボードで以下の Auth ユーザーを **手動作成** 済み
--      - konchaaaaan373+mitas-admin@gmail.com     （neco_admin）
--      - konchaaaaan373+mitas-alliance@gmail.com  （alliance_admin）
--      - konchaaaaan373+mitas-facility1@gmail.com （facility_admin / デモ中央病院）
--      - konchaaaaan373+mitas-facility2@gmail.com （facility_admin / デモ訪問看護）
--      - konchaaaaan373+mitas-worker1@gmail.com   （worker / 医師）
--      - konchaaaaan373+mitas-worker2@gmail.com   （worker / 看護師）
--   2. UUID の手動指定は不要。本シードはメールアドレスから auth.users.id を
--      自動取得します。1人でも未作成の場合は EXCEPTION でロールバックします。
--   3. db/migrations/9999_all_in_one_setup.sql （または 0001〜0006 の
--      個別マイグレーション）が適用済みであること。
--
-- 安全策:
--   - すべてのレコードに 'DEMO' プレフィックスまたは（DEMO）表記を付与
--   - request/proposal/assignment/invoice の番号は 'XX-DEMO-NNNN' 形式
--   - auth.users にメールが見つからない場合は EXCEPTION で全行ロールバック
--   - 再実行を安全にするため、冒頭で既存 DEMO 行を DELETE してから INSERT
--   - ユニーク制約違反などのエラーは捕捉せず、Supabase の result 画面に
--     そのまま表示する（無音の rollback を避ける）
-- ================================================================

DO $$
DECLARE
  -- ========== Auth ユーザーのメール（固定） ==========
  c_email_neco     constant text := 'konchaaaaan373+mitas-admin@gmail.com';
  c_email_alliance constant text := 'konchaaaaan373+mitas-alliance@gmail.com';
  c_email_fa1      constant text := 'konchaaaaan373+mitas-facility1@gmail.com';
  c_email_fa2      constant text := 'konchaaaaan373+mitas-facility2@gmail.com';
  c_email_w1       constant text := 'konchaaaaan373+mitas-worker1@gmail.com';
  c_email_w2       constant text := 'konchaaaaan373+mitas-worker2@gmail.com';

  -- ========== auth.users.id（メールから取得） ==========
  v_neco_user      uuid;
  v_alliance_user  uuid;
  v_fa1_user       uuid;
  v_fa2_user       uuid;
  v_w1_user        uuid;
  v_w2_user        uuid;

  -- ========== 組織 UUID（DEMO 固定） ==========
  v_org_demo_hosp  uuid := 'aaaaaaaa-0000-0000-0000-0000000000d1';
  v_org_demo_vns   uuid := 'aaaaaaaa-0000-0000-0000-0000000000d2';

  -- ========== 動的に取得する ID ==========
  v_worker_1_id    uuid;
  v_worker_2_id    uuid;
  v_request_1_id   uuid;
  v_request_2_id   uuid;
  v_request_3_id   uuid;
  v_proposal_1_id  uuid;
  v_proposal_2_id  uuid;
  v_assignment_1_id uuid;

  v_missing        text[] := ARRAY[]::text[];
BEGIN
  -- ----------------------------------------------------------
  -- 0. メールから auth.users.id を解決（不足分があれば EXCEPTION）
  -- ----------------------------------------------------------
  SELECT id INTO v_neco_user     FROM auth.users WHERE email = c_email_neco;
  SELECT id INTO v_alliance_user FROM auth.users WHERE email = c_email_alliance;
  SELECT id INTO v_fa1_user      FROM auth.users WHERE email = c_email_fa1;
  SELECT id INTO v_fa2_user      FROM auth.users WHERE email = c_email_fa2;
  SELECT id INTO v_w1_user       FROM auth.users WHERE email = c_email_w1;
  SELECT id INTO v_w2_user       FROM auth.users WHERE email = c_email_w2;

  IF v_neco_user     IS NULL THEN v_missing := array_append(v_missing, c_email_neco);     END IF;
  IF v_alliance_user IS NULL THEN v_missing := array_append(v_missing, c_email_alliance); END IF;
  IF v_fa1_user      IS NULL THEN v_missing := array_append(v_missing, c_email_fa1);      END IF;
  IF v_fa2_user      IS NULL THEN v_missing := array_append(v_missing, c_email_fa2);      END IF;
  IF v_w1_user       IS NULL THEN v_missing := array_append(v_missing, c_email_w1);       END IF;
  IF v_w2_user       IS NULL THEN v_missing := array_append(v_missing, c_email_w2);       END IF;

  IF array_length(v_missing, 1) IS NOT NULL THEN
    RAISE EXCEPTION
      '[Mitas LIVE seed] 以下の Auth ユーザーが auth.users に見つかりません。Supabase ダッシュボードで作成してから再実行してください: %',
      array_to_string(v_missing, ', ');
  END IF;

  RAISE NOTICE '[Mitas LIVE seed] auth.users 解決完了: neco=%, alliance=%, facility1=%, facility2=%, worker1=%, worker2=%',
    v_neco_user, v_alliance_user, v_fa1_user, v_fa2_user, v_w1_user, v_w2_user;

  -- ----------------------------------------------------------
  -- 0b. 既存 DEMO 行を一旦削除（再実行を確実に成功させるため）
  --     auth.users / user_roles は残し、role と display_name は上書き UPDATE する
  -- ----------------------------------------------------------
  DELETE FROM activity_log
    WHERE entity_id IN (
      SELECT id FROM staffing_requests WHERE request_number LIKE 'SR-DEMO-%'
      UNION SELECT id FROM proposals          WHERE proposal_number LIKE 'PR-DEMO-%'
      UNION SELECT id FROM assignments        WHERE assignment_number LIKE 'AS-DEMO-%'
    );
  DELETE FROM work_logs
    WHERE assignment_id IN (
      SELECT id FROM assignments WHERE assignment_number LIKE 'AS-DEMO-%'
    );
  DELETE FROM assignments        WHERE assignment_number LIKE 'AS-DEMO-%';
  DELETE FROM proposals          WHERE proposal_number  LIKE 'PR-DEMO-%';
  DELETE FROM staffing_requests  WHERE request_number   LIKE 'SR-DEMO-%';

  DELETE FROM worker_credentials
    WHERE worker_id IN (
      SELECT id FROM worker_profiles WHERE full_name LIKE '%（DEMO）'
    );
  DELETE FROM worker_availability
    WHERE worker_id IN (
      SELECT id FROM worker_profiles WHERE full_name LIKE '%（DEMO）'
    );
  DELETE FROM worker_profiles    WHERE full_name LIKE '%（DEMO）';

  DELETE FROM organization_members
    WHERE organization_id IN (v_org_demo_hosp, v_org_demo_vns);
  DELETE FROM organizations
    WHERE id IN (v_org_demo_hosp, v_org_demo_vns);

  -- ----------------------------------------------------------
  -- 1. 組織（DEMO）
  -- ----------------------------------------------------------
  INSERT INTO organizations (id, name, organization_type, prefecture, city, address_line1, postal_code, note)
  VALUES
    (v_org_demo_hosp, 'デモ中央病院（Mitas Demo）',         'hospital',
     '東京都', '千代田区', '丸の内1-0-0（DEMO）', '100-0005',
     'DEMO DATA - Mitas for Alliance live smoke test'),
    (v_org_demo_vns,  'デモ訪問看護ステーション（Mitas Demo）', 'visiting_nurse_station',
     '東京都', '渋谷区', '神南1-0-0（DEMO）',   '150-0041',
     'DEMO DATA - Mitas for Alliance live smoke test')
  ON CONFLICT (id) DO NOTHING;

  -- ----------------------------------------------------------
  -- 2. ロール付与（user_roles）
  -- ----------------------------------------------------------
  INSERT INTO user_roles (user_id, role, display_name) VALUES
    (v_neco_user,     'neco_admin',     '【DEMO】Neco運用 担当'),
    (v_alliance_user, 'alliance_admin', '【DEMO】医療連携 担当'),
    (v_fa1_user,      'facility_admin', '【DEMO】デモ中央病院 採用担当'),
    (v_fa2_user,      'facility_admin', '【DEMO】デモ訪問看護 管理者'),
    (v_w1_user,       'worker',         '【DEMO】田中 健太郎'),
    (v_w2_user,       'worker',         '【DEMO】佐藤 美咲')
  ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role,
                                       display_name = EXCLUDED.display_name;

  -- ----------------------------------------------------------
  -- 3. 組織メンバー（facility_admin と組織を紐付け）
  -- ----------------------------------------------------------
  INSERT INTO organization_members (user_id, organization_id, role) VALUES
    (v_fa1_user, v_org_demo_hosp, 'admin'),
    (v_fa2_user, v_org_demo_vns,  'admin')
  ON CONFLICT (user_id, organization_id) DO NOTHING;

  -- ----------------------------------------------------------
  -- 4. 医療者プロフィール（DEMO のみ）
  -- ----------------------------------------------------------
  INSERT INTO worker_profiles (
    user_id, full_name, full_name_kana, profession_type, primary_specialty,
    years_experience, current_prefecture, desired_prefectures,
    is_available_for_offers, onboarding_status, onboarding_approved_at, onboarding_approved_by
  ) VALUES (
    v_w1_user, '田中 健太郎（DEMO）', 'タナカ ケンタロウ', 'physician', '内科',
    10, '東京都', ARRAY['東京都','神奈川県','千葉県'],
    true, 'approved', NOW() - INTERVAL '30 days', v_neco_user
  )
  ON CONFLICT (user_id) DO UPDATE SET full_name = EXCLUDED.full_name
  RETURNING id INTO v_worker_1_id;

  INSERT INTO worker_profiles (
    user_id, full_name, full_name_kana, profession_type, primary_specialty,
    years_experience, current_prefecture, desired_prefectures,
    is_available_for_offers, onboarding_status, onboarding_approved_at, onboarding_approved_by
  ) VALUES (
    v_w2_user, '佐藤 美咲（DEMO）', 'サトウ ミサキ', 'nurse', '訪問看護',
    7, '東京都', ARRAY['東京都','埼玉県'],
    true, 'approved', NOW() - INTERVAL '20 days', v_neco_user
  )
  ON CONFLICT (user_id) DO UPDATE SET full_name = EXCLUDED.full_name
  RETURNING id INTO v_worker_2_id;

  -- ----------------------------------------------------------
  -- 5. 資格情報（DEMO）
  -- ----------------------------------------------------------
  INSERT INTO worker_credentials (
    worker_id, credential_type, credential_name, issuer,
    issued_date, status, verified_by, verified_at
  ) VALUES
    (v_worker_1_id, 'medical_license', '医師免許（DEMO）', '厚生労働省',
       '2015-04-01', 'verified', v_neco_user, NOW() - INTERVAL '25 days'),
    (v_worker_2_id, 'nursing_license', '看護師免許（DEMO）', '厚生労働省',
       '2018-04-01', 'verified', v_neco_user, NOW() - INTERVAL '15 days')
  ON CONFLICT DO NOTHING;

  -- ----------------------------------------------------------
  -- 6. 勤務可能時間（DEMO 看護師の土日）
  -- ----------------------------------------------------------
  INSERT INTO worker_availability (worker_id, is_recurring, day_of_week, start_time, end_time, shift_type)
  VALUES
    (v_worker_2_id, true, 6, '10:00', '18:00', 'regular_shift'), -- 土曜
    (v_worker_2_id, true, 0, '10:00', '18:00', 'regular_shift')  -- 日曜
  ON CONFLICT DO NOTHING;

  -- ----------------------------------------------------------
  -- 7. 勤務枠依頼（DEMO 3件：submitted / accepted / proposing）
  -- ----------------------------------------------------------
  INSERT INTO staffing_requests (
    request_number, organization_id, created_by_user_id,
    title, description, profession_type, specialty, headcount, shift_type,
    start_at, end_at, hourly_rate_min, hourly_rate_max,
    required_licenses, status, priority, submitted_at
  ) VALUES (
    'SR-DEMO-0001', v_org_demo_hosp, v_fa1_user,
    '内科外来 当直医（DEMO 緊急）',
    E'DEMO DATA - 常勤医退職に伴う当直枠の代替\n\n【想定患者数】\n外来5〜10名（DEMO）\n\n【業務範囲】\n一般内科、当直対応\n\n【バックアップ体制】\n上級医オンコール\n\n【電子カルテ】\nDEMO-EMR\n\n【集合場所・持ち物】\n医局集合、白衣持参\n\n【注意事項】\nDEMO DATA。実勤務はありません。',
    'physician', '内科', 1, 'on_call',
    NOW() + INTERVAL '5 days', NOW() + INTERVAL '5 days 16 hours',
    15000, 18000,
    ARRAY['医師免許'], 'submitted', 'urgent', NOW() - INTERVAL '1 day'
  )
  RETURNING id INTO v_request_1_id;

  INSERT INTO staffing_requests (
    request_number, organization_id, created_by_user_id,
    title, description, profession_type, headcount, shift_type,
    start_at, end_at, hourly_rate_min, hourly_rate_max,
    status, priority, submitted_at, accepted_at
  ) VALUES (
    'SR-DEMO-0002', v_org_demo_vns, v_fa2_user,
    '訪問看護 週末スポット（DEMO）',
    'DEMO DATA - 訪問看護 週末勤務枠',
    'nurse', 1, 'spot',
    NOW() + INTERVAL '7 days', NOW() + INTERVAL '7 days 8 hours',
    3500, 4000,
    'accepted', 'medium',
    NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days'
  )
  RETURNING id INTO v_request_2_id;

  INSERT INTO staffing_requests (
    request_number, organization_id, created_by_user_id,
    title, description, profession_type, specialty, headcount, shift_type,
    start_at, end_at, hourly_rate_min, hourly_rate_max,
    status, priority, submitted_at, accepted_at
  ) VALUES (
    'SR-DEMO-0003', v_org_demo_hosp, v_fa1_user,
    '健診 GW 応援（DEMO）',
    'DEMO DATA - GW 応援勤務枠',
    'physician', '健診', 2, 'spot',
    NOW() + INTERVAL '14 days', NOW() + INTERVAL '14 days 8 hours',
    12000, 15000,
    'proposing', 'high',
    NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days'
  )
  RETURNING id INTO v_request_3_id;

  -- ----------------------------------------------------------
  -- 8. 提案（DEMO 2件：proposed_to_facility / facility_accepted）
  -- ----------------------------------------------------------
  INSERT INTO proposals (
    proposal_number, request_id, worker_id, proposed_by,
    proposed_hourly_rate, status,
    match_score, match_reason
  ) VALUES (
    'PR-DEMO-0001', v_request_2_id, v_worker_2_id, v_neco_user,
    3800, 'proposed_to_facility',
    92.5, 'DEMO - 訪問看護経験7年・希望エリア一致・週末稼働可'
  )
  RETURNING id INTO v_proposal_1_id;

  INSERT INTO proposals (
    proposal_number, request_id, worker_id, proposed_by,
    proposed_hourly_rate, status,
    worker_responded_at, facility_responded_at, facility_responded_by,
    match_score, match_reason
  ) VALUES (
    'PR-DEMO-0002', v_request_3_id, v_worker_1_id, v_neco_user,
    13000, 'facility_accepted',
    NOW() - INTERVAL '36 hours', NOW() - INTERVAL '12 hours', v_fa1_user,
    88.0, 'DEMO - 内科経験10年・健診応援可'
  )
  RETURNING id INTO v_proposal_2_id;

  -- ----------------------------------------------------------
  -- 9. 確定アサイン（DEMO 1件：confirmed）
  --    facility_accepted の PR-DEMO-0002（request_3 × worker_1）を
  --    勤務確定（assignment）に変換する。proposals には
  --    UNIQUE(request_id, worker_id) があるため、同じ組合せの追加
  --    proposal は作れない。AS-DEMO-0001 は PR-DEMO-0002 と紐付く。
  -- ----------------------------------------------------------
  INSERT INTO assignments (
    assignment_number, proposal_id, request_id, worker_id, organization_id,
    scheduled_start_at, scheduled_end_at, hourly_rate, total_compensation,
    status
  )
  SELECT
    'AS-DEMO-0001',
    p.id,
    v_request_3_id,
    v_worker_1_id,
    v_org_demo_hosp,
    NOW() + INTERVAL '14 days',
    NOW() + INTERVAL '14 days 8 hours',
    13000, 104000,
    'confirmed'
  FROM proposals p
  WHERE p.proposal_number = 'PR-DEMO-0002'
  ON CONFLICT (proposal_id) DO NOTHING
  RETURNING id INTO v_assignment_1_id;

  -- ----------------------------------------------------------
  -- 10. 監査ログサンプル（DEMO）
  -- ----------------------------------------------------------
  INSERT INTO activity_log (
    actor_user_id, actor_role, action, entity_type, entity_id, organization_id, after_state
  ) VALUES
    (v_fa1_user,  'facility_admin', 'request.submitted',          'staffing_request', v_request_1_id, v_org_demo_hosp,
     jsonb_build_object('status','submitted','demo',true)),
    (v_neco_user, 'neco_admin',     'request.accepted',           'staffing_request', v_request_2_id, v_org_demo_vns,
     jsonb_build_object('status','accepted','demo',true)),
    (v_neco_user, 'neco_admin',     'proposal.created',           'proposal',         v_proposal_1_id, v_org_demo_vns,
     jsonb_build_object('status','created','demo',true)),
    (v_fa2_user,  'facility_admin', 'proposal.facility_accepted', 'proposal',         v_proposal_2_id, v_org_demo_hosp,
     jsonb_build_object('status','facility_accepted','demo',true));

  -- ----------------------------------------------------------
  -- 完了通知
  -- ----------------------------------------------------------
  RAISE NOTICE '----------------------------------------------------------';
  RAISE NOTICE 'Mitas for Alliance ライブデモシード投入完了（フィクション）';
  RAISE NOTICE '  organizations: 2 (デモ中央病院 / デモ訪問看護)';
  RAISE NOTICE '  worker_profiles: 2 (DEMO)';
  RAISE NOTICE '  staffing_requests: 3 (SR-DEMO-0001..0003)';
  RAISE NOTICE '  proposals: 2 (PR-DEMO-0001..0002)';
  RAISE NOTICE '  assignments: 1 (AS-DEMO-0001 confirmed, from PR-DEMO-0002)';
  RAISE NOTICE '';
  RAISE NOTICE 'デモ終了後は docs/LIVE_DEMO_SEED_PLAN.md の';
  RAISE NOTICE '「削除（ロールバック）手順」を参照して削除してください。';
  RAISE NOTICE '----------------------------------------------------------';
END $$;
