-- 病院管理者ユーザーテーブル
-- organizations テーブルと紐づく形で管理者アカウントを保持する

CREATE TABLE IF NOT EXISTS hospital_users (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          VARCHAR(50)  NOT NULL UNIQUE,          -- ログインID（HOSP-001 形式）
  organization_id UUID         REFERENCES organizations(id) ON DELETE SET NULL,
  name            VARCHAR(255) NOT NULL,                  -- 組織表示名
  pwd_hash        VARCHAR(64)  NOT NULL,                  -- HMAC-SHA256(password, SESSION_SECRET)
  role            VARCHAR(50)  NOT NULL DEFAULT 'hospital', -- 将来の権限拡張用
  is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
  last_login_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hospital_users_org_id ON hospital_users(org_id);
CREATE INDEX IF NOT EXISTS idx_hospital_users_organization ON hospital_users(organization_id);

DROP TRIGGER IF EXISTS trg_hospital_users_updated_at ON hospital_users;
CREATE TRIGGER trg_hospital_users_updated_at
  BEFORE UPDATE ON hospital_users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ログイン履歴テーブル（監査ログ）
CREATE TABLE IF NOT EXISTS hospital_login_logs (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id     VARCHAR(50) NOT NULL,
  success    BOOLEAN     NOT NULL,
  ip_address VARCHAR(50),
  user_agent TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_login_logs_org_time ON hospital_login_logs(org_id, occurred_at DESC);

COMMENT ON TABLE hospital_users      IS '病院管理者ログインアカウント';
COMMENT ON TABLE hospital_login_logs IS 'ログイン試行の監査ログ';
