INSERT INTO organizations (
  id,
  name,
  legal_name,
  organization_type,
  prefecture,
  city,
  address_line1,
  postal_code,
  note
) VALUES
  (
    '1f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '西新宿ホームケアグループ',
    '医療法人西新宿ホームケアグループ',
    'home_visit_clinic',
    '東京都',
    '新宿区',
    '西新宿1-20-3',
    '160-0023',
    '在宅医療と訪問看護を複数拠点で運営'
  ),
  (
    '1f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0002',
    'みなと訪問看護ステーション',
    '株式会社みなとケア',
    'visiting_nurse_station',
    '東京都',
    '港区',
    '芝2-10-5',
    '105-0014',
    '24時間対応体制あり'
  );

INSERT INTO organization_contacts (
  id,
  organization_id,
  name,
  role_title,
  email,
  phone,
  preferred_contact_channel,
  is_primary
) VALUES
  (
    '2f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '1f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '山田 真紀',
    '事務長',
    'm-yamada@example.com',
    '03-1111-2222',
    'email',
    TRUE
  ),
  (
    '2f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0002',
    '1f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0002',
    '佐々木 美穂',
    '看護管理者',
    'miho-sasaki@example.com',
    '03-3333-4444',
    'phone',
    TRUE
  );

INSERT INTO facilities (
  id,
  organization_id,
  facility_name,
  facility_type,
  prefecture,
  city,
  address_line1,
  postal_code,
  service_area,
  bed_count,
  patient_volume_monthly
) VALUES
  (
    '3f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '1f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '西新宿在宅診療所',
    'home_visit_clinic',
    '東京都',
    '新宿区',
    '西新宿1-20-3',
    '160-0023',
    '新宿区・中野区・渋谷区',
    NULL,
    420
  ),
  (
    '3f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0002',
    '1f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0002',
    'みなと訪問看護ステーション本店',
    'visiting_nurse_station',
    '東京都',
    '港区',
    '芝2-10-5',
    '105-0014',
    '港区・品川区',
    NULL,
    310
  );

INSERT INTO inquiries (
  id,
  organization_name,
  contact_name,
  email,
  phone,
  organization_type,
  prefecture,
  inquiry_type,
  urgency_level,
  message,
  desired_support,
  status
) VALUES
  (
    '4f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '西新宿ホームケアグループ',
    '山田 真紀',
    'm-yamada@example.com',
    '03-1111-2222',
    'home_visit_clinic',
    '東京都',
    '急募相談',
    'urgent',
    '訪問診療を担える常勤医師の欠員が発生し、4週間以内の立ち上がりが必要です。',
    ARRAY['要件整理', '候補者紹介'],
    'converted'
  );

INSERT INTO staffing_cases (
  id,
  organization_id,
  primary_contact_id,
  source_inquiry_id,
  title,
  summary,
  background,
  case_status,
  priority_level,
  compliance_risk,
  owner_name,
  target_start_date,
  required_by_date,
  latest_contacted_at
) VALUES
  (
    '5f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '1f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '2f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '4f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '訪問診療医師の緊急補充',
    '訪問診療の主担当医師が退職予定のため、4週間以内の補充が必要。',
    '患者引継ぎとオンコール体制維持が必要。',
    'sourcing',
    'urgent',
    '在宅患者の継続診療への影響',
    'Konchi',
    CURRENT_DATE + INTERVAL '30 day',
    CURRENT_DATE + INTERVAL '21 day',
    NOW()
  );

UPDATE inquiries
SET converted_organization_id = '1f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    converted_case_id = '5f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001'
WHERE id = '4f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001';

INSERT INTO staffing_requirements (
  id,
  case_id,
  facility_id,
  profession_type,
  specialty,
  employment_type,
  headcount,
  min_experience_years,
  license_requirements,
  must_have_skills,
  preferred_skills,
  shift_pattern,
  work_days,
  compensation_min,
  compensation_max,
  compensation_unit,
  work_prefecture,
  work_city,
  urgency_reason
) VALUES
  (
    '6f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '5f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '3f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    'physician',
    '在宅医療',
    'full_time',
    1,
    5,
    ARRAY['医師免許'],
    ARRAY['訪問診療', '看取り対応'],
    ARRAY['オンコール対応', '多職種連携'],
    '平日 + オンコール',
    ARRAY['月', '火', '水', '木', '金'],
    1400000,
    1800000,
    'monthly',
    '東京都',
    '新宿区',
    '主担当医退職に伴う緊急補充'
  );

INSERT INTO candidate_profiles (
  id,
  full_name,
  full_name_kana,
  email,
  phone,
  profession_type,
  primary_specialty,
  years_experience,
  current_prefecture,
  current_city,
  desired_prefectures,
  desired_employment_types,
  licenses,
  skills,
  availability_status,
  min_compensation,
  profile_summary,
  source_channel,
  consent_to_contact
) VALUES
  (
    '7f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '田中 恒一',
    'タナカ コウイチ',
    'koichi.tanaka@example.com',
    '090-1111-2222',
    'physician',
    '在宅医療',
    9,
    '東京都',
    '世田谷区',
    ARRAY['東京都', '神奈川県'],
    ARRAY['full_time', 'contract'],
    ARRAY['医師免許'],
    ARRAY['訪問診療', '緩和ケア', '看取り対応'],
    'within_2_weeks',
    1500000,
    '在宅医療クリニックでの常勤経験あり。多職種連携と終末期対応に強み。',
    'other',
    TRUE
  ),
  (
    '7f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0002',
    '高橋 美咲',
    'タカハシ ミサキ',
    'misaki.takahashi@example.com',
    '090-3333-4444',
    'nurse',
    '訪問看護',
    7,
    '東京都',
    '大田区',
    ARRAY['東京都'],
    ARRAY['full_time', 'part_time'],
    ARRAY['看護師免許'],
    ARRAY['訪問看護', 'オンコール', '家族支援'],
    'immediate',
    420000,
    '訪問看護ステーション管理者補佐の経験あり。',
    'other',
    TRUE
  );

INSERT INTO case_matches (
  id,
  case_id,
  requirement_id,
  candidate_id,
  stage,
  match_score,
  match_reason,
  owner_note,
  introduced_at
) VALUES
  (
    '8f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '5f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '6f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '7f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    'screening',
    91.50,
    '在宅医療経験、看取り対応、都内勤務希望が高一致。',
    '初回ヒアリングの印象良好。条件面は詳細確認待ち。',
    NOW()
  );

INSERT INTO follow_up_tasks (
  id,
  case_id,
  requirement_id,
  match_id,
  assigned_to,
  title,
  description,
  due_at,
  status
) VALUES
  (
    '9f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '5f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '6f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    '8f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    'Konchi',
    '候補者との条件確認',
    '勤務開始可能日とオンコール頻度の許容範囲を確認する。',
    NOW() + INTERVAL '1 day',
    'open'
  );

INSERT INTO case_activities (
  case_id,
  activity_type,
  summary,
  detail,
  created_by
) VALUES
  (
    '5f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    'case_created',
    '問い合わせを案件化',
    '{"source":"web_form","operator":"Konchi"}'::JSONB,
    'Konchi'
  ),
  (
    '5f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001',
    'candidate_matched',
    '候補者を一次選定に追加',
    '{"candidate_id":"7f8bb0a8-5f4a-4d79-b8c6-7d2b4f5f0001","score":91.5}'::JSONB,
    'Konchi'
  );
