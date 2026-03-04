/**
 * DB 初期化 Netlify Function
 *
 * スキーマ作成 & デモデータ投入を行う管理者専用エンドポイント。
 *
 * Route (netlify.toml で設定):
 *   POST /api/admin/db-init
 *
 * 認証:
 *   Header: x-admin-secret: <ADMIN_SECRET 環境変数>
 *
 * クエリパラメータ:
 *   ?seed=true  → デモデータも投入する（任意）
 *   ?reset=true → 既存テーブルを DROP して再作成（危険！本番不可）
 */

const { getDb } = require('./lib/db');
const { json, CORS_HEADERS } = require('./lib/auth-utils');
const bcrypt = require('bcryptjs');

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

// ── Schema DDL（テーブル・インデックス・トリガー） ───────────────────────────

const DDL_TABLES = [
  // pgcrypto は gen_random_uuid() のために必要
  `CREATE EXTENSION IF NOT EXISTS "pgcrypto"`,

  // ── users ───────────────────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS users (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email               VARCHAR(255) UNIQUE NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,
    user_type           VARCHAR(20)  NOT NULL CHECK (user_type IN ('doctor','nurse','medical','admin')),
    name                VARCHAR(255) NOT NULL,
    name_kana           VARCHAR(255),
    avatar_initial      VARCHAR(10),
    avatar_color        VARCHAR(20),
    is_active           BOOLEAN      DEFAULT true,
    email_notification  BOOLEAN      DEFAULT false,
    created_at          TIMESTAMPTZ  DEFAULT NOW(),
    updated_at          TIMESTAMPTZ  DEFAULT NOW()
  )`,

  // email_notification カラム追加（既存DBへのマイグレーション用）
  `ALTER TABLE users ADD COLUMN IF NOT EXISTS email_notification BOOLEAN DEFAULT false`,

  // ── doctor_profiles ─────────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS doctor_profiles (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID         UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    specialty    VARCHAR(255),
    sub_specialty VARCHAR(255),
    experience   VARCHAR(50),
    affiliation  VARCHAR(255),
    prefecture   VARCHAR(50),
    available_days TEXT[],
    hourly_rate  VARCHAR(100),
    bio          TEXT,
    created_at   TIMESTAMPTZ  DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  DEFAULT NOW()
  )`,

  // ── nurse_profiles ──────────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS nurse_profiles (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID         UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    specialty    VARCHAR(255),
    sub_specialty VARCHAR(255),
    experience   VARCHAR(50),
    affiliation  VARCHAR(255),
    prefecture   VARCHAR(50),
    available_days TEXT[],
    hourly_rate  VARCHAR(100),
    bio          TEXT,
    created_at   TIMESTAMPTZ  DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  DEFAULT NOW()
  )`,

  // ── medical_institution_profiles ────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS medical_institution_profiles (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID         UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_name  VARCHAR(255),
    facility_type VARCHAR(255),
    prefecture    VARCHAR(50),
    city          VARCHAR(100),
    patient_count INTEGER,
    needs         TEXT[],
    bio           TEXT,
    created_at    TIMESTAMPTZ  DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  DEFAULT NOW()
  )`,

  // ── job_listings ────────────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS job_listings (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id   UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title            VARCHAR(255) NOT NULL,
    description      TEXT,
    required_type    VARCHAR(20)  CHECK (required_type IN ('doctor','nurse','both')),
    specialty        VARCHAR(255),
    employment_type  VARCHAR(50),
    work_days        TEXT[],
    hourly_rate_min  INTEGER,
    hourly_rate_max  INTEGER,
    prefecture       VARCHAR(50),
    city             VARCHAR(100),
    is_active        BOOLEAN      DEFAULT true,
    created_at       TIMESTAMPTZ  DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  DEFAULT NOW()
  )`,

  // ── job_applications ────────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS job_applications (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id       UUID         NOT NULL REFERENCES job_listings(id) ON DELETE CASCADE,
    applicant_id UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status       VARCHAR(20)  DEFAULT 'pending'
                   CHECK (status IN ('pending','reviewing','accepted','rejected','withdrawn')),
    message      TEXT,
    created_at   TIMESTAMPTZ  DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  DEFAULT NOW(),
    UNIQUE(job_id, applicant_id)
  )`,

  // ── conversations ───────────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS conversations (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    participant1_id  UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    participant2_id  UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_message_at  TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  DEFAULT NOW(),
    UNIQUE(participant1_id, participant2_id)
  )`,

  // ── messages ────────────────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS messages (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID         NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content         TEXT         NOT NULL,
    is_read         BOOLEAN      DEFAULT false,
    created_at      TIMESTAMPTZ  DEFAULT NOW()
  )`,

  // ── line_events ─────────────────────────────────────────────────────────
  `CREATE TABLE IF NOT EXISTS line_events (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    received_at      TIMESTAMPTZ  NOT NULL,
    destination      VARCHAR(255),
    webhook_event_id VARCHAR(255),
    event_type       VARCHAR(50),
    ts               BIGINT,
    mode             VARCHAR(50),
    source_type      VARCHAR(50),
    source_user_id   VARCHAR(255),
    source_group_id  VARCHAR(255),
    source_room_id   VARCHAR(255),
    message_type     VARCHAR(50),
    message_text     TEXT,
    raw_event        JSONB,
    created_at       TIMESTAMPTZ  DEFAULT NOW()
  )`,
];

