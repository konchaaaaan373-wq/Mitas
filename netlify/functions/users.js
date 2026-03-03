/**
 * Users Netlify Function – ユーザー登録・プロフィール管理
 *
 * Routes (via /api/users/* → /.netlify/functions/users/:splat):
 *   POST /api/users/register          – 新規ユーザー登録
 *   GET  /api/users/profile           – 自分のプロフィール取得（要認証）
 *   PUT  /api/users/profile           – 自分のプロフィール更新（要認証）
 *   GET  /api/users/:id               – 他ユーザーの公開プロフィール取得（要認証）
 */

const bcrypt = require('bcryptjs');
const { getDb } = require('./lib/db');
const {
  verifyToken, createToken,
  json, safeParseJson, getBearerToken, CORS_HEADERS,
} = require('./lib/auth-utils');

const SALT_ROUNDS = 10;

// ── Helpers ──────────────────────────────────────────────────────────────────

const getSubPath = (path) =>
  (path || '').replace(/\/?\.netlify\/functions\/users\/?/, '').replace(/^\/+/, '');

/** Bearer トークンからユーザーIDを検証して返す。失敗時は null を返す */
const authenticate = (event) => {
  const token = getBearerToken(event);
  if (!token) return null;
  return verifyToken(token);
};

/** DB の users 行からフロントエンド互換オブジェクトへ変換（password_hash を除外） */
function formatUser(user, profile = {}) {
  return {
    id:            user.id,
    email:         user.email,
    type:          user.user_type,
    name:          user.name,
    nameKana:      user.name_kana,
    avatarInitial: user.avatar_initial,
    avatarColor:   user.avatar_color,
    // doctor / nurse
    specialty:     profile.specialty      || null,
    subSpecialty:  profile.sub_specialty  || null,
    experience:    profile.experience     || null,
    affiliation:   profile.affiliation    || null,
    prefecture:    profile.prefecture     || null,
    available:     profile.available_days || null,
    hourlyRate:    profile.hourly_rate    || null,
    bio:           profile.bio            || null,
    // medical institution
    contactName:   profile.contact_name   || null,
    facilityType:  profile.facility_type  || null,
    city:          profile.city           || null,
    patientCount:  profile.patient_count  || null,
    needs:         profile.needs          || null,
  };
}

async function fetchProfile(sql, userId, userType) {
  if (userType === 'doctor') {
    const [p] = await sql`SELECT * FROM doctor_profiles WHERE user_id = ${userId}`;
    return p || {};
  }
  if (userType === 'nurse') {
    const [p] = await sql`SELECT * FROM nurse_profiles WHERE user_id = ${userId}`;
    return p || {};
  }
  if (userType === 'medical') {
    const [p] = await sql`SELECT * FROM medical_institution_profiles WHERE user_id = ${userId}`;
    return p || {};
  }
  return {};
}

