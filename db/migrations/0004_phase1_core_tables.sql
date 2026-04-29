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
