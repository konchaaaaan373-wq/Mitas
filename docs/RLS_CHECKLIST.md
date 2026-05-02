# Mitas for Alliance Permission / RLS Checklist

本書は、Mitas for Alliance の **Row Level Security (RLS)・ロール権限** が想定通り動いていることを手動で確認するためのチェックリストです。

リリース前・大規模変更後・新しいテーブル追加時に流してください。
所要時間：30〜60分。

---

## 0. 前提

- Supabase ダッシュボードにアクセス可能
- 各ロールのテストユーザーが用意されている
- `db/migrations/` の RLS ポリシーが最新適用されている
- ブラウザの開発者ツール（Network タブ）でリクエスト／レスポンスを確認できる

ロール一覧：
| ロール | 用途 |
|---|---|
| `worker` | 医療者 |
| `facility_admin` | 施設管理者（自組織に紐づく） |
| `neco_admin` | Neco 運用者（全体管理） |
| `alliance_admin` | 連携法人責任者（閲覧中心） |

---

## 1. worker

### 1.1 自分のリソースのみ参照できる
- [ ] 自分の `worker_profiles` 1件のみ取得できる
- [ ] 他の医療者の `worker_profiles` は取得できない（403 / 0件）
- [ ] 自分宛の `assignments` のみ取得できる
- [ ] 他の医療者の `assignments` は取得できない
- [ ] 自分の `worker_credentials` のみ取得できる
- [ ] 他の医療者の `worker_credentials` は取得できない
- [ ] 自分の `worker_availability` のみ取得・更新できる

### 1.2 状態遷移の制限
- [ ] `assignments` を `checked_in` / `checked_out` / `completion_reported` / `disputed` に更新できる
- [ ] `assignments` を `completion_confirmed` に更新しようとすると拒否される（403 / 409）
- [ ] `proposals` の `facility_accepted` / `facility_declined` に更新できない
- [ ] `staffing_requests` を更新できない
- [ ] `invoices` を作成・更新できない

### 1.3 worker-app の画面挙動
- [ ] `/worker-app.html` を直接開ける
- [ ] `/dashboard.html` `/neco-console.html` `/alliance-dashboard.html` を直接開いた場合、API が 403 / 401 を返してデータが表示されない
- [ ] 「勤務開始（チェックイン）」「勤務終了（チェックアウト）」「勤務完了を報告する」「条件に問題あり（紛争を申告）」が動作する

---

## 2. facility_admin

### 2.1 自組織のリソースのみ参照できる
- [ ] 自組織の `staffing_requests` のみ取得できる
- [ ] 他施設の `staffing_requests` は取得できない（0件 / 403）
- [ ] 自組織宛の `proposals` のみ取得できる
- [ ] 他施設宛の `proposals` は取得できない
- [ ] 自組織の `assignments` のみ取得できる
- [ ] 他施設の `assignments` は取得できない
- [ ] 自組織の `invoices` のみ取得できる
- [ ] 他施設の `invoices` は取得できない

### 2.2 作成・更新の権限
- [ ] `staffing_requests` を作成できる（`organization_id` は自組織に固定される）
- [ ] 他組織の `organization_id` で `staffing_requests` を作成しようとすると拒否される
- [ ] `proposals` を作成できない（neco_admin 専用）
- [ ] 自組織宛の `proposals` を `facility_accepted` / `facility_declined` に更新できる
- [ ] 他施設宛の `proposals` を更新しようとすると拒否される
- [ ] 自組織の `assignments` を `completion_confirmed` / `disputed` に更新できる
- [ ] 自組織の `assignments` を勝手に作成できない（neco_admin 専用）
- [ ] 自組織以外の `invoices` を作成・更新できない

### 2.3 dashboard.html の画面挙動
- [ ] `/dashboard.html` を直接開ける
- [ ] `/neco-console.html` を直接開いた場合、状態遷移ボタンや提案作成 API が 403 を返す
- [ ] `/worker-app.html` `/alliance-dashboard.html` を直接開いた場合、対応データが表示されない
- [ ] 勤務枠登録モーダルから提出 → 自組織のリストに反映される
- [ ] 提案テーブルの「承認する」「条件確認を依頼」「見送る」が自組織の提案に対してのみ動作する

---

## 3. neco_admin

### 3.1 全体を管理できる
- [ ] 全組織の `staffing_requests` を取得できる
- [ ] 全組織の `proposals` を取得・作成・更新できる
- [ ] 全組織の `assignments` を取得・作成・更新できる
- [ ] 全組織の `invoices` を取得・作成できる
- [ ] 全組織の `worker_profiles` を取得できる（onboarding 用）
- [ ] 全組織の `worker_credentials` を取得・更新できる（資格確認）

### 3.2 状態遷移
- [ ] `staffing_requests` を `submitted → under_review → accepted → proposing → partially_assigned → fully_assigned → ...` に更新できる
- [ ] `proposals` を 5 アクション（`worker_contacted` / `worker_accepted` / `worker_declined` / `proposed_to_facility` / `withdrawn`）で更新できる
- [ ] `facility_accepted` の proposal から `assignments` を新規作成できる
- [ ] `assignments` の completion 関連状態を全て遷移できる
- [ ] `invoices` を draft → issued → paid に更新できる

