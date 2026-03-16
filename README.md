# MITAS

MITAS は、病院・訪問看護・介護事業所の急な欠員や人員要件不足に対して、要件整理から人材充足までを支援するサービスです。

## このリポジトリの位置づけ

- `_mitas-site/`: 公開サイトの静的ファイル
- `docs/`: 業務要件と運用ドキュメント
- `db/migrations/`: 初期スキーマと将来のマイグレーション
- `db/seeds/`: 開発・検証用 seed データ

## データベース方針

Mitas の DB は、単なる問い合わせ保存ではなく、次の業務を一気通貫で支える前提で設計しています。

- 問い合わせ受付
- 医療機関・施設・担当者の管理
- 欠員案件ごとの要件整理
- 候補者プール管理
- マッチング進捗管理
- タスクと活動履歴の蓄積

詳細は以下を参照してください。

- [DB要件定義](/Users/konchi/Documents/New%20project/Mitas/docs/MITAS_DB_REQUIREMENTS.md)
- [DB設計・運用ガイド](/Users/konchi/Documents/New%20project/Mitas/docs/DATABASE.md)

## ローカルでの初期化

1. `.env.example` を `.env` にコピーして値を設定
2. Netlify DB の接続情報を環境変数へ設定
3. スキーマを適用

```bash
psql "$NETLIFY_DATABASE_URL_UNPOOLED" -f db/migrations/0001_mitas_core.sql
```

4. 開発用データを投入する場合

```bash
psql "$NETLIFY_DATABASE_URL_UNPOOLED" -f db/seeds/0001_demo_seed.sql
```

## 現時点の優先実装

1. 問い合わせフォーム保存
2. 案件管理 UI
3. 候補者登録とマッチング管理
4. ダッシュボードと KPI 集計
