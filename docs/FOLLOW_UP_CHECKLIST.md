# Mitas for Alliance — Follow-up Checklist（残課題チェックリスト）

2026-05-02 の Live スモークテスト（Conditional Pass）で **未確認のまま残ったフロー** を、優先順位順に **「最小手順 + 期待結果 + 結果記録表」** で具体化した checklist です。
本書のチェックを順次埋めることで Conditional Pass → Pass を目指します。

実施手順：
1. 該当セクションの「最小手順」を順番に実行
2. 「期待される表示」と差分があれば「観察された問題」欄に記入
3. 「結果記録表」の `[ ]` を `[x]` に塗り替え、Pass / Fail を残す
4. 全項目クリア → 該当セクション完了

新規バグが出たら別途 Issue / `docs/results/` 配下に新しい結果ファイルを作成して紐付けてください。

---

## 0. 共通環境

### 0.1 利用するユーザー

| ロール | メール |
|---|---|
| neco_admin | `konchaaaaan373+mitas-admin@gmail.com` |
| alliance_admin | `konchaaaaan373+mitas-alliance@gmail.com` |
| facility_admin（中央病院） | `konchaaaaan373+mitas-facility1@gmail.com` |
| facility_admin（訪問看護） | `konchaaaaan373+mitas-facility2@gmail.com` |
| worker（医師） | `konchaaaaan373+mitas-worker1@gmail.com` |
| worker（看護師） | `konchaaaaan373+mitas-worker2@gmail.com` |

### 0.2 利用 URL

```
https://mitas.necofindjob.com/login.html
```

ログイン後はロール別自動遷移により所定の画面に着くため、URL を手で打つ必要は基本ない。

### 0.3 ブラウザ準備

- DevTools（`Option + Cmd + I`）→ Console / Network タブを開きながら実施
- ロール切替時はログアウト推奨。同時並行検証時はシークレットウィンドウを併用

### 0.4 共通の合格判定

- Console に **赤字エラーなし**（`Identifier 'supabase'` 等の lexical エラー含む）
- Network タブに **失敗（4xx/5xx）リクエストなし**（CSP の sourcemap 警告は無視可）
- 操作後の DB レコードが意図通り

---

## 1. 新規勤務枠登録から始める Live フロー（優先度：高）

DEMO シードで前進済みの `SR-DEMO-*` は使わず、**完全に新規** の勤務枠を投入して `submitted → invoiced` までを通す。

### 1.1 最小手順

| Step | ロール | 操作 |
|---|---|---|
| 1 | facility_admin（中央病院）でログイン | `/login.html` → 自動で `/dashboard.html` |
| 2 | 上部の「**+ 新しい勤務枠を登録**」ボタンをクリック | モーダルが開く |
| 3 | 必須項目を入力 | 勤務枠名「フォローアップ検証 内科外来」／必要職種「医師」／必要人数 1／勤務種別「応援勤務」／勤務開始予定（任意の未来日）／充足希望日（任意の未来日） |
| 4 | 構造化入力補助を 6 項目すべて記入 | 想定患者数 / 業務範囲 / バックアップ体制 / 電子カルテ / 集合場所・持ち物 / 注意事項 |
| 5 | 「**勤務枠を登録**」を送信 | 「勤務枠を受け付けました」モーダル |
| 6 | ログアウト → neco_admin でログイン | 自動で `/neco-console.html` |
| 7 | 左タブ「**新規依頼**」 | 上記の勤務枠が新規行で表示（経過日数 0 日） |
| 8 | 行をクリック → 詳細パネル | 要件確認チェックリスト・次アクション「要件確認」 |
| 9 | 状態遷移ボタン `submitted → under_review → accepted → proposing` | 各遷移でトースト成功・activity_log 追加 |
| 10 | 医療者候補ランキング → 田中 健太郎（DEMO）の「施設へ提案」 | 提案モーダル → 「提案を作成」 |
| 11 | 提案カードの「**打診済みにする**」 | proposal_status=worker_contacted |
| 12 | 「**医療者承諾にする**」 | worker_accepted |
| 13 | 「**施設へ提案する**」 | proposed_to_facility |
| 14 | ログアウト → facility_admin（中央病院）でログイン | `/dashboard.html` 配置候補タブ |
| 15 | 該当行の「**承認する**」 | facility_accepted、ヒント切替 |
| 16 | ログアウト → neco_admin でログイン | `/neco-console.html` |
| 17 | 提案カードの「**勤務確定を作成**」 | モーダル開く |
| 18 | 入力検証：時給／開始終了を確認後「勤務確定を作成」 | assignment 作成 |
| 19 | ログアウト → worker1（医師）でログイン | `/worker-app.html` |
| 20 | 本日 / 勤務予定で新しい assignment を確認し、チェックイン | status=checked_in |
| 21 | チェックアウト → 完了報告 | status=completion_reported |
| 22 | ログアウト → facility_admin（中央病院）でログイン | `/dashboard.html` 勤務確定・稼働 |
| 23 | 「**完了確定**」 | status=completion_confirmed |
| 24 | ログアウト → neco_admin でログイン | `/neco-console.html` |
| 25 | 詳細パネル → 確定勤務・稼働状況の「**請求書を作成**」 | invoice 作成 |
| 26 | タイムライン・監査ログを確認 | 全 action が時系列で表示・actor_role が日本語タグで表示・invoice.issued あり |