const DDL_INDEXES = [
  `CREATE INDEX IF NOT EXISTS idx_users_email    ON users(email)`,
  `CREATE INDEX IF NOT EXISTS idx_users_type     ON users(user_type)`,
  `CREATE INDEX IF NOT EXISTS idx_jobs_inst      ON job_listings(institution_id)`,
  `CREATE INDEX IF NOT EXISTS idx_jobs_active    ON job_listings(is_active, created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_apps_job       ON job_applications(job_id)`,
  `CREATE INDEX IF NOT EXISTS idx_apps_applicant ON job_applications(applicant_id)`,
  `CREATE INDEX IF NOT EXISTS idx_msgs_conv      ON messages(conversation_id, created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_convs_p1       ON conversations(participant1_id)`,
  `CREATE INDEX IF NOT EXISTS idx_convs_p2       ON conversations(participant2_id)`,
  `CREATE INDEX IF NOT EXISTS idx_line_recv      ON line_events(received_at DESC)`,
];

const DDL_TRIGGERS = [
  `CREATE OR REPLACE FUNCTION update_updated_at()
   RETURNS TRIGGER AS $$
   BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
   $$ LANGUAGE plpgsql`,

  ...['users','doctor_profiles','nurse_profiles','medical_institution_profiles',
      'job_listings','job_applications'].map((tbl) => `
   DO $$ BEGIN
     CREATE TRIGGER trg_${tbl}_updated_at
       BEFORE UPDATE ON ${tbl}
       FOR EACH ROW EXECUTE FUNCTION update_updated_at();
   EXCEPTION WHEN duplicate_object THEN NULL; END $$`),
];

const RESET_TABLES = [
  'line_events','messages','conversations',
  'job_applications','job_listings',
  'medical_institution_profiles','nurse_profiles','doctor_profiles',
  'users',
];

// ── Neco system user helper ───────────────────────────────────────────────────

/**
 * Neco システムユーザーを取得または作成する。
 * user_type = 'admin'、email = 'neco-system@neco.jp で固定。
 */
async function ensureNecoSystemUser(sql) {
  const existing = await sql`SELECT id FROM users WHERE email = 'neco-system@neco.jp'`;
  if (existing.length > 0) return existing[0].id;

  const bcrypt = require('bcryptjs');
  const password_hash = await bcrypt.hash('neco-system-' + Date.now(), 10);
  const [row] = await sql`
    INSERT INTO users (email, password_hash, user_type, name, avatar_initial, avatar_color, is_active)
    VALUES ('neco-system@neco.jp', ${password_hash}, 'admin', 'Neco', 'N', '#FF6B9D', true)
    RETURNING id
  `;
  return row.id;
}

// ── Seed data ────────────────────────────────────────────────────────────────

