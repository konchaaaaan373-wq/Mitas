# Mitas for Alliance スモークテスト

本書は、Mitas for Alliance の MVP に対する **手動スモークテスト** 手順をまとめたものです。
リリース前・大きな変更後・デモ準備時に、本書の手順を一度通して動作確認してください。

新機能を追加するためのテストではなく、**主要フロー全体が壊れていないこと** を素早く確認するためのチェックリストです。

---

## 1. 前提環境

### 1.1 推奨環境
- ブラウザ：最新版 Chrome / Edge / Safari
- 解像度：1280×800 以上（モバイル確認は別途 worker-app を 375 幅で）
- ネットワーク：通常のオフィス環境
- 時刻：端末時刻が正しい（リマインド・経過時間計算に影響）

### 1.2 アプリの動作モード
| モード | 切替方法 | 備考 |
|---|---|---|
| Mock mode | Supabase 環境変数を未設定 / `YOUR_PROJECT` のままにする | 認証なしで全画面が動く。デモに最適 |
| Live mode | `SUPABASE_URL` / `SUPABASE_ANON_KEY` を設定し、各 HTML 上部の `window.__SUPABASE_URL__` を反映 | ログインが必要 |

スモークテストは **両モード** で軽く確認することを推奨します。

### 1.3 主要URL
| 画面 | パス | ロール |
|---|---|---|
| 公開トップ | `/` （`/service.html` にリライト） | 全ユーザー |
| ログイン | `/login.html` | 全ユーザー |
| 連携法人ダッシュボード | `/alliance-dashboard.html` | alliance_admin |
| 配置マッチングコンソール | `/neco-console.html` | neco_admin |
| 施設管理ダッシュボード | `/dashboard.html` | facility_admin |
| 医療者向け勤務機会アプリ | `/worker-app.html` | worker |

---

## 2. テストユーザー

`db/seeds/0002_workflow_demo.sql` で投入される想定 UUID と一致させてください。
Supabase ダッシュボードで、以下の固定 UUID で auth.users を作成してから seed を流すと便利です。

| ロール | 想定 UUID | 表示名 |
|---|---|---|
| neco_admin | `11111111-1111-1111-1111-111111111111` | Neco運用 太郎 |
| alliance_admin | `22222222-2222-2222-2222-222222222222` | 医療連携 花子 |
| facility_admin (さくら病院) | `33333333-3333-3333-3333-333333333333` | さくら病院 採用担当 |
| facility_admin (みどり訪問看護) | `44444444-4444-4444-4444-444444444444` | みどり訪問看護 管理者 |
| worker (医師) | `55555555-5555-5555-5555-555555555555` | 山田 健司 |
| worker (看護師) | `66666666-6666-6666-6666-666666666666` | 鈴木 美咲 |

mock mode で確認する場合は、`/login.html` を経由せず各 URL を直接開いてください。

---

## 3. ロール別画面確認

### 3.1 facility_admin
1. `/dashboard.html` を開く
2. 上部に **人材需給サマリー** とKPIカード（未充足勤務枠／候補者提案中／承認待ち／今週の確定勤務／完了確認待ち／請求確認）が表示される
3. 「対応が必要な事項」通知センターが表示され、件数つきで項目が並ぶ
4. サイドバーに 人材需給／勤務枠管理／配置候補／勤務確定・稼働／対応事項／新規依頼／請求・実績／設定 が表示される
5. 「+ 新しい勤務枠を登録」ボタンを押下し、モーダルが開く
6. モーダル内の構造化入力補助（想定患者数 / 業務範囲 / バックアップ体制 / 電子カルテ / 集合場所・持ち物 / 注意事項）が動作する

### 3.2 worker
1. `/worker-app.html` を開く
2. 「医療専門職向け勤務機会アプリ」のヒーローテキストが表示される
3. 本日の勤務／勤務予定／プロフィール の3タブが下部ナビに表示される
4. アプリ内リマインドのカードが状況に応じて出る（明日の勤務 / 本日の勤務 / 勤務開始時刻が近づいています など）
5. 勤務予定カードに「次の対応」ピル（勤務開始時にチェックイン 等）が表示される
6. 勤務機会のご相談（将来実装予定）セクションが勤務予定タブの末尾に出る

