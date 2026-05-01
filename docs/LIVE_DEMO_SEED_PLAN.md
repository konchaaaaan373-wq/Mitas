# Mitas for Alliance — Live Demo Seed Plan

本書は、**実環境（Live Supabase）** に投入する **デモ用フィクションデータ** の設計書です。

⚠️ 本書のデータは **すべてフィクション** です。
実在の医療機関名・医療従事者氏名・患者情報・診療情報は **絶対に含めないでください**。
本番運用ユーザーが投入された後は、本デモデータは削除または明示的に「DEMO」と判別できる状態で運用してください。

---

## 1. デモデータの基本方針

| 項目 | 方針 |
|---|---|
| 名称 | 架空の組織名・施設名・人名のみ |
| 個人情報 | 患者情報・診療情報は一切含めない |
| 連絡先 | `*.example.com` ドメインのメール、`03-0000-XXXX` 形式の固定電話のみ |
| ID形式 | UUID は seed 内で固定、`aaaaaaaa-…` `11111111-…` などプレフィックスで判別可能 |
| データ量 | スモークテスト・15分版デモを通せる最小構成（2施設・3医療者・5依頼程度） |
| 削除容易性 | `DELETE` で安全に巻き戻せる範囲（`organization_id` / `worker_id` を起点に削除可） |
| 区別 | `note` または `description` 欄に **「DEMO DATA」** を明記 |

---

## 2. デモデータ構成

### 2.1 デモ組織（連携法人下の医療機関）

| ID | 種別 | 名称 |
|---|---|---|
| `aaaaaaaa-0000-0000-0000-0000000000d1` | hospital | デモ中央病院（Mitas Demo） |
| `aaaaaaaa-0000-0000-0000-0000000000d2` | visiting_nurse_station | デモ訪問看護ステーション（Mitas Demo） |

### 2.2 デモ Auth ユーザー（手動作成必須）

Supabase Auth では **パスワード作成にダッシュボード操作が必要** なため、
以下のユーザーは Supabase ダッシュボードで手動作成してください。
**UUID は自動生成のままで構いません。** seed 実行時にメールアドレスから
`auth.users.id` を自動取得します。

| メール | パスワード方針 | 役割 |
|---|---|---|
| `konchaaaaan373+mitas-admin@gmail.com` | 強力（外部公開不可） | neco_admin |
| `konchaaaaan373+mitas-alliance@gmail.com` | 強力 | alliance_admin |
| `konchaaaaan373+mitas-facility1@gmail.com` | 強力 | facility_admin（デモ中央病院） |
| `konchaaaaan373+mitas-facility2@gmail.com` | 強力 | facility_admin（デモ訪問看護） |
| `konchaaaaan373+mitas-worker1@gmail.com` | 強力 | worker（医師） |
| `konchaaaaan373+mitas-worker2@gmail.com` | 強力 | worker（看護師） |

**手順**：
1. Supabase ダッシュボード → Authentication → Add user
2. 上記メールで作成（UUID は自動生成のまま、置き換え不要）
3. SQL Editor で `db/seeds/0003_live_demo_seed.sql` を実行
   - 1人でも未作成の場合は、不足メール一覧つきの `EXCEPTION` で安全に
     ロールバックされます

### 2.3 デモ医療者プロフィール

| 名前 | 職種 | 専門 | 経験年数 | 居住地 |
|---|---|---|---|---|
| 田中 健太郎（DEMO） | physician | 内科 | 10 | 東京都 |
| 佐藤 美咲（DEMO） | nurse | 訪問看護 | 7 | 東京都 |

### 2.4 デモ資格（worker_credentials）

| 医療者 | 資格 | 状態 |
|---|---|---|
| 田中 健太郎（DEMO） | 医師免許 | verified |
| 佐藤 美咲（DEMO） | 看護師免許 | verified |

### 2.5 デモ勤務可能時間（worker_availability）

| 医療者 | 設定 |
|---|---|
| 佐藤 美咲（DEMO） | 毎週土曜 10:00–18:00（regular_shift） |
| 佐藤 美咲（DEMO） | 毎週日曜 10:00–18:00（regular_shift） |

### 2.6 デモ勤務枠（staffing_requests）

| 番号 | 状態 | タイトル | 必要職種 | 勤務種別 | 優先度 |
|---|---|---|---|---|---|
| `SR-DEMO-0001` | submitted | 内科外来 当直医（DEMO 緊急） | physician | on_call | urgent |
| `SR-DEMO-0002` | accepted  | 訪問看護 週末スポット（DEMO） | nurse | spot | medium |
| `SR-DEMO-0003` | proposing | 健診 GW 応援（DEMO） | physician | spot | high |

### 2.7 デモ提案（proposals）

| 番号 | 状態 | 対象勤務枠 | 医療者 |
|---|---|---|---|
| `PR-DEMO-0001` | proposed_to_facility | SR-DEMO-0002 | 佐藤 美咲（DEMO） |
| `PR-DEMO-0002` | facility_accepted | SR-DEMO-0003 | 田中 健太郎（DEMO） |

