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
    id:                user.id,
    email:             user.email,
    type:              user.user_type,
    name:              user.name,
    nameKana:          user.name_kana,
    avatarInitial:     user.avatar_initial,
    avatarColor:       user.avatar_color,
    emailNotification: user.email_notification || false,
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

/**
 * Neco システムユーザーを取得または作成する。
 * 新規ユーザー登録時にウェルカム会話を作るために使用。
 */
async function getOrCreateNecoUser(sql) {
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

/**
 * 新規ユーザーのウェルカム会話を Neco との間に作成し、ウェルカムメッセージを送信する。
 */
async function createNecoWelcomeConversation(sql, newUserId) {
  try {
    const necoId = await getOrCreateNecoUser(sql);

    // participant ID を正規化（小さい方が participant1）
    const p1 = newUserId < necoId ? newUserId : necoId;
    const p2 = newUserId < necoId ? necoId : newUserId;

    // 既存の会話を確認
    let [conv] = await sql`
      SELECT id FROM conversations WHERE participant1_id = ${p1} AND participant2_id = ${p2}
    `;

    if (!conv) {
      [conv] = await sql`
        INSERT INTO conversations (participant1_id, participant2_id, last_message_at)
        VALUES (${p1}, ${p2}, NOW())
        RETURNING id
      `;
    }

    // ウェルカムメッセージを Neco から送信
    const welcomeMessage = `はじめまして！Necoです。あなたの転職・キャリアアップを全力で応援します🐱

在宅医療・訪問診療に特化した求人情報をご紹介しています。
ご質問やご要望があれば、お気軽にこちらでメッセージをお送りください。

✨ 転職案件のご提案や、医療機関からのスカウトメッセージもこちらに届きます。どうぞよろしくお願いいたします！`;

    await sql`
      INSERT INTO messages (conversation_id, sender_id, content)
      VALUES (${conv.id}, ${necoId}, ${welcomeMessage})
    `;

    await sql`UPDATE conversations SET last_message_at = NOW() WHERE id = ${conv.id}`;
  } catch (err) {
    console.error('[users] createNecoWelcomeConversation error:', err.message);
    // ウェルカム会話の作成失敗はユーザー登録を阻害しない
  }
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
      emailNotification,
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

      const emailNotifValue = emailNotification === true || emailNotification === 'true';

      const [userRow] = await sql`
        INSERT INTO users
          (email, password_hash, user_type, name, name_kana, avatar_initial, avatar_color, email_notification)
        VALUES
          (${normalizedEmail}, ${password_hash}, ${user_type}, ${name},
           ${nameKana || null}, ${avatarInitial || name[0] || null}, ${avatarColor || null},
           ${emailNotifValue})
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

      // Neco とのウェルカム会話を作成（非同期で行い、失敗してもユーザー登録は成功）
      await createNecoWelcomeConversation(sql, userRow.id);

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
          body.avatarInitial !== undefined || body.avatarColor !== undefined ||
          body.emailNotification !== undefined) {
        const emailNotifValue = body.emailNotification !== undefined
          ? (body.emailNotification === true || body.emailNotification === 'true')
          : null;
        await sql`
          UPDATE users SET
            name               = COALESCE(${body.name || null},          name),
            name_kana          = COALESCE(${body.nameKana || null},      name_kana),
            avatar_initial     = COALESCE(${body.avatarInitial || null}, avatar_initial),
            avatar_color       = COALESCE(${body.avatarColor || null},   avatar_color),
            email_notification = COALESCE(${emailNotifValue},            email_notification)
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
