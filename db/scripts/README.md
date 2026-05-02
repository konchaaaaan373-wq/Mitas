# db/scripts

`db/migrations/` がスキーマ進化を、`db/seeds/` がデモ／検証用初期データを管理するのに対し、本フォルダには **本番運用中のデータ補完・修復用 SQL** を置きます。

## 特徴

- **冪等性を必ず確保**：複数回実行しても結果が変わらないこと（NOT EXISTS / WHERE フィルタ等）
- **実行前確認・実行後確認 SQL を必ず併記**：件数や差分を投入前後で見比べられる
- **BEGIN/COMMIT で囲む**：途中失敗時にロールバックできる
- **対象範囲は限定的**：時間範囲（過去 N 日）や条件（NULL のみ／対応行なしのみ）で絞る

## 実行方法

1. Supabase SQL Editor を開く
2. 本フォルダ内の対象 `.sql` ファイルを **そのまま貼り付ける**
3. まず A セクション（実行前確認）の SELECT を実行し、想定件数か確認
4. B セクション（UPDATE/INSERT）を BEGIN/COMMIT 込みで実行
5. C セクション（実行後確認）の SELECT で結果を確認

## ファイル一覧

| ファイル | 用途 | 想定実行頻度 |
|---|---|---|
| `0001_backfill_actor_role.sql` | `activity_log.actor_role` が NULL の過去レコードを `user_roles` から逆引きで補完 | 一度 |
| `0002_backfill_invoice_issued.sql` | `activity_log` に `invoice.issued` 行が無い `invoices` レコードに遡及で監査ログを追加 | 一度 |

## 注意

- これらのスクリプトは **過去のバグの後始末** です。本来は Function 側 / Client 側のコードで予防すべきもので、対応する修正は既にコミット済み（`actor_role`: commit `80cc467` ／ `invoice.issued`: commit `7e74a61`）
- 実行は本番運用切替前、または本番運用開始直後の早い段階で行うことを推奨
- 実行後は本フォルダの README に「YYYY-MM-DD 実行済み」を追記すると、二重実行を避けられます

## 実行履歴メモ（運用者が追記）

- `0001_backfill_actor_role.sql`：（未実行）
- `0002_backfill_invoice_issued.sql`：（未実行）
