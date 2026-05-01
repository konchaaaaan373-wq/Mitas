# Mitas for Alliance — Live スモークテスト結果記録テンプレート

本書は、Live 環境で `docs/LIVE_SMOKE_TEST.md` を実施した結果を記録するための **テンプレート** です。

使い方：
1. 本ファイルを `docs/results/LIVE_SMOKE_<YYYYMMDD>_<initial>.md` などにコピー
2. テスト中に随時記入
3. 終了後、プロダクトオーナー・Neco 運用責任者に共有
4. Fail 項目は Issue / 修正 PR を作成して紐付け

---

## 1. テストメタ情報

| 項目 | 記入内容 |
|---|---|
| テスト実施日 | YYYY-MM-DD HH:MM |
| 実施終了 | YYYY-MM-DD HH:MM |
| 実施者 | 氏名（ロール／所属） |
| 実施環境 | 例：本番 `https://mitas.necofindjob.com` ／ ステージング 等 |
| Git ブランチ | 例：`claude/mitas-alliance-rebrand-lfpVX` |
| Git commit | 例：`abcdef0123456789` |
| Netlify deploy ID | 例：`https://app.netlify.com/.../deploys/...` |
| Supabase プロジェクト | 例：`<project-ref>.supabase.co` |
| 適用シード | 例：`db/seeds/0003_live_demo_seed.sql` |
| Mock mode 状態 | Disabled |
| 備考 | 環境特有の注意点／同時開催イベント／関係者通知の有無 等 |

---

## 2. テストユーザー

実施時に使った Auth ユーザーと UUID を控えてください。

| ロール | メール | UUID | display_name |
|---|---|---|---|
| neco_admin | demo-neco@mitas-demo.example | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | 【DEMO】Neco運用 担当 |
| alliance_admin | demo-alliance@mitas-demo.example | | 【DEMO】医療連携 担当 |
| facility_admin（デモ中央病院） | demo-facility-1@mitas-demo.example | | 【DEMO】デモ中央病院 採用担当 |
| facility_admin（デモ訪問看護） | demo-facility-2@mitas-demo.example | | 【DEMO】デモ訪問看護 管理者 |
| worker（医師） | demo-doctor@mitas-demo.example | | 【DEMO】田中 健太郎 |
| worker（看護師） | demo-nurse@mitas-demo.example | | 【DEMO】佐藤 美咲 |

---

## 3. Preflight チェック結果

`docs/LIVE_PREFLIGHT_CHECKLIST.md` を実施した結果を記録します。

| セクション | 結果 | 補足 |
|---|---|---|
| A. デプロイと配信 | ✅／❌／NA | |
| B. Netlify 環境変数 | ✅／❌／NA | |
| C. フロントの Supabase 設定 | ✅／❌／NA | |
| D. Supabase セットアップ | ✅／❌／NA | |
| E. データ安全性の最終確認 | ✅／❌／NA | |
| F. アプリ動作モード | ✅／❌／NA | |
| G. ログイン確認（最小） | ✅／❌／NA | |
| H. 通知・連絡 | ✅／❌／NA | |
| I. テスト後アクション準備 | ✅／❌／NA | |

> どれか ❌ がある場合は、本テストを中断してください。

---

## 4. ログインチェック

| ロール | 開いた URL | 結果 | 確認内容 | 備考 |
|---|---|---|---|---|
| neco_admin | `/login.html` → `/neco-console.html` | Pass / Fail | 配置マッチングコンソール表示／稼働監視ロード | |
| alliance_admin | `/login.html` → `/alliance-dashboard.html` | Pass / Fail | KPI 8枚読み込み | |
| facility_admin（デモ中央病院） | `/login.html` → `/dashboard.html` | Pass / Fail | SR-DEMO-0001 / 0003 のみ見える | |
| facility_admin（デモ訪問看護） | `/login.html` → `/dashboard.html` | Pass / Fail | SR-DEMO-0002 のみ見える | |
| worker（医師） | `/login.html` → `/worker-app.html` | Pass / Fail | アプリヒーロー表示 | |
| worker（看護師） | `/login.html` → `/worker-app.html` | Pass / Fail | AS-DEMO-0001 が本日／勤務予定に表示 | |

---

## 5. End-to-End ワークフロー結果

