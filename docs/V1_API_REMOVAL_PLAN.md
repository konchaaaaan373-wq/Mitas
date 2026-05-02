# Mitas for Alliance — 旧 v1 API 削除計画

`netlify.toml` に残存する旧 v1 系 API redirect と、`netlify/functions/` の旧 v1 実装を整理する計画書です。
**本書は計画書であり、削除自体は別 PR で段階的に行います**（影響範囲確認の後）。

---

## 1. 現状の把握

### 1.1 `netlify.toml` redirect → 実体ファイル の対応

| `from` | `to` | 実体ファイル | 状態 |
|---|---|---|---|
| `/api/auth/*` | `/.netlify/functions/auth/:splat` | **無し** | ⚠️ orphan |
| `/api/users/*` | `/.netlify/functions/users/:splat` | **無し** | ⚠️ orphan |
| `/api/jobs*` | `/.netlify/functions/jobs(/:splat)?` | **無し** | ⚠️ orphan |
| `/api/applications*` | `/.netlify/functions/applications(/:splat)?` | **無し** | ⚠️ orphan |
| `/api/messages*` | `/.netlify/functions/messages(/:splat)?` | **無し** | ⚠️ orphan |
| `/api/admin/db-init` | `/.netlify/functions/db-init` | **無し** | ⚠️ orphan |
| `/api/admin/stats` | `/.netlify/functions/admin-stats` | **無し** | ⚠️ orphan |
| `/api/line/webhook` | `/.netlify/functions/line-webhook` | **無し** | ⚠️ orphan（LINE 連携別途） |
| `/api/hospital/login` | `/.netlify/functions/hospital-login` | あり | 旧 v1（v2 でも参照されない） |
| `/api/hospital/cases` | `/.netlify/functions/hospital-cases` | あり | 旧 v1（v2 でも参照されない） |
| `/api/hospital/candidates` | `/.netlify/functions/hospital-candidates` | あり | 旧 v1（v2 でも参照されない） |
| `/api/v2/requests*` | `/.netlify/functions/requests-v2(/:splat)?` | あり | **現役 v2** |
| `/api/v2/proposals*` | `/.netlify/functions/proposals-v2(/:splat)?` | あり | **現役 v2** |
| `/api/v2/assignments*` | `/.netlify/functions/assignments-v2(/:splat)?` | あり | **現役 v2** |
| `/api/v2/invoices*` | `/.netlify/functions/invoices-v2(/:splat)?` | あり | **現役 v2** |
| `/api/v2/dashboard/kpi` | `/.netlify/functions/dashboard-kpi-v2` | あり | **現役 v2** |

### 1.2 削除候補の集計

- **orphan redirect（実体無し）**：8 件 — `/api/auth/*` / `/api/users/*` / `/api/jobs*` / `/api/applications*` / `/api/messages*` / `/api/admin/db-init` / `/api/admin/stats` / `/api/line/webhook`
- **旧 v1 実体ファイル＋関連 redirect**：3 セット
  - `hospital-login.js` ＋ `/api/hospital/login` redirect
  - `hospital-cases.js` ＋ `/api/hospital/cases` redirect
  - `hospital-candidates.js` ＋ `/api/hospital/candidates` redirect

### 1.3 フロントエンドからの参照調査結果

```
$ grep -rln "/api/hospital/\|/api/auth/\|/api/users/\|/api/jobs\|/api/applications\|/api/messages\|/api/admin/\|/api/line/" \
       *.html *.js
（マッチなし）
```

→ **現フロント（HTML / hospital-login.js）からは旧 v1 API を一切呼んでいない**。

---

## 2. 削除対象の整理

### 2.1 Phase A：実体無し orphan redirect の削除（影響度：低）

8 件の redirect は実体ファイルが無く、呼ばれても 404 が返る現状。
**削除しても 404 → 404 で挙動は同じ**。

| 削除対象（`netlify.toml` の `[[redirects]]` ブロック） |
|---|
| `from = "/api/auth/*"` |
| `from = "/api/users/*"` |
| `from = "/api/jobs"` および `from = "/api/jobs/*"` |
| `from = "/api/applications"` および `from = "/api/applications/*"` |
| `from = "/api/messages"` および `from = "/api/messages/*"` |
| `from = "/api/admin/db-init"` |
| `from = "/api/admin/stats"` |
| `from = "/api/line/webhook"` |

### 2.2 Phase B：旧 v1 実装の削除（影響度：中）

| 削除対象 | 関連 redirect | 影響範囲 |
|---|---|---|
| `netlify/functions/hospital-login.js` | `/api/hospital/login` | 現フロント未使用。**ただしルートの `hospital-login.js`（クライアント側 helper）と同名で混乱しやすいので、サーバー側のみ削除** |
| `netlify/functions/hospital-cases.js` | `/api/hospital/cases` | 現フロント未使用 |
| `netlify/functions/hospital-candidates.js` | `/api/hospital/candidates` | 現フロント未使用 |

⚠️ **`hospital-login.js` という同名ファイルが 2 つある**（ルートのクライアント JS と Functions 側のサーバー JS）。Functions 側のみ削除する場合、ルートの `/hospital-login.js` は維持すること。

