# Mitas – Claude Code Project Guide

## Project Overview

**Mitas** (mitas.necofindjob.com) は、医療機関の人材要件マッチングプラットフォームです。
在宅医療施設・クリニック・病院が必要とする医師・看護師の要件を登録し、最適な人材とマッチングします。

ターゲット：**医療機関側（院長・事務長・採用担当者）**

necoとの関係：neco（求職者向け）の姉妹サービス。バックエンドは共通化を検討。

---

## Repository Structure

```
/
├── index.html              # ランディングページ（医療機関向け）
├── terms.html              # 利用規約
├── privacy-policy.html     # プライバシーポリシー
├── 404.html                # カスタム404
├── sitemap.xml
├── robots.txt
├── netlify.toml            # Netlify設定
└── favicon.svg
```

---

## Tech Stack

- **Frontend**: Vanilla HTML, CSS, JavaScript（ビルドステップなし）
- **Hosting**: Netlify（静的サイト）
- **Functions**: Netlify Functions（Node.js）
- **Auth**: HMAC-SHA256署名トークン（crypto モジュール）

---

## ブランディング

- **カラー**: ネイビー (#1B3A6B) をメイン、ティール (#0EA5E9) をアクセント
- **トーン**: 信頼感・専門性重視。フォーマルだが親しみやすい
- **フォント**: Noto Sans JP

necoとの差別化：necoはカジュアル・カラフル（ピンク系）、mitasはプロフェッショナル（ネイビー系）

---

## Workflow Rules

オーナーは非エンジニア。毎タスク以下のフローを必ず守る：

1. **Develop** – `claude/` ブランチで開発
2. **Commit** – 変更内容を明確に記述してコミット
3. **Push** – originへプッシュ
4. **PR** – `gh pr create` でPR作成、URLをユーザーに返す
5. **End** – PRリンクを必ず提示して終了

---

## Development Notes

- **ビルドステップなし**: HTML/CSS/JSを直接編集
- **言語**: UIは日本語で統一
- **テスト**: ブラウザでの手動確認が現行ワークフロー
- ローカル関数テスト: `netlify dev`（Netlify CLI必要）