### 3.3 neco_admin
1. `/neco-console.html` を開く
2. 上部に **稼働監視** セクションが表示される
3. 本日対応ToDo（7項目）／対応期限・滞留アラート／状態別カテゴリ が読み込まれる
4. 左カラムの勤務枠依頼タブ（新規依頼／要件確認／配置調整中／稼働・完了）が動く
5. 勤務枠カードに「次アクション：要件確認」などのラベルが表示される
6. 勤務枠を選択すると、右パネルに 要件確認チェックリスト・次アクション・医療者候補ランキング・提案済み候補・確定勤務・タイムライン・AI配置支援（将来実装予定）が描画される

### 3.4 alliance_admin
1. `/alliance-dashboard.html` を開く
2. ヘッダーに **Mitas for Alliance / 連携法人 人材需給ダッシュボード** が表示される
3. 「未充足勤務枠」「稼働可能医療者」など、KPIカード8枚が読み込まれる
4. 施設別ランキング・職種別不足・充足率テーブル・夜勤/オンコール未充足・AI配置支援（将来実装予定）が描画される

---

## 4. 主要状態遷移テスト（End-to-End）

以下は、1件の勤務枠が「依頼 → 提案 → 確定 → 稼働 → 完了 → 請求」へ進む一連のフローです。
mock mode では一部のサーバ状態遷移が「（モック）」表示で擬似的に進みます。Live mode では実DBを更新します。

### 手順
| # | ロール | 操作 | 期待結果 |
|---|---|---|---|
| 1 | facility_admin | `/dashboard.html` → 「+ 新しい勤務枠を登録」 → 勤務枠名・職種・必要人数・勤務開始予定・充足希望日を入力 → 送信 | 「勤務枠を受け付けました」モーダルが表示される |
| 2 | neco_admin | `/neco-console.html` 左タブ「新規依頼」で対象を選択 | 詳細パネルに 要件確認チェックリスト・次アクション「要件確認」が表示される |
| 2-1 | neco_admin | 状態遷移ボタンで `submitted → under_review → accepted` | 各遷移が「状態を…に変更しました」トーストで成功する |
| 3 | neco_admin | 「医療者候補ランキング」から候補医療者の「施設へ提案」ボタンを押下し、提案を作成（モーダル）| 提案済み候補リストに新しい提案カードが追加される |
| 4 | neco_admin | 提案カードの「打診済みにする」ボタン押下 | proposal_status が `worker_contacted` になる |
| 5 | neco_admin | 「医療者承諾にする」ボタン押下 | proposal_status が `worker_accepted` になる |
| 6 | neco_admin | 「施設へ提案する」ボタン押下 | proposal_status が `proposed_to_facility` になる |
| 7 | facility_admin | `/dashboard.html` → 配置候補 → 該当行の「承認する」 | proposal_status が `facility_accepted` に変わり、「Necoが勤務確定手続き中」が表示される |
| 8 | neco_admin | 提案カードの **「勤務確定を作成」** → 勤務開始予定／終了予定／時給 を確認 → 送信 | 「勤務確定を作成しました」トースト。確定勤務・稼働状況セクションに新しい assignment が追加される |
| 9 | worker | `/worker-app.html` → 本日の勤務 / 勤務予定 で確定勤務を確認 | アプリ内リマインドが「明日の勤務 / 本日の勤務」など状況に応じて出る |
| 10 | worker | 本日カードの **「勤務開始（チェックイン）」** ボタン押下 | assignment.status が `checked_in` になり、ガイダンスが「勤務中です」に変わる |
| 11 | worker | 「勤務終了（チェックアウト）」ボタン押下 | assignment.status が `checked_out` になり、リマインドが「完了報告のお願い」になる |
| 12 | worker | 「勤務完了を報告する」ボタン押下 | assignment.status が `completion_reported` になり、施設確認待ちの表示に変わる |
| 13 | facility_admin | `/dashboard.html` → 勤務確定・稼働 で対象行の **「完了確定」** | assignment.status が `completion_confirmed` に変わり、「完了確定済み」の表示になる |
| 14 | neco_admin | `/neco-console.html` 詳細パネル → 確定勤務・稼働状況の **「請求書を作成」** → 発行日・支払期日・税率を確認 → 送信 | 請求書が作成され、トーストで成功表示 |
| 15 | 全ロール | `/neco-console.html` 詳細パネル下部の **タイムライン・監査ログ** 確認 | 上記操作が時系列で活動ログに記録されている |

