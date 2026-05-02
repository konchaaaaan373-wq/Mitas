# Mitas for Alliance — Follow-up Checklist（残課題チェックリスト）

2026-05-02 の Live スモークテスト（Conditional Pass）で **未確認のまま残ったフロー** を整理した checklist です。
本書のチェックを順次埋めることで Conditional Pass → Pass を目指します。

実施するごとに該当行に [✓] を付け、結果や所感を「メモ」欄に追記してください。
新規バグが出たら別途 Issue / `docs/results/` 配下に新しい結果ファイルを作成して紐付けます。

---

## 1. worker（看護師、worker2）フロー

worker1（医師）で End-to-End 完走済みだが、worker2（看護師）側からの flow は未実施。

| 項目 | 想定 | 結果 | メモ |
|---|---|---|---|
| `konchaaaaan373+mitas-worker2@gmail.com` でログイン → `/worker-app.html` 自動遷移 | Pass 想定 | [ ] | |
| 「医療者プロフィール」タブで佐藤 美咲（DEMO）が表示 | 専門「訪問看護」、経験 7 年、東京都・埼玉県 | [ ] | |
| 「勤務可能時間」セクションに 土曜・日曜 10:00–18:00 が表示 | seed で投入済み | [ ] | |
| 「資格書類」セクションに 看護師免許（DEMO）が verified 状態で表示 | seed で投入済み | [ ] | |
| 「Neco確認状況」セクションに 資格確認完了が表示 | 集計値 1/1 件 verified | [ ] | |
| 「勤務機会の案内を受け取る」トグルが ON で「オファー受付中」表示 | seed で `is_available_for_offers=true` | [ ] | |
| 本日／勤務予定タブで AS-DEMO-0001 が **見えない** こと | AS-DEMO-0001 は worker1 に紐付くため、RLS で worker2 には見えないはず | [ ] | RLS 確認の重要項目 |
| 勤務予定タブの末尾に「勤務機会のご相談（将来実装予定）」セクションが表示 | 全 worker 共通 | [ ] | |

> **重要**：もし AS-DEMO-0001 が worker2 に見えてしまったら、RLS の `assignments_select_role` ポリシーに不備がある可能性。即座に Issue 化すること。

---

## 2. 新規勤務枠登録から始めるフロー

DEMO シードで前進済みの SR-DEMO-* は使わず、本当に空の状態から新規 request を投入してフルフローを通す。

| 項目 | 想定 | 結果 | メモ |
|---|---|---|---|
| facility_admin（中央病院）で「新しい勤務枠を登録」モーダルを開く | `/dashboard.html` 上部のボタン | [ ] | |
| 構造化入力補助（想定患者数 / 業務範囲 / バックアップ体制 / 電子カルテ / 集合場所・持ち物 / 注意事項）を一通り入力 | 全フィールド可視 | [ ] | |
| 「勤務枠を登録」ボタンで POST → 「受け付けました」モーダル | `submitted` で DB に投入 | [ ] | |
| neco_admin で「新規依頼」タブに新しい行が表示 | 経過日数 0 日 | [ ] | |
| 状態遷移ボタンで `submitted → under_review → accepted → proposing` | 各遷移で activity_log 追加 | [ ] | |
| 候補者ランキングから提案作成 → 5 アクション全部押下 | created → worker_contacted → worker_accepted → proposed_to_facility | [ ] | |
| facility_admin で承認 → facility_accepted | proposal status 切替、ヒント文も切替 | [ ] | |
| neco_admin で「勤務確定を作成」モーダル → 入力検証ブロック動作 | 必要項目欠如時に送信 disable | [ ] | |
| assignment 作成 → 通常通り稼働ライフサイクル → 請求書まで | End-to-End | [ ] | |
| 全段階の activity_log がタイムラインに actor_role 付きで時系列表示 | 修正版 logActivity が機能 | [ ] | |

---