// ── Handler ──────────────────────────────────────────────────────────────────

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: CORS_HEADERS, body: '' };
  }

  const method  = event.httpMethod;
  const subPath = getSubPath(event.path);
  const sql     = getDb();

  // ──────────────────────────────────────────────────────────────────────────
  // POST /api/users/register
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'POST' && subPath === 'register') {
    const body = safeParseJson(event.body);
    if (!body) return json(400, { ok: false, error: '無効なリクエストです' });

    const {
      email, password, user_type,
      name, nameKana, avatarInitial, avatarColor,
      // doctor / nurse profile
      specialty, subSpecialty, experience, affiliation,
      prefecture, available, hourlyRate, bio,
      // medical profile
      contactName, facilityType, city, patientCount, needs,
    } = body;

    if (!email || !password || !user_type || !name) {
      return json(400, { ok: false, error: 'メール・パスワード・ユーザー種別・名前は必須です' });
    }
    if (!['doctor', 'nurse', 'medical'].includes(user_type)) {
      return json(400, { ok: false, error: '無効なユーザー種別です' });
    }
    if (String(password).length < 8) {
      return json(400, { ok: false, error: 'パスワードは8文字以上にしてください' });
    }

    const normalizedEmail = String(email).trim().toLowerCase();

    try {
      // 重複チェック
      const existing = await sql`SELECT id FROM users WHERE email = ${normalizedEmail}`;
      if (existing.length > 0) {
        return json(409, { ok: false, error: 'このメールアドレスはすでに登録されています' });
      }

      const password_hash = await bcrypt.hash(String(password), SALT_ROUNDS);

      const [userRow] = await sql`
        INSERT INTO users
          (email, password_hash, user_type, name, name_kana, avatar_initial, avatar_color)
        VALUES
          (${normalizedEmail}, ${password_hash}, ${user_type}, ${name},
           ${nameKana || null}, ${avatarInitial || name[0] || null}, ${avatarColor || null})
        RETURNING *
      `;

      // プロフィール挿入
      if (user_type === 'doctor') {
        await sql`
          INSERT INTO doctor_profiles
            (user_id, specialty, sub_specialty, experience, affiliation,
             prefecture, available_days, hourly_rate, bio)
          VALUES
            (${userRow.id}, ${specialty || null}, ${subSpecialty || null},
             ${experience || null}, ${affiliation || null}, ${prefecture || null},
             ${available || null}, ${hourlyRate || null}, ${bio || null})
        `;
      } else if (user_type === 'nurse') {
        await sql`
          INSERT INTO nurse_profiles
            (user_id, specialty, sub_specialty, experience, affiliation,
             prefecture, available_days, hourly_rate, bio)
          VALUES
            (${userRow.id}, ${specialty || null}, ${subSpecialty || null},
             ${experience || null}, ${affiliation || null}, ${prefecture || null},
             ${available || null}, ${hourlyRate || null}, ${bio || null})
        `;
      } else if (user_type === 'medical') {
        await sql`
          INSERT INTO medical_institution_profiles
            (user_id, contact_name, facility_type, prefecture, city,
             patient_count, needs, bio)
          VALUES
            (${userRow.id}, ${contactName || null}, ${facilityType || null},
             ${prefecture || null}, ${city || null},
             ${patientCount || null}, ${needs || null}, ${bio || null})
        `;
      }

      const profile  = await fetchProfile(sql, userRow.id, user_type);
      const userData = formatUser(userRow, profile);
      const token    = createToken(userData);

      return json(201, { ok: true, token, user: userData });
    } catch (err) {
      console.error('[users] register error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GET /api/users/profile  – 自分のプロフィール
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'GET' && subPath === 'profile') {
    const payload = authenticate(event);
    if (!payload) return json(401, { ok: false, error: '認証が必要です' });

    try {
      const [user] = await sql`
        SELECT * FROM users WHERE id = ${payload.id} AND is_active = true
      `;
      if (!user) return json(404, { ok: false, error: 'ユーザーが見つかりません' });

      const profile  = await fetchProfile(sql, user.id, user.user_type);
      return json(200, { ok: true, user: formatUser(user, profile) });
    } catch (err) {
      console.error('[users] profile get error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUT /api/users/profile  – プロフィール更新
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'PUT' && subPath === 'profile') {
    const payload = authenticate(event);
    if (!payload) return json(401, { ok: false, error: '認証が必要です' });

    const body = safeParseJson(event.body);
    if (!body) return json(400, { ok: false, error: '無効なリクエストです' });

    try {
      const [user] = await sql`
        SELECT * FROM users WHERE id = ${payload.id} AND is_active = true
      `;
      if (!user) return json(404, { ok: false, error: 'ユーザーが見つかりません' });

      // users テーブル更新
      if (body.name || body.nameKana !== undefined ||
          body.avatarInitial !== undefined || body.avatarColor !== undefined) {
        await sql`
          UPDATE users SET
            name           = COALESCE(${body.name || null},          name),
            name_kana      = COALESCE(${body.nameKana || null},      name_kana),
            avatar_initial = COALESCE(${body.avatarInitial || null}, avatar_initial),
            avatar_color   = COALESCE(${body.avatarColor || null},   avatar_color)
          WHERE id = ${user.id}
        `;
      }

      // プロフィールテーブル更新
      if (user.user_type === 'doctor') {
        await sql`
          UPDATE doctor_profiles SET
            specialty      = COALESCE(${body.specialty     || null}, specialty),
            sub_specialty  = COALESCE(${body.subSpecialty  || null}, sub_specialty),
            experience     = COALESCE(${body.experience    || null}, experience),
            affiliation    = COALESCE(${body.affiliation   || null}, affiliation),
            prefecture     = COALESCE(${body.prefecture    || null}, prefecture),
            available_days = COALESCE(${body.available     || null}, available_days),
            hourly_rate    = COALESCE(${body.hourlyRate    || null}, hourly_rate),
            bio            = COALESCE(${body.bio           || null}, bio)
          WHERE user_id = ${user.id}
        `;
      } else if (user.user_type === 'nurse') {
        await sql`
          UPDATE nurse_profiles SET
            specialty      = COALESCE(${body.specialty    || null}, specialty),
            sub_specialty  = COALESCE(${body.subSpecialty || null}, sub_specialty),
            experience     = COALESCE(${body.experience   || null}, experience),
            affiliation    = COALESCE(${body.affiliation  || null}, affiliation),
            prefecture     = COALESCE(${body.prefecture   || null}, prefecture),
            available_days = COALESCE(${body.available    || null}, available_days),
            hourly_rate    = COALESCE(${body.hourlyRate   || null}, hourly_rate),
            bio            = COALESCE(${body.bio          || null}, bio)
          WHERE user_id = ${user.id}
        `;
      } else if (user.user_type === 'medical') {
        await sql`
          UPDATE medical_institution_profiles SET
            contact_name  = COALESCE(${body.contactName  || null}, contact_name),
            facility_type = COALESCE(${body.facilityType || null}, facility_type),
            prefecture    = COALESCE(${body.prefecture   || null}, prefecture),
            city          = COALESCE(${body.city         || null}, city),
            patient_count = COALESCE(${body.patientCount || null}, patient_count),
            needs         = COALESCE(${body.needs        || null}, needs),
            bio           = COALESCE(${body.bio          || null}, bio)
          WHERE user_id = ${user.id}
        `;
      }

      const [updated] = await sql`SELECT * FROM users WHERE id = ${user.id}`;
      const profile   = await fetchProfile(sql, user.id, user.user_type);
      return json(200, { ok: true, user: formatUser(updated, profile) });
    } catch (err) {
      console.error('[users] profile update error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GET /api/users/:id  – 他ユーザーの公開プロフィール（要認証）
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'GET' && subPath && !subPath.includes('/')) {
    const payload = authenticate(event);
    if (!payload) return json(401, { ok: false, error: '認証が必要です' });

    const targetId = subPath;

    try {
      const [user] = await sql`
        SELECT * FROM users WHERE id = ${targetId} AND is_active = true
      `;
      if (!user) return json(404, { ok: false, error: 'ユーザーが見つかりません' });

      const profile = await fetchProfile(sql, user.id, user.user_type);
      return json(200, { ok: true, user: formatUser(user, profile) });
    } catch (err) {
      console.error('[users] get by id error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  return json(404, { ok: false, error: 'Not found' });
};