### 1.2 結果記録表

| # | 確認項目 | 結果 | 観察された問題 |
|---|---|---|---|
| 1 | 勤務枠登録モーダルが開く／閉じる | [ ] Pass / [ ] Fail | |
| 2 | 構造化入力が `description` に整形されて保存 | [ ] Pass / [ ] Fail | |
| 3 | neco-console 新規依頼タブに自動表示 | [ ] Pass / [ ] Fail | |
| 4 | 状態遷移 4 段階が成功 | [ ] Pass / [ ] Fail | |
| 5 | 提案 5 アクション（打診→承諾→施設提案→…）が成功 | [ ] Pass / [ ] Fail | |
| 6 | facility 承認後にヒントが「Necoが勤務確定手続き中」へ切替 | [ ] Pass / [ ] Fail | |
| 7 | 勤務確定モーダルの入力検証（必要項目欠如時に送信 disable） | [ ] Pass / [ ] Fail | |
| 8 | worker チェックイン／アウト／完了報告の 3 段階 | [ ] Pass / [ ] Fail | |
| 9 | facility 完了確定 | [ ] Pass / [ ] Fail | |
| 10 | neco 請求書作成 | [ ] Pass / [ ] Fail | |
| 11 | タイムラインに全 action が actor_role 付きで表示 | [ ] Pass / [ ] Fail | |
| 12 | invoice.issued がタイムラインに表示 | [ ] Pass / [ ] Fail | |

> **DB 変更（クリーンアップ）**：本フローで作成したテストデータは DEMO プレフィックスではないため、検証後に必要なら以下で削除可能。**Section 6.1 のクリーンアップ SQL 参照**。

---

## 2. 中央病院 vs 訪問看護のデータ独立性（優先度：高）

組織横断で他施設のデータが見えないことを RLS ベースで確認。

### 2.1 最小手順

| Step | ロール | 操作 |
|---|---|---|
| 1 | facility_admin（**中央病院**）でログイン | `/dashboard.html` |
| 2 | 左サイドバー「**勤務枠管理**」をクリック | 中央病院の勤務枠のみ表示 |
| 3 | 表に表示される `request_number` を全て控える | 後で 2 と比較 |
| 4 | 「**配置候補**」タブ | 自施設宛 proposal のみ |
| 5 | 「**勤務確定・稼働**」タブ | 自施設の assignment のみ |
| 6 | 「**請求・実績**」タブ | 自施設の invoice のみ |
| 7 | DevTools Network → 任意の `/rest/v1/staffing_requests` リクエストの Response を確認 | 自組織のレコードのみ含まれている |
| 8 | ログアウト → facility_admin（**訪問看護**）でログイン | `/dashboard.html` |
| 9 | 同じく勤務枠管理／配置候補／勤務確定・稼働／請求・実績 を確認 | 訪問看護の勤務枠のみ／中央病院の勤務枠が見えない |
| 10 | 表に表示される `request_number` を全て控える | Step 3 と比較して **重複ゼロ** |