## 3. 中央病院 vs 訪問看護のデータ独立性（RLS 検証）

組織横断で他施設のデータが見えないことを確認。

| 項目 | 想定 | 結果 | メモ |
|---|---|---|---|
| facility1（中央病院）で `/dashboard.html` を開く | SR-DEMO-0001 / 0003 のみ表示、SR-DEMO-0002 は見えない | [ ] | |
| 同じく「配置候補」タブで自施設宛 proposal のみ表示 | PR-DEMO-0002（中央病院宛）のみ | [ ] | |
| 同じく「勤務確定・稼働」タブで自施設の assignment のみ | AS-DEMO-0001 のみ | [ ] | |
| 同じく「請求・実績」タブで自施設の請求のみ | テスト中に作成した中央病院宛 invoice のみ | [ ] | |
| facility2（訪問看護）で `/dashboard.html` を開く | SR-DEMO-0002 のみ表示、SR-DEMO-0001 / 0003 は見えない | [ ] | |
| 同じく proposal は PR-DEMO-0001（訪問看護宛）のみ | | [ ] | |
| facility1 で組織情報設定画面を開いて facility2 の組織 ID を打ち込んで取得を試みる | API が 403 / 0 件を返す | [ ] | RLS_CHECKLIST.md 5.1 と同等 |
| 直接 PostgREST `/rest/v1/staffing_requests?select=*` を facility1 トークンで叩く | 自組織のみ返る | [ ] | DevTools Network 観察 |

---

## 4. alliance-dashboard KPI 表示

alliance_admin でアクセスし、連携法人全体の KPI が読み込めることを確認。

| 項目 | 想定 | 結果 | メモ |
|---|---|---|---|
| `konchaaaaan373+mitas-alliance@gmail.com` でログイン → `/alliance-dashboard.html` 自動遷移 | ロール別自動遷移 | [ ] | |
| KPI カード 8 枚が読み込まれる | 緊急未充足枠／未充足勤務枠／未充足人数／30日以内充足／進行中稼働／紛争・確認中／稼働可能医療者／期限間近資格確認 | [ ] | |
| 「未充足勤務枠が多い施設」ランキング表示 | `v_unfilled_requests_summary` ビュー | [ ] | DB ビューが投入済みか要確認 |
| 「職種別の人材不足」バーチャート表示 | `v_shortage_by_specialty` ビュー | [ ] | 同上 |
| 「充足率（過去90日・施設×職種）」テーブル表示 | `v_fill_rate` ビュー | [ ] | 同上 |
| 「夜勤・オンコールの未充足」テーブル表示 | `v_night_duty_gaps` ビュー | [ ] | 同上 |
| 「AI配置支援（将来実装予定）」セクション表示 | 静的テキスト | [ ] | |
| RLS：alliance_admin が個人情報（worker_profiles 詳細）を直接取得できない | 403 / 集計ビューのみ閲覧可 | [ ] | 重要 |

> ビュー（`v_*`）が DB に存在しないと KPI が空になる。`db/migrations/9999_all_in_one_setup.sql` でビューが定義されているか確認すること。

---

## 5. request.status の自動進行

DB トリガーで request が assignment ライフサイクルと連動して進む（または進まない）ことを検証。

| 項目 | 想定 | 結果 | メモ |
|---|---|---|---|
| assignment を `confirmed` で作成した直後の request.status | `proposing → fully_assigned` または `partially_assigned`（headcount 次第）に自動進行することを期待 | [ ] | DB トリガー `tg_assignments_after_*` の有無を要確認 |
| すべての assignment が `completion_confirmed` になった後の request.status | `confirmed` に進む（または neco_admin が手動で進める仕様か） | [ ] | |
| invoice 作成時に request.status が `invoiced` に進むか | client 側か DB トリガー | [ ] | |
| 期待通りに進まない場合は「neco_admin が手動で進める仕様」と運用ドキュメントに明記 | OR DB トリガー追加 | [ ] | 仕様化／実装の選択 |

