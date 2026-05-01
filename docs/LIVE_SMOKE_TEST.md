# Mitas for Alliance — Live スモークテスト

本書は、本番（Live）環境での **手動スモークテスト** 手順です。
`docs/SMOKE_TEST.md` は Mock mode 中心のチェックリストでしたが、
本書は **実 Supabase 環境＋ライブデモシード** を対象にします。

⚠️ Live 環境での確認は、想定外のメール送信・課金・データ汚染を起こす可能性があります。
**本書のすべての手順を流す前に、本ドキュメントを通読してください。**

---

## 0. 想定環境

| 項目 | 値 |
|---|---|
| 公開URL | `https://mitas.necofindjob.com`（または本番ドメイン） |
| プラットフォーム | Netlify（HTML 静的配信 + Functions） |
| DB／認証 | Supabase（PostgREST + Auth） |
| ロール | `worker` / `facility_admin` / `neco_admin` / `alliance_admin` |
| デモデータ | `db/seeds/0003_live_demo_seed.sql` で投入されたフィクション |

---

## 1. 事前チェックリスト

### 1.1 環境変数（Netlify Environment Variables）
| 変数 | 用途 |
|---|---|
| `SUPABASE_URL` | Supabase プロジェクトURL |
| `SUPABASE_ANON_KEY` | クライアント用 anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | サーバ用（activity_log 書き込み等） |
| （任意）`MITAS_TEST_MODE` | 本番運用切替前であることが明示できる場合に設定 |

### 1.2 各 HTML 内の Supabase URL
`alliance-dashboard.html` / `dashboard.html` / `worker-app.html` / `neco-console.html` / `login.html` などの先頭に以下が直書きされている。**Supabase プロジェクト切替時はここも更新**：

```js
window.__SUPABASE_URL__      = 'https://<your-project>.supabase.co';
window.__SUPABASE_ANON_KEY__ = '<anon-key>';
```

### 1.3 マイグレーション適用状態
- `db/migrations/9999_all_in_one_setup.sql` が適用済み、または個別マイグレーション 0001〜0006 がすべて適用済み
- `user_roles` / `organization_members` / `worker_profiles` / `staffing_requests` / `proposals` / `assignments` / `work_logs` / `invoices` / `activity_log` が存在
- RLS が有効になっている

### 1.4 Auth ユーザーの作成
Supabase ダッシュボード → Authentication → Add user で以下を作成：

- `demo-neco@mitas-demo.example`（neco_admin）
- `demo-alliance@mitas-demo.example`（alliance_admin）
- `demo-facility-1@mitas-demo.example`（facility_admin / デモ中央病院）
- `demo-facility-2@mitas-demo.example`（facility_admin / デモ訪問看護）
- `demo-doctor@mitas-demo.example`（worker / 医師）
- `demo-nurse@mitas-demo.example`（worker / 看護師）

各ユーザーの **生成された UUID をメモ** してください。

### 1.5 ライブデモシード投入
1. `db/seeds/0003_live_demo_seed.sql` を開く
2. 冒頭の `DECLARE` ブロックの `v_neco_user` 等の固定値を、**1.4 で控えた UUID に置き換える**
3. Supabase SQL Editor で実行
4. 出力に `Mitas for Alliance ライブデモシード投入完了（フィクション）` が出ること
5. `auth.users が見つかりません` が出た場合は 1.4 を再確認

### 1.6 個人情報を含むデータが事前に存在しないこと
- `staffing_requests` に DEMO 以外のデータが残っていないこと（過去の本番テストデータ等）
- `worker_profiles` に DEMO 以外のレコードがないこと
- 必要に応じて `0003` 投入前にバックアップを取得

---

## 2. ログインチェック

各ロールでログインし、想定画面が開けることを確認します。

| ロール | URL | 期待結果 |
|---|---|---|
| neco_admin | `/login.html` → `/neco-console.html` | 配置マッチングコンソールが表示／稼働監視がロードされる |
| alliance_admin | `/login.html` → `/alliance-dashboard.html` | 連携法人 人材需給ダッシュボードが表示／KPI が読み込まれる |
| facility_admin（デモ中央病院） | `/login.html` → `/dashboard.html` | 施設人材需給ダッシュボードが表示／自施設の SR-DEMO-0001/0003 のみ見える |
| facility_admin（デモ訪問看護） | `/login.html` → `/dashboard.html` | 自施設の SR-DEMO-0002 のみ見える |
| worker（医師） | `/login.html` → `/worker-app.html` | 医療専門職向け勤務機会アプリが表示 |
| worker（看護師） | `/login.html` → `/worker-app.html` | AS-DEMO-0001 が「本日／勤務予定」に出る |