async function runSeed(sql) {
  const SALT_ROUNDS = 10;
  const hash = (pw) => bcrypt.hash(pw, SALT_ROUNDS);

  // Neco システムユーザー（必ず存在させる）
  await ensureNecoSystemUser(sql);

  // Demo users
  const users = [
    {
      email: 'dr-demo@neco.jp', password: 'demo1234', user_type: 'doctor',
      name: '田中 太郎', name_kana: 'タナカ タロウ',
      avatar_initial: '田', avatar_color: '#FF6B9D',
      profile: {
        specialty: '内科', sub_specialty: '在宅医療', experience: '8年',
        affiliation: '東京医科大学病院', prefecture: '東京都',
        available_days: ['土', '日'], hourly_rate: '5万円〜',
        bio: '在宅医療に情熱を持ち、患者さんの生活に寄り添った医療を提供しています。',
      },
    },
    {
      email: 'dr-sato@neco.jp', password: 'demo1234', user_type: 'doctor',
      name: '佐藤 美咲', name_kana: 'サトウ ミサキ',
      avatar_initial: '佐', avatar_color: '#A78BFA',
      profile: {
        specialty: '総合診療', sub_specialty: '在宅医療・緩和ケア', experience: '12年',
        affiliation: '慶應義塾大学病院', prefecture: '神奈川県',
        available_days: ['月', '水', '金'], hourly_rate: '6万円〜',
        bio: '緩和ケアを専門に、患者さんと家族を支える在宅医療を実践しています。',
      },
    },
    {
      email: 'nurse-demo@neco.jp', password: 'demo1234', user_type: 'nurse',
      name: '山本 花子', name_kana: 'ヤマモト ハナコ',
      avatar_initial: '山', avatar_color: '#34D399',
      profile: {
        specialty: '訪問看護', sub_specialty: '在宅ケア・緩和ケア', experience: '6年',
        affiliation: '東京訪問看護ステーション', prefecture: '東京都',
        available_days: ['月', '火', '水', '木', '金'], hourly_rate: '3万円〜',
        bio: '在宅での看護ケアを通じて、患者さんとご家族の生活を支えることにやりがいを感じています。',
      },
    },
    {
      email: 'clinic-demo@neco.jp', password: 'demo1234', user_type: 'medical',
      name: 'さくら在宅クリニック', name_kana: 'サクラザイタククリニック',
      avatar_initial: 'さ', avatar_color: '#4ECDC4',
      profile: {
        contact_name: '山田 花子', facility_type: '在宅医療クリニック',
        prefecture: '東京都', city: '渋谷区', patient_count: 180,
        needs: ['内科外来', '在宅診療'],
        bio: '渋谷区を中心に在宅医療を提供しています。患者さんの在宅生活を支えるチームです。',
      },
    },
    {
      email: 'hospital-demo@neco.jp', password: 'demo1234', user_type: 'medical',
      name: 'みなと訪問看護ステーション', name_kana: 'ミナトホウモンカンゴステーション',
      avatar_initial: 'み', avatar_color: '#4CC9F0',
      profile: {
        contact_name: '鈴木 一郎', facility_type: '訪問看護ステーション',
        prefecture: '東京都', city: '港区', patient_count: 95,
        needs: ['総合診療', '緩和ケア'],
        bio: '港区を拠点に、医師と協力して在宅療養を支えています。',
      },
    },
  ];

  for (const u of users) {
    // Skip if already exists
    const existing = await sql`SELECT id FROM users WHERE email = ${u.email}`;
    if (existing.length > 0) continue;

    const password_hash = await hash(u.password);
    const [row] = await sql`
      INSERT INTO users (email, password_hash, user_type, name, name_kana, avatar_initial, avatar_color)
      VALUES (${u.email}, ${password_hash}, ${u.user_type}, ${u.name}, ${u.name_kana},
              ${u.avatar_initial}, ${u.avatar_color})
      RETURNING id
    `;
    const userId = row.id;

    if (u.user_type === 'doctor') {
      const p = u.profile;
      await sql`
        INSERT INTO doctor_profiles
          (user_id, specialty, sub_specialty, experience, affiliation,
           prefecture, available_days, hourly_rate, bio)
        VALUES (${userId}, ${p.specialty}, ${p.sub_specialty}, ${p.experience},
                ${p.affiliation}, ${p.prefecture}, ${p.available_days},
                ${p.hourly_rate}, ${p.bio})
      `;
    } else if (u.user_type === 'nurse') {
      const p = u.profile;
      await sql`
        INSERT INTO nurse_profiles
          (user_id, specialty, sub_specialty, experience, affiliation,
           prefecture, available_days, hourly_rate, bio)
        VALUES (${userId}, ${p.specialty}, ${p.sub_specialty}, ${p.experience},
                ${p.affiliation}, ${p.prefecture}, ${p.available_days},
                ${p.hourly_rate}, ${p.bio})
      `;
    } else if (u.user_type === 'medical') {
      const p = u.profile;
      await sql`
        INSERT INTO medical_institution_profiles
          (user_id, contact_name, facility_type, prefecture, city, patient_count, needs, bio)
        VALUES (${userId}, ${p.contact_name}, ${p.facility_type}, ${p.prefecture},
                ${p.city}, ${p.patient_count}, ${p.needs}, ${p.bio})
      `;

      // Demo job listings from medical institutions
      if (u.email === 'clinic-demo@neco.jp') {
        await sql`
          INSERT INTO job_listings
            (institution_id, title, description, required_type, specialty,
             employment_type, work_days, hourly_rate_min, hourly_rate_max, prefecture, city)
          VALUES
            (${userId},
             '在宅診療 内科医師 募集（非常勤）',
             '渋谷区を中心に在宅診療を行っていただける内科医師を募集しています。患者様のご自宅を訪問し、継続的な医療を提供していただきます。',
             'doctor', '内科', '非常勤', '{土,日}', 40000, 60000, '東京都', '渋谷区'),
            (${userId},
             '訪問看護師 常勤・非常勤',
             '在宅クリニックと連携した訪問看護師を募集。チームで患者さんをサポートする環境です。',
             'nurse', '訪問看護', '常勤', '{月,火,水,木,金}', 25000, 35000, '東京都', '渋谷区')
        `;
      }
    }
  }
}

