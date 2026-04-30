# MITAS

MITAS は、病院・訪問看護・介護事業所の急な欠員や人員要件不足に対して、要件整理から人材充足までを支援するサービスです。

## このリポジトリの位置づけ

- `_mitas-site/`: 公開サイトの静的ファイル
- `docs/`: 業務要件と運用ドキュメント
- `db/migrations/`: 初期スキーマとマイグレーション
- `db/seeds/`: 開発・検証用 seed データ
- `netlify/functions/`: Netlify Functions（API レイヤー）

## アーキテクチャ概要

MITAS は 4 ロールを区別する Phase 1 スキーマ（v2）で動作します。

- **facility_admin**：病院・施設の管理者
- **worker**：医師・看護師・療法士などの医療従事者
- **neco_admin**：Neco 社内オペレーター
- **alliance_admin**：地域連携責任者

認証は Supabase Auth（メール/パスワード）、認可は PostgreSQL の RLS で
4 ロール毎の閲覧範囲を強制します。状態遷移は DB トリガーで検証します。

### ロール別 UI

| 画面 | 想定ユーザー | 主な機能 |
|---|---|---|
| `dashboard.html` | facility_admin | 案件管理 / 候補者・提案確認 / アサイン管理 / 請求 / 通知センター |
| `worker-app.html` | worker | Today（チェックイン・完了報告）/ Schedule / Profile |
| `neco-console.html` | neco_admin | 依頼一覧 / 状態遷移 / 候補者抽出（マッチスコアリング）/ 提案作成 / 請求書作成 / 勤怠タイムライン |
| `alliance-dashboard.html` | alliance_admin | 地域KPI / 充足率 / 不足分布 |
| `login.html` | 全ロール | Supabase Auth ログイン（next リダイレクト対応） |

### v2 API（Netlify Functions）

| ルート | メソッド | 概要 |
|---|---|---|
| `/api/v2/requests` | GET / POST / PATCH | 人材依頼の CRUD（状態遷移 PATCH 込み） |
| `/api/v2/proposals` | GET / PATCH | 提案の閲覧・状態更新（POST はフロントから直接 PostgREST） |
| `/api/v2/assignments` | GET / PATCH | アサインの閲覧・状態更新（check-in / completion 等） |
| `/api/v2/invoices` | GET | 請求書の閲覧（POST はフロントから直接 PostgREST） |
| `/api/v2/dashboard/kpi` | GET | 地域KPI（alliance_admin / neco_admin のみ） |

不正な状態遷移（DB の SQLSTATE 22023）は HTTP 409 にマップされます。

## データベース方針

Mitas の DB は、業務を一気通貫で支える前提で設計しています。

- 問い合わせ受付（draft / submitted な依頼）
- 依頼の状態遷移（submitted → under_review → accepted → proposing → fully_assigned → in_progress → completion_pending → confirmed → invoiced → paid）
- 候補者プール管理（worker_profiles + worker_credentials + worker_availability）
- マッチング進捗（proposals）
- 確定アサインと勤怠（assignments + work_logs）
- 請求と入金（invoices + invoice_line_items）
- 全テーブル横断の監査ログ（activity_log）

詳細は以下を参照してください。

- `docs/MITAS_DB_REQUIREMENTS.md` — DB 要件定義
- `docs/DATABASE.md` — DB 設計・運用ガイド

## ローカルでの初期化

1. `.env.example` を `.env` にコピーして値を設定
2. Netlify / Supabase の接続情報を環境変数へ設定
3. マイグレーションを順に適用

```bash
psql "$NETLIFY_DATABASE_URL_UNPOOLED" -f db/migrations/0001_mitas_core.sql
psql "$NETLIFY_DATABASE_URL_UNPOOLED" -f db/migrations/0004_phase1_core_tables.sql
psql "$NETLIFY_DATABASE_URL_UNPOOLED" -f db/migrations/0005_phase1_state_machine.sql
psql "$NETLIFY_DATABASE_URL_UNPOOLED" -f db/migrations/0006_phase1_rls_policies.sql
psql "$NETLIFY_DATABASE_URL_UNPOOLED" -f db/migrations/0007_phase1_views.sql
```

4. 開発用データを投入する場合

```bash
psql "$NETLIFY_DATABASE_URL_UNPOOLED" -f db/seeds/0001_demo_seed.sql
```

## モックモード

`window.__SUPABASE_URL__` がプレースホルダー（`YOUR_PROJECT` を含む）の場合、
すべての画面（`dashboard.html` / `worker-app.html` / `neco-console.html` /
`alliance-dashboard.html`）が**モックモード**で動作し、固定のサンプルデータで
UI 確認ができます。状態遷移・提案作成・請求書作成などもクライアント側で
模擬されるので、Supabase 設定なしでも全フローを試せます。

## 状態遷移マトリクス（要約）

```
依頼:  draft → submitted → under_review → accepted → proposing
       → partially_assigned → fully_assigned → in_progress
       → completion_pending → confirmed → invoiced → paid
       （いずれの段階からも cancelled / rejected へ遷移可）

提案:  created → worker_contacted → worker_accepted/declined
       → proposed_to_facility → facility_accepted/declined
       → withdrawn / expired

アサイン: confirmed → checked_in → checked_out
         → completion_reported → completion_confirmed / disputed
         （cancelled / no_show は別経路）

請求:  draft → issued → paid / overdue / void
```

DB トリガー（`db/migrations/0005_phase1_state_machine.sql`）が
不正な遷移を SQLSTATE 22023 で拒否するため、API 層は薄いプロキシで
構いません。

## 現時点の優先実装

Phase 1（v2）の主要 UI が一通り揃いました。

- [x] 認証（Supabase Auth・next リダイレクト）
- [x] facility_admin: 案件管理 / 候補者・提案 / アサイン管理 / 請求 / 通知センター
- [x] worker: チェックイン / 完了報告 / 紛争申告 / プロフィール管理
- [x] neco_admin: 依頼一覧 / 状態遷移 / 候補者抽出（マッチスコア）/ 提案作成 / 請求書作成 / 勤怠タイムライン
- [x] alliance_admin: 地域KPIダッシュボード
- [ ] 通知（Webhook 経由のメール / LINE 通知）
- [ ] 請求書 PDF 生成
- [ ] 詳細ロギングと監査UI
