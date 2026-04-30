-- ================================================================
-- MITAS Phase 1 v2: 全マイグレーション統合版（一括セットアップ用）
-- ================================================================
-- このファイル1つを Supabase SQL Editor で実行すると、必要なテーブル・
-- 状態遷移トリガー・RLSポリシー・集計ビューがすべて作成されます。
--
-- 元ファイル（個別マイグレーション）:
--   0001_mitas_core.sql           : 旧コアテーブル
--   0003_organization_members.sql : organizations / organization_members
--   0004_phase1_core_tables.sql   : v2 メインテーブル群
--   0005_phase1_state_machine.sql : 状態遷移トリガー
--   0006_phase1_rls_policies.sql  : 4ロール RLS ポリシー
--   0007_phase1_views.sql         : 集計ビュー10種
--
-- 0002_hospital_users.sql は旧 hospital ユーザー機能のため省略。
-- ================================================================

-- ───────────────────────────────────────────
-- Supabase テンプレート由来のクリーンアップ
-- プロジェクト作成時にテンプレートが追加した可能性のあるトリガーを削除
-- ───────────────────────────────────────────
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;


-- ════════════════════════════════════════════════════════════
-- 0001_mitas_core.sql
-- ════════════════════════════════════════════════════════════
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'organization_type') THEN
    CREATE TYPE organization_type AS ENUM (
      'hospital',
      'clinic',
      'home_visit_clinic',
      'visiting_nurse_station',
      'nursing_facility',
      'pharmacy',
      'home_care_office',
      'other'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inquiry_status') THEN
    CREATE TYPE inquiry_status AS ENUM (
      'new',
      'reviewing',
      'qualified',
      'converted',
      'closed',
      'spam'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'case_status') THEN
    CREATE TYPE case_status AS ENUM (
      'draft',
      'intake',
      'scoping',
      'sourcing',
      'interviewing',
      'offer',
      'placed',
      'on_hold',
      'closed_won',
      'closed_lost'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'priority_level') THEN
    CREATE TYPE priority_level AS ENUM (
      'low',
      'medium',
      'high',
      'urgent',
      'critical'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'profession_type') THEN
    CREATE TYPE profession_type AS ENUM (
      'physician',
      'nurse',
      'pharmacist',
      'therapist',
      'care_worker',
      'care_manager',
      'medical_clerk',
      'other'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'employment_type') THEN
    CREATE TYPE employment_type AS ENUM (
      'full_time',
      'part_time',
      'temporary',
      'dispatch',
      'contract',
      'locum',
      'other'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'availability_status') THEN
    CREATE TYPE availability_status AS ENUM (
      'immediate',
      'within_2_weeks',
      'within_1_month',
      'future',
      'unavailable'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'match_stage') THEN
    CREATE TYPE match_stage AS ENUM (
      'shortlisted',
      'contacted',
      'screening',
      'interview',
      'offer',
      'placed',
      'declined',
      'archived'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_status') THEN
    CREATE TYPE task_status AS ENUM (
      'open',
      'in_progress',
      'done',
      'cancelled'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'contact_channel') THEN
    CREATE TYPE contact_channel AS ENUM (
      'email',
      'phone',
      'line',
      'web_form',
      'other'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  legal_name VARCHAR(255),
  organization_type organization_type NOT NULL DEFAULT 'other',
  corporate_number VARCHAR(20),
  website_url TEXT,
  prefecture VARCHAR(50),
  city VARCHAR(100),
  address_line1 VARCHAR(255),
  postal_code VARCHAR(20),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS organization_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  role_title VARCHAR(255),
  email CITEXT,
  phone VARCHAR(50),
  preferred_contact_channel contact_channel DEFAULT 'email',
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS facilities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  facility_name VARCHAR(255) NOT NULL,
  facility_type organization_type NOT NULL DEFAULT 'other',
  prefecture VARCHAR(50),
  city VARCHAR(100),
  address_line1 VARCHAR(255),
  postal_code VARCHAR(20),
  service_area TEXT,
  bed_count INTEGER CHECK (bed_count IS NULL OR bed_count >= 0),
  patient_volume_monthly INTEGER CHECK (patient_volume_monthly IS NULL OR patient_volume_monthly >= 0),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS inquiries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_name VARCHAR(255) NOT NULL,
  contact_name VARCHAR(255) NOT NULL,
  email CITEXT NOT NULL,
  phone VARCHAR(50),
  organization_type organization_type DEFAULT 'other',
  prefecture VARCHAR(50),
  inquiry_type VARCHAR(100),
  urgency_level priority_level DEFAULT 'medium',
  message TEXT NOT NULL,
  desired_support TEXT[],
  status inquiry_status NOT NULL DEFAULT 'new',
  source_channel contact_channel NOT NULL DEFAULT 'web_form',
  converted_organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
  converted_case_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS staffing_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  primary_contact_id UUID REFERENCES organization_contacts(id) ON DELETE SET NULL,
  source_inquiry_id UUID UNIQUE REFERENCES inquiries(id) ON DELETE SET NULL,
  title VARCHAR(255) NOT NULL,
  summary TEXT NOT NULL,
  background TEXT,
  case_status case_status NOT NULL DEFAULT 'intake',
  priority_level priority_level NOT NULL DEFAULT 'medium',
  compliance_risk VARCHAR(100),
  owner_name VARCHAR(255),
  target_start_date DATE,
  required_by_date DATE,
  latest_contacted_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'inquiries_converted_case_id_fkey'
  ) THEN
    ALTER TABLE inquiries
      ADD CONSTRAINT inquiries_converted_case_id_fkey
      FOREIGN KEY (converted_case_id) REFERENCES staffing_cases(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS staffing_requirements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES staffing_cases(id) ON DELETE CASCADE,
  facility_id UUID REFERENCES facilities(id) ON DELETE SET NULL,
  profession_type profession_type NOT NULL,
  specialty VARCHAR(255),
  sub_specialty VARCHAR(255),
  employment_type employment_type NOT NULL DEFAULT 'full_time',
  headcount INTEGER NOT NULL DEFAULT 1 CHECK (headcount > 0),
  min_experience_years INTEGER CHECK (min_experience_years IS NULL OR min_experience_years >= 0),
  license_requirements TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  must_have_skills TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  preferred_skills TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  shift_pattern VARCHAR(255),
  work_days TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  compensation_min INTEGER CHECK (compensation_min IS NULL OR compensation_min >= 0),
  compensation_max INTEGER CHECK (compensation_max IS NULL OR compensation_max >= 0),
  compensation_unit VARCHAR(50) DEFAULT 'monthly',
  work_prefecture VARCHAR(50),
  work_city VARCHAR(100),
  urgency_reason TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (
    compensation_min IS NULL
    OR compensation_max IS NULL
    OR compensation_min <= compensation_max
  )
);

CREATE TABLE IF NOT EXISTS candidate_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name VARCHAR(255) NOT NULL,
  full_name_kana VARCHAR(255),
  email CITEXT,
  phone VARCHAR(50),
  profession_type profession_type NOT NULL,
  primary_specialty VARCHAR(255),
  years_experience INTEGER CHECK (years_experience IS NULL OR years_experience >= 0),
  current_prefecture VARCHAR(50),
  current_city VARCHAR(100),
  desired_prefectures TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  desired_employment_types TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  licenses TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  skills TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  availability_status availability_status NOT NULL DEFAULT 'future',
  min_compensation INTEGER CHECK (min_compensation IS NULL OR min_compensation >= 0),
  profile_summary TEXT,
  source_channel contact_channel DEFAULT 'other',
  consent_to_contact BOOLEAN NOT NULL DEFAULT FALSE,
  last_contacted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS case_matches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES staffing_cases(id) ON DELETE CASCADE,
  requirement_id UUID NOT NULL REFERENCES staffing_requirements(id) ON DELETE CASCADE,
  candidate_id UUID NOT NULL REFERENCES candidate_profiles(id) ON DELETE CASCADE,
  stage match_stage NOT NULL DEFAULT 'shortlisted',
  match_score NUMERIC(5,2) CHECK (match_score IS NULL OR (match_score >= 0 AND match_score <= 100)),
  match_reason TEXT,
  owner_note TEXT,
  declined_reason TEXT,
  introduced_at TIMESTAMPTZ,
  interview_at TIMESTAMPTZ,
  placement_start_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (requirement_id, candidate_id)
);

CREATE TABLE IF NOT EXISTS follow_up_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES staffing_cases(id) ON DELETE CASCADE,
  requirement_id UUID REFERENCES staffing_requirements(id) ON DELETE SET NULL,
  match_id UUID REFERENCES case_matches(id) ON DELETE SET NULL,
  assigned_to VARCHAR(255),
  title VARCHAR(255) NOT NULL,
  description TEXT,
  due_at TIMESTAMPTZ,
  status task_status NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS case_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES staffing_cases(id) ON DELETE CASCADE,
  activity_type VARCHAR(100) NOT NULL,
  summary TEXT NOT NULL,
  detail JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_by VARCHAR(255),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_organizations_type ON organizations(organization_type);
CREATE INDEX IF NOT EXISTS idx_facilities_org ON facilities(organization_id);
CREATE INDEX IF NOT EXISTS idx_inquiries_status ON inquiries(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_staffing_cases_status ON staffing_cases(case_status, priority_level, required_by_date);
CREATE INDEX IF NOT EXISTS idx_staffing_cases_org ON staffing_cases(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_staffing_requirements_case ON staffing_requirements(case_id, profession_type, is_active);
CREATE INDEX IF NOT EXISTS idx_staffing_requirements_license_gin ON staffing_requirements USING GIN (license_requirements);
CREATE INDEX IF NOT EXISTS idx_staffing_requirements_must_have_gin ON staffing_requirements USING GIN (must_have_skills);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_profession ON candidate_profiles(profession_type, availability_status);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_licenses_gin ON candidate_profiles USING GIN (licenses);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_skills_gin ON candidate_profiles USING GIN (skills);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_prefectures_gin ON candidate_profiles USING GIN (desired_prefectures);
CREATE INDEX IF NOT EXISTS idx_case_matches_case_stage ON case_matches(case_id, stage, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_follow_up_tasks_status_due ON follow_up_tasks(status, due_at);
CREATE INDEX IF NOT EXISTS idx_case_activities_case_time ON case_activities(case_id, occurred_at DESC);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_organizations_updated_at ON organizations;
CREATE TRIGGER trg_organizations_updated_at
BEFORE UPDATE ON organizations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_organization_contacts_updated_at ON organization_contacts;
CREATE TRIGGER trg_organization_contacts_updated_at
BEFORE UPDATE ON organization_contacts
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_facilities_updated_at ON facilities;
CREATE TRIGGER trg_facilities_updated_at
BEFORE UPDATE ON facilities
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_inquiries_updated_at ON inquiries;
CREATE TRIGGER trg_inquiries_updated_at
BEFORE UPDATE ON inquiries
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_staffing_cases_updated_at ON staffing_cases;
CREATE TRIGGER trg_staffing_cases_updated_at
BEFORE UPDATE ON staffing_cases
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_staffing_requirements_updated_at ON staffing_requirements;
CREATE TRIGGER trg_staffing_requirements_updated_at
BEFORE UPDATE ON staffing_requirements
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_candidate_profiles_updated_at ON candidate_profiles;
CREATE TRIGGER trg_candidate_profiles_updated_at
BEFORE UPDATE ON candidate_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_case_matches_updated_at ON case_matches;
CREATE TRIGGER trg_case_matches_updated_at
BEFORE UPDATE ON case_matches
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_follow_up_tasks_updated_at ON follow_up_tasks;
CREATE TRIGGER trg_follow_up_tasks_updated_at
BEFORE UPDATE ON follow_up_tasks
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE VIEW v_case_pipeline_summary AS
SELECT
  sc.id,
  sc.title,
  sc.case_status,
  sc.priority_level,
  sc.required_by_date,
  o.name AS organization_name,
  COUNT(DISTINCT sr.id) AS requirement_count,
  COUNT(DISTINCT cm.id) AS match_count,
  COUNT(DISTINCT cm.id) FILTER (WHERE cm.stage IN ('interview', 'offer', 'placed')) AS progressed_match_count,
  COUNT(DISTINCT ft.id) FILTER (WHERE ft.status IN ('open', 'in_progress')) AS open_task_count
FROM staffing_cases sc
JOIN organizations o ON o.id = sc.organization_id
LEFT JOIN staffing_requirements sr ON sr.case_id = sc.id
LEFT JOIN case_matches cm ON cm.case_id = sc.id
LEFT JOIN follow_up_tasks ft ON ft.case_id = sc.id
GROUP BY sc.id, o.name;

CREATE OR REPLACE VIEW v_candidate_match_readiness AS
SELECT
  cp.id,
  cp.full_name,
  cp.profession_type,
  cp.primary_specialty,
  cp.availability_status,
  cp.current_prefecture,
  cp.desired_prefectures,
  cp.licenses,
  cp.skills,
  COUNT(cm.id) FILTER (WHERE cm.stage <> 'archived') AS active_match_count
FROM candidate_profiles cp
LEFT JOIN case_matches cm ON cm.candidate_id = cp.id
GROUP BY cp.id;

-- ════════════════════════════════════════════════════════════
-- 0003_organization_members.sql
-- ════════════════════════════════════════════════════════════
-- ================================================================
-- 0003_organization_members.sql
-- Supabase Auth ユーザー と 組織 を紐付けるテーブル
-- Row Level Security (RLS) を有効化し、
-- 各病院スタッフが自組織のデータのみ閲覧・操作できるようにする
-- ================================================================

-- ----------------------------------------------------------------
-- 組織テーブル（なければ作成）
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS organizations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  short_name    text,
  postal_code   text,
  address       text,
  phone         text,
  email         text,
  website       text,
  facility_type text,           -- 'hospital' | 'clinic' | 'nursing' | 'pharmacy'
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------
-- 組織メンバーテーブル
-- Supabase Auth の users.id と organizations.id を紐付ける
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS organization_members (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  role            text NOT NULL DEFAULT 'member',  -- 'owner' | 'admin' | 'member'
  is_active       boolean NOT NULL DEFAULT true,
  invited_by      uuid REFERENCES auth.users(id),
  joined_at       timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, organization_id)
);

-- インデックス：user_id での高速検索
CREATE INDEX IF NOT EXISTS idx_org_members_user_id ON organization_members(user_id);
CREATE INDEX IF NOT EXISTS idx_org_members_org_id  ON organization_members(organization_id);

-- ----------------------------------------------------------------
-- 案件テーブル（staffing_cases）
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staffing_cases (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_number     text NOT NULL UNIQUE,             -- 'SC-2026-001' 形式
  organization_id uuid NOT NULL REFERENCES organizations(id),
  title           text NOT NULL,
  profession_type text NOT NULL,                    -- 'physician' | 'nurse' | ...
  headcount       int  NOT NULL DEFAULT 1,
  employment_type text,                             -- 'full_time' | 'part_time' | 'contract'
  case_status     text NOT NULL DEFAULT 'intake',   -- intake | scoping | sourcing | interviewing | offer | placed | cancelled
  priority_level  text NOT NULL DEFAULT 'medium',   -- critical | urgent | high | medium | low
  deadline        date,
  note            text,
  owner_user_id   uuid REFERENCES auth.users(id),
  match_total     int NOT NULL DEFAULT 0,
  match_interview int NOT NULL DEFAULT 0,
  match_offer     int NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cases_org_id     ON staffing_cases(organization_id);
CREATE INDEX IF NOT EXISTS idx_cases_status     ON staffing_cases(case_status);
CREATE INDEX IF NOT EXISTS idx_cases_created_at ON staffing_cases(created_at DESC);

-- ----------------------------------------------------------------
-- updated_at 自動更新トリガー
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_organizations_updated_at    ON organizations;
DROP TRIGGER IF EXISTS trg_staffing_cases_updated_at   ON staffing_cases;

CREATE TRIGGER trg_organizations_updated_at
  BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_staffing_cases_updated_at
  BEFORE UPDATE ON staffing_cases
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ================================================================
-- Row Level Security (RLS) の設定
-- 各テーブルで有効化し、ユーザーが自組織データのみ操作できるようにする
-- ================================================================

-- organizations テーブル
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

-- 自分が所属する組織のみ閲覧可
CREATE POLICY "members can view their org"
  ON organizations FOR SELECT
  USING (
    id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

-- ----------------------------------------------------------------
-- organization_members テーブル
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;

-- 自分自身のメンバーレコード、および同組織メンバーのレコードを閲覧可
CREATE POLICY "members can view same org members"
  ON organization_members FOR SELECT
  USING (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

-- owner/admin のみメンバー追加可
CREATE POLICY "admins can insert members"
  ON organization_members FOR INSERT
  WITH CHECK (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid()
        AND role IN ('owner', 'admin')
        AND is_active = true
    )
  );

-- owner/admin のみメンバー更新可
CREATE POLICY "admins can update members"
  ON organization_members FOR UPDATE
  USING (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid()
        AND role IN ('owner', 'admin')
        AND is_active = true
    )
  );

-- ----------------------------------------------------------------
-- staffing_cases テーブル
ALTER TABLE staffing_cases ENABLE ROW LEVEL SECURITY;

-- 自組織の案件のみ閲覧可
CREATE POLICY "members can view org cases"
  ON staffing_cases FOR SELECT
  USING (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

-- admin 以上のみ案件作成可
CREATE POLICY "admins can create cases"
  ON staffing_cases FOR INSERT
  WITH CHECK (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid()
        AND role IN ('owner', 'admin')
        AND is_active = true
    )
  );

-- admin 以上のみ案件更新可
CREATE POLICY "admins can update cases"
  ON staffing_cases FOR UPDATE
  USING (
    organization_id IN (
      SELECT organization_id FROM organization_members
      WHERE user_id = auth.uid()
        AND role IN ('owner', 'admin')
        AND is_active = true
    )
  );

-- ================================================================
-- 初期データ：開発用テストアカウント用組織
-- （本番環境では削除またはコメントアウト）
-- ================================================================

-- INSERT INTO organizations (id, name, short_name, facility_type)
-- VALUES (
--   'aaaaaaaa-0000-0000-0000-000000000001',
--   'さくら病院グループ',
--   'さくら病院',
--   'hospital'
-- ) ON CONFLICT DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- 0004_phase1_core_tables.sql
-- ════════════════════════════════════════════════════════════
-- ================================================================
-- 0004_phase1_core_tables.sql
-- Phase 1: コアテーブルのみ（RLSと状態機械トリガーは別マイグレーション）
--
-- 目的: 4ロール（facility_admin / worker / neco_admin / alliance_admin）
-- とコントロール型マッチングワークフローの土台となるテーブル群を追加。
--
-- スコープ:
--   - 列挙型（user_role, request_status, proposal_status,
--     assignment_status, invoice_status, credential_status, shift_type）
--   - user_roles テーブル（auth.users への役割付与）
--   - worker_profiles / worker_credentials / worker_availability
--   - staffing_requests / proposals / assignments / work_logs
--   - invoices / invoice_line_items
--   - activity_log（監査）
--   - updated_at トリガー、基本インデックス
--
-- 含まれないもの（後続マイグレーションで対応）:
--   - 状態遷移バリデーション関数・トリガー
--   - 4ロール分の Row Level Security ポリシー
--   - 集計ビュー
-- ================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- ================================================================
-- ENUMS
-- ================================================================
DO $$
BEGIN
  -- ユーザーロール
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE user_role AS ENUM (
      'facility_admin',
      'worker',
      'neco_admin',
      'alliance_admin'
    );
  END IF;

  -- スタッフィング依頼の状態
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'request_status') THEN
    CREATE TYPE request_status AS ENUM (
      'draft',
      'submitted',
      'under_review',
      'accepted',
      'rejected',
      'proposing',
      'partially_assigned',
      'fully_assigned',
      'in_progress',
      'completion_pending',
      'confirmed',
      'invoiced',
      'paid',
      'cancelled'
    );
  END IF;

  -- 提案の状態
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'proposal_status') THEN
    CREATE TYPE proposal_status AS ENUM (
      'created',
      'worker_contacted',
      'worker_accepted',
      'worker_declined',
      'proposed_to_facility',
      'facility_accepted',
      'facility_declined',
      'withdrawn',
      'expired'
    );
  END IF;

  -- アサインメントの状態
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'assignment_status') THEN
    CREATE TYPE assignment_status AS ENUM (
      'confirmed',
      'checked_in',
      'checked_out',
      'completion_reported',
      'completion_confirmed',
      'disputed',
      'cancelled',
      'no_show'
    );
  END IF;

  -- 資格検証の状態
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'credential_status') THEN
    CREATE TYPE credential_status AS ENUM (
      'pending',
      'verified',
      'rejected',
      'expired'
    );
  END IF;

  -- 請求書の状態
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'invoice_status') THEN
    CREATE TYPE invoice_status AS ENUM (
      'draft',
      'issued',
      'paid',
      'overdue',
      'void'
    );
  END IF;

  -- 勤務形態（シフト分類）
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'shift_type') THEN
    CREATE TYPE shift_type AS ENUM (
      'regular_shift',
      'on_call',
      'night_duty',
      'spot',
      'other'
    );
  END IF;

  -- worker のオンボーディング状態
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'worker_onboarding_status') THEN
    CREATE TYPE worker_onboarding_status AS ENUM (
      'incomplete',
      'submitted',
      'approved',
      'suspended'
    );
  END IF;

  -- work_log の種別
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'work_log_type') THEN
    CREATE TYPE work_log_type AS ENUM (
      'check_in',
      'check_out',
      'break_start',
      'break_end',
      'note',
      'incident'
    );
  END IF;
