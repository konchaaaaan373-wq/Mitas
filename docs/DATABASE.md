# MITAS データベース設計・運用ガイド

## 概要

MITAS は Netlify DB（Neon PostgreSQL）を利用し、以下の業務を一気通貫で管理します。

- 問い合わせ受付
- 法人 / 施設 / 担当者管理
- 欠員案件の管理
- 候補者プール管理
- マッチング進捗管理
- タスク / 活動履歴管理

要件の背景は [DB要件定義](/Users/konchi/Documents/New%20project/Mitas/docs/MITAS_DB_REQUIREMENTS.md) を参照してください。

## 採用している構成

### コアテーブル

- `organizations`
- `organization_contacts`
- `facilities`
- `inquiries`
- `staffing_cases`
- `staffing_requirements`
- `candidate_profiles`
- `case_matches`
- `follow_up_tasks`
- `case_activities`

### 補助ビュー

- `v_case_pipeline_summary`
- `v_candidate_match_readiness`

## ER の考え方

```text
organizations
├── organization_contacts
├── facilities
└── staffing_cases
    ├── staffing_requirements
    │   └── case_matches
    │       └── candidate_profiles
    ├── follow_up_tasks
    └── case_activities

inquiries
└── staffing_cases (converted)
```

## テーブル要約

### `inquiries`

公開サイトや営業起点の問い合わせ保存用。

- 問い合わせ元
- 緊急度
- 必要支援
- 案件化されたかどうか

### `organizations`

顧客法人のマスタ。

### `facilities`

同一法人内の拠点管理。
複数施設運営に備えて、法人と分離しています。

### `staffing_cases`

実際に支援する案件本体。
問い合わせは複数案件へ発展しうるため分離しています。

### `staffing_requirements`

案件に紐づく募集要件。
1案件に複数職種・複数人数がある前提で独立させています。

### `candidate_profiles`

候補者プール。
案件と独立して保持することで、再提案や将来案件への転用がしやすくなります。

### `case_matches`

案件要件と候補者の紐づけ。
進捗ステージと見送り理由を管理します。

### `follow_up_tasks`

次アクション管理。
案件単位、要件単位、候補者単位のいずれにも紐づけ可能です。

### `case_activities`

対応履歴。
監査・引き継ぎ・分析の土台になります。

## 初期化手順

### 1. スキーマ適用

```bash
psql "$NETLIFY_DATABASE_URL_UNPOOLED" -f db/migrations/0001_mitas_core.sql
```

### 2. 開発用 seed 投入

```bash
psql "$NETLIFY_DATABASE_URL_UNPOOLED" -f db/seeds/0001_demo_seed.sql
```

## 運用ルール

### 保存してよい情報

- 法人情報
- 担当者情報
- 採用 / 充足に必要な条件
- 候補者の職務経歴要約
- オペレーションログ

### 保存しない情報

- 患者個人情報
- 医療記録
- マイナンバー
- 法的判断を要する診療情報

## 今後の拡張候補

### フェーズ 2

- ユーザー認証
- 管理画面
- 検索 API
- ダッシュボード集計 API

### フェーズ 3

- 商談 / 契約管理
- 成約売上管理
- 候補者スコアリング自動化
- メール / LINE 通知連携

## 推奨実装順

1. 問い合わせ保存 API
2. 案件一覧 / 詳細 API
3. 候補者 CRUD
4. マッチング管理 API
5. ダッシュボードビュー活用