### 2.3 残置（現役）

以下は **削除しない**：

| 残置対象 | 理由 |
|---|---|
| `netlify.toml` の `/api/v2/*` redirect 群 | 現フロントが利用中 |
| `netlify/functions/requests-v2.js` 他 v2 系 | 現役 |
| `netlify/functions/dashboard-kpi-v2.js` | alliance-dashboard が利用中 |
| `netlify/functions/_utils/supabase.js` | 全 v2 Function の共通 utility |
| `hospital-login.js`（**ルートのクライアント JS**） | login.html / dashboard.html / forgot-password.html が読み込み中 |

---

## 3. 削除前の確認 SQL / コマンド

### 3.1 リポジトリ全体での参照チェック

削除を実行する直前に必ず以下を流して **0 件** を確認。

```bash
# 各 endpoint がどこからも参照されていないことを確認
for ep in "/api/hospital/login" "/api/hospital/cases" "/api/hospital/candidates" \
          "/api/auth/" "/api/users/" "/api/jobs" "/api/applications" "/api/messages" \
          "/api/admin/" "/api/line/"; do
  echo "=== $ep ==="
  grep -rln "$ep" --include="*.html" --include="*.js" --include="*.ts" --include="*.tsx" \
       --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=docs .
done
```

### 3.2 Netlify Functions の参照チェック

```bash
# 削除候補の Function が他から require されていないか
for fn in hospital-login hospital-cases hospital-candidates; do
  echo "=== $fn ==="
  grep -rln "require.*$fn\|from.*$fn" netlify/functions/
done
```

### 3.3 docs での参照

```bash
grep -rln "hospital-login\|hospital-cases\|hospital-candidates\|/api/hospital/\|/api/auth/\|/api/users/" docs/
```

→ `docs/` 配下に古い記述があれば、削除と同じ PR で更新する。

---

## 4. 実行順序（PR 構成）

### Phase A PR（先に実施）

**ブランチ名（例）**：`claude/cleanup-orphan-redirects`
**変更内容**：
- `netlify.toml` から orphan redirect 8 件を削除

**確認項目**：
- [ ] section 3.1 のチェックで 0 件
- [ ] netlify.toml の syntax が valid（local で `netlify build --dry` または手動レビュー）
- [ ] Deploy Preview で / 配下の主要画面が崩れない

### Phase B PR（A のマージ後）

**ブランチ名（例）**：`claude/remove-legacy-v1-functions`
**変更内容**：
- `netlify/functions/hospital-login.js` を削除（**サーバー側のみ**、ルートのクライアント JS は維持）
- `netlify/functions/hospital-cases.js` を削除
- `netlify/functions/hospital-candidates.js` を削除
- `netlify.toml` の `/api/hospital/login` `/api/hospital/cases` `/api/hospital/candidates` redirect を削除

**確認項目**：
- [ ] section 3.1 / 3.2 のチェックで 0 件
- [ ] ルートの `/hospital-login.js`（クライアント側）が同名で残っていることを再確認
- [ ] Deploy Preview で `/login.html` が正常動作（ルート JS が使われる）
- [ ] `/dashboard.html` の認証フローが正常
- [ ] `docs/` の旧 API 言及があれば更新

---

## 5. ロールバック手順

### Phase A をロールバック
```bash
git revert <Phase A の merge commit>
git push origin main
```
orphan redirect が再度 netlify.toml に戻る。挙動への影響は無い（404 → 404 のまま）。

### Phase B をロールバック
```bash
git revert <Phase B の merge commit>
git push origin main
```
削除した Function ファイルと redirect が復活。旧 v1 API がまた呼べるようになる（誰も呼んでいないので影響無し）。

---

## 6. 想定されるリスクと対策

| リスク | 影響度 | 対策 |
|---|---|---|
| 外部 / 旧クライアントが旧 v1 API をまだ呼んでいる | 不明 | 削除前に `netlify` Function logs を確認し、過去 30 日間の呼び出し有無を確認 |
| ルートの `/hospital-login.js`（クライアント）を Functions 側と同時に削除してしまう | 高（auth 不能になる） | Phase B PR で **必ずパスを `netlify/functions/` 配下に限定**して `git rm` する |
| docs に旧 API リンクが残ってリンク切れ | 低 | Phase B 時に grep で検出して同 PR で修正 |
| LINE webhook を将来再導入したい | 低 | redirect のみ削除。実装する時には新規追加。ロールバックも可能 |

---

## 7. 完了判定

- Phase A マージ後、本番環境で `/api/auth/*` 等が 404 を返し続ける（変化なし）
- Phase B マージ後、本番環境で `/api/hospital/*` が 404（削除前は 200 OK で空配列等）
- 4 ロールでログイン → 主要画面が正常動作（リグレッションなし）
- `docs/FOLLOW_UP_CHECKLIST.md` の関連項目を再実行

---

## 8. 関連

- 本書執筆時点での GitHub PR フロー：本計画は **2 PR に分けて** 段階的に実施
- 緊急対応で main 直 push をしないこと（CLAUDE.md ワークフロールール準拠）
- 各 Phase の PR 説明には本書のセクション番号を引用すること