> 自動進行が **無い** 場合、neco-console から手動で「状態遷移」ボタンを押して進めることになる。本セッション中、SR-DEMO-0003 を手動で `fully_assigned` に進めた跡があり、これは仕様確認の必要あり。

---

## 6. mock mode 全画面リグレッション

`window.__SUPABASE_URL__` を `YOUR_PROJECT_xxx` に書き換えた状態で、以下を確認。

| 画面 | 確認項目 | 結果 | メモ |
|---|---|---|---|
| `/worker-app.html` | mock バナー表示／本日アサインカード表示／タブ切替／プロフィールに mock データ | [ ] | |
| `/dashboard.html` | mock auth スキップ／KPI 6 枚／対応事項通知／勤務枠管理／配置候補／勤務確定・稼働 | [ ] | 本 PR で mock スキップ追加 |
| `/neco-console.html` | 稼働監視／本日対応ToDo／滞留アラート／勤務枠依頼一覧（4 タブ）／詳細パネル／タイムライン | [ ] | |
| `/alliance-dashboard.html` | KPI 8 枚／施設別ランキング／職種別不足／充足率／夜勤・オンコール未充足 | [ ] | |
| 4 画面とも Console エラーなし | `Identifier 'supabase' has already been declared` のような lexical エラーが出ない | [ ] | |
| 4 画面とも Network タブで失敗（4xx / 5xx）リクエストなし | mock fallback が機能 | [ ] | |

---

## 7. ブラウザ互換性

主要ブラウザで動作することを確認。

| ブラウザ | 確認項目 | 結果 | メモ |
|---|---|---|---|
| Chrome（最新） | 全画面 | [ ] | 本セッションで確認済 |
| Edge（最新） | 全画面 | [ ] | |
| Safari（最新、Mac） | 全画面 | [ ] | webkit 由来の問題が出やすい |
| Safari（iOS） | worker-app（モバイル） | [ ] | チェックイン時 GPS 動作 |
| Firefox（最新） | 全画面 | [ ] | |

---

## 8. 軽微な UI / UX

優先度低だが時間あれば確認。

| 項目 | 想定 | 結果 | メモ |
|---|---|---|---|
| 「条件確認を依頼」ボタン押下 | 現状はトースト案内のみ。専用フォーム未実装。仕様明記 or 実装決定が必要 | [ ] | |
| 勤務機会セクション（worker-app）のクリック | 現状は disabled。文言「将来実装予定」が表示される | [ ] | |
| AI配置支援パネル（neco-console）のドラフトコピー | 「本文をコピー」ボタンでクリップボードに入る | [ ] | |
| キーボードショートカット（neco-console） | `1〜4` でタブ切替、`/` で検索フォーカス、`?` でヘルプ表示 | [ ] | |
| 各画面のレスポンシブ動作 | 1024px / 768px / 480px で崩れない | [ ] | |

---

## 完了基準

- 1〜5 すべての項目が [✓] になり、新規 High issue が無い → **Pass** 判定
- 一部 [ ] が残るが High issue が無い → **Conditional Pass** 維持
- High issue が出た場合 → 個別 PR で修正 → 該当項目を再テスト

確認結果は `docs/results/LIVE_SMOKE_TEST_RESULT_<YYYYMMDD>.md` に蓄積してください。

---

## 関連ドキュメント

- `docs/SMOKE_TEST.md` — Mock mode 中心のスモークテスト
- `docs/LIVE_SMOKE_TEST.md` — Live 環境のスモークテスト
- `docs/LIVE_PREFLIGHT_CHECKLIST.md` — Live テスト直前のチェック
- `docs/LIVE_DEMO_SEED_PLAN.md` — デモシード設計
- `docs/RLS_CHECKLIST.md` — Live 環境での権限確認
- `docs/results/LIVE_SMOKE_TEST_RESULT_20260502.md` — 直近の実施結果（Conditional Pass）