END $$;

-- ================================================================
-- 共通関数: updated_at 自動更新
-- （0001 の set_updated_at が既にある場合は再利用）
-- ================================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- 1. user_roles
--    auth.users に対するグローバルロール付与
--    （組織への所属は organization_members で管理）
-- ================================================================
CREATE TABLE IF NOT EXISTS user_roles (
  user_id      uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role         user_role NOT NULL,
  display_name text,
  is_active    boolean NOT NULL DEFAULT true,
  granted_by   uuid REFERENCES auth.users(id),
  granted_at   timestamptz NOT NULL DEFAULT NOW(),
  created_at   timestamptz NOT NULL DEFAULT NOW(),
  updated_at   timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_roles_role ON user_roles(role) WHERE is_active = true;

DROP TRIGGER IF EXISTS trg_user_roles_updated_at ON user_roles;
CREATE TRIGGER trg_user_roles_updated_at
  BEFORE UPDATE ON user_roles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE user_roles IS 'auth.users に紐づくグローバルロール（4種類）';
COMMENT ON COLUMN user_roles.role IS 'facility_admin | worker | neco_admin | alliance_admin';

-- ================================================================
-- 2. worker_profiles
--    医療従事者の専門プロフィール
--    （Neco管理の candidate_profiles とは別。本人が自身で管理）
-- ================================================================
CREATE TABLE IF NOT EXISTS worker_profiles (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  candidate_profile_id     uuid REFERENCES candidate_profiles(id) ON DELETE SET NULL,
  full_name                varchar(255) NOT NULL,
  full_name_kana           varchar(255),
  email                    citext,
  phone                    varchar(50),
  date_of_birth            date,
  profession_type          profession_type NOT NULL,
  primary_specialty        varchar(255),
  sub_specialties          text[] NOT NULL DEFAULT ARRAY[]::text[],
  years_experience         integer CHECK (years_experience IS NULL OR years_experience >= 0),
  current_prefecture       varchar(50),
  current_city             varchar(100),
  desired_prefectures      text[] NOT NULL DEFAULT ARRAY[]::text[],
  bio                      text,
  work_radius_km           integer CHECK (work_radius_km IS NULL OR work_radius_km >= 0),
  is_available_for_offers  boolean NOT NULL DEFAULT false,
  onboarding_status        worker_onboarding_status NOT NULL DEFAULT 'incomplete',
  onboarding_submitted_at  timestamptz,
  onboarding_approved_at   timestamptz,
  onboarding_approved_by   uuid REFERENCES auth.users(id),
  suspended_reason         text,
  last_active_at           timestamptz,
  created_at               timestamptz NOT NULL DEFAULT NOW(),
  updated_at               timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_worker_profiles_user        ON worker_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_worker_profiles_profession  ON worker_profiles(profession_type);
CREATE INDEX IF NOT EXISTS idx_worker_profiles_onboarding  ON worker_profiles(onboarding_status);
CREATE INDEX IF NOT EXISTS idx_worker_profiles_available   ON worker_profiles(is_available_for_offers) WHERE is_available_for_offers = true;
CREATE INDEX IF NOT EXISTS idx_worker_profiles_specialties ON worker_profiles USING GIN (sub_specialties);

DROP TRIGGER IF EXISTS trg_worker_profiles_updated_at ON worker_profiles;
CREATE TRIGGER trg_worker_profiles_updated_at
  BEFORE UPDATE ON worker_profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE worker_profiles IS '医療従事者の自己管理プロフィール（auth.users と 1:1）';

-- ================================================================
-- 3. worker_credentials
--    医師免許・看護師免許・専門医資格などのアップロード情報
-- ================================================================
CREATE TABLE IF NOT EXISTS worker_credentials (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id            uuid NOT NULL REFERENCES worker_profiles(id) ON DELETE CASCADE,
  credential_type      varchar(100) NOT NULL,
  credential_name      varchar(255) NOT NULL,
  issuer               varchar(255),
  credential_number    varchar(100),
  issued_date          date,
  expiry_date          date,
  document_url         text,
  document_mime_type   varchar(100),
  status               credential_status NOT NULL DEFAULT 'pending',
  verified_by          uuid REFERENCES auth.users(id),
  verified_at          timestamptz,
  rejection_reason     text,
  created_at           timestamptz NOT NULL DEFAULT NOW(),
  updated_at           timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_worker_credentials_worker ON worker_credentials(worker_id);
CREATE INDEX IF NOT EXISTS idx_worker_credentials_status ON worker_credentials(status);
CREATE INDEX IF NOT EXISTS idx_worker_credentials_expiry ON worker_credentials(expiry_date) WHERE expiry_date IS NOT NULL;

DROP TRIGGER IF EXISTS trg_worker_credentials_updated_at ON worker_credentials;
CREATE TRIGGER trg_worker_credentials_updated_at
  BEFORE UPDATE ON worker_credentials
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE worker_credentials IS '医療従事者の資格・免許とその検証ステータス';

-- ================================================================
-- 4. worker_availability
--    空き時間・勤務可能枠（繰り返し or 特定日）
-- ================================================================
CREATE TABLE IF NOT EXISTS worker_availability (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  worker_id       uuid NOT NULL REFERENCES worker_profiles(id) ON DELETE CASCADE,
  is_recurring    boolean NOT NULL DEFAULT false,
  day_of_week     smallint CHECK (day_of_week IS NULL OR (day_of_week BETWEEN 0 AND 6)),
  specific_date   date,
  start_time      time NOT NULL,
  end_time        time NOT NULL,
  shift_type      shift_type NOT NULL DEFAULT 'regular_shift',
  is_blocked      boolean NOT NULL DEFAULT false,
  note            text,
  created_at      timestamptz NOT NULL DEFAULT NOW(),
  updated_at      timestamptz NOT NULL DEFAULT NOW(),
  CHECK (
    (is_recurring = true  AND day_of_week IS NOT NULL AND specific_date IS NULL) OR
    (is_recurring = false AND specific_date IS NOT NULL)
  ),
  CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS idx_worker_availability_worker  ON worker_availability(worker_id);
CREATE INDEX IF NOT EXISTS idx_worker_availability_date    ON worker_availability(specific_date) WHERE specific_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_worker_availability_dow     ON worker_availability(day_of_week)   WHERE is_recurring = true;

DROP TRIGGER IF EXISTS trg_worker_availability_updated_at ON worker_availability;
CREATE TRIGGER trg_worker_availability_updated_at
  BEFORE UPDATE ON worker_availability
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE worker_availability IS '医療従事者の勤務可能枠（曜日繰り返し or 特定日）';

-- ================================================================
-- 5. staffing_requests
--    施設からの正式な人材要請（コントロール型ワークフローの中心）
--    既存の staffing_cases（CRMビュー）とは別の操作単位
-- ================================================================
CREATE TABLE IF NOT EXISTS staffing_requests (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_number           varchar(30) NOT NULL UNIQUE,
  organization_id          uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
  facility_id              uuid REFERENCES facilities(id) ON DELETE SET NULL,
  case_id                  uuid REFERENCES staffing_cases(id) ON DELETE SET NULL,
  created_by_user_id       uuid REFERENCES auth.users(id),

  -- 要件本文
  title                    varchar(255) NOT NULL,
  description              text,
  profession_type          profession_type NOT NULL,
  specialty                varchar(255),
  headcount                integer NOT NULL DEFAULT 1 CHECK (headcount > 0),
  shift_type               shift_type NOT NULL DEFAULT 'regular_shift',

  -- スケジュール
  start_at                 timestamptz,
  end_at                   timestamptz,

  -- 報酬
  hourly_rate_min          integer CHECK (hourly_rate_min IS NULL OR hourly_rate_min >= 0),
  hourly_rate_max          integer CHECK (hourly_rate_max IS NULL OR hourly_rate_max >= 0),
  total_budget             integer CHECK (total_budget IS NULL OR total_budget >= 0),

  -- 必須・歓迎要件
  required_licenses        text[] NOT NULL DEFAULT ARRAY[]::text[],
  required_skills          text[] NOT NULL DEFAULT ARRAY[]::text[],
  preferred_skills         text[] NOT NULL DEFAULT ARRAY[]::text[],

  -- 状態
  status                   request_status NOT NULL DEFAULT 'draft',
  priority                 priority_level NOT NULL DEFAULT 'medium',

  -- Necoによるレビュー
  reviewed_by              uuid REFERENCES auth.users(id),
  reviewed_at              timestamptz,
  review_note              text,
  rejection_reason         text,

  -- キャンセル
  cancelled_reason         text,
  cancelled_at             timestamptz,
  cancelled_by             uuid REFERENCES auth.users(id),

  -- 監査用タイムスタンプ
  submitted_at             timestamptz,
  accepted_at              timestamptz,
  fulfilled_at             timestamptz,

  created_at               timestamptz NOT NULL DEFAULT NOW(),
  updated_at               timestamptz NOT NULL DEFAULT NOW(),

  CHECK (end_at IS NULL OR start_at IS NULL OR end_at > start_at),
  CHECK (
    hourly_rate_min IS NULL OR hourly_rate_max IS NULL OR
    hourly_rate_min <= hourly_rate_max
  )
);

CREATE INDEX IF NOT EXISTS idx_staffing_requests_org       ON staffing_requests(organization_id, status);
CREATE INDEX IF NOT EXISTS idx_staffing_requests_status    ON staffing_requests(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_staffing_requests_start     ON staffing_requests(start_at);
CREATE INDEX IF NOT EXISTS idx_staffing_requests_profession ON staffing_requests(profession_type, status);
CREATE INDEX IF NOT EXISTS idx_staffing_requests_licenses_gin ON staffing_requests USING GIN (required_licenses);

DROP TRIGGER IF EXISTS trg_staffing_requests_updated_at ON staffing_requests;
CREATE TRIGGER trg_staffing_requests_updated_at
  BEFORE UPDATE ON staffing_requests
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE staffing_requests IS '施設からの正式な人材要請（状態機械の中心エンティティ）';

-- ================================================================
-- 6. proposals
--    Neco が施設に対して候補ワーカーを提案
-- ================================================================
CREATE TABLE IF NOT EXISTS proposals (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  proposal_number             varchar(30) NOT NULL UNIQUE,
  request_id                  uuid NOT NULL REFERENCES staffing_requests(id) ON DELETE CASCADE,
  worker_id                   uuid NOT NULL REFERENCES worker_profiles(id) ON DELETE RESTRICT,
  proposed_by                 uuid REFERENCES auth.users(id),

  -- この提案固有の条件（依頼の範囲内で個別交渉した値）
  proposed_hourly_rate        integer CHECK (proposed_hourly_rate IS NULL OR proposed_hourly_rate >= 0),
  proposed_total_compensation integer CHECK (proposed_total_compensation IS NULL OR proposed_total_compensation >= 0),
  proposed_start_at           timestamptz,
  proposed_end_at             timestamptz,

  -- ワーカー側の応答
  worker_responded_at         timestamptz,
  worker_response_note        text,

  -- 施設側の応答
  facility_responded_at       timestamptz,
  facility_responded_by       uuid REFERENCES auth.users(id),
  facility_response_note      text,

  -- マッチング根拠
  match_score                 numeric(5,2) CHECK (match_score IS NULL OR (match_score >= 0 AND match_score <= 100)),
  match_reason                text,

  -- 状態
  status                      proposal_status NOT NULL DEFAULT 'created',
  expires_at                  timestamptz,

  created_at                  timestamptz NOT NULL DEFAULT NOW(),
  updated_at                  timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (request_id, worker_id)
);

CREATE INDEX IF NOT EXISTS idx_proposals_request    ON proposals(request_id, status);
CREATE INDEX IF NOT EXISTS idx_proposals_worker     ON proposals(worker_id, status);
CREATE INDEX IF NOT EXISTS idx_proposals_status     ON proposals(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_proposals_expires    ON proposals(expires_at) WHERE expires_at IS NOT NULL;

DROP TRIGGER IF EXISTS trg_proposals_updated_at ON proposals;
CREATE TRIGGER trg_proposals_updated_at
  BEFORE UPDATE ON proposals
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE proposals IS 'Neco が施設に対して提案する個別の候補ワーカー';

-- ================================================================
-- 7. assignments
--    確定したアサイン（proposal が承認されると 1:1 で生成）
-- ================================================================
CREATE TABLE IF NOT EXISTS assignments (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_number          varchar(30) NOT NULL UNIQUE,
  proposal_id                uuid NOT NULL UNIQUE REFERENCES proposals(id) ON DELETE RESTRICT,
  request_id                 uuid NOT NULL REFERENCES staffing_requests(id) ON DELETE RESTRICT,
  worker_id                  uuid NOT NULL REFERENCES worker_profiles(id) ON DELETE RESTRICT,
  organization_id            uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,

  -- 確定した条件（proposal から固定化）
  scheduled_start_at         timestamptz NOT NULL,
  scheduled_end_at           timestamptz NOT NULL,
  hourly_rate                integer NOT NULL CHECK (hourly_rate >= 0),
  total_compensation         integer CHECK (total_compensation IS NULL OR total_compensation >= 0),

  -- 状態
  status                     assignment_status NOT NULL DEFAULT 'confirmed',

  -- check-in / check-out
  checked_in_at              timestamptz,
  checked_out_at             timestamptz,
  check_in_lat               numeric(9,6),
  check_in_lng               numeric(9,6),
  check_out_lat              numeric(9,6),
  check_out_lng              numeric(9,6),

  -- 完了報告（ワーカー側 → 施設側）
  worker_completion_note     text,
  worker_reported_at         timestamptz,
  facility_confirmed_at      timestamptz,
  facility_confirmed_by      uuid REFERENCES auth.users(id),
  facility_completion_note   text,

  -- 紛争処理
  dispute_reason             text,
  dispute_opened_at          timestamptz,
  dispute_resolved_at        timestamptz,
  dispute_resolved_by        uuid REFERENCES auth.users(id),

  -- キャンセル
  cancelled_reason           text,
  cancelled_at               timestamptz,
  cancelled_by               uuid REFERENCES auth.users(id),

  created_at                 timestamptz NOT NULL DEFAULT NOW(),
  updated_at                 timestamptz NOT NULL DEFAULT NOW(),

  CHECK (scheduled_end_at > scheduled_start_at),
  CHECK (checked_out_at IS NULL OR checked_in_at IS NULL OR checked_out_at >= checked_in_at)
);

CREATE INDEX IF NOT EXISTS idx_assignments_worker        ON assignments(worker_id, status, scheduled_start_at DESC);
CREATE INDEX IF NOT EXISTS idx_assignments_org           ON assignments(organization_id, status, scheduled_start_at DESC);
CREATE INDEX IF NOT EXISTS idx_assignments_request       ON assignments(request_id);
CREATE INDEX IF NOT EXISTS idx_assignments_status        ON assignments(status);
CREATE INDEX IF NOT EXISTS idx_assignments_scheduled     ON assignments(scheduled_start_at);

DROP TRIGGER IF EXISTS trg_assignments_updated_at ON assignments;
CREATE TRIGGER trg_assignments_updated_at
  BEFORE UPDATE ON assignments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE assignments IS '確定したアサイン（proposal の承認で 1:1 生成）';

-- ================================================================
-- 8. work_logs
--    アサイン中の細粒度ログ（チェックイン/アウト/休憩/メモ/インシデント）
-- ================================================================
CREATE TABLE IF NOT EXISTS work_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id   uuid NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
  log_type        work_log_type NOT NULL,
  occurred_at     timestamptz NOT NULL DEFAULT NOW(),
  recorded_by     uuid REFERENCES auth.users(id),
  detail          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_work_logs_assignment ON work_logs(assignment_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_work_logs_type       ON work_logs(log_type, occurred_at DESC);

COMMENT ON TABLE work_logs IS 'アサイン進行中の細粒度ログ（タイムスタンプ・休憩・インシデント）';

-- ================================================================
-- 9. invoices
--    請求書ヘッダー（組織単位・期間単位）
-- ================================================================
CREATE TABLE IF NOT EXISTS invoices (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number      varchar(30) NOT NULL UNIQUE,
  organization_id     uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
  period_start        date NOT NULL,
  period_end          date NOT NULL,
  subtotal            integer NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  tax                 integer NOT NULL DEFAULT 0 CHECK (tax >= 0),
  total               integer NOT NULL DEFAULT 0 CHECK (total >= 0),
  currency            varchar(3) NOT NULL DEFAULT 'JPY',
  issue_date          date,
  due_date            date,
  paid_date           date,
  status              invoice_status NOT NULL DEFAULT 'draft',
  pdf_url             text,
  note                text,
  issued_by           uuid REFERENCES auth.users(id),
  created_at          timestamptz NOT NULL DEFAULT NOW(),
  updated_at          timestamptz NOT NULL DEFAULT NOW(),
  CHECK (period_end >= period_start),
  CHECK (due_date IS NULL OR issue_date IS NULL OR due_date >= issue_date)
);

CREATE INDEX IF NOT EXISTS idx_invoices_org    ON invoices(organization_id, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status, due_date);

DROP TRIGGER IF EXISTS trg_invoices_updated_at ON invoices;
CREATE TRIGGER trg_invoices_updated_at
  BEFORE UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE invoices IS '組織単位の請求書ヘッダー';

-- ================================================================
-- 10. invoice_line_items
--     請求書明細（アサイン単位）
-- ================================================================
CREATE TABLE IF NOT EXISTS invoice_line_items (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id      uuid NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  assignment_id   uuid REFERENCES assignments(id) ON DELETE SET NULL,
  description     text NOT NULL,
  hours           numeric(8,2) CHECK (hours IS NULL OR hours >= 0),
  hourly_rate     integer CHECK (hourly_rate IS NULL OR hourly_rate >= 0),
  amount          integer NOT NULL CHECK (amount >= 0),
  sort_order      integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invoice_lines_invoice    ON invoice_line_items(invoice_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_invoice_lines_assignment ON invoice_line_items(assignment_id);

COMMENT ON TABLE invoice_line_items IS '請求書明細（アサイン単位の課金行）';

-- ================================================================
-- 11. activity_log
--    システム全体の監査ログ（誰が何をいつ）
-- ================================================================
CREATE TABLE IF NOT EXISTS activity_log (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_role       user_role,
  action           varchar(100) NOT NULL,
  entity_type      varchar(50) NOT NULL,
  entity_id        uuid,
  organization_id  uuid REFERENCES organizations(id) ON DELETE SET NULL,
  before_state     jsonb,
  after_state      jsonb,
  ip_address       varchar(50),
  user_agent       text,
  occurred_at      timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activity_log_entity ON activity_log(entity_type, entity_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_log_actor  ON activity_log(actor_user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_log_org    ON activity_log(organization_id, occurred_at DESC) WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_activity_log_action ON activity_log(action, occurred_at DESC);

COMMENT ON TABLE activity_log IS '全テーブル横断の監査ログ（操作者・対象・前後状態）';

-- ================================================================
-- ここまでがコアテーブル定義
-- 状態遷移バリデーションと RLS は次のマイグレーションで追加します
-- ================================================================

-- ════════════════════════════════════════════════════════════
-- 0005_phase1_state_machine.sql
-- ════════════════════════════════════════════════════════════
-- ================================================================
-- 0005_phase1_state_machine.sql
-- Phase 1: 状態遷移バリデーション
--
-- 0004 で定義した4つのエンティティの状態遷移を検証する。
-- 不正な遷移は EXCEPTION で拒否し、正常な遷移ではタイムスタンプを自動更新。
--
-- 対象:
--   staffing_requests   (request_status)
--   proposals           (proposal_status)
--   assignments         (assignment_status)
--   invoices            (invoice_status)
--
-- 注意:
--   - INSERT は初期状態を強制しない（draft / created / confirmed / draft）
--   - 直接 UPDATE での status 変更時のみバリデーションを実行
--   - 不正遷移時は SQLSTATE '22023'（invalid_parameter_value）相当
-- ================================================================

-- ================================================================
-- 1. staffing_requests の状態遷移
-- ================================================================
CREATE OR REPLACE FUNCTION validate_request_transition()
RETURNS TRIGGER AS $$
BEGIN
  -- ステータス未変更ならスキップ
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- キャンセルは進行中の状態からならいつでも可
  IF NEW.status = 'cancelled' AND OLD.status NOT IN ('paid', 'cancelled') THEN
    -- cancelled_at と cancelled_by は呼び出し側で設定
    IF NEW.cancelled_at IS NULL THEN
      NEW.cancelled_at := NOW();
    END IF;
    RETURN NEW;
  END IF;

  -- 通常の有効遷移
  IF NOT (
    (OLD.status = 'draft'              AND NEW.status = 'submitted') OR
    (OLD.status = 'submitted'          AND NEW.status = 'under_review') OR
    (OLD.status = 'under_review'       AND NEW.status IN ('accepted', 'rejected')) OR
    (OLD.status = 'accepted'           AND NEW.status = 'proposing') OR
    (OLD.status = 'proposing'          AND NEW.status IN ('partially_assigned', 'fully_assigned')) OR
    (OLD.status = 'partially_assigned' AND NEW.status IN ('fully_assigned', 'in_progress')) OR
    (OLD.status = 'fully_assigned'     AND NEW.status = 'in_progress') OR
    (OLD.status = 'in_progress'        AND NEW.status = 'completion_pending') OR
    (OLD.status = 'completion_pending' AND NEW.status IN ('confirmed', 'in_progress')) OR
    (OLD.status = 'confirmed'          AND NEW.status = 'invoiced') OR
    (OLD.status = 'invoiced'           AND NEW.status = 'paid')
  ) THEN
    RAISE EXCEPTION 'Invalid staffing_requests transition: % -> %',
      OLD.status, NEW.status
      USING ERRCODE = '22023';
  END IF;

  -- 状態に応じたタイムスタンプ自動更新
  IF NEW.status = 'submitted' AND NEW.submitted_at IS NULL THEN
    NEW.submitted_at := NOW();
  END IF;
  IF NEW.status = 'under_review' AND NEW.reviewed_at IS NULL THEN
    NEW.reviewed_at := NOW();
  END IF;
  IF NEW.status = 'accepted' AND NEW.accepted_at IS NULL THEN
    NEW.accepted_at := NOW();
  END IF;
  IF NEW.status IN ('fully_assigned', 'in_progress') AND NEW.fulfilled_at IS NULL THEN
    NEW.fulfilled_at := NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_request_transition ON staffing_requests;
CREATE TRIGGER trg_validate_request_transition
  BEFORE UPDATE OF status ON staffing_requests
  FOR EACH ROW EXECUTE FUNCTION validate_request_transition();

COMMENT ON FUNCTION validate_request_transition()
  IS 'staffing_requests.status の遷移を検証し不正な変更を拒否する';

-- ================================================================
-- 2. proposals の状態遷移
-- ================================================================
CREATE OR REPLACE FUNCTION validate_proposal_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- 終了状態（facility_accepted/declined, worker_declined, withdrawn, expired）からの変更は不可
  IF OLD.status IN (
    'worker_declined', 'facility_accepted', 'facility_declined',
    'withdrawn', 'expired'
  ) THEN
    RAISE EXCEPTION 'proposals is in terminal state: %', OLD.status
      USING ERRCODE = '22023';
  END IF;

  -- withdrawn / expired はどの非終了状態からでも可能
  IF NEW.status IN ('withdrawn', 'expired') THEN
    RETURN NEW;
  END IF;

  IF NOT (
    (OLD.status = 'created'              AND NEW.status = 'worker_contacted') OR
    (OLD.status = 'worker_contacted'     AND NEW.status IN ('worker_accepted', 'worker_declined')) OR
    (OLD.status = 'worker_accepted'      AND NEW.status = 'proposed_to_facility') OR
    (OLD.status = 'proposed_to_facility' AND NEW.status IN ('facility_accepted', 'facility_declined'))
  ) THEN
    RAISE EXCEPTION 'Invalid proposals transition: % -> %',
      OLD.status, NEW.status
      USING ERRCODE = '22023';
  END IF;

  -- ワーカー応答時刻の自動更新
  IF NEW.status IN ('worker_accepted', 'worker_declined')
     AND NEW.worker_responded_at IS NULL THEN
    NEW.worker_responded_at := NOW();
  END IF;
  -- 施設応答時刻の自動更新
  IF NEW.status IN ('facility_accepted', 'facility_declined')
     AND NEW.facility_responded_at IS NULL THEN
    NEW.facility_responded_at := NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_proposal_transition ON proposals;
CREATE TRIGGER trg_validate_proposal_transition
  BEFORE UPDATE OF status ON proposals
  FOR EACH ROW EXECUTE FUNCTION validate_proposal_transition();

COMMENT ON FUNCTION validate_proposal_transition()
  IS 'proposals.status の遷移を検証し不正な変更を拒否する';

-- ================================================================
-- 3. assignments の状態遷移
-- ================================================================
CREATE OR REPLACE FUNCTION validate_assignment_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- 終了状態
  IF OLD.status IN ('completion_confirmed', 'cancelled', 'no_show') THEN
    RAISE EXCEPTION 'assignments is in terminal state: %', OLD.status
      USING ERRCODE = '22023';
  END IF;

  -- cancelled は disputed と confirmed からのみ
  IF NEW.status = 'cancelled' THEN
    IF OLD.status NOT IN ('confirmed', 'disputed', 'checked_in') THEN
      RAISE EXCEPTION 'cannot cancel assignment in state %', OLD.status
        USING ERRCODE = '22023';
    END IF;
    IF NEW.cancelled_at IS NULL THEN
      NEW.cancelled_at := NOW();
    END IF;
    RETURN NEW;
  END IF;

  -- no_show は confirmed からのみ
  IF NEW.status = 'no_show' THEN
    IF OLD.status <> 'confirmed' THEN
      RAISE EXCEPTION 'no_show only valid from confirmed, was %', OLD.status
        USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
  END IF;

  IF NOT (
    (OLD.status = 'confirmed'            AND NEW.status = 'checked_in') OR
    (OLD.status = 'checked_in'           AND NEW.status IN ('checked_out', 'disputed')) OR
    (OLD.status = 'checked_out'          AND NEW.status IN ('completion_reported', 'disputed')) OR
    (OLD.status = 'completion_reported'  AND NEW.status IN ('completion_confirmed', 'disputed')) OR
    (OLD.status = 'disputed'             AND NEW.status = 'completion_confirmed')
  ) THEN
    RAISE EXCEPTION 'Invalid assignments transition: % -> %',
      OLD.status, NEW.status
      USING ERRCODE = '22023';
  END IF;

  -- check-in/out のタイムスタンプ自動補完
  IF NEW.status = 'checked_in' AND NEW.checked_in_at IS NULL THEN
    NEW.checked_in_at := NOW();
  END IF;
  IF NEW.status = 'checked_out' AND NEW.checked_out_at IS NULL THEN
    NEW.checked_out_at := NOW();
  END IF;
  IF NEW.status = 'completion_reported' AND NEW.worker_reported_at IS NULL THEN
    NEW.worker_reported_at := NOW();
  END IF;
  IF NEW.status = 'completion_confirmed' AND NEW.facility_confirmed_at IS NULL THEN
    NEW.facility_confirmed_at := NOW();
  END IF;
  IF NEW.status = 'disputed' AND NEW.dispute_opened_at IS NULL THEN
    NEW.dispute_opened_at := NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_assignment_transition ON assignments;
CREATE TRIGGER trg_validate_assignment_transition
  BEFORE UPDATE OF status ON assignments
  FOR EACH ROW EXECUTE FUNCTION validate_assignment_transition();

COMMENT ON FUNCTION validate_assignment_transition()
  IS 'assignments.status の遷移を検証し不正な変更を拒否する';

-- ================================================================
-- 4. invoices の状態遷移
-- ================================================================
CREATE OR REPLACE FUNCTION validate_invoice_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- 終了状態
  IF OLD.status IN ('paid', 'void') THEN
    RAISE EXCEPTION 'invoices is in terminal state: %', OLD.status
      USING ERRCODE = '22023';
  END IF;

  IF NOT (
    (OLD.status = 'draft'    AND NEW.status IN ('issued', 'void')) OR
    (OLD.status = 'issued'   AND NEW.status IN ('paid', 'overdue', 'void')) OR
    (OLD.status = 'overdue'  AND NEW.status IN ('paid', 'void'))
  ) THEN
    RAISE EXCEPTION 'Invalid invoices transition: % -> %',
      OLD.status, NEW.status
      USING ERRCODE = '22023';
  END IF;

  -- 発行・支払日の自動補完
  IF NEW.status = 'issued' AND NEW.issue_date IS NULL THEN
    NEW.issue_date := CURRENT_DATE;
  END IF;
  IF NEW.status = 'paid' AND NEW.paid_date IS NULL THEN
    NEW.paid_date := CURRENT_DATE;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_invoice_transition ON invoices;
CREATE TRIGGER trg_validate_invoice_transition
  BEFORE UPDATE OF status ON invoices
  FOR EACH ROW EXECUTE FUNCTION validate_invoice_transition();

COMMENT ON FUNCTION validate_invoice_transition()
  IS 'invoices.status の遷移を検証し不正な変更を拒否する';

-- ================================================================
-- 5. 補助関数：終端状態判定
-- ================================================================
CREATE OR REPLACE FUNCTION is_request_terminal(s request_status)
RETURNS boolean AS $$
  SELECT s IN ('paid', 'cancelled', 'rejected');
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION is_proposal_terminal(s proposal_status)
RETURNS boolean AS $$
  SELECT s IN ('worker_declined', 'facility_accepted', 'facility_declined',
               'withdrawn', 'expired');
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION is_assignment_terminal(s assignment_status)
RETURNS boolean AS $$
  SELECT s IN ('completion_confirmed', 'cancelled', 'no_show');
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION is_invoice_terminal(s invoice_status)
RETURNS boolean AS $$
  SELECT s IN ('paid', 'void');
$$ LANGUAGE SQL IMMUTABLE;

COMMENT ON FUNCTION is_request_terminal(request_status)    IS '依頼が終端状態かを判定';
COMMENT ON FUNCTION is_proposal_terminal(proposal_status)  IS '提案が終端状態かを判定';
COMMENT ON FUNCTION is_assignment_terminal(assignment_status) IS 'アサインが終端状態かを判定';
COMMENT ON FUNCTION is_invoice_terminal(invoice_status)    IS '請求書が終端状態かを判定';

-- ════════════════════════════════════════════════════════════
-- 0006_phase1_rls_policies.sql
-- ════════════════════════════════════════════════════════════
-- ================================================================
-- 0006_phase1_rls_policies.sql
-- Phase 1: 4ロール対応の Row Level Security ポリシー
--
-- 前提: 0004（コアテーブル）と 0005（状態遷移）が適用済み
--
-- ロール別の見え方の方針:
--   facility_admin   : 自組織のデータのみ。worker情報はアサイン経由のみ
--   worker           : 自分のプロフィール・空き枠・自分宛の提案・自分のアサイン
--   neco_admin       : 全データの読み書き（運用オペレーター）
--   alliance_admin   : 全データの読み取りのみ（経営・分析）
--
-- 注意:
--   - 既存の organization_members を facility_admin の組織紐付けに利用
--   - ヘルパー関数は SECURITY DEFINER + STABLE で再帰回避と性能確保
--   - 認証なしの匿名アクセスは全テーブルで完全拒否
-- ================================================================

-- ================================================================
-- ヘルパー関数
-- ================================================================

-- 現在のユーザーのロールを返す（ログインなしの場合は NULL）
CREATE OR REPLACE FUNCTION current_user_role()
RETURNS user_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role
  FROM user_roles
  WHERE user_id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;
COMMENT ON FUNCTION current_user_role() IS '現在のSupabaseユーザーのロールを返す';

-- neco_admin かどうか
CREATE OR REPLACE FUNCTION is_neco_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid()
      AND role = 'neco_admin'
      AND is_active = true
  );
$$;

-- alliance_admin かどうか
CREATE OR REPLACE FUNCTION is_alliance_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid()
      AND role = 'alliance_admin'
      AND is_active = true
  );
$$;

-- 指定組織の facility_admin かどうか
CREATE OR REPLACE FUNCTION is_facility_admin_of(p_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM organization_members om
    JOIN user_roles ur ON ur.user_id = om.user_id
    WHERE om.user_id = auth.uid()
      AND om.organization_id = p_org_id
      AND om.is_active = true
      AND ur.role = 'facility_admin'
      AND ur.is_active = true
  );
$$;

-- worker かどうか
CREATE OR REPLACE FUNCTION is_worker()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid()
      AND role = 'worker'
      AND is_active = true
  );
$$;

-- 現在ユーザーの worker_profiles.id を返す（worker でない場合は NULL）
CREATE OR REPLACE FUNCTION current_worker_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id
  FROM worker_profiles
  WHERE user_id = auth.uid()
  LIMIT 1;
$$;

-- ================================================================
-- 1. user_roles
-- ================================================================
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_roles_self_read" ON user_roles;
CREATE POLICY "user_roles_self_read"
  ON user_roles FOR SELECT
  USING (user_id = auth.uid() OR is_neco_admin() OR is_alliance_admin());

DROP POLICY IF EXISTS "user_roles_neco_write" ON user_roles;
CREATE POLICY "user_roles_neco_write"
  ON user_roles FOR ALL
  USING (is_neco_admin())
  WITH CHECK (is_neco_admin());

-- ================================================================
-- 2. worker_profiles
-- ================================================================
ALTER TABLE worker_profiles ENABLE ROW LEVEL SECURITY;

-- 本人 / neco / alliance / アサイン関連の facility_admin が閲覧可
DROP POLICY IF EXISTS "worker_profiles_select" ON worker_profiles;
CREATE POLICY "worker_profiles_select"
  ON worker_profiles FOR SELECT
  USING (
    user_id = auth.uid()
    OR is_neco_admin()
    OR is_alliance_admin()
    OR EXISTS (
      SELECT 1 FROM assignments a
      WHERE a.worker_id = worker_profiles.id
        AND is_facility_admin_of(a.organization_id)
    )
  );

-- 本人のみ自身のプロフィール作成可
DROP POLICY IF EXISTS "worker_profiles_self_insert" ON worker_profiles;
CREATE POLICY "worker_profiles_self_insert"
  ON worker_profiles FOR INSERT
  WITH CHECK (user_id = auth.uid() OR is_neco_admin());

-- 本人 / neco_admin が更新可（onboarding の承認は neco のみ想定）
DROP POLICY IF EXISTS "worker_profiles_update" ON worker_profiles;
CREATE POLICY "worker_profiles_update"
  ON worker_profiles FOR UPDATE
  USING (user_id = auth.uid() OR is_neco_admin())
  WITH CHECK (user_id = auth.uid() OR is_neco_admin());

-- ================================================================
-- 3. worker_credentials
-- ================================================================
ALTER TABLE worker_credentials ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "worker_credentials_select" ON worker_credentials;
CREATE POLICY "worker_credentials_select"
  ON worker_credentials FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM worker_profiles wp
      WHERE wp.id = worker_credentials.worker_id
        AND wp.user_id = auth.uid()
    )
    OR is_neco_admin()
    OR is_alliance_admin()
    OR EXISTS (
      SELECT 1
      FROM assignments a
      WHERE a.worker_id = worker_credentials.worker_id
        AND is_facility_admin_of(a.organization_id)
    )
  );

DROP POLICY IF EXISTS "worker_credentials_self_insert" ON worker_credentials;
CREATE POLICY "worker_credentials_self_insert"
  ON worker_credentials FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM worker_profiles wp
      WHERE wp.id = worker_credentials.worker_id
        AND wp.user_id = auth.uid()
    )
    OR is_neco_admin()
  );

-- 本人は内容更新可（ただし verified_by/verified_at/status='verified' への変更は neco のみ）
-- DBレベルでは緩く許可し、API層で検証することを想定
DROP POLICY IF EXISTS "worker_credentials_update" ON worker_credentials;
CREATE POLICY "worker_credentials_update"
  ON worker_credentials FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM worker_profiles wp
      WHERE wp.id = worker_credentials.worker_id
        AND wp.user_id = auth.uid()
    )
    OR is_neco_admin()
  );

-- ================================================================
-- 4. worker_availability
-- ================================================================
ALTER TABLE worker_availability ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "worker_availability_select" ON worker_availability;
CREATE POLICY "worker_availability_select"
  ON worker_availability FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM worker_profiles wp
      WHERE wp.id = worker_availability.worker_id
        AND wp.user_id = auth.uid()
    )
    OR is_neco_admin()
    OR is_alliance_admin()
  );

DROP POLICY IF EXISTS "worker_availability_self_write" ON worker_availability;
CREATE POLICY "worker_availability_self_write"
  ON worker_availability FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM worker_profiles wp
      WHERE wp.id = worker_availability.worker_id
        AND wp.user_id = auth.uid()
    )
    OR is_neco_admin()
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM worker_profiles wp
      WHERE wp.id = worker_availability.worker_id
        AND wp.user_id = auth.uid()
    )
    OR is_neco_admin()
  );

