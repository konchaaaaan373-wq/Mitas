# Mitas for Alliance — Live Preflight Checklist

本書は、**Live スモークテストを開始する直前** に通すべき短い事前チェックリストです。
各項目は 1〜3 分で確認できる粒度に絞っています。詳細手順は `docs/LIVE_SMOKE_TEST.md` と `docs/LIVE_DEMO_SEED_PLAN.md` を参照してください。

⚠️ 一つでも未完了の項目がある場合は、**Live スモークテストを開始しないでください**。
本番ユーザー・実データ・課金・通知が意図せず動く可能性があります。

---

## A. デプロイと配信

- [ ] **Netlify deploy が最新 commit で完了している**
  - Netlify ダッシュボード → Deploys → 最新が "Published"
  - ブランチが想定通り（例：`claude/mitas-alliance-rebrand-lfpVX` または `main`）
- [ ] **本番ドメインで HTTP 200 が返る**
  - `curl -sI https://<your-domain>/service.html | head -1`
- [ ] **直近のデプロイログにエラーがない**
  - Functions のビルドが成功している
  - 静的ファイルの配信が成功している

---

## B. Netlify 環境変数

`Netlify dashboard → Site settings → Environment variables` で以下を確認：

- [ ] `SUPABASE_URL` — Supabase プロジェクトURL（本番用）
- [ ] `SUPABASE_ANON_KEY` — クライアントから使う anon key
- [ ] `SUPABASE_SERVICE_ROLE_KEY` — **Functions からのみ使われる**（HTML/JS には埋め込まれていない）
- [ ] （任意）`MITAS_TEST_MODE` などのフラグが意図通り

> `service_role` key は Netlify Functions 内でのみ参照されること。
> `grep -rn "SUPABASE_SERVICE_ROLE_KEY" netlify/functions` で参照箇所が `_utils/supabase.js` 等に限定されていることを確認できます。

---

## C. フロントの Supabase 設定

各 HTML の冒頭にある以下の値が、Live で使うプロジェクトと一致していること：

- [ ] `alliance-dashboard.html`
- [ ] `dashboard.html`
- [ ] `worker-app.html`
- [ ] `neco-console.html`
- [ ] `login.html` / `forgot-password.html` / `reset-password.html`

```js
window.__SUPABASE_URL__      = 'https://<your-project>.supabase.co';
window.__SUPABASE_ANON_KEY__ = '<anon-key>';
```

`<your-project>` のままになっていないか、anon key がフロントに埋め込まれていることを Network タブでも確認できます。

---

## D. Supabase セットアップ

### D.1 マイグレーション
- [ ] `db/migrations/9999_all_in_one_setup.sql` 適用済み（または 0001〜0006 を個別適用済み）
- [ ] `staffing_requests / proposals / assignments / work_logs / invoices / activity_log / worker_profiles / worker_credentials / worker_availability / organizations / organization_members / user_roles` が存在
- [ ] RLS が **全主要テーブルで有効** になっている
- [ ] 状態遷移トリガー（`validate_request_transition` など）が登録されている

### D.2 Auth ユーザー（手動作成）
seed はメールから `auth.users.id` を自動取得するため、UUID の控えは不要。
6人すべてが Authentication → Users に **同じメール** で作成済みであることを確認：

- [ ] `konchaaaaan373+mitas-admin@gmail.com`（neco_admin 用）
- [ ] `konchaaaaan373+mitas-alliance@gmail.com`（alliance_admin 用）
- [ ] `konchaaaaan373+mitas-facility1@gmail.com`（facility_admin / デモ中央病院）
- [ ] `konchaaaaan373+mitas-facility2@gmail.com`（facility_admin / デモ訪問看護）
- [ ] `konchaaaaan373+mitas-worker1@gmail.com`（worker / 医師）
- [ ] `konchaaaaan373+mitas-worker2@gmail.com`（worker / 看護師）

### D.3 ロール付与（user_roles）
- [ ] `db/seeds/0003_live_demo_seed.sql` をそのまま SQL Editor で実行
      （UUID 置換は不要。1人でも未作成なら `EXCEPTION` で安全にロールバック）
- [ ] SQL 実行後、`SELECT user_id, role, display_name FROM user_roles WHERE display_name LIKE '【DEMO】%';` で 6 行返る
- [ ] `display_name` の先頭が `【DEMO】` で始まっている

