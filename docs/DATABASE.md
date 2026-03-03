# NECO データベース設計・運用ガイド

## 概要

NECO は **Netlify DB（Neon PostgreSQL）** を使用します。
接続は `@netlify/neon` パッケージ経由で自動設定されます。

---

## テーブル設計（ER 図）

```
users
├── doctor_profiles        (1:1, user_id FK)
├── nurse_profiles         (1:1, user_id FK)
├── medical_institution_profiles (1:1, user_id FK)
├── job_listings           (1:N, institution_id FK)
│   └── job_applications   (N:M, job_id + applicant_id)
├── conversations          (N:M, participant1_id + participant2_id)
│   └── messages           (1:N, conversation_id FK)
└── line_events            (独立, LINE Webhook ログ)
```

---

## テーブル詳細

### `users` – 全ユーザー共通

| カラム | 型 | 説明 |
|--------|-----|------|
| id | UUID PK | gen_random_uuid() |
| email | VARCHAR(255) UNIQUE | メールアドレス |
| password_hash | VARCHAR(255) | bcrypt ハッシュ (10 rounds) |
| user_type | VARCHAR(20) | `doctor` / `nurse` / `medical` / `admin` |
| name | VARCHAR(255) | 氏名・施設名 |
| name_kana | VARCHAR(255) | 氏名カナ |
| avatar_initial | VARCHAR(10) | アバター文字 |
| avatar_color | VARCHAR(20) | アバター色 (hex) |
| is_active | BOOLEAN | ソフトデリートフラグ |
| created_at / updated_at | TIMESTAMPTZ | 自動管理 |

### `doctor_profiles` / `nurse_profiles`

| カラム | 型 | 説明 |
|--------|-----|------|
| user_id | UUID FK → users | 1:1 |
| specialty | VARCHAR | 専門科 |
| sub_specialty | VARCHAR | サブ専門 |
| experience | VARCHAR | 経験年数 |
| affiliation | VARCHAR | 所属機関 |
| prefecture | VARCHAR | 都道府県 |
| available_days | TEXT[] | 勤務可能曜日 |
| hourly_rate | VARCHAR | 希望時給 |
| bio | TEXT | 自己紹介 |

### `medical_institution_profiles`

| カラム | 型 | 説明 |
|--------|-----|------|
| user_id | UUID FK → users | 1:1 |
| contact_name | VARCHAR | 担当者名 |
| facility_type | VARCHAR | 施設種別 |
| prefecture / city | VARCHAR | 所在地 |
| patient_count | INTEGER | 患者数 |
| needs | TEXT[] | 募集職種ニーズ |
| bio | TEXT | 施設紹介 |

### `job_listings`

| カラム | 型 | 説明 |
|--------|-----|------|
| institution_id | UUID FK → users | 医療機関 |
| title | VARCHAR(255) | 求人タイトル |
| required_type | VARCHAR | `doctor`/`nurse`/`both` |
| specialty | VARCHAR | 求める専門 |
| employment_type | VARCHAR | 常勤/非常勤 etc. |
| work_days | TEXT[] | 勤務曜日 |
| hourly_rate_min/max | INTEGER | 時給レンジ（円） |
| prefecture / city | VARCHAR | 勤務地 |
| is_active | BOOLEAN | ソフトデリート |

### `job_applications`

| カラム | 型 | 説明 |
|--------|-----|------|
| job_id | UUID FK → job_listings | |
| applicant_id | UUID FK → users | |
| status | VARCHAR | `pending`/`reviewing`/`accepted`/`rejected`/`withdrawn` |
| message | TEXT | 応募メッセージ |

ユニーク制約: `(job_id, applicant_id)`

### `conversations` / `messages`

| カラム | 型 | 説明 |
|--------|-----|------|
| participant1_id / participant2_id | UUID FK → users | ID昇順で正規化 |
| last_message_at | TIMESTAMPTZ | 最終メッセージ日時 |

メッセージ: `conversation_id`, `sender_id`, `content`, `is_read`

### `line_events`

LINE Webhook イベントのログテーブル。
`raw_event` カラムに JSONB で完全なイベントデータを保持。

---

## 環境変数

Netlify ダッシュボード → Site settings → Environment variables に設定してください。

| 変数名 | 必須 | 説明 |
|--------|------|------|
| `NETLIFY_DATABASE_URL` | ✅ | Netlify DB で自動設定 |
| `NETLIFY_DATABASE_URL_UNPOOLED` | ✅ | Netlify DB で自動設定 |
| `SESSION_SECRET` | ✅ | JWT 署名キー（32文字以上のランダム文字列） |
| `ADMIN_SECRET` | ✅ | DB 初期化 API の認証キー |
| `LINE_CHANNEL_SECRET` | LINE使用時 | LINE Webhook 署名検証 |
| `GAS_WEBHOOK_URL` | オプション | Google Apps Script 転送先 |
| `GAS_WEBHOOK_SECRET` | オプション | GAS 共有シークレット |

### SESSION_SECRET 生成方法
```bash
openssl rand -hex 32
```

---

## DB 初期化手順

### 1. 初回セットアップ（テーブル作成のみ）

