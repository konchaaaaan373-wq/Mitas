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
--      - demo-neco@mitas-demo.example      （neco_admin）
--      - demo-alliance@mitas-demo.example  （alliance_admin）
--      - demo-facility-1@mitas-demo.example（facility_admin / デモ中央病院）
--      - demo-facility-2@mitas-demo.example（facility_admin / デモ訪問看護）
--      - demo-doctor@mitas-demo.example    （worker / 医師）
--      - demo-nurse@mitas-demo.example     （worker / 看護師）
--   2. 上記ユーザーの auth.users.id を、下の DECLARE ブロックの
--      v_neco_user / v_alliance_user / v_fa1_user / v_fa2_user /
--      v_w1_user / v_w2_user に **置き換えて** 実行してください。
--   3. db/migrations/9999_all_in_one_setup.sql （または 0001〜0006 の
--      個別マイグレーション）が適用済みであること。
--
-- 安全策:
--   - すべてのレコードに 'DEMO' プレフィックスまたは（DEMO）表記を付与
--   - request/proposal/assignment/invoice の番号は 'XX-DEMO-NNNN' 形式
--   - auth.users が見つからない場合は NOTICE を出して安全に終了
--   - unique_violation 発生時は再投入として NOTICE のみで終了
-- ================================================================

DO $$
DECLARE
  -- ========== Auth ユーザー UUID（実値に置き換える） ==========
  v_neco_user      uuid := '11111111-1111-1111-1111-1111111111d1';  -- ← 実 UUID に置き換え
  v_alliance_user  uuid := '22222222-2222-2222-2222-2222222222d1';  -- ← 実 UUID に置き換え
  v_fa1_user       uuid := '33333333-3333-3333-3333-3333333333d1';  -- ← 実 UUID に置き換え
  v_fa2_user       uuid := '33333333-3333-3333-3333-3333333333d2';  -- ← 実 UUID に置き換え
  v_w1_user        uuid := '55555555-5555-5555-5555-5555555555d1';  -- ← 実 UUID に置き換え
  v_w2_user        uuid := '55555555-5555-5555-5555-5555555555d2';  -- ← 実 UUID に置き換え

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

  v_users_exist    boolean;