`docs/LIVE_SMOKE_TEST.md` 第3章の 15 ステップを実施した結果。

| # | ロール | 操作 | 期待結果 | 結果 | スクリーンショット | 備考・観察事項 |
|---|---|---|---|---|---|---|
| 1 | facility_admin（中央病院） | 勤務枠登録（モーダル） | 受付モーダルが出る／DBに INSERT | Pass / Fail | `screenshots/01_*.png` | |
| 2 | neco_admin | 状態遷移 `submitted→under_review→accepted` | 各遷移トースト成功／activity_log 追加 | Pass / Fail | | |
| 3 | neco_admin | 提案作成（モーダル） | proposal `created` 追加 | Pass / Fail | | |
| 4 | neco_admin | 「打診済みにする」 | proposal_status=worker_contacted | Pass / Fail | | |
| 5 | neco_admin | 「医療者承諾にする」 | proposal_status=worker_accepted | Pass / Fail | | |
| 6 | neco_admin | 「施設へ提案する」 | proposal_status=proposed_to_facility | Pass / Fail | | |
| 7 | facility_admin | 「承認する」 | proposal_status=facility_accepted／ヒント切替 | Pass / Fail | | |
| 8 | neco_admin | 「勤務確定を作成」（モーダル） | assignment 作成／稼働監視に表示 | Pass / Fail | | |
| 9 | worker | worker-app で勤務確認 | リマインドカード／勤務前確認表示 | Pass / Fail | | |
| 10 | worker | チェックイン | assignment.status=checked_in | Pass / Fail | | |
| 11 | worker | チェックアウト | assignment.status=checked_out | Pass / Fail | | |
| 12 | worker | 完了報告 | assignment.status=completion_reported | Pass / Fail | | |
| 13 | facility_admin | 「完了確定」 | assignment.status=completion_confirmed | Pass / Fail | | |
| 14 | neco_admin | 請求書作成（モーダル） | invoice INSERT／成功トースト | Pass / Fail | | |
| 15 | 全ロール | activity_log タイムライン確認 | 上記すべての action が時系列で並ぶ | Pass / Fail | | |

### 5.1 短縮経路（DEMO データ利用）
時間がない場合の経路（PR-DEMO-0003 / AS-DEMO-0001 を使用）。

| # | ロール | 操作 | 結果 | 備考 |
|---|---|---|---|---|
| 9 | worker（看護師） | AS-DEMO-0001 を確認 | Pass / Fail | |
| 10 | worker（看護師） | チェックイン | Pass / Fail | |
| 11 | worker（看護師） | チェックアウト | Pass / Fail | |
| 12 | worker（看護師） | 完了報告 | Pass / Fail | |
| 13 | facility_admin（みどり訪問看護） | 完了確定 | Pass / Fail | |
| 14 | neco_admin | 請求書作成 | Pass / Fail | |
| 15 | 全ロール | タイムライン確認 | Pass / Fail | |

---

## 6. 期待結果サマリ（成功条件）

| 区分 | 項目 | 結果 | 備考 |
|---|---|---|---|
| 画面 | alliance-dashboard 全要素描画 | Pass / Fail | |
| 画面 | dashboard 全要素描画 | Pass / Fail | |
| 画面 | neco-console 全要素描画（稼働監視・滞留アラート 含む） | Pass / Fail | |
| 画面 | worker-app 全要素描画（リマインド・勤務前確認 含む） | Pass / Fail | |
| 状態遷移 | 全ステータス遷移ボタンが想定通り | Pass / Fail | |
| 状態遷移 | DB 上の status が更新される | Pass / Fail | |
| 状態遷移 | activity_log に対応 action が追加される | Pass / Fail | |
| RLS | 別組織 facility_admin に他組織データが見えない | Pass / Fail | |
| RLS | worker に他者アサインが見えない | Pass / Fail | |
| RLS | 想定外ロールでの API が 401/403/0件 | Pass / Fail | |

---

## 7. 検出された問題

### 7.1 RLS の問題

| ID | 観察箇所 | 想定 | 実際 | 再現手順 | 重要度 | 対応者 | Issue/PR |
|---|---|---|---|---|---|---|---|
| RLS-001 | | | | | High / Mid / Low | | |
| RLS-002 | | | | | | | |

### 7.2 状態遷移の問題