-- ================================================================
-- 5. staffing_requests
-- ================================================================
ALTER TABLE staffing_requests ENABLE ROW LEVEL SECURITY;

-- 自組織 / neco / alliance が閲覧可
DROP POLICY IF EXISTS "staffing_requests_select" ON staffing_requests;
CREATE POLICY "staffing_requests_select"
  ON staffing_requests FOR SELECT
  USING (
    is_facility_admin_of(organization_id)
    OR is_neco_admin()
    OR is_alliance_admin()
  );

-- facility_admin（自組織）または neco_admin が作成可
DROP POLICY IF EXISTS "staffing_requests_insert" ON staffing_requests;
CREATE POLICY "staffing_requests_insert"
  ON staffing_requests FOR INSERT
  WITH CHECK (
    is_facility_admin_of(organization_id)
    OR is_neco_admin()
  );

-- 同上で更新可（state machine 制約は別途トリガーで）
DROP POLICY IF EXISTS "staffing_requests_update" ON staffing_requests;
CREATE POLICY "staffing_requests_update"
  ON staffing_requests FOR UPDATE
  USING (
    is_facility_admin_of(organization_id)
    OR is_neco_admin()
  )
  WITH CHECK (
    is_facility_admin_of(organization_id)
    OR is_neco_admin()
  );