### 2.2 期待される結果（DEMO 投入直後の状態）

| 組織 | 表示されるべき | 表示されるべきでない |
|---|---|---|
| 中央病院（facility1） | `SR-DEMO-0001` `SR-DEMO-0003`、PR-DEMO-0002、AS-DEMO-0001、関連 invoice | `SR-DEMO-0002`、PR-DEMO-0001 |
| 訪問看護（facility2） | `SR-DEMO-0002`、PR-DEMO-0001 | `SR-DEMO-0001` `SR-DEMO-0003`、PR-DEMO-0002、AS-DEMO-0001 |

### 2.3 結果記録表

| # | 確認項目 | 結果 | 観察された問題 |
|---|---|---|---|
| 1 | facility1 で SR-DEMO-0001 / 0003 が見える | [ ] Pass / [ ] Fail | |
| 2 | facility1 で SR-DEMO-0002 が見えない | [ ] Pass / [ ] Fail | RLS 違反なら高重要度 |
| 3 | facility1 の Network レスポンスに他組織レコードが混入していない | [ ] Pass / [ ] Fail | |
| 4 | facility2 で SR-DEMO-0002 のみ見える | [ ] Pass / [ ] Fail | |
| 5 | facility2 で SR-DEMO-0001 / 0003 / AS-DEMO-0001 が見えない | [ ] Pass / [ ] Fail | RLS 違反なら高重要度 |
| 6 | facility2 で PR-DEMO-0001（訪問看護宛）のみ見える | [ ] Pass / [ ] Fail | |
| 7 | 表示された `request_number` の集合が両組織で重複ゼロ | [ ] Pass / [ ] Fail | |

> **DB 変更なし**。閲覧のみ。

---

## 3. alliance-dashboard KPI 表示（優先度：中）

alliance_admin で全体 KPI ビュー（`v_*`）が読み込めることを確認。

### 3.1 事前確認 SQL（DB 変更なし）

ビューが DB に存在することを確認：

```sql
-- 期待: 8 行（v_unfilled_requests_summary, v_fill_rate,
--           v_shortage_by_specialty, v_night_duty_gaps,
--           v_alliance_dashboard, v_workforce_utilization,
--           v_invoice_summary, v_credential_attention 等）
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name LIKE 'v\_%' ESCAPE '\'
ORDER BY table_name;
```

存在しないビューがあれば、`db/migrations/9999_all_in_one_setup.sql` の該当 `CREATE OR REPLACE VIEW` を再実行する必要がある（適用漏れ）。

### 3.2 最小手順

| Step | ロール | 操作 |
|---|---|---|
| 1 | alliance_admin でログイン | `/login.html` → 自動で `/alliance-dashboard.html` |
| 2 | 上部の KPI カード 8 枚を目視 | 緊急未充足枠／未充足勤務枠／未充足人数／30日以内充足／進行中稼働／紛争・確認中／稼働可能医療者／期限間近資格確認 |
| 3 | 「未充足勤務枠が多い施設」ランキングを確認 | DEMO 投入された組織の未充足枠が表示 |
| 4 | 「職種別の人材不足」バー | physician / nurse 等のバー表示 |
| 5 | 「充足率（過去90日・施設×職種）」テーブル | 行が描画される |
| 6 | 「夜勤・オンコールの未充足」テーブル | 行が描画される |
| 7 | 「AI配置支援（将来実装予定）」セクション | 静的テキスト表示 |
| 8 | DevTools Network → `dashboard/kpi`、`v_unfilled_requests_summary`、`v_fill_rate`、`v_shortage_by_specialty`、`v_night_duty_gaps` の各リクエストが 200 で返る | RLS で 403 / 0 件にならない |
| 9 | 個人情報を直接取得しないことを確認 | DevTools で `worker_profiles?select=*` を直接叩いた場合に 403 もしくは集計のみ |

### 3.3 結果記録表