```bash
curl -X POST https://<your-domain>/api/admin/db-init \
  -H "x-admin-secret: <ADMIN_SECRET>"
```

### 2. テーブル作成 + デモデータ投入

```bash
curl -X POST "https://<your-domain>/api/admin/db-init?seed=true" \
  -H "x-admin-secret: <ADMIN_SECRET>"
```

デモアカウント（パスワード: `demo1234`）:

| メールアドレス | 種別 | 名前 |
|----------------|------|------|
| dr-demo@neco.jp | 医師 | 田中 太郎 |
| dr-sato@neco.jp | 医師 | 佐藤 美咲 |
| nurse-demo@neco.jp | 看護師 | 山本 花子 |
| clinic-demo@neco.jp | 医療機関 | さくら在宅クリニック |
| hospital-demo@neco.jp | 医療機関 | みなと訪問看護ステーション |

### 3. リセット（開発環境のみ）

```bash
curl -X POST "https://<your-domain>/api/admin/db-init?reset=true&seed=true" \
  -H "x-admin-secret: <ADMIN_SECRET>"
```

⚠️ **本番環境では `?reset=true` を絶対に使用しないでください。**

---

## API エンドポイント一覧

### 認証 `/api/auth/*`

| メソッド | パス | 説明 |
|---------|------|------|
| POST | `/api/auth/login` | ログイン |
| GET | `/api/auth/me` | 自分のプロフィール取得 |
| POST | `/api/auth/verify` | トークン検証 |

### ユーザー `/api/users/*`

| メソッド | パス | 認証 | 説明 |
|---------|------|------|------|
| POST | `/api/users/register` | 不要 | 新規登録 |
| GET | `/api/users/profile` | 必要 | 自分のプロフィール |
| PUT | `/api/users/profile` | 必要 | プロフィール更新 |
| GET | `/api/users/:id` | 必要 | 他ユーザーの公開プロフィール |

### 求人 `/api/jobs/*`

| メソッド | パス | 認証 | 説明 |
|---------|------|------|------|
| GET | `/api/jobs` | 不要 | 求人一覧（フィルタ可） |
| GET | `/api/jobs/:id` | 不要 | 求人詳細 |
| POST | `/api/jobs` | 医療機関 | 求人作成 |
| PUT | `/api/jobs/:id` | 医療機関(作成者) | 求人更新 |
| DELETE | `/api/jobs/:id` | 医療機関(作成者) | 求人削除（ソフト） |

**フィルタパラメータ（GET /api/jobs）:**
- `?type=doctor|nurse|both`
- `?prefecture=東京都`
- `?specialty=内科`
- `?limit=20&offset=0`

### 応募 `/api/applications/*`

| メソッド | パス | 認証 | 説明 |
|---------|------|------|------|
| POST | `/api/applications` | 医師・看護師 | 応募 |
| GET | `/api/applications` | 必要 | 応募一覧（役割別） |
| GET | `/api/applications/:id` | 必要 | 応募詳細 |
| PUT | `/api/applications/:id/status` | 医療機関 | ステータス更新 |
| DELETE | `/api/applications/:id` | 応募者 | 取り下げ |

### メッセージ `/api/messages/*`

| メソッド | パス | 認証 | 説明 |
|---------|------|------|------|
| GET | `/api/messages/conversations` | 必要 | 会話一覧 |
| POST | `/api/messages/conversations` | 必要 | 会話開始 |
| GET | `/api/messages/conversations/:id` | 必要 | メッセージ履歴 |
| POST | `/api/messages/conversations/:id/send` | 必要 | メッセージ送信 |
| POST | `/api/messages/conversations/:id/read` | 必要 | 既読マーク |

---

## セキュリティ

- **パスワード**: bcryptjs (10 rounds)
- **トークン**: HMAC-SHA256 署名、7日有効期限
- **SQL インジェクション**: neon タグテンプレートによるパラメータバインド
- **アクセス制御**: 全保護エンドポイントでユーザー種別チェック
- **DB 初期化 API**: `ADMIN_SECRET` ヘッダーによる保護

---

## 運用・保守

### ログ確認

Netlify Functions のログは Netlify ダッシュボード → Functions タブで確認できます。
エラーは `console.error` で出力されます。

### バックアップ

Neon は自動バックアップ（PITR: 時点復元）に対応しています。
Neon ダッシュボード → Branches でスナップショット管理が可能です。

### スケーリング

Neon はサーバーレスで自動スケールします。
接続プールは `NETLIFY_DATABASE_URL`（PgBouncer 経由）が使用されます。

### インデックス監視

```sql
-- 未使用インデックスの確認
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY tablename;

-- テーブルサイズ確認
SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

### 古いデータのクリーンアップ（月次推奨）

```sql
-- 90日以上前の LINE イベントを削除
DELETE FROM line_events WHERE received_at < NOW() - INTERVAL '90 days';

-- 取り下げ・拒否された応募を1年後に削除
DELETE FROM job_applications
WHERE status IN ('withdrawn', 'rejected')
  AND updated_at < NOW() - INTERVAL '1 year';
```
