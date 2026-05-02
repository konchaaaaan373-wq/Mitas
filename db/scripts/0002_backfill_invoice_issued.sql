-- ================================================================
-- 0002_backfill_invoice_issued.sql
-- 目的: 既に作成された invoice に対して activity_log の invoice.issued
--       行が無いものに、遡及で記録を追加する。
-- 背景: neco-console.html の請求書作成は PostgREST 直接 POST だったため、
--       activity_log への記録が漏れていた。client 側修正は完了済み
--       （commit 7e74a61）だが、修正前に作成された invoice の履歴を
--       遡及で埋めるためのスクリプト。
-- 安全策:
--   - INSERT 対象は「activity_log に対応する invoice エントリが無い
--     invoices 行のみ」を NOT EXISTS で限定。
--   - actor_user_id は invoices.issued_by を優先、無ければ neco_admin
--     ユーザー（demo-neco@*）を SELECT で解決。
--   - 解決できない場合は INSERT をスキップ（actor_user_id NULL を許容）。
--   - トランザクション内で実行（途中失敗で全行ロールバック）。
-- 使い方: Supabase SQL Editor に貼り付けて実行。
--         必要に応じて WHERE 句の期間を調整してください
--         （デフォルトは過去 30 日）。
-- ================================================================

-- ───────────────────────────────────────────────────────────────
-- A. 実行前確認：補完対象の件数
-- ───────────────────────────────────────────────────────────────

-- A-1. activity_log に invoice 行が無い invoice の件数
SELECT
  COUNT(*) AS missing_log_invoices
FROM invoices i
WHERE NOT EXISTS (
  SELECT 1 FROM activity_log al
  WHERE al.entity_type = 'invoice'
    AND al.entity_id   = i.id
)
  AND i.created_at >= NOW() - INTERVAL '30 days';

-- A-2. 対象 invoice の一覧（存在するなら）
SELECT i.id, i.invoice_number, i.organization_id, i.status, i.total, i.created_at
FROM invoices i
WHERE NOT EXISTS (
  SELECT 1 FROM activity_log al
  WHERE al.entity_type = 'invoice'
    AND al.entity_id   = i.id
)
  AND i.created_at >= NOW() - INTERVAL '30 days'
ORDER BY i.created_at DESC;

-- A-3. neco_admin ユーザーが解決できるか確認（actor_user_id のフォールバック）
SELECT u.id, u.email
FROM auth.users u
WHERE u.email LIKE 'konchaaaaan373+mitas-admin@%'
   OR u.email LIKE 'demo-neco@%'
LIMIT 5;


-- ───────────────────────────────────────────────────────────────
-- B. 実行：トランザクション内で INSERT
--    INSERT 対象は ① activity_log に対応行が無い invoice のみ
--                  ② 過去 30 日に作成されたもの（古い行は触らない）
--    actor_user_id は issued_by を優先し、フォールバックで neco_admin。
-- ───────────────────────────────────────────────────────────────

BEGIN;

INSERT INTO activity_log (
  actor_user_id,
  actor_role,
  action,
  entity_type,
  entity_id,
  organization_id,
  after_state,
  occurred_at
)
SELECT
  COALESCE(
    i.issued_by,
    (SELECT u.id FROM auth.users u
       WHERE u.email LIKE 'konchaaaaan373+mitas-admin@%'
          OR u.email LIKE 'demo-neco@%'
       LIMIT 1)
  )                                                        AS actor_user_id,
  'neco_admin'                                              AS actor_role,
  'invoice.issued'                                          AS action,
  'invoice'                                                 AS entity_type,
  i.id                                                      AS entity_id,
  i.organization_id                                         AS organization_id,
  jsonb_build_object(
    'status',         i.status,
    'total',          i.total,
    'invoice_number', i.invoice_number,
    'backfilled',     true
  )                                                         AS after_state,
  i.created_at                                              AS occurred_at
FROM invoices i
WHERE NOT EXISTS (
  SELECT 1 FROM activity_log al
  WHERE al.entity_type = 'invoice'
    AND al.entity_id   = i.id
)
  AND i.created_at >= NOW() - INTERVAL '30 days';

-- 想定通りなら COMMIT、そうでなければ ROLLBACK
COMMIT;


-- ───────────────────────────────────────────────────────────────
-- C. 実行後確認：補完が反映されたか
-- ───────────────────────────────────────────────────────────────

-- C-1. 補完後に残っている「activity_log 無し invoice」の件数
SELECT
  COUNT(*) AS still_missing
FROM invoices i
WHERE NOT EXISTS (
  SELECT 1 FROM activity_log al
  WHERE al.entity_type = 'invoice'
    AND al.entity_id   = i.id
)
  AND i.created_at >= NOW() - INTERVAL '30 days';

-- C-2. 直近に追加された invoice エントリ（after_state.backfilled=true）
SELECT al.id, al.actor_role, al.entity_id, al.occurred_at,
       al.after_state ->> 'invoice_number' AS invoice_number,
       al.after_state ->> 'backfilled'     AS backfilled
FROM activity_log al
WHERE al.entity_type = 'invoice'
  AND al.action      = 'invoice.issued'
ORDER BY al.occurred_at DESC
LIMIT 10;