| # | 確認項目 | 結果 | 観察された問題 |
|---|---|---|---|
| 1 | 事前 SQL でビュー 5 件以上存在 | [ ] Pass / [ ] Fail | |
| 2 | KPI カード 8 枚すべて読み込み完了 | [ ] Pass / [ ] Fail | 「読み込み中…」が残る場合 fail |
| 3 | 未充足ランキングの行が描画 | [ ] Pass / [ ] Fail | |
| 4 | 職種別不足バーが描画 | [ ] Pass / [ ] Fail | |
| 5 | 充足率テーブルが描画 | [ ] Pass / [ ] Fail | |
| 6 | 夜勤・オンコールテーブルが描画 | [ ] Pass / [ ] Fail | |
| 7 | Network で各 v_* リクエストが 200 | [ ] Pass / [ ] Fail | |
| 8 | alliance_admin が個人情報を直取得できない | [ ] Pass / [ ] Fail | RLS 確認 |

> **DB 変更なし**。事前確認 SQL のみ実行（SELECT のみ）。

---

## 4. worker2（看護師）フロー（優先度：中）

worker1 で End-to-End 完走済み。worker2 でプロフィール表示と RLS 独立性を確認。

### 4.1 最小手順

| Step | ロール | 操作 |
|---|---|---|
| 1 | worker2（看護師）でログイン | `/login.html` → 自動で `/worker-app.html` |
| 2 | 「**本日の勤務**」タブ | 「本日確定している勤務はありません」 or 該当なし表示 |
| 3 | 「**勤務予定**」タブ | 表示できる勤務予定なし |
| 4 | 「**勤務予定**」タブの末尾 | 「勤務機会のご相談（将来実装予定）」セクション表示 |
| 5 | 「**医療者プロフィール**」タブ | 7 セクション表示（基本情報／専門領域／対応可能業務／希望勤務条件／勤務可能時間／資格書類／Neco確認状況） |
| 6 | 専門領域：訪問看護、経験 7 年、希望地域：東京都・埼玉県 を確認 | seed 通りの値 |
| 7 | 勤務可能時間：土曜・日曜 10:00–18:00 を確認 | seed で投入された 2 行 |
| 8 | 資格書類：看護師免許（DEMO）verified を確認 | seed 通り |
| 9 | Neco確認状況：「資格確認完了」表示 | 1/1 件 verified |
| 10 | 「勤務機会の案内を受け取る」トグル ON 表示 | seed の `is_available_for_offers=true` |
| 11 | DevTools Network → `/api/v2/assignments` の Response | **0 件**（または worker2 自身のもののみ） |

### 4.2 重要：RLS 検証

| Step | 操作 | 期待 |
|---|---|---|
| A | worker2 でログイン状態を保持 | |
| B | DevTools Console で以下を実行：`fetch('/rest/v1/assignments?select=id,assignment_number,worker_id&assignment_number=eq.AS-DEMO-0001', {headers: {apikey: window.__SUPABASE_ANON_KEY__, Authorization: 'Bearer ' + (await window.supabase.auth.getSession()).data.session.access_token}}).then(r => r.json()).then(console.log)` | **空配列 `[]`** が返る（RLS で他者 assignment が見えない） |

> **AS-DEMO-0001 が worker2 に見えてしまったら High 重要度の RLS バグ**。即座に Issue 化すること。

### 4.3 結果記録表

| # | 確認項目 | 結果 | 観察された問題 |
|---|---|---|---|
| 1 | ロール別自動遷移で `/worker-app.html` に到達 | [ ] Pass / [ ] Fail | |
| 2 | 本日の勤務タブが空状態を表示（hang しない） | [ ] Pass / [ ] Fail | |
| 3 | 勤務予定タブが空状態を表示 | [ ] Pass / [ ] Fail | |
| 4 | 勤務機会セクション（将来実装予定）が表示 | [ ] Pass / [ ] Fail | |
| 5 | プロフィール 7 セクションすべて表示 | [ ] Pass / [ ] Fail | |
| 6 | 専門領域・経験年数・希望地域が seed 通り | [ ] Pass / [ ] Fail | |
| 7 | 勤務可能時間が 2 行（土・日） | [ ] Pass / [ ] Fail | |
| 8 | 資格書類が verified で表示 | [ ] Pass / [ ] Fail | |
| 9 | Neco確認状況が「資格確認完了」 | [ ] Pass / [ ] Fail | |
| 10 | オファー受付トグルが ON | [ ] Pass / [ ] Fail | |
| 11 | **AS-DEMO-0001 が worker2 に見えない** | [ ] Pass / [ ] Fail | **High 重要度** |
| 12 | Network で `/api/v2/assignments` レスポンスに他者データが混入していない | [ ] Pass / [ ] Fail | |