BEGIN
  -- ----------------------------------------------------------
  -- 0. 前提チェック：auth.users が存在するか
  -- ----------------------------------------------------------
  SELECT EXISTS (
    SELECT 1 FROM auth.users WHERE id = v_neco_user
  ) INTO v_users_exist;

  IF NOT v_users_exist THEN
    RAISE NOTICE '----------------------------------------------------------';
    RAISE NOTICE 'Auth ユーザーが見つかりません。';
    RAISE NOTICE 'Supabase ダッシュボードで以下のユーザーを手動作成し、';
    RAISE NOTICE 'auth.users.id を本ファイル冒頭の DECLARE ブロックに';
    RAISE NOTICE '置き換えてから再度実行してください。';
    RAISE NOTICE '  - demo-neco@mitas-demo.example';
    RAISE NOTICE '  - demo-alliance@mitas-demo.example';
    RAISE NOTICE '  - demo-facility-1@mitas-demo.example';
    RAISE NOTICE '  - demo-facility-2@mitas-demo.example';
    RAISE NOTICE '  - demo-doctor@mitas-demo.example';
    RAISE NOTICE '  - demo-nurse@mitas-demo.example';
    RAISE NOTICE '----------------------------------------------------------';
    RETURN;
  END IF;

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
    required_licenses, status, priority, submitted_at, notes
  ) VALUES (
    'SR-DEMO-0001', v_org_demo_hosp, v_fa1_user,
    '内科外来 当直医（DEMO 緊急）', 'DEMO DATA - 常勤医退職に伴う当直枠の代替',
    'physician', '内科', 1, 'on_call',
    NOW() + INTERVAL '5 days', NOW() + INTERVAL '5 days 16 hours',
    15000, 18000,
    ARRAY['医師免許'], 'submitted', 'urgent', NOW() - INTERVAL '1 day',
    E'【想定患者数】\n外来5〜10名（DEMO）\n\n【業務範囲】\n一般内科、当直対応\n\n【バックアップ体制】\n上級医オンコール\n\n【電子カルテ】\nDEMO-EMR\n\n【集合場所・持ち物】\n医局集合、白衣持参\n\n【注意事項】\nDEMO DATA。実勤務はありません。'
  )
  RETURNING id INTO v_request_1_id;

  INSERT INTO staffing_requests (
    request_number, organization_id, created_by_user_id,
    title, profession_type, headcount, shift_type,
    start_at, end_at, hourly_rate_min, hourly_rate_max,
    status, priority, submitted_at, accepted_at, notes
  ) VALUES (
    'SR-DEMO-0002', v_org_demo_vns, v_fa2_user,
    '訪問看護 週末スポット（DEMO）', 'nurse', 1, 'spot',
    NOW() + INTERVAL '7 days', NOW() + INTERVAL '7 days 8 hours',
    3500, 4000,
    'accepted', 'medium',
    NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days',
    'DEMO DATA - 訪問看護 週末勤務枠'
  )
  RETURNING id INTO v_request_2_id;

  INSERT INTO staffing_requests (
    request_number, organization_id, created_by_user_id,
    title, profession_type, specialty, headcount, shift_type,
    start_at, end_at, hourly_rate_min, hourly_rate_max,
    status, priority, submitted_at, accepted_at, notes
  ) VALUES (
    'SR-DEMO-0003', v_org_demo_hosp, v_fa1_user,
    '健診 GW 応援（DEMO）', 'physician', '健診', 2, 'spot',
    NOW() + INTERVAL '14 days', NOW() + INTERVAL '14 days 8 hours',
    12000, 15000,
    'proposing', 'high',
    NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days',
    'DEMO DATA - GW 応援勤務枠'
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
  --    PR-DEMO-0002 は施設承認済みのため、UI から「勤務確定を作成」を
  --    試せるよう、ここでは未確定のままにしておく。
  --    PR-DEMO-0001 は施設承認待ちなのでアサイン未作成が自然。
  --    別途 confirmed 状態のサンプルを 1 件用意する。
  -- ----------------------------------------------------------
  -- ※ assignments の生成には proposal が facility_accepted である必要があるため、
  --   別途確定済み用に PR-DEMO-0003 を facility_accepted で追加し、
  --   AS-DEMO-0001 を作成する。
  INSERT INTO proposals (
    proposal_number, request_id, worker_id, proposed_by,
    proposed_hourly_rate, status,
    worker_responded_at, facility_responded_at, facility_responded_by,
    match_score, match_reason
  ) VALUES (
    'PR-DEMO-0003', v_request_2_id, v_worker_2_id, v_neco_user,
    3800, 'facility_accepted',
    NOW() - INTERVAL '48 hours', NOW() - INTERVAL '24 hours', v_fa2_user,
    95.0, 'DEMO - 訪問看護 確定勤務サンプル'
  )
  ON CONFLICT (proposal_number) DO NOTHING;

  INSERT INTO assignments (
    assignment_number, proposal_id, request_id, worker_id, organization_id,
    scheduled_start_at, scheduled_end_at, hourly_rate, total_compensation,
    status
  )
  SELECT
    'AS-DEMO-0001',
    p.id,
    v_request_2_id,
    v_worker_2_id,
    v_org_demo_vns,
    NOW() + INTERVAL '7 days',
    NOW() + INTERVAL '7 days 8 hours',
    3800, 30400,
    'confirmed'
  FROM proposals p
  WHERE p.proposal_number = 'PR-DEMO-0003'
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
  RAISE NOTICE '  proposals: 3 (PR-DEMO-0001..0003)';
  RAISE NOTICE '  assignments: 1 (AS-DEMO-0001 confirmed)';
  RAISE NOTICE '';
  RAISE NOTICE 'デモ終了後は docs/LIVE_DEMO_SEED_PLAN.md の';
  RAISE NOTICE '「削除（ロールバック）手順」を参照して削除してください。';
  RAISE NOTICE '----------------------------------------------------------';

EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'デモシードは既に投入済みのためスキップしました（unique_violation）';
END $$;
