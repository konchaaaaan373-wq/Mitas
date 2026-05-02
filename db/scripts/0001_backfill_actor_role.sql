-- ================================================================
-- 0001_backfill_actor_role.sql
-- 目的: activity_log.actor_role が NULL のレコードを user_roles から
--       逆引きして補完する。
-- 背景: 2026-05-02 以前は Netlify Functions の logActivity が actor_role
--       引数を受け取らず NULL のまま記録していたため、タイムライン UI で
--       actor_role が「—」表記になっていた。logActivity の修正は完了済み
--       （commit 80cc467）だが、過去レコードは遡及補完が必要。
-- 安全策:
--   - 本スクリプトは UPDATE ... WHERE actor_role IS NULL のみ。
--     既に actor_role が入っている行には触れない。
--   - UPDATE の前後に確認 SELECT を実行し、件数を比較できる。
--   - トランザクション内で実行（途中失敗で全行ロールバック）。
-- 使い方: Supabase SQL Editor に貼り付けて実行。
-- ================================================================

-- ───────────────────────────────────────────────────────────────
-- A. 実行前確認：補完対象の件数と内訳
-- ───────────────────────────────────────────────────────────────

-- A-1. 補完対象（actor_role IS NULL かつ actor_user_id がある）
SELECT
  COUNT(*)                                              AS total_to_backfill,
  COUNT(*) FILTER (WHERE actor_user_id IS NOT NULL)     AS resolvable,
  COUNT(*) FILTER (WHERE actor_user_id IS NULL)         AS unresolvable_no_actor
FROM activity_log
WHERE actor_role IS NULL;

-- A-2. action 別の補完対象内訳（参考）
SELECT action, COUNT(*) AS cnt
FROM activity_log
WHERE actor_role IS NULL
  AND actor_user_id IS NOT NULL
GROUP BY action
ORDER BY cnt DESC, action;

-- A-3. 補完不可（actor_user_id も NULL の行）の例（あれば手動調査）
SELECT id, action, entity_type, entity_id, occurred_at
FROM activity_log
WHERE actor_role IS NULL AND actor_user_id IS NULL
ORDER BY occurred_at DESC
LIMIT 10;


-- ───────────────────────────────────────────────────────────────
-- B. 実行：トランザクション内で UPDATE
--    user_roles に対応行が無い user_id（auth.users から削除済み等）は
--    JOIN で除外されるため NULL のまま残る → 安全。
-- ───────────────────────────────────────────────────────────────

BEGIN;

UPDATE activity_log al
SET actor_role = ur.role
FROM user_roles ur
WHERE al.actor_role IS NULL
  AND al.actor_user_id = ur.user_id;

-- 想定通りなら COMMIT、そうでなければ ROLLBACK
-- 件数が想定と大きく乖離している場合は ROLLBACK を実行してください
COMMIT;


-- ───────────────────────────────────────────────────────────────
-- C. 実行後確認：残件数と直近の actor_role 分布
-- ───────────────────────────────────────────────────────────────

-- C-1. 補完後に残った NULL レコード（基本は actor_user_id も NULL のもの）
SELECT
  COUNT(*)                                          AS still_null,
  COUNT(*) FILTER (WHERE actor_user_id IS NOT NULL) AS unresolved_with_actor,
  COUNT(*) FILTER (WHERE actor_user_id IS NULL)     AS no_actor_at_all
FROM activity_log
WHERE actor_role IS NULL;

-- C-2. 直近 24 時間の actor_role 分布（補完が反映されているか確認）
SELECT actor_role, COUNT(*) AS cnt
FROM activity_log
WHERE occurred_at >= NOW() - INTERVAL '24 hours'
GROUP BY actor_role
ORDER BY cnt DESC;

-- C-3. 直近 10 行のサンプル表示
SELECT id, actor_role, action, entity_type, occurred_at
FROM activity_log
ORDER BY occurred_at DESC
LIMIT 10;