// ── Handler ──────────────────────────────────────────────────────────────────

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: CORS_HEADERS, body: '' };
  }

  if (event.httpMethod !== 'POST') {
    return json(405, { ok: false, error: 'Method Not Allowed' });
  }

  // Admin secret check
  const secret = event.headers['x-admin-secret'] || '';
  if (!ADMIN_SECRET || secret !== ADMIN_SECRET) {
    return json(401, { ok: false, error: '管理者シークレットが無効です' });
  }

  const params = event.queryStringParameters || {};
  const doSeed  = params.seed  === 'true';
  const doReset = params.reset === 'true';

  const sql = getDb();
  const results = [];

  try {
    // Optional: drop & recreate (dev/staging only)
    if (doReset) {
      for (const tbl of RESET_TABLES) {
        await sql.query(`DROP TABLE IF EXISTS ${tbl} CASCADE`);
        results.push(`DROP TABLE ${tbl}`);
      }
    }

    // Create tables
    for (const stmt of DDL_TABLES) {
      await sql.query(stmt);
      results.push('OK: ' + stmt.trim().split('\n')[0].slice(0, 60));
    }

    // Create indexes
    for (const stmt of DDL_INDEXES) {
      await sql.query(stmt);
      results.push('OK: ' + stmt.trim().slice(0, 60));
    }

    // Create triggers
    for (const stmt of DDL_TRIGGERS) {
      await sql.query(stmt);
      results.push('OK: trigger');
    }

    // Seed
    if (doSeed) {
      await runSeed(sql);
      results.push('OK: seed data inserted');
    }

    return json(200, {
      ok: true,
      message: 'DB初期化完了',
      seeded: doSeed,
      steps: results,
    });
  } catch (err) {
    return json(500, {
      ok: false,
      error: 'DB初期化エラー',
      detail: err.message,
    });
  }
};