-- 削除は neco_admin のみ
DROP POLICY IF EXISTS "staffing_requests_delete" ON staffing_requests;
CREATE POLICY "staffing_requests_delete"
  ON staffing_requests FOR DELETE
  USING (is_neco_admin());

-- ================================================================
-- 6. proposals
-- ================================================================
ALTER TABLE proposals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "proposals_select" ON proposals;
CREATE POLICY "proposals_select"
  ON proposals FOR SELECT
  USING (
    is_neco_admin()
    OR is_alliance_admin()
    OR worker_id = current_worker_id()
    OR EXISTS (
      SELECT 1 FROM staffing_requests sr
      WHERE sr.id = proposals.request_id
        AND is_facility_admin_of(sr.organization_id)
    )
  );

-- 提案作成は neco_admin のみ
DROP POLICY IF EXISTS "proposals_insert" ON proposals;
CREATE POLICY "proposals_insert"
  ON proposals FOR INSERT
  WITH CHECK (is_neco_admin());

-- 更新: neco_admin / 本人worker（自分宛の応答） / facility（自組織宛の応答）
DROP POLICY IF EXISTS "proposals_update" ON proposals;
CREATE POLICY "proposals_update"
  ON proposals FOR UPDATE
  USING (
    is_neco_admin()
    OR worker_id = current_worker_id()
    OR EXISTS (
      SELECT 1 FROM staffing_requests sr
      WHERE sr.id = proposals.request_id
        AND is_facility_admin_of(sr.organization_id)
    )
  );