### 3.3 neco-console.html の画面挙動
- [ ] `/neco-console.html` を直接開ける
- [ ] 稼働監視 / 本日対応ToDo / 対応期限・滞留アラート が読み込まれる
- [ ] 勤務枠詳細パネルの状態遷移ボタンが状態に応じて表示される
- [ ] 提案カードの 5 アクションボタンが現状ステータスに応じて出し分けされる
- [ ] facility_accepted の提案で「勤務確定を作成」ボタンが押せる
- [ ] activity_log タイムラインが表示される

---

## 4. alliance_admin

### 4.1 閲覧範囲
- [ ] 連携法人配下の組織の `staffing_requests` / `assignments` 集計（v_unfilled_requests_summary, v_fill_rate, v_shortage_by_specialty, v_night_duty_gaps）を閲覧できる
- [ ] 個別の `worker_profiles` 個人情報まではアクセスしない（集計ビューを介して閲覧）
- [ ] `proposals` `assignments` の詳細は必要に応じて閲覧（個人情報の更新権限は持たない）

### 4.2 編集権限の制限
- [ ] `staffing_requests` を新規作成できない（または自連携法人内にスコープ）
- [ ] `proposals` を作成・更新できない
- [ ] `assignments` を作成・更新できない
- [ ] `invoices` を作成・更新できない
- [ ] `worker_profiles` の個人情報を更新できない

### 4.3 alliance-dashboard.html の画面挙動
- [ ] `/alliance-dashboard.html` を直接開ける
- [ ] KPIカード／施設別ランキング／職種別不足／充足率／夜勤・オンコール未充足 が読み込まれる
- [ ] `/dashboard.html` `/neco-console.html` の編集系ボタンを押した場合、API が 403 を返す

---

## 5. 横断確認

### 5.1 直接 PostgREST アクセス
| URL | worker | facility_admin | neco_admin | alliance_admin |
|---|---|---|---|---|
| `/rest/v1/worker_profiles?select=*` | 自分のみ | RLS による許可範囲 | 全件 | 集計ビューのみ |
| `/rest/v1/staffing_requests?select=*` | 0件 | 自組織のみ | 全件 | 連携法人配下 |
| `/rest/v1/proposals?select=*` | 自分宛のみ | 自組織宛のみ | 全件 | 連携法人配下 |
| `/rest/v1/assignments?select=*` | 自分のみ | 自組織のみ | 全件 | 連携法人配下 |
| `/rest/v1/invoices?select=*` | 0件 | 自組織のみ | 全件 | 連携法人配下 |
| `/rest/v1/activity_log?select=*` | 0件 / 自分関連のみ | 自組織関連のみ | 全件 | 連携法人配下 |

### 5.2 Netlify Functions
| エンドポイント | 主要権限 | 備考 |
|---|---|---|
| `POST /api/v2/requests` | facility_admin | `organization_id` は自組織に紐付く |
| `PATCH /api/v2/requests/:id` | facility_admin / neco_admin | DBトリガーで状態遷移を検証 |
| `POST /api/v2/proposals` | neco_admin | facility_admin は不可 |
| `PATCH /api/v2/proposals/:id` | neco_admin / facility_admin（自組織のみ） | facility 側は `facility_accepted` / `facility_declined` のみ |
| `POST /api/v2/assignments` | neco_admin（RLS で限定） | proposal は `facility_accepted` 必須 |
| `PATCH /api/v2/assignments/:id` | worker / facility_admin / neco_admin | 各ロールの遷移範囲は DB トリガー |
| `POST /api/v2/invoices` | neco_admin | |

### 5.3 認証エラー時の挙動
- [ ] トークンなしで API 呼び出し → 401
- [ ] 期限切れトークン → 401
- [ ] 想定外ロールで `POST /api/v2/proposals` → 403 / 409 / RLS エラー
- [ ] 想定外ロールで `POST /api/v2/assignments` → 同上

---

## 6. 監査ログ

- [ ] `activity_log` には `actor_user_id` / `actor_role` / `action` / `entity_type` / `entity_id` / `organization_id` / `before` / `after` / `occurred_at` が記録される
- [ ] worker による check-in/out が `assignment.checked_in` / `assignment.checked_out` として残る
- [ ] facility_admin の `completion_confirmed` が `assignment.completion_confirmed` として残る
- [ ] neco_admin による proposal status 変更が `proposal.<新状態>` として残る
- [ ] neco_admin による assignment 作成が `assignment.created` として残る

---

## 7. RLS ポリシー名（参考）

主要なポリシー名は以下です。実装は `db/migrations/0006_phase1_rls.sql` 等を参照してください。

- `worker_profiles_select_self`
- `worker_profiles_update_self`
- `worker_credentials_select_self`
- `staffing_requests_select_facility`
- `staffing_requests_insert_facility`
- `proposals_select_role`
- `proposals_insert_neco`
- `proposals_update_role`
- `assignments_select_role`
- `assignments_insert_neco`
- `assignments_update_role`
- `invoices_select_facility_or_neco`
- `invoices_insert_neco`
- `activity_log_select_role`

ポリシー名・実装が変わった場合は、本書の参照箇所を更新してください。

---

## 8. 確認後の取り扱い

- 想定外の挙動が見つかった場合は、Issue / 修正 PR を作成してください
- 「想定外に閲覧できた」事象は **個人情報漏えいリスク** として最優先で扱ってください
- リリース前は必ず本書の **2 / 3 / 5.1** を最低限実施してください
