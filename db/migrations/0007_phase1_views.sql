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