### 2.8 デモ確定アサイン（assignments）

| 番号 | 状態 | 対象提案 | 勤務開始予定 |
|---|---|---|---|
| `AS-DEMO-0001` | confirmed | PR-DEMO-0002 | now + 7 days |

### 2.9 デモ請求書（invoices, optional）

スモークテストの「請求作成」を画面で体験するため、**初期では未投入** とし、デモ中に Neco 担当者が手動作成する想定です。
事前に投入したい場合は `IN-DEMO-0001`（status: draft）を `aaaaaaaa-…d2`（デモ訪問看護）の今月分として作成してください。

---

## 3. 投入順序

```
1. Auth ユーザー作成（Supabase ダッシュボード）
2. SQL 実行（UUID 置き換え不要：seed がメールから自動取得）
   - organizations / facilities
   - user_roles / organization_members
   - worker_profiles / worker_credentials / worker_availability
   - staffing_requests
   - proposals
   - assignments
   - （optional）invoices
   - activity_log（必要に応じて）
```

---

## 4. 削除（ロールバック）手順

デモが終わった後の安全な削除順は以下です（外部キー依存の逆順）。

```sql
DELETE FROM activity_log
  WHERE entity_id IN (
    SELECT id FROM staffing_requests WHERE request_number LIKE 'SR-DEMO-%'
    UNION SELECT id FROM proposals WHERE proposal_number LIKE 'PR-DEMO-%'
    UNION SELECT id FROM assignments WHERE assignment_number LIKE 'AS-DEMO-%'
    UNION SELECT id FROM invoices WHERE invoice_number LIKE 'IN-DEMO-%'
  );

DELETE FROM invoice_line_items WHERE assignment_id IN (
  SELECT id FROM assignments WHERE assignment_number LIKE 'AS-DEMO-%'
);
DELETE FROM invoices WHERE invoice_number LIKE 'IN-DEMO-%';
DELETE FROM work_logs WHERE assignment_id IN (
  SELECT id FROM assignments WHERE assignment_number LIKE 'AS-DEMO-%'
);
DELETE FROM assignments WHERE assignment_number LIKE 'AS-DEMO-%';
DELETE FROM proposals WHERE proposal_number LIKE 'PR-DEMO-%';
DELETE FROM staffing_requests WHERE request_number LIKE 'SR-DEMO-%';

DELETE FROM worker_credentials WHERE worker_id IN (
  SELECT id FROM worker_profiles WHERE full_name LIKE '%（DEMO）'
);
DELETE FROM worker_availability WHERE worker_id IN (
  SELECT id FROM worker_profiles WHERE full_name LIKE '%（DEMO）'
);
DELETE FROM worker_profiles WHERE full_name LIKE '%（DEMO）';

DELETE FROM organization_members WHERE organization_id IN (
  'aaaaaaaa-0000-0000-0000-0000000000d1',
  'aaaaaaaa-0000-0000-0000-0000000000d2'
);
DELETE FROM organizations WHERE id IN (
  'aaaaaaaa-0000-0000-0000-0000000000d1',
  'aaaaaaaa-0000-0000-0000-0000000000d2'
);
```

Auth ユーザーは Supabase ダッシュボードから個別に削除してください（CASCADE で `user_roles` も削除されます）。

---

## 5. データ安全性のチェックリスト

- [ ] すべての氏名・組織名に「（DEMO）」または「Mitas Demo」を含む
- [ ] メールは `*.example` ドメインのみ
- [ ] 電話番号は `03-0000-XXXX` のみ
- [ ] 患者情報・診療内容は含まれない
- [ ] 実在の医療機関名・医療者氏名と衝突しない
- [ ] `note` / `description` に **「DEMO DATA - Mitas for Alliance live smoke test」** を含める
- [ ] 本番運用切替時は本データを削除する手順が明記されている

---

## 6. 参考：Mock mode との違い

| 項目 | Mock mode | Live demo seed |
|---|---|---|
| 認証 | 不要 | Supabase Auth が必要 |
| RLS | 効かない（全データ共有） | ロール別にRLSが効く |
| 状態遷移 | クライアント state のみ | DB トリガーが状態遷移を強制 |
| 通知 | UI のみ | UI + DB の activity_log 記録 |
| 永続化 | リロードで初期化 | DB に保存される |
| 用途 | 画面確認・5分デモ | 本格デモ・運用前リハーサル |

両モードを使い分けて、**まず Mock mode → 次に Live demo seed** の順で確認することを推奨します。

---

## 7. 関連ドキュメント

- `docs/SMOKE_TEST.md` — Mock mode 中心の手動スモークテスト
- `docs/LIVE_SMOKE_TEST.md` — Live 環境向けスモークテスト
- `docs/DEMO_SCENARIO.md` — 5分版／15分版のデモ進行
- `docs/RLS_CHECKLIST.md` — Live 環境での権限確認
- `db/seeds/0003_live_demo_seed.sql` — 本書の SQL 実装
