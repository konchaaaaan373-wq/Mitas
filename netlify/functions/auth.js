/**
 * Neco Auth Netlify Function
 *
 * ユーザー認証 API。デモハードコードから Neon PostgreSQL に移行済み。
 * パスワードは bcryptjs でハッシュ化。
 *
 * Routes (accessed via /api/auth/* → /.netlify/functions/auth/:splat):
 *   POST /api/auth/login    – ログイン → token + user
 *   GET  /api/auth/me       – Bearer トークンでプロフィール取得
 *   POST /api/auth/verify   – トークン検証
 */

const bcrypt = require('bcryptjs');
const { getDb } = require('./lib/db');
const {
  createToken, verifyToken,
  json, safeParseJson, getBearerToken, CORS_HEADERS,
} = require('./lib/auth-utils');

// ── DB helpers ───────────────────────────────────────────────────────────────

/** ユーザー行とプロフィールをマージしてフロントエンド互換オブジェクトを返す */
async function fetchUserWithProfile(sql, user) {
  let profile = {};

  if (user.user_type === 'doctor') {
    const [p] = await sql`
      SELECT * FROM doctor_profiles WHERE user_id = ${user.id}
    `;
    profile = p || {};
  } else if (user.user_type === 'nurse') {
    const [p] = await sql`
      SELECT * FROM nurse_profiles WHERE user_id = ${user.id}
    `;
    profile = p || {};
  } else if (user.user_type === 'medical') {
    const [p] = await sql`
      SELECT * FROM medical_institution_profiles WHERE user_id = ${user.id}
    `;
    profile = p || {};
  }

  // フロントエンドが期待するキー名（camelCase）に変換
  return {
    id:             user.id,
    email:          user.email,
    type:           user.user_type,
    name:           user.name,
    nameKana:       user.name_kana,
    avatarInitial:  user.avatar_initial,
    avatarColor:    user.avatar_color,
    // doctor / nurse 共通
    specialty:      profile.specialty      || null,
    subSpecialty:   profile.sub_specialty  || null,
    experience:     profile.experience     || null,
    affiliation:    profile.affiliation    || null,
    prefecture:     profile.prefecture     || null,
    available:      profile.available_days || null,
    hourlyRate:     profile.hourly_rate    || null,
    bio:            profile.bio            || null,
    // medical institution
    contactName:    profile.contact_name   || null,
    facilityType:   profile.facility_type  || null,
    city:           profile.city           || null,
    patientCount:   profile.patient_count  || null,
    needs:          profile.needs          || null,
  };
}

// ── Sub-path extractor ───────────────────────────────────────────────────────

const getSubPath = (eventPath) =>
  (eventPath || '')
    .replace(/\/?\.netlify\/functions\/auth/, '')
    .replace(/^\/+/, '');

// ── Handler ──────────────────────────────────────────────────────────────────

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: CORS_HEADERS, body: '' };
  }

  const method  = event.httpMethod;
  const subPath = getSubPath(event.path);
  const sql     = getDb();

  // ────────────────────────────────────────────────────────────────────────
  // POST /api/auth/login
  // ────────────────────────────────────────────────────────────────────────
  if (method === 'POST' && subPath === 'login') {
    const body = safeParseJson(event.body);
    if (!body) return json(400, { ok: false, error: '無効なリクエストです' });

    const { email, password } = body;
    if (!email || !password) {
      return json(400, { ok: false, error: 'メールアドレスとパスワードを入力してください' });
    }

    const normalizedEmail = String(email).trim().toLowerCase();

    let user;
    try {
      const rows = await sql`
        SELECT * FROM users WHERE email = ${normalizedEmail} AND is_active = true
      `;
      user = rows[0];
    } catch (err) {
      console.error('[auth] DB error on login:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }

    if (!user) {
      return json(401, { ok: false, error: 'メールアドレスまたはパスワードが正しくありません' });
    }

    const valid = await bcrypt.compare(String(password), user.password_hash);
    if (!valid) {
      return json(401, { ok: false, error: 'メールアドレスまたはパスワードが正しくありません' });
    }

    const userData = await fetchUserWithProfile(sql, user);
    const token    = createToken(userData);
    return json(200, { ok: true, token, user: userData });
  }

  // ────────────────────────────────────────────────────────────────────────
  // GET /api/auth/me
  // ────────────────────────────────────────────────────────────────────────
  if (method === 'GET' && subPath === 'me') {
    const token   = getBearerToken(event);
    if (!token) return json(401, { ok: false, error: '認証が必要です' });

    const payload = verifyToken(token);
    if (!payload) return json(401, { ok: false, error: 'トークンが無効または期限切れです' });

    let user;
    try {
      const rows = await sql`
        SELECT * FROM users WHERE id = ${payload.id} AND is_active = true
      `;
      user = rows[0];
    } catch (err) {
      console.error('[auth] DB error on me:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }

    if (!user) return json(401, { ok: false, error: 'ユーザーが見つかりません' });

    const userData = await fetchUserWithProfile(sql, user);
    return json(200, { ok: true, user: userData });
  }

  // ────────────────────────────────────────────────────────────────────────
  // POST /api/auth/verify
  // ────────────────────────────────────────────────────────────────────────
  if (method === 'POST' && subPath === 'verify') {
    const body = safeParseJson(event.body);
    if (!body || !body.token) {
      return json(400, { ok: false, error: 'トークンが必要です' });
    }
    const payload = verifyToken(body.token);
    if (!payload) {
      return json(401, { ok: false, error: 'トークンが無効または期限切れです' });
    }
    return json(200, { ok: true, payload });
  }

  return json(404, { ok: false, error: 'Not found' });
};
