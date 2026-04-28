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
