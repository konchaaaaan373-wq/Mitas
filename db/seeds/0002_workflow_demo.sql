-- ================================================================
-- 0002_workflow_demo.sql
-- Phase 1 ワークフローのデモシード
--
-- 用途: 開発・検証用のサンプルデータ
-- 注意:
--   - Supabase Auth ユーザーが先に作成されている前提
--   - 下記の固定UUIDで auth.users が存在しない場合は、
--     ON CONFLICT DO NOTHING + DO 句のチェックで安全にスキップ
--
-- 想定するauth.usersのUUID（実際の Supabase ダッシュボードで作成してください）:
--   neco_admin_1     : 11111111-1111-1111-1111-111111111111
--   alliance_admin_1 : 22222222-2222-2222-2222-222222222222
--   facility_admin_1 : 33333333-3333-3333-3333-333333333333  -- さくら病院 admin
--   facility_admin_2 : 44444444-4444-4444-4444-444444444444  -- みどり訪問看護 admin
--   worker_1         : 55555555-5555-5555-5555-555555555555  -- 内科医
--   worker_2         : 66666666-6666-6666-6666-666666666666  -- 訪問看護師
-- ================================================================

DO $$
DECLARE
  v_neco_user      uuid := '11111111-1111-1111-1111-111111111111';
  v_alliance_user  uuid := '22222222-2222-2222-2222-222222222222';
  v_fa1_user       uuid := '33333333-3333-3333-3333-333333333333';
  v_fa2_user       uuid := '44444444-4444-4444-4444-444444444444';
  v_w1_user        uuid := '55555555-5555-5555-5555-555555555555';
  v_w2_user        uuid := '66666666-6666-6666-6666-666666666666';

  v_org_sakura     uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_org_midori     uuid := 'aaaaaaaa-0000-0000-0000-000000000002';

  v_worker_1_id    uuid;
  v_worker_2_id    uuid;
  v_request_1_id   uuid;
  v_request_2_id   uuid;
  v_proposal_1_id  uuid;
  v_assignment_1_id uuid;

  v_users_exist    boolean;