DROP POLICY IF EXISTS "proposals_delete" ON proposals;
CREATE POLICY "proposals_delete"
  ON proposals FOR DELETE
  USING (is_neco_admin());

-- ================================================================
-- 7. assignments
-- ================================================================
ALTER TABLE assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "assignments_select" ON assignments;
CREATE POLICY "assignments_select"
  ON assignments FOR SELECT
  USING (
    is_neco_admin()
    OR is_alliance_admin()
    OR worker_id = current_worker_id()
    OR is_facility_admin_of(organization_id)
  );

-- 作成は neco_admin のみ（proposal 承認フローから生成）
DROP POLICY IF EXISTS "assignments_insert" ON assignments;
CREATE POLICY "assignments_insert"
  ON assignments FOR INSERT
  WITH CHECK (is_neco_admin());

-- 更新: neco / 本人worker（check-in/outなど） / facility（completion 確認）
DROP POLICY IF EXISTS "assignments_update" ON assignments;
CREATE POLICY "assignments_update"
  ON assignments FOR UPDATE
  USING (
    is_neco_admin()
    OR worker_id = current_worker_id()
    OR is_facility_admin_of(organization_id)
  );

DROP POLICY IF EXISTS "assignments_delete" ON assignments;
CREATE POLICY "assignments_delete"
  ON assignments FOR DELETE
  USING (is_neco_admin());