### 2.1 ロール別アクセス制御
- `/login.html` 後の自動リダイレクトが想定どおり動く
- 想定外のロールが他ロール画面を直接開いた場合、データが空 / 401 / 403 で返る
- `docs/RLS_CHECKLIST.md` 5.1 セクションを最低限確認

---

## 3. End-to-End ワークフローテスト（ライブデモ）

以下、`docs/SMOKE_TEST.md` の 15 ステップを **Live 環境で** 実施します。
demo データの `SR-DEMO-0003 / PR-DEMO-0003 / AS-DEMO-0001` は既に確定済みなので、**残りの DEMO データを使って一気通貫を体験** します。

| # | ロール | 画面 | 操作 | 期待結果 |
|---|---|---|---|---|
| 1 | facility_admin（デモ中央病院） | dashboard | 「+ 新しい勤務枠を登録」→ 適当に入力 → 送信 | 勤務枠が新規作成（`SR-DEMO-XXXX` ではなく自動生成番号） |
| 2 | neco_admin | neco-console | 新規依頼タブで上で作成した依頼を選択 → 状態遷移ボタン `under_review → accepted` | 状態が更新される |
| 3 | neco_admin | neco-console | 医療者候補ランキング → 「施設へ提案」（モーダル）→ 提案作成 | 提案 created で追加 |
| 4 | neco_admin | neco-console | 提案カードの「打診済みにする」 | proposal_status が `worker_contacted` |
| 5 | neco_admin | neco-console | 「医療者承諾にする」 | `worker_accepted` |
| 6 | neco_admin | neco-console | 「施設へ提案する」 | `proposed_to_facility` |
| 7 | facility_admin | dashboard | 配置候補テーブル → 該当行の「承認する」 | `facility_accepted`、ヒントが「Necoが勤務確定手続き中」に切替 |
| 8 | neco_admin | neco-console | 提案カード「勤務確定を作成」→ 開始/終了/時給確認 → 送信 | 確定アサインが作成、稼働監視で「勤務開始前」に出る |
| 9 | worker（看護師 or 医師） | worker-app | 本日 / 勤務予定 で勤務確認 | アプリ内リマインドカードと勤務前確認ブロックが出る |
| 10 | worker | worker-app | 「勤務開始（チェックイン）」 | `assignment.status` が `checked_in` |
| 11 | worker | worker-app | 「勤務終了（チェックアウト）」 | `checked_out` |
| 12 | worker | worker-app | 「勤務完了を報告する」 | `completion_reported` |
| 13 | facility_admin | dashboard | 勤務確定・稼働 → 「完了確定」 | `completion_confirmed` |
| 14 | neco_admin | neco-console | 確定勤務・稼働状況 → 「請求書を作成」 → 送信 | `invoices` に新規発行 |
| 15 | 全ロール | neco-console | タイムライン・監査ログ で操作履歴を確認 | proposal/assignment/invoice の各 `action` が時系列で表示 |

### 3.1 既存 DEMO データを使う場合の最短経路
時間がない場合は、既に `facility_accepted` まで進んだ `PR-DEMO-0003 / AS-DEMO-0001` を使い、
**ステップ 9〜15** だけを worker（看護師）で実施することで、稼働〜完了〜請求の流れを 5 分程度で体験可能。

---

## 4. 期待結果（成功条件）

### 4.1 各画面の動作
- [ ] alliance-dashboard：KPI 8枚、施設別ランキング、職種別不足、充足率テーブル、夜勤・オンコール未充足、AI配置支援パネル が描画
- [ ] dashboard：KPI 6枚、対応が必要な事項、勤務枠管理、配置候補、勤務確定・稼働、請求・実績 が描画
- [ ] neco-console：稼働監視（本日対応ToDo / 滞留アラート / 状態別カテゴリ）、左タブ4種、右パネルの要件確認チェックリスト・次アクション・候補者ランキング・提案・確定アサイン・タイムライン・AI配置支援
- [ ] worker-app：本日／勤務予定／医療者プロフィール の3タブ、アプリ内リマインドカード、勤務前確認ブロック