| ID | 操作 | 期待状態遷移 | 実際の挙動 | エラーメッセージ | 重要度 | 対応者 | Issue/PR |
|---|---|---|---|---|---|---|---|
| ST-001 | | | | | | | |

### 7.3 UI / UX の問題

| ID | 画面 | 観察 | 期待 | スクリーンショット | 重要度 | 対応者 | Issue/PR |
|---|---|---|---|---|---|---|---|
| UI-001 | | | | | | | |

### 7.4 その他（パフォーマンス・通信エラー等）

| ID | 観察箇所 | 内容 | 重要度 | 対応者 | Issue/PR |
|---|---|---|---|---|---|
| ETC-001 | | | | | |

---

## 8. エラーメッセージ・ログ

### 8.1 ブラウザ Console エラー
```
（ペースト箇所）
```

### 8.2 Netlify Functions ログ（必要に応じて）
```
（ペースト箇所）
```

### 8.3 Supabase ログ（必要に応じて）
```
（ペースト箇所）
```

---

## 9. スクリーンショット

スクリーンショットの保存場所と一覧を控えてください。

| ファイル | 内容 |
|---|---|
| `screenshots/01_create_request.png` | facility_admin が勤務枠登録 |
| `screenshots/02_neco_state_transition.png` | neco_admin の状態遷移 |
| ... | |

---

## 10. ロールバック・クリーンアップ

| 項目 | 結果 | 実施時刻 | 備考 |
|---|---|---|---|
| 動的に作成した勤務枠/提案/アサインの削除 | Done / Skipped | YYYY-MM-DD HH:MM | |
| `docs/LIVE_DEMO_SEED_PLAN.md` 4節の削除 SQL 実行 | Done / Skipped | YYYY-MM-DD HH:MM | |
| Supabase Auth デモユーザー削除 | Done / Skipped | YYYY-MM-DD HH:MM | |
| 削除確認 SQL（残件数=0） | Done / Skipped | YYYY-MM-DD HH:MM | |

削除確認 SQL（参考）：
```sql
SELECT
  (SELECT COUNT(*) FROM staffing_requests WHERE request_number LIKE 'SR-DEMO-%') AS sr,
  (SELECT COUNT(*) FROM proposals          WHERE proposal_number LIKE 'PR-DEMO-%') AS pr,
  (SELECT COUNT(*) FROM assignments        WHERE assignment_number LIKE 'AS-DEMO-%') AS asg,
  (SELECT COUNT(*) FROM invoices           WHERE invoice_number LIKE 'IN-DEMO-%') AS inv,
  (SELECT COUNT(*) FROM worker_profiles    WHERE full_name LIKE '%（DEMO）') AS wp;
```

---

## 11. 再テスト

修正後の再テスト結果を残します。

| 元の問題 ID | 再テスト日 | 再テスト実施者 | 結果 | 備考 |
|---|---|---|---|---|
| RLS-001 | YYYY-MM-DD | | Pass / Fail | |
| ST-001 | | | | |
| UI-001 | | | | |

---

## 12. 総合判定

- [ ] **Pass**：すべての必須項目が成功し、本番運用フェーズに進める
- [ ] **Conditional Pass**：High 重要度の問題はないが、Mid/Low の改善項目あり（→ Issue 化）
- [ ] **Fail**：High 重要度の問題があり、修正後に再テストが必要

### 12.1 サマリコメント
（テスト全体の所感・次の優先タスク・運用上の注意点を簡潔に）

### 12.2 次のアクション
1.
2.
3.

---

## 13. 共有先・承認

| 役割 | 氏名 | 確認日 | 署名／コメント |
|---|---|---|---|
| 実施者 | | | |
| プロダクトオーナー | | | |
| Neco 運用責任者 | | | |
| インフラ担当 | | | |

---

## 関連ドキュメント

- `docs/LIVE_PREFLIGHT_CHECKLIST.md` — 本テスト直前のチェック
- `docs/LIVE_SMOKE_TEST.md` — 本テスト本体
- `docs/LIVE_DEMO_SEED_PLAN.md` — デモシード設計と削除 SQL
- `docs/SMOKE_TEST.md` — Mock mode 中心の手動スモークテスト
- `docs/RLS_CHECKLIST.md` — Live 環境での権限確認
- `db/seeds/0003_live_demo_seed.sql` — デモシード SQL