-- ================================================================
-- 8. work_logs
-- ================================================================
ALTER TABLE work_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "work_logs_select" ON work_logs;
CREATE POLICY "work_logs_select"
  ON work_logs FOR SELECT
  USING (
    is_neco_admin()
    OR is_alliance_admin()
    OR EXISTS (
      SELECT 1 FROM assignments a
      WHERE a.id = work_logs.assignment_id
        AND (a.worker_id = current_worker_id()
             OR is_facility_admin_of(a.organization_id))
    )
  );

-- 挿入: 自分のアサイン / facility / neco
DROP POLICY IF EXISTS "work_logs_insert" ON work_logs;
CREATE POLICY "work_logs_insert"
  ON work_logs FOR INSERT
  WITH CHECK (
    is_neco_admin()
    OR EXISTS (
      SELECT 1 FROM assignments a
      WHERE a.id = work_logs.assignment_id
        AND (a.worker_id = current_worker_id()
             OR is_facility_admin_of(a.organization_id))
    )
  );

-- 更新・削除は neco のみ（log は基本不変）
DROP POLICY IF EXISTS "work_logs_neco_modify" ON work_logs;
CREATE POLICY "work_logs_neco_modify"
  ON work_logs FOR UPDATE
  USING (is_neco_admin());

DROP POLICY IF EXISTS "work_logs_neco_delete" ON work_logs;
CREATE POLICY "work_logs_neco_delete"
  ON work_logs FOR DELETE
  USING (is_neco_admin());