> **DB 変更なし**。閲覧のみ。

---

## 5. request.status の自動進行（優先度：中）

assignment 作成・完了時に request.status が自動で進むかを検証。

### 5.1 仕様（migrations から判明した事実）

`db/migrations/9999_all_in_one_setup.sql` line 1342–1345 の `trg_validate_request_transition` は、
**遷移の妥当性を検証する** トリガーであり、**自動で status を進める実装ではない**。

つまり：
- assignment を `confirmed` で作成しても、request.status は `proposing` のまま
- assignment が `completion_confirmed` になっても、request.status は変化しない
- request.status は **neco_admin が手動で進める仕様**（neco-console の状態遷移ボタン経由）

### 5.2 事前確認 SQL（DB 変更なし）

トリガーが「検証のみ」であることを再確認：

```sql
-- 1. 関数の中身を確認（自動進行ロジックの有無）
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'validate_request_transition';

-- 2. assignments への AFTER INSERT/UPDATE トリガーが
--    request 側を更新していないか確認
SELECT tgname, pg_get_triggerdef(t.oid)
FROM pg_trigger t
WHERE tgrelid = 'assignments'::regclass
  AND tgname NOT LIKE 'pg_%'
  AND tgname NOT LIKE 'RI_%';
```

### 5.3 動作確認手順

`SR-DEMO-0003` を使って実際の挙動を確認（既に AS-DEMO-0001 があり、`completion_confirmed` 済みのはず）。

| Step | 操作 | 期待 |
|---|---|---|
| 1 | neco_admin でログイン → `/neco-console.html` → SR-DEMO-0003 を選択 | 詳細パネル表示 |
| 2 | 詳細パネル上部の現在の `request.status` を確認 | `proposing` のまま、または手動で `fully_assigned` に進めた状態 |
| 3 | DevTools Console で `await fetch('/rest/v1/staffing_requests?id=eq.<request_id>&select=status,fulfilled_at', {headers: ...}).then(r => r.json())` を実行 | 同上 |
| 4 | （任意）状態遷移ボタンで `proposing → fully_assigned` を手動実行 | トリガーで `fulfilled_at` が NOW() に自動設定される |
| 5 | DB を再確認 | status=fully_assigned, fulfilled_at が更新済み |

### 5.4 結果記録表

| # | 確認項目 | 結果 | メモ |
|---|---|---|---|
| 1 | 事前 SQL：`validate_request_transition` は検証のみ（自動進行なし） | [ ] Confirmed / [ ] Different | |
| 2 | assignments テーブルに request 状態を更新する AFTER トリガーが無い | [ ] Confirmed / [ ] Different | |
| 3 | assignment が completion_confirmed でも request.status は変化しない | [ ] Pass / [ ] Fail | 仕様通り |
| 4 | 手動で proposing → fully_assigned 遷移時に fulfilled_at が自動設定 | [ ] Pass / [ ] Fail | |
| 5 | 不正な遷移（例：proposing → confirmed 直接）が拒否される | [ ] Pass / [ ] Fail | RAISE EXCEPTION |

### 5.5 仕様化メモ

トリガーが「自動進行しない」ことが確認できたら、以下を運用ドキュメントに明記する：

- **request.status は neco_admin が手動で進める運用**
- 自動進行が望ましいなら、別 PR で `assignments` への AFTER INSERT/UPDATE トリガー（または client 側コード）を追加する設計議論が必要

> **DB 変更なし**。事前確認 SQL のみ実行。状態遷移は既存ボタンで実施。

---

## 6. 補助：DB クリーンアップ SQL（必要時のみ）

新規勤務枠登録フロー（Section 1）で作成したデータを削除したい場合のみ実行。

### 6.1 事前確認 SQL（実行前）