### 補助確認
- `/neco-console.html` 上部の **稼働監視 → 対応期限・滞留アラート** に、未確定 / 提案待ち / 完了確認待ち などが表示されている
- `/dashboard.html` の通知センターに、経過時間付きの推奨文（「候補者提案から N時間経過しています…」など）が表示されている

---

## 5. 権限／RLS 確認

`docs/RLS_CHECKLIST.md` を参照してください。本スモークテストでは最低限以下を確認します。

- worker でログイン → `/dashboard.html` を直接開いた場合、自組織のデータが見えない／API が 403 になる
- facility_admin でログイン → `/neco-console.html` を直接開いた場合、状態遷移ボタンや提案作成ができない／API が 403 になる
- 他施設の facility_admin に切り替え → 自組織宛でない proposals / assignments / invoices が見えない

---

## 6. mock mode 確認

1. `window.__SUPABASE_URL__` を未設定または `YOUR_PROJECT` のままにする
2. 各画面を直接開く
3. 「モックモードで動作中」バナーが出ること（worker-app）
4. 一覧テーブルの最終行に「（モック）」と書かれること（neco-console / dashboard）
5. 主要状態（confirmed / checked_in / checked_out / completion_reported / completion_confirmed / disputed）が確定アサインに揃って見えること
6. 提案リストに created / worker_contacted / worker_accepted / worker_declined / proposed_to_facility / facility_accepted / facility_declined / withdrawn / expired が一通り見えること
7. 請求リストに draft / issued / paid / overdue が一通り見えること

---

## 7. 既知の注意点

- **mock mode の状態変更**: 一部の状態遷移はローカル state にのみ反映されます。リロードで初期状態に戻ります。
- **assignment_number の採番**: Live mode では `AS-{YYYY}-{NNNN}` を `like` クエリで連番採番。並列作成時は最終的な一意性は DB の UNIQUE 制約に依存します。
- **request の状態遷移**: DB トリガーが許可しない遷移はサーバ側で 409 を返します。クライアントの「状態遷移」ボタンが想定どおり 409 を返すかは Live mode で確認してください。
- **「条件確認を依頼」ボタン**: 現状は施設管理者の意図を Neco 担当に伝えるトースト案内のみです。専用フォームは未実装。
- **勤務機会セクション（worker-app）**: 将来実装予定。クリックは無効化されています。
- **AI配置支援**: ルールベースのプレビューのみ。外部 AI API は未接続。

---

## 8. 既存機能チェック（リグレッション）

リファクタや UI 変更を加えた後は、以下のリストを最後に流してください。

- [ ] 各ロールでログインできる
- [ ] 各ロールで該当画面のみアクセスできる
- [ ] facility_admin が勤務枠を作成できる
- [ ] neco_admin が状態遷移ボタンで request status を進められる
- [ ] neco_admin が提案を作成できる
- [ ] neco_admin が proposal_status を 5 つのアクションで進められる
- [ ] facility_admin が提案を承認・見送りできる
- [ ] neco_admin が `facility_accepted` から勤務確定を作成できる
- [ ] worker がチェックイン／チェックアウト／完了報告／紛争申告できる
- [ ] facility_admin が完了確定／確認事項申告できる
- [ ] neco_admin が請求書を作成できる
- [ ] activity_log タイムラインが表示される
- [ ] 稼働監視 / 滞留アラート / アプリ内リマインドが表示される
- [ ] mock mode で全画面が表示される（API なしでも崩れない）