-- ================================================================
-- 9. invoices
-- ================================================================
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "invoices_select" ON invoices;
CREATE POLICY "invoices_select"
  ON invoices FOR SELECT
  USING (
    is_neco_admin()
    OR is_alliance_admin()
    OR is_facility_admin_of(organization_id)
  );

DROP POLICY IF EXISTS "invoices_neco_write" ON invoices;
CREATE POLICY "invoices_neco_write"
  ON invoices FOR ALL
  USING (is_neco_admin())
  WITH CHECK (is_neco_admin());

-- ================================================================
-- 10. invoice_line_items
-- ================================================================
ALTER TABLE invoice_line_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "invoice_lines_select" ON invoice_line_items;
CREATE POLICY "invoice_lines_select"
  ON invoice_line_items FOR SELECT
  USING (
    is_neco_admin()
    OR is_alliance_admin()
    OR EXISTS (
      SELECT 1 FROM invoices inv
      WHERE inv.id = invoice_line_items.invoice_id
        AND is_facility_admin_of(inv.organization_id)
    )
  );

DROP POLICY IF EXISTS "invoice_lines_neco_write" ON invoice_line_items;
CREATE POLICY "invoice_lines_neco_write"
  ON invoice_line_items FOR ALL
  USING (is_neco_admin())
  WITH CHECK (is_neco_admin());

-- ================================================================
-- 11. activity_log
-- ================================================================
ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;

-- neco_admin / alliance_admin は全件、本人は自身のアクションのみ
DROP POLICY IF EXISTS "activity_log_select" ON activity_log;
CREATE POLICY "activity_log_select"
  ON activity_log FOR SELECT
  USING (
    is_neco_admin()
    OR is_alliance_admin()
    OR actor_user_id = auth.uid()
    OR (organization_id IS NOT NULL AND is_facility_admin_of(organization_id))
  );

-- 挿入は誰でも可（ただしactor_user_id強制で偽装防止）
DROP POLICY IF EXISTS "activity_log_insert" ON activity_log;
CREATE POLICY "activity_log_insert"
  ON activity_log FOR INSERT
  WITH CHECK (
    actor_user_id = auth.uid() OR is_neco_admin()
  );

-- 更新・削除は不可（監査ログは不変）
-- ※ ENABLE RLS の効果で、ポリシー無しのオペレーションは拒否される