BEGIN
  -- auth.users が存在するかチェック
  SELECT EXISTS (
    SELECT 1 FROM auth.users WHERE id = v_neco_user
  ) INTO v_users_exist;

  IF NOT v_users_exist THEN
    RAISE NOTICE 'auth.users が見つかりません。Supabase ダッシュボードで対応UUIDのユーザーを作成してから再度実行してください。';
    RETURN;
  END IF;

  -- ----------------------------------------------------------
  -- 組織
  -- ----------------------------------------------------------
  INSERT INTO organizations (id, name, organization_type)
  VALUES
    (v_org_sakura, 'さくら病院グループ',         'hospital'),
    (v_org_midori, 'みどり訪問看護ステーション', 'visiting_nurse_station')
  ON CONFLICT (id) DO NOTHING;

  -- ----------------------------------------------------------
  -- ロール付与
  -- ----------------------------------------------------------
  INSERT INTO user_roles (user_id, role, display_name) VALUES
    (v_neco_user,     'neco_admin',     'Neco運用 太郎'),
    (v_alliance_user, 'alliance_admin', '医療連携 花子'),
    (v_fa1_user,      'facility_admin', 'さくら病院 採用担当'),
    (v_fa2_user,      'facility_admin', 'みどり訪問看護 管理者'),
    (v_w1_user,       'worker',         '医師 山田'),
    (v_w2_user,       'worker',         '看護師 鈴木')
  ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;

  -- ----------------------------------------------------------
  -- 組織メンバー（facility_admin と組織を紐付け）
  -- ----------------------------------------------------------
  INSERT INTO organization_members (user_id, organization_id, role) VALUES
    (v_fa1_user, v_org_sakura, 'admin'),
    (v_fa2_user, v_org_midori, 'admin')
  ON CONFLICT (user_id, organization_id) DO NOTHING;

  -- ----------------------------------------------------------
  -- ワーカープロフィール
  -- ----------------------------------------------------------
  INSERT INTO worker_profiles (
    user_id, full_name, full_name_kana, profession_type, primary_specialty,
    years_experience, current_prefecture, desired_prefectures,
    is_available_for_offers, onboarding_status, onboarding_approved_at, onboarding_approved_by
  ) VALUES (
    v_w1_user, '山田 健司', 'ヤマダ ケンジ', 'physician', '内科',
    12, '東京都', ARRAY['東京都','神奈川県','千葉県'],
    true, 'approved', NOW() - INTERVAL '30 days', v_neco_user
  )
  ON CONFLICT (user_id) DO UPDATE SET full_name = EXCLUDED.full_name
  RETURNING id INTO v_worker_1_id;

  INSERT INTO worker_profiles (
    user_id, full_name, full_name_kana, profession_type, primary_specialty,
    years_experience, current_prefecture, desired_prefectures,
    is_available_for_offers, onboarding_status, onboarding_approved_at, onboarding_approved_by
  ) VALUES (
    v_w2_user, '鈴木 美咲', 'スズキ ミサキ', 'nurse', '訪問看護',
    8, '東京都', ARRAY['東京都','埼玉県'],
    true, 'approved', NOW() - INTERVAL '20 days', v_neco_user
  )
  ON CONFLICT (user_id) DO UPDATE SET full_name = EXCLUDED.full_name
  RETURNING id INTO v_worker_2_id;

  -- ----------------------------------------------------------
  -- 資格情報
  -- ----------------------------------------------------------
  INSERT INTO worker_credentials (
    worker_id, credential_type, credential_name, issuer,
    issued_date, status, verified_by, verified_at
  ) VALUES
    (v_worker_1_id, 'medical_license', '医師免許',     '厚生労働省',
       '2014-04-01', 'verified', v_neco_user, NOW() - INTERVAL '25 days'),
    (v_worker_2_id, 'nursing_license', '看護師免許',   '厚生労働省',
       '2018-04-01', 'verified', v_neco_user, NOW() - INTERVAL '15 days');

  -- ----------------------------------------------------------
  -- 空き枠（worker_2 は土日 10-18時 訪問看護OK）
  -- ----------------------------------------------------------
  INSERT INTO worker_availability (worker_id, is_recurring, day_of_week, start_time, end_time, shift_type)
  VALUES
    (v_worker_2_id, true, 6, '10:00', '18:00', 'regular_shift'), -- 土曜
    (v_worker_2_id, true, 0, '10:00', '18:00', 'regular_shift'); -- 日曜

  -- ----------------------------------------------------------
  -- スタッフィング依頼（さくら病院: 内科医 緊急）
  -- ----------------------------------------------------------
  INSERT INTO staffing_requests (
    request_number, organization_id, created_by_user_id,
    title, description, profession_type, specialty, headcount, shift_type,
    start_at, end_at, hourly_rate_min, hourly_rate_max,
    required_licenses, status, priority, submitted_at
  ) VALUES (
    'SR-2026-0001', v_org_sakura, v_fa1_user,
    '内科外来 当直医（5月急募）', '常勤医退職に伴う当直枠の代替',
    'physician', '内科', 1, 'on_call',
    NOW() + INTERVAL '5 days', NOW() + INTERVAL '5 days 16 hours',
    15000, 18000,
    ARRAY['医師免許'], 'submitted', 'urgent', NOW() - INTERVAL '1 day'
  )
  RETURNING id INTO v_request_1_id;

  INSERT INTO staffing_requests (
    request_number, organization_id, created_by_user_id,
    title, profession_type, headcount, shift_type,
    start_at, end_at, hourly_rate_min, hourly_rate_max,
    status, priority, submitted_at, accepted_at
  ) VALUES (
    'SR-2026-0002', v_org_midori, v_fa2_user,
    '訪問看護 週末スポット', 'nurse', 1, 'spot',
    NOW() + INTERVAL '7 days', NOW() + INTERVAL '7 days 8 hours',
    3500, 4000,
    'accepted', 'medium', NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days'
  )
  RETURNING id INTO v_request_2_id;

  -- ----------------------------------------------------------
  -- 提案（worker_2 を request_2 に提案 → facility_accepted）
  -- ----------------------------------------------------------
  INSERT INTO proposals (
    proposal_number, request_id, worker_id, proposed_by,
    proposed_hourly_rate, status,
    worker_responded_at, facility_responded_at, facility_responded_by,
    match_score, match_reason
  ) VALUES (
    'PR-2026-0001', v_request_2_id, v_worker_2_id, v_neco_user,
    3800, 'facility_accepted',
    NOW() - INTERVAL '36 hours', NOW() - INTERVAL '24 hours', v_fa2_user,
    92.5, '訪問看護経験8年・希望エリア一致・週末稼働可'
  )
  RETURNING id INTO v_proposal_1_id;

  -- ----------------------------------------------------------
  -- アサインメント（confirmed状態で生成）
  -- ----------------------------------------------------------
  INSERT INTO assignments (
    assignment_number, proposal_id, request_id, worker_id, organization_id,
    scheduled_start_at, scheduled_end_at, hourly_rate, total_compensation,
    status
  ) VALUES (
    'AS-2026-0001', v_proposal_1_id, v_request_2_id, v_worker_2_id, v_org_midori,
    NOW() + INTERVAL '7 days', NOW() + INTERVAL '7 days 8 hours',
    3800, 30400, 'confirmed'
  )
  RETURNING id INTO v_assignment_1_id;

  -- ----------------------------------------------------------
  -- 請求書（draftで作成）
  -- ----------------------------------------------------------
  INSERT INTO invoices (
    invoice_number, organization_id, period_start, period_end,
    subtotal, tax, total, status
  ) VALUES (
    'IN-2026-0001', v_org_midori,
    date_trunc('month', CURRENT_DATE)::date,
    (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::date,
    30400, 3040, 33440, 'draft'
  );

  -- ----------------------------------------------------------
  -- 監査ログサンプル
  -- ----------------------------------------------------------
  INSERT INTO activity_log (
    actor_user_id, actor_role, action, entity_type, entity_id, organization_id, after_state
  ) VALUES
    (v_fa1_user, 'facility_admin', 'request.submitted',  'staffing_request', v_request_1_id, v_org_sakura,
     jsonb_build_object('status','submitted')),
    (v_neco_user, 'neco_admin',   'request.accepted',   'staffing_request', v_request_2_id, v_org_midori,
     jsonb_build_object('status','accepted')),
    (v_neco_user, 'neco_admin',   'proposal.created',   'proposal',         v_proposal_1_id, v_org_midori,
     jsonb_build_object('status','created')),
    (v_fa2_user, 'facility_admin', 'proposal.accepted', 'proposal',         v_proposal_1_id, v_org_midori,
     jsonb_build_object('status','facility_accepted'));

  RAISE NOTICE 'デモデータを投入しました: requests=%, proposals=%, assignments=%',
    2, 1, 1;

EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'シードは既に投入済みのためスキップします（unique_violation）';
END $$;
