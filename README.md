# NECO — 在宅医療の求人マッチングプラットフォーム

**あなたの一生物のバイトを、一緒に探す。**

NECO（[necofindjob.com](https://necofindjob.com)）は、医師・看護師と在宅医療施設をつなぐ求人マッチングサービスです。

---

## 技術スタック

| 領域 | 技術 |
|------|------|
| フロントエンド | HTML / CSS / Vanilla JS（ビルドステップなし） |
| ホスティング | Netlify（静的サイト） |
| サーバーレス関数 | Netlify Functions（Node.js、esbuild バンドル） |
| データベース | Netlify DB（Neon PostgreSQL） |
| 認証 | HMAC-SHA256 署名トークン（`crypto` 組み込みモジュール） |
| LINE 連携 | Webhook → Google Apps Script → Google Sheets |

---

## ディレクトリ構成

```
/
├── index.html                  # トップページ
├── nurse.html                  # 看護師向けランディングページ
├── for-medical.html            # 医療施設向けランディングページ
├── company.html                # 会社案内
├── login.html                  # 統合ログイン
├── login-doctor.html           # 医師ログイン
├── login-nurse.html            # 看護師ログイン
├── login-medical.html          # 医療施設ログイン
├── dashboard.html              # 医師・看護師ダッシュボード（要認証）
├── medical-dashboard.html      # 医療施設ダッシュボード（要認証）
├── admin-dashboard.html        # 管理者ダッシュボード（要認証）
├── admin-setup.html            # 管理者初期設定
├── register-doctor.html        # 医師登録
├── register-medical.html       # 医療施設登録
├── profile-doctor.html         # 医師プロフィール編集
├── profile-medical.html        # 医療施設プロフィール編集
├── guide.html                  # ご利用ガイド
├── faq.html                    # よくある質問
├── terms.html                  # 利用規約
├── privacy-policy.html         # プライバシーポリシー
├── license.html                # 特定商取引法に基づく表記
├── line-consent.html           # LINE データ連携同意ページ
├── 404.html                    # カスタム 404
├── sitemap.xml
├── robots.txt
├── netlify.toml                # Netlify 設定（ヘッダー・リダイレクト）
├── package.json
├── netlify/
│   └── functions/
│       ├── auth.js             # 認証 API
│       ├── users.js            # ユーザー登録・プロフィール API
│       ├── jobs.js             # 求人 API
│       ├── applications.js     # 応募 API
│       ├── messages.js         # メッセージ API
│       ├── admin-stats.js      # 管理者統計 API
│       ├── db-init.js          # DB 初期化 API
│       ├── line-webhook.js     # LINE Webhook
│       └── lib/                # 共通ユーティリティ
└── docs/
    ├── DATABASE.md             # DB 設計・運用ガイド
    └── LINE_WEBHOOK_SETUP.md   # LINE 連携設定手順
```

---

## ローカル開発

### 前提条件

- [Node.js](https://nodejs.org/) v18 以上
- [Netlify CLI](https://docs.netlify.com/cli/get-started/) (`npm install -g netlify-cli`)

### セットアップ

```bash
# リポジトリをクローン
git clone https://github.com/konchaaaaan373-wq/neco.git
cd neco

# 依存パッケージをインストール
npm install

# 環境変数ファイルを作成
cp .env.example .env
# .env を編集して各値を設定（後述）

# 開発サーバー起動（Netlify Functions を含む）
netlify dev
```

ブラウザで `http://localhost:8888` にアクセスします。

### 環境変数

| 変数名 | 必須 | 説明 |
|--------|:----:|------|
| `NETLIFY_DATABASE_URL` | ✅ | Netlify DB 接続 URL（プール）|
| `NETLIFY_DATABASE_URL_UNPOOLED` | ✅ | Netlify DB 接続 URL（直接）|
| `SESSION_SECRET` | ✅ | JWT 署名キー（32 文字以上のランダム文字列）|
| `NECO_ADMIN_PASSWORD` | ✅ | 管理者ダッシュボードのパスワード |
| `ADMIN_SECRET` | ✅ | DB 初期化 API 保護キー |
| `LINE_CHANNEL_SECRET` | LINE 使用時 | LINE Webhook 署名検証 |
| `GAS_WEBHOOK_URL` | オプション | Google Apps Script 転送先 URL |
| `GAS_WEBHOOK_SECRET` | オプション | GAS 共有シークレット |

`SESSION_SECRET` の生成例：
```bash
openssl rand -hex 32
```

---

## DB 初期化

テーブル作成とデモデータの投入は `docs/DATABASE.md` を参照してください。

---

## API エンドポイント

| メソッド | パス | 説明 |
|---------|------|------|
| POST | `/api/auth/login` | ログイン |
| GET | `/api/auth/me` | 自分のプロフィール取得 |
| POST | `/api/users/register` | 新規ユーザー登録 |
| GET/PUT | `/api/users/profile` | プロフィール取得・更新 |
| GET | `/api/jobs` | 求人一覧 |
| POST | `/api/jobs` | 求人作成（医療施設のみ） |
| POST | `/api/applications` | 求人への応募 |
| GET | `/api/messages/conversations` | メッセージ一覧 |
| POST | `/api/line/webhook` | LINE Webhook 受信 |
| POST | `/api/admin/db-init` | DB 初期化（要 ADMIN_SECRET） |
| GET | `/api/admin/stats` | 管理者統計（要認証） |

詳細は `docs/DATABASE.md` を参照。

---

## デプロイ

`main` ブランチへのプッシュで Netlify が自動デプロイします。
プルリクエストを作成するとプレビューデプロイが自動生成されます。

---

## セキュリティ

- パスワードは **bcryptjs**（10 rounds）でハッシュ化
- トークンは **HMAC-SHA256** 署名、7日有効期限
- SQL インジェクション対策：neon タグテンプレートによるパラメータバインド
- セキュリティヘッダー（CSP・HSTS・X-Frame-Options 等）は `netlify.toml` で設定

セキュリティ上の問題を発見した場合は、Issue を立てずに直接管理者へご連絡ください。

---

## ライセンス

Copyright © 2024 NECO. All rights reserved.
