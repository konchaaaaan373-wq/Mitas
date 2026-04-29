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