### D.4 シード適用
- [ ] `0003_live_demo_seed.sql` 実行で `Mitas for Alliance ライブデモシード投入完了（フィクション）` の NOTICE が出た
- [ ] `SELECT request_number FROM staffing_requests WHERE request_number LIKE 'SR-DEMO-%' ORDER BY request_number;` が 3 行返る（`SR-DEMO-0001/0002/0003`）
- [ ] `SELECT proposal_number FROM proposals WHERE proposal_number LIKE 'PR-DEMO-%' ORDER BY proposal_number;` が 3 行返る
- [ ] `SELECT assignment_number FROM assignments WHERE assignment_number LIKE 'AS-DEMO-%';` が 1 行返る（`AS-DEMO-0001`）

---

## E. データ安全性の最終確認

- [ ] `staffing_requests` / `proposals` / `assignments` / `worker_profiles` に **DEMO 以外の本番データが残っていない**
  - 過去のテスト・本番運用が始まっていないこと
  - 残っている場合はバックアップを取得してから判断
- [ ] フィクション以外の **患者情報（氏名・住所・診療内容）が含まれていない**
- [ ] フィクション以外の **実医療従事者の個人情報が含まれていない**
- [ ] 全 DEMO レコードに `（DEMO）` / `Mitas Demo` / `XX-DEMO-NNNN` / `DEMO DATA` のいずれかが含まれている

---

## F. アプリ動作モード

- [ ] **Mock mode が無効化されている**
  - 各 HTML の `window.__SUPABASE_URL__` が `'YOUR_PROJECT'` を含んでいないこと
  - 各画面を開いた際に `（モック）` 表記が **出ない** こと
- [ ] テスト用ブラウザのキャッシュ／Service Worker をクリア済み
- [ ] 開発者ツール（Console / Network）を開いた状態でテストする

---

## G. ログイン確認（最小）

事前にすべてのロールでログインできることを確認：

- [ ] neco_admin で `/login.html` → `/neco-console.html` が表示
- [ ] alliance_admin で `/login.html` → `/alliance-dashboard.html` が表示
- [ ] facility_admin（デモ中央病院）で `/login.html` → `/dashboard.html` が表示し、自施設の SR-DEMO-0001 / SR-DEMO-0003 のみ見える
- [ ] facility_admin（デモ訪問看護）で `/login.html` → `/dashboard.html` が表示し、SR-DEMO-0002 のみ見える
- [ ] worker（医師）で `/login.html` → `/worker-app.html` が表示
- [ ] worker（看護師）で `/login.html` → `/worker-app.html` が表示し、AS-DEMO-0001 が「本日／勤務予定」に出る

> 1ロールでもログインに失敗する場合は、Netlify Functions のログ・Supabase Auth のログ・`user_roles` の状態を確認してください。

---

## H. 通知・連絡

- [ ] 共同開発者・運用者に **Live スモークテスト開始** をアナウンス（Slack / メール）
- [ ] 緊急停止時の連絡先（プロダクトオーナー / インフラ担当）が手元にある
- [ ] テスト中の DB 変更が他環境に影響しないことを確認（同じ Supabase を共有していないか）

---

## I. テスト後アクション準備

- [ ] `docs/LIVE_SMOKE_TEST_RESULT_TEMPLATE.md` をコピーし、結果記録ファイルを準備
- [ ] スクリーンショット保存先のフォルダ／URL を決めている
- [ ] デモ終了後の **削除 SQL（`docs/LIVE_DEMO_SEED_PLAN.md` 4節）** を手元に準備
- [ ] 削除完了の確認 SQL（残レコード件数チェック）も準備

---

## 完了条件

すべてのチェックボックスにチェックが入ったら、`docs/LIVE_SMOKE_TEST.md` 第3章の End-to-End ワークフローテストへ進んでください。
未チェック項目がある場合は、テストを開始せずに該当箇所を解消してください。

---

## 関連ドキュメント

- `docs/LIVE_SMOKE_TEST.md` — 本書を通過した後に実施するスモークテスト
- `docs/LIVE_DEMO_SEED_PLAN.md` — デモシード設計と削除 SQL
- `docs/SMOKE_TEST.md` — Mock mode 中心の手動スモークテスト（参考）
- `docs/RLS_CHECKLIST.md` — Live 環境での権限確認
- `docs/LIVE_SMOKE_TEST_RESULT_TEMPLATE.md` — スモークテスト結果記録テンプレート
- `db/seeds/0003_live_demo_seed.sql` — デモシード SQL