-- ================================================================
-- ヘルパー関数の権限
-- authenticated（Supabase の認証済みロール）から呼び出せるようにする
-- ================================================================
GRANT EXECUTE ON FUNCTION current_user_role()         TO authenticated;
GRANT EXECUTE ON FUNCTION is_neco_admin()             TO authenticated;
GRANT EXECUTE ON FUNCTION is_alliance_admin()         TO authenticated;
GRANT EXECUTE ON FUNCTION is_facility_admin_of(uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION is_worker()                 TO authenticated;
GRANT EXECUTE ON FUNCTION current_worker_id()         TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 0007_phase1_views.sql
-- ════════════════════════════════════════════════════════════
-- ================================================================
-- 0007_phase1_views.sql
-- Phase 1: 集計ビュー（Regional Alliance Dashboard 用）
--
-- 前提: 0004（コアテーブル）, 0005（状態遷移）, 0006（RLS）が適用済み
--
-- 提供する分析指標:
--   - 未充足リクエスト数（職種別・組織別）
--   - 充足率（Fill Rate）
--   - 充足までの所要時間（Time to Fill）
--   - 職種・専門領域別の不足headcount
--   - 夜勤・on-call の穴
--   - ワーカー稼働率（Workforce Utilization）
--   - 請求サマリー
--
-- 注意:
--   - VIEW は SECURITY INVOKER（呼出者の権限で評価）= 元テーブルのRLSが適用される
--   - alliance_admin はRLSにより全データを集計可能
-- ================================================================

-- ================================================================
-- 1. v_request_pipeline
--    依頼の状態別パイプライン件数
-- ================================================================
CREATE OR REPLACE VIEW v_request_pipeline AS
SELECT
  organization_id,
  status,
  COUNT(*) AS request_count,
  SUM(headcount) AS total_headcount,
  COUNT(*) FILTER (WHERE priority IN ('urgent', 'critical')) AS urgent_count,
  MIN(start_at) FILTER (WHERE status NOT IN ('paid', 'cancelled', 'rejected')) AS earliest_open_start_at
FROM staffing_requests
GROUP BY organization_id, status;

COMMENT ON VIEW v_request_pipeline IS '組織×状態 別の依頼パイプライン件数とheadcount';

-- ================================================================
-- 2. v_unfilled_requests_summary
--    未充足リクエストのサマリー（組織別）
-- ================================================================
CREATE OR REPLACE VIEW v_unfilled_requests_summary AS
SELECT
  sr.organization_id,
  o.name AS organization_name,
  COUNT(*) AS unfilled_count,
  SUM(sr.headcount) AS total_unfilled_headcount,
  COUNT(*) FILTER (WHERE sr.priority = 'critical') AS critical_count,
  COUNT(*) FILTER (WHERE sr.priority = 'urgent')   AS urgent_count,
  COUNT(*) FILTER (WHERE sr.start_at < NOW() + INTERVAL '7 days') AS within_7d_count,
  COUNT(*) FILTER (WHERE sr.start_at < NOW())                    AS overdue_count,
  AVG(EXTRACT(EPOCH FROM (NOW() - sr.submitted_at))/86400) FILTER (WHERE sr.submitted_at IS NOT NULL)
    AS avg_days_open
FROM staffing_requests sr
JOIN organizations o ON o.id = sr.organization_id
WHERE sr.status NOT IN ('paid', 'cancelled', 'rejected', 'fully_assigned', 'in_progress',
                        'completion_pending', 'confirmed', 'invoiced')
GROUP BY sr.organization_id, o.name;

COMMENT ON VIEW v_unfilled_requests_summary IS '未充足の依頼サマリー（組織別の急ぎ件数・日数等）';

-- ================================================================
-- 3. v_fill_rate
--    充足率: 完了アサイン数 / 要求headcount合計
--    過去90日に submitted されたリクエストを対象
-- ================================================================
CREATE OR REPLACE VIEW v_fill_rate AS
WITH window_requests AS (
  SELECT
    sr.id,
    sr.organization_id,
    sr.headcount,
    sr.profession_type,
    sr.submitted_at
  FROM staffing_requests sr
  WHERE sr.submitted_at IS NOT NULL
    AND sr.submitted_at >= NOW() - INTERVAL '90 days'
),
filled AS (
  SELECT
    wr.id AS request_id,
    COUNT(a.id) FILTER (WHERE a.status = 'completion_confirmed') AS filled_headcount
  FROM window_requests wr
  LEFT JOIN assignments a ON a.request_id = wr.id
  GROUP BY wr.id
)
SELECT
  wr.organization_id,
  wr.profession_type,
  COUNT(wr.id)                                AS request_count,
  SUM(wr.headcount)                           AS demanded_headcount,
  COALESCE(SUM(f.filled_headcount), 0)        AS filled_headcount,
  CASE WHEN SUM(wr.headcount) > 0
       THEN ROUND(100.0 * COALESCE(SUM(f.filled_headcount), 0) / SUM(wr.headcount), 2)
       ELSE NULL
  END AS fill_rate_pct
FROM window_requests wr
LEFT JOIN filled f ON f.request_id = wr.id
GROUP BY wr.organization_id, wr.profession_type;

COMMENT ON VIEW v_fill_rate IS '過去90日の組織×職種別充足率';

-- ================================================================
-- 4. v_time_to_fill
--    充足までの所要時間（submitted → 最初の completion_confirmed）
-- ================================================================
CREATE OR REPLACE VIEW v_time_to_fill AS
SELECT
  sr.organization_id,
  sr.profession_type,
  sr.id AS request_id,
  sr.request_number,
  sr.submitted_at,
  MIN(a.facility_confirmed_at) FILTER (WHERE a.status = 'completion_confirmed')
    AS first_confirmed_at,
  EXTRACT(EPOCH FROM (
    MIN(a.facility_confirmed_at) FILTER (WHERE a.status = 'completion_confirmed')
    - sr.submitted_at
  )) / 86400 AS days_to_first_fill
FROM staffing_requests sr
LEFT JOIN assignments a ON a.request_id = sr.id
WHERE sr.submitted_at IS NOT NULL
GROUP BY sr.id, sr.organization_id, sr.profession_type, sr.request_number, sr.submitted_at;

COMMENT ON VIEW v_time_to_fill IS '依頼ごとの初回充足までの所要日数';

-- ================================================================
-- 5. v_shortage_by_specialty
--    職種×専門領域別の不足headcount
-- ================================================================
CREATE OR REPLACE VIEW v_shortage_by_specialty AS
SELECT
  profession_type,
  COALESCE(specialty, '(unspecified)') AS specialty,
  COUNT(*) AS open_request_count,
  SUM(headcount) AS open_headcount,
  COUNT(*) FILTER (WHERE priority IN ('urgent', 'critical')) AS urgent_count
FROM staffing_requests
WHERE status IN ('submitted', 'under_review', 'accepted', 'proposing', 'partially_assigned')
GROUP BY profession_type, specialty;

COMMENT ON VIEW v_shortage_by_specialty IS '職種×専門領域別の未充足headcount';

-- ================================================================
-- 6. v_night_duty_gaps
--    夜勤・on-callシフトの未充足
-- ================================================================
CREATE OR REPLACE VIEW v_night_duty_gaps AS
SELECT
  organization_id,
  profession_type,
  shift_type,
  COUNT(*) AS open_count,
  SUM(headcount) AS open_headcount,
  MIN(start_at) AS earliest_start_at
FROM staffing_requests
WHERE status IN ('submitted', 'under_review', 'accepted', 'proposing', 'partially_assigned')
  AND shift_type IN ('night_duty', 'on_call')
GROUP BY organization_id, profession_type, shift_type;

COMMENT ON VIEW v_night_duty_gaps IS '夜勤・on-callシフトの未充足分布';

-- ================================================================
-- 7. v_workforce_utilization
--    ワーカー単位の稼働率（過去30日）
-- ================================================================
CREATE OR REPLACE VIEW v_workforce_utilization AS
SELECT
  wp.id AS worker_id,
  wp.full_name,
  wp.profession_type,
  wp.primary_specialty,
  COUNT(a.id) AS assignment_count_30d,
  COUNT(a.id) FILTER (WHERE a.status = 'completion_confirmed') AS completed_count_30d,
  COUNT(a.id) FILTER (WHERE a.status IN ('cancelled', 'no_show'))  AS cancelled_count_30d,
  COALESCE(SUM(
    EXTRACT(EPOCH FROM (a.checked_out_at - a.checked_in_at)) / 3600
  ) FILTER (WHERE a.checked_out_at IS NOT NULL AND a.checked_in_at IS NOT NULL), 0) AS hours_worked_30d,
  MAX(a.scheduled_start_at) AS last_scheduled_at
FROM worker_profiles wp
LEFT JOIN assignments a
  ON a.worker_id = wp.id
 AND a.scheduled_start_at >= NOW() - INTERVAL '30 days'
GROUP BY wp.id;

COMMENT ON VIEW v_workforce_utilization IS '過去30日のワーカー稼働状況';

-- ================================================================
-- 8. v_invoice_summary
--    請求サマリー（組織×月）
-- ================================================================
CREATE OR REPLACE VIEW v_invoice_summary AS
SELECT
  organization_id,
  date_trunc('month', period_start)::date AS billing_month,
  status,
  COUNT(*) AS invoice_count,
  SUM(subtotal) AS total_subtotal,
  SUM(tax)      AS total_tax,
  SUM(total)    AS total_amount
FROM invoices
GROUP BY organization_id, billing_month, status;

COMMENT ON VIEW v_invoice_summary IS '組織×月×状態 別の請求サマリー';

-- ================================================================
-- 9. v_credential_attention
--    要対応の資格（pending検証 / 期限切れ間近 / 期限切れ）
-- ================================================================
CREATE OR REPLACE VIEW v_credential_attention AS
SELECT
  wc.id AS credential_id,
  wc.worker_id,
  wp.full_name,
  wp.profession_type,
  wc.credential_type,
  wc.credential_name,
  wc.status,
  wc.expiry_date,
  CASE
    WHEN wc.status = 'pending'                                      THEN 'pending_verification'
    WHEN wc.status = 'verified' AND wc.expiry_date < CURRENT_DATE   THEN 'expired'
    WHEN wc.status = 'verified' AND wc.expiry_date < CURRENT_DATE + INTERVAL '60 days' THEN 'expiring_soon'
    ELSE 'ok'
  END AS attention_type
FROM worker_credentials wc
JOIN worker_profiles wp ON wp.id = wc.worker_id
WHERE wc.status IN ('pending', 'verified');

COMMENT ON VIEW v_credential_attention IS '検証待ち・期限間近・期限切れの資格';

-- ================================================================
-- 10. v_alliance_dashboard
--     経営ダッシュボード用の総合KPI（1行）
-- ================================================================
CREATE OR REPLACE VIEW v_alliance_dashboard AS
SELECT
  -- 依頼系
  (SELECT COUNT(*) FROM staffing_requests
    WHERE status IN ('submitted','under_review','accepted','proposing','partially_assigned')) AS open_requests,
  (SELECT SUM(headcount) FROM staffing_requests
    WHERE status IN ('submitted','under_review','accepted','proposing','partially_assigned')) AS open_headcount,
  (SELECT COUNT(*) FROM staffing_requests
    WHERE priority IN ('urgent','critical')
      AND status IN ('submitted','under_review','accepted','proposing','partially_assigned')) AS urgent_open,
  -- アサイン系
  (SELECT COUNT(*) FROM assignments
    WHERE status IN ('confirmed','checked_in','checked_out','completion_reported')) AS active_assignments,
  (SELECT COUNT(*) FROM assignments
    WHERE status = 'disputed') AS open_disputes,
  -- 過去30日のスループット
  (SELECT COUNT(*) FROM assignments
    WHERE status = 'completion_confirmed'
      AND facility_confirmed_at >= NOW() - INTERVAL '30 days') AS completed_30d,
  (SELECT COUNT(*) FROM assignments
    WHERE status IN ('cancelled','no_show')
      AND updated_at >= NOW() - INTERVAL '30 days') AS lost_30d,
  -- ワーカー
  (SELECT COUNT(*) FROM worker_profiles
    WHERE onboarding_status = 'approved' AND is_available_for_offers = true) AS active_workers,
  (SELECT COUNT(*) FROM worker_profiles
    WHERE onboarding_status = 'submitted') AS pending_onboarding,
  -- 資格
  (SELECT COUNT(*) FROM worker_credentials
    WHERE status = 'pending') AS pending_credentials,
  (SELECT COUNT(*) FROM worker_credentials
    WHERE status = 'verified' AND expiry_date < CURRENT_DATE + INTERVAL '60 days') AS expiring_credentials,
  -- 請求
  (SELECT SUM(total) FROM invoices
    WHERE status = 'paid'
      AND paid_date >= date_trunc('month', CURRENT_DATE)) AS revenue_this_month,
  (SELECT SUM(total) FROM invoices
    WHERE status IN ('issued','overdue')) AS outstanding_amount,
  NOW() AS generated_at;

COMMENT ON VIEW v_alliance_dashboard IS 'Alliance Dashboard 用の総合KPI（1行）';

-- ================================================================
-- ヘッドリストのインデックス補強（集計性能）
-- ================================================================
CREATE INDEX IF NOT EXISTS idx_assignments_facility_confirmed
  ON assignments(facility_confirmed_at) WHERE status = 'completion_confirmed';
CREATE INDEX IF NOT EXISTS idx_invoices_paid_date
  ON invoices(paid_date) WHERE status = 'paid';