### 4.2 状態遷移
- [ ] 各ステータス遷移ボタン押下時に、トーストで成功表示
- [ ] DB 上で `staffing_requests.status` / `proposals.status` / `assignments.status` が更新される
- [ ] `activity_log` に `*.status` のレコードが追加される

### 4.3 RLS 制御
- [ ] 別組織の facility_admin で開いた場合、当該組織の SR/PR/AS/IN は見えない
- [ ] worker で他者のアサインが見えない
- [ ] 想定外ロールでの API が 401/403/0件 を返す

### 4.4 既知の制限
- 「条件確認を依頼」ボタンは現状トースト案内のみ（DB 変更なし）
- 勤務機会セクション（worker-app）は将来実装予定（disabled）
- AI配置支援パネルはルールベースのプレビュー
- mock mode 由来の状態（disputed 等）はライブDBで再現するには別途 DB 操作が必要

---

## 5. ロールバック・クリーンアップ

### 5.1 デモデータ削除
`docs/LIVE_DEMO_SEED_PLAN.md` の「削除（ロールバック）手順」セクションをコピーして SQL Editor で実行。

### 5.2 Auth ユーザー削除
Supabase ダッシュボード → Authentication → ユーザー一覧から `demo-*@mitas-demo.example` を個別削除。
`user_roles` は CASCADE で自動削除されるが、念のため SELECT で確認。

### 5.3 開発中に作成された動的データの削除
`SR-DEMO-` `PR-DEMO-` `AS-DEMO-` プレフィックスを使っていない、スモークテスト中に動的に作成された勤務枠・提案・アサイン・請求書がある場合は、`request_number` などで特定して個別に削除。

```sql
-- 例：今日作成された請求書を確認
SELECT id, invoice_number, organization_id, total, status, created_at
FROM invoices
WHERE created_at >= CURRENT_DATE
ORDER BY created_at DESC;
```

### 5.4 既存テスト環境への影響確認
- 他の開発者が同じ Supabase プロジェクトを使っている場合、デモ実行前に通知
- 削除後、`db/seeds/0003_live_demo_seed.sql` を再投入できる状態であることを確認

---

## 6. 既知のリスクと注意点

| リスク | 対策 |
|---|---|
| 実在の医療機関名と酷似した DEMO 名称 | 投入前に `organizations.name` を必ず「（Mitas Demo）」付きにする |
| 患者情報の誤入力 | スモークテスト中も患者氏名・診療内容は入力しない |
| メール送信トリガー | 現状 Mitas は外部メール送信を行わないが、今後追加した場合は本番ユーザーに送信されないよう Auth ユーザーは `*.example` ドメイン限定 |
| 課金・有料機能の誤操作 | 該当機能は現状なし。導入時は有料 API キー（外部 AI 等）を本番デモから外す |
| RLS の抜け漏れ | `docs/RLS_CHECKLIST.md` 全項目を最低 1 度チェック |
| 共同作業者への影響 | `claude/*` ブランチで運用、デモ前後に Slack/メールで通知 |
| Supabase プロジェクト混在 | フロントの `window.__SUPABASE_URL__` と Netlify の `SUPABASE_URL` が **同じプロジェクト** を指していること |

---

## 7. ライブテスト後のレポート

スモークテストが完了したら、以下を控えてください（共有先：プロダクトオーナー / Neco 運用責任者）。

- 実施日時
- 実施者
- 実施した手順番号（3 のうち何を実施したか）
- 失敗した項目と再現手順
- 想定と異なる挙動（例：API レスポンスが遅い、状態遷移が拒否された 等）
- DEMO データの削除完了時刻

---

## 8. 関連ドキュメント

- `docs/SMOKE_TEST.md` — Mock mode 中心の手動スモークテスト
- `docs/LIVE_DEMO_SEED_PLAN.md` — 本書で使うフィクションデータの設計と削除手順
- `docs/DEMO_SCENARIO.md` — 5分版／15分版のデモ進行
- `docs/RLS_CHECKLIST.md` — Live 環境での権限確認
- `db/seeds/0003_live_demo_seed.sql` — 本書で使うデモシード SQL