```sql
-- 削除対象：DEMO プレフィックス以外で、フォローアップ検証中に作成された勤務枠
SELECT id, request_number, title, status, created_at
FROM staffing_requests
WHERE title LIKE 'フォローアップ検証%'
  AND created_at >= NOW() - INTERVAL '7 days'
ORDER BY created_at DESC;
```

### 6.2 実行 SQL（必要時のみ）

```sql
BEGIN;

-- 関連 activity_log
DELETE FROM activity_log
WHERE entity_id IN (
  SELECT id FROM staffing_requests WHERE title LIKE 'フォローアップ検証%'
  UNION
  SELECT id FROM proposals
    WHERE request_id IN (SELECT id FROM staffing_requests WHERE title LIKE 'フォローアップ検証%')
  UNION
  SELECT id FROM assignments
    WHERE request_id IN (SELECT id FROM staffing_requests WHERE title LIKE 'フォローアップ検証%')
);

-- 関連 invoice_line_items / invoices
DELETE FROM invoice_line_items
WHERE assignment_id IN (
  SELECT id FROM assignments
  WHERE request_id IN (SELECT id FROM staffing_requests WHERE title LIKE 'フォローアップ検証%')
);
DELETE FROM invoices
WHERE id NOT IN (SELECT invoice_id FROM invoice_line_items WHERE invoice_id IS NOT NULL)
  AND invoice_number LIKE 'IN-%'
  AND created_at >= NOW() - INTERVAL '7 days';

-- 関連 work_logs / assignments / proposals / staffing_requests
DELETE FROM work_logs
WHERE assignment_id IN (
  SELECT id FROM assignments
  WHERE request_id IN (SELECT id FROM staffing_requests WHERE title LIKE 'フォローアップ検証%')
);
DELETE FROM assignments
WHERE request_id IN (SELECT id FROM staffing_requests WHERE title LIKE 'フォローアップ検証%');
DELETE FROM proposals
WHERE request_id IN (SELECT id FROM staffing_requests WHERE title LIKE 'フォローアップ検証%');
DELETE FROM staffing_requests WHERE title LIKE 'フォローアップ検証%';

COMMIT;
```

### 6.3 実行後確認 SQL

```sql
-- いずれも 0 行になっているはず
SELECT 'staffing_requests' AS tbl, COUNT(*) AS remaining FROM staffing_requests WHERE title LIKE 'フォローアップ検証%'
UNION ALL
SELECT 'proposals',         COUNT(*) FROM proposals
  WHERE request_id IN (SELECT id FROM staffing_requests WHERE title LIKE 'フォローアップ検証%')
UNION ALL
SELECT 'assignments',       COUNT(*) FROM assignments
  WHERE request_id IN (SELECT id FROM staffing_requests WHERE title LIKE 'フォローアップ検証%');
```

> ⚠️ クリーンアップは Section 1 完走後のみ実行。それ以前のテストで作成された行が残っている場合は WHERE 句を慎重に調整すること。

---

## 7. 完了基準

- Section 1〜5 すべての結果記録表で **Fail = 0** → **Pass** 判定
- Fail があるが High 重要度（RLS 違反等）は無い → **Conditional Pass** 維持
- High 重要度 Fail が出た場合 → 個別 PR で修正 → 該当 Section を再テスト

確認結果は本書を埋めるとともに、`docs/results/LIVE_SMOKE_TEST_RESULT_<YYYYMMDD>.md` に総括を残してください。

---

## 関連ドキュメント

- `docs/SMOKE_TEST.md` — Mock mode 中心のスモークテスト
- `docs/LIVE_SMOKE_TEST.md` — Live 環境のスモークテスト
- `docs/LIVE_PREFLIGHT_CHECKLIST.md` — Live テスト直前のチェック
- `docs/LIVE_DEMO_SEED_PLAN.md` — デモシード設計
- `docs/RLS_CHECKLIST.md` — Live 環境での権限確認
- `docs/V1_API_REMOVAL_PLAN.md` — 旧 v1 API 削除計画
- `docs/results/LIVE_SMOKE_TEST_RESULT_20260502.md` — 直近の実施結果（Conditional Pass）
