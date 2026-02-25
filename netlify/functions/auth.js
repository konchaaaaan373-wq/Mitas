/**
 * Neco Auth Netlify Function
 *
 * Handles authentication for doctors and medical institutions.
 *
 * DEMO NOTICE: User credentials are hardcoded for demo purposes.
 * In production, replace DEMO_USERS with database queries (e.g., Supabase, PlanetScale)
 * and use bcrypt for password hashing.
 *
 * Routes (accessed via /api/auth/*  → /.netlify/functions/auth/:splat):
 *   POST /api/auth/login   – validate credentials, return signed token + user
 *   GET  /api/auth/me      – verify Bearer token, return user profile
 *   POST /api/auth/verify  – verify a token string, return its payload
 */

const crypto = require('crypto');

// ---------------------------------------------------------------------------
// Secret key – set SESSION_SECRET in Netlify environment variables.
// The fallback value is intentionally weak and only safe for demo deployments.
// ---------------------------------------------------------------------------
const SESSION_SECRET =
  process.env.SESSION_SECRET || 'neco-demo-secret-CHANGE-ME-in-production';

// ---------------------------------------------------------------------------
// Demo user store – replace with real DB queries in production.
// Passwords stored in plain text here ONLY for demo; use bcrypt in production.
// ---------------------------------------------------------------------------
const DEMO_USERS = [
  // --- Doctors ---
  {
    id: 'dr-001',
    email: 'dr-demo@neco.jp',
    password: 'demo1234',
    type: 'doctor',
    name: '田中 太郎',
    nameKana: 'タナカ タロウ',
    specialty: '内科',
    subSpecialty: '在宅医療',
    experience: '8年',
    affiliation: '東京医科大学病院',
    prefecture: '東京都',
    available: ['土', '日'],
    hourlyRate: '5万円〜',
    bio: '在宅医療に情熱を持ち、患者さんの生活に寄り添った医療を提供しています。',
    avatarInitial: '田',
    avatarColor: '#FF6B9D',
  },
  {
    id: 'dr-002',
    email: 'dr-sato@neco.jp',
    password: 'demo1234',
    type: 'doctor',
    name: '佐藤 美咲',
    nameKana: 'サトウ ミサキ',
    specialty: '総合診療',
    subSpecialty: '在宅医療・緩和ケア',
    experience: '12年',
    affiliation: '慶應義塾大学病院',
    prefecture: '神奈川県',
    available: ['月', '水', '金'],
    hourlyRate: '6万円〜',
    bio: '緩和ケアを専門に、患者さんと家族を支える在宅医療を実践しています。',
    avatarInitial: '佐',
    avatarColor: '#A78BFA',
  },
  // --- Medical institutions ---
  {
    id: 'mc-001',
    email: 'clinic-demo@neco.jp',
    password: 'demo1234',
    type: 'medical',
    name: 'さくら在宅クリニック',
    contactName: '山田 花子',
    facilityType: '在宅医療クリニック',
    prefecture: '東京都',
    city: '渋谷区',
    patientCount: 180,
    needs: ['内科外来', '在宅診療'],
    bio: '渋谷区を中心に在宅医療を提供しています。患者さんの在宅生活を支えるチームです。',
    avatarInitial: 'さ',
    avatarColor: '#4ECDC4',
  },
  {
    id: 'mc-002',
    email: 'hospital-demo@neco.jp',
    password: 'demo1234',
    type: 'medical',
    name: 'みなと訪問看護ステーション',
    contactName: '鈴木 一郎',
    facilityType: '訪問看護ステーション',
    prefecture: '東京都',
    city: '港区',
    patientCount: 95,
    needs: ['総合診療', '緩和ケア'],
    bio: '港区を拠点に、医師と協力して在宅療養を支えています。',
    avatarInitial: 'み',
    avatarColor: '#4CC9F0',
  },
];

// ---------------------------------------------------------------------------
// Token utilities (simple HMAC-based; good for demo, use proper JWT in prod)
// ---------------------------------------------------------------------------
const sign = (data) =>
  crypto.createHmac('sha256', SESSION_SECRET).update(data).digest('hex');

const toBase64url = (str) =>
  Buffer.from(str)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');

const fromBase64url = (str) => {
  const padded =
    str.replace(/-/g, '+').replace(/_/g, '/') +
    '='.repeat((4 - (str.length % 4)) % 4);
  return Buffer.from(padded, 'base64').toString();
};

const createToken = (user) => {
  const payload = {
    id: user.id,
    email: user.email,
    type: user.type,
    name: user.name,
    iat: Date.now(),
    exp: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 days
  };
  const payloadStr = toBase64url(JSON.stringify(payload));
  const signature = sign(payloadStr);
  return `${payloadStr}.${signature}`;
};

const verifyToken = (token) => {
  try {
    const dotIdx = token.lastIndexOf('.');
    if (dotIdx === -1) return null;
    const payloadStr = token.slice(0, dotIdx);
    const signature = token.slice(dotIdx + 1);
    if (sign(payloadStr) !== signature) return null;
    const payload = JSON.parse(fromBase64url(payloadStr));
    if (payload.exp < Date.now()) return null;
    return payload;
  } catch (_) {
    return null;
  }
};

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS_HEADERS },
  body: JSON.stringify(body),
});

const safeParseJson = (raw) => {
  try {
    return JSON.parse(raw || '{}');
  } catch (_) {
    return null;
  }
};

// Strip the function base path to get the sub-route
const getSubPath = (eventPath) =>
  (eventPath || '')
    .replace(/\/?\.netlify\/functions\/auth/, '')
    .replace(/^\/+/, '');

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------
exports.handler = async (event) => {
  // Pre-flight CORS
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: CORS_HEADERS, body: '' };
  }

  const method = event.httpMethod;
  const subPath = getSubPath(event.path);

  // ------------------------------------------------------------------
  // POST /api/auth/login
  // Body: { email: string, password: string }
  // Returns: { ok: true, token, user } | { ok: false, error }
  // ------------------------------------------------------------------
  if (method === 'POST' && subPath === 'login') {
    const body = safeParseJson(event.body);
    if (!body) return json(400, { ok: false, error: '無効なリクエストです' });

    const { email, password } = body;
    if (!email || !password) {
      return json(400, { ok: false, error: 'メールアドレスとパスワードを入力してください' });
    }

    const normalizedEmail = String(email).trim().toLowerCase();
    const user = DEMO_USERS.find(
      (u) => u.email === normalizedEmail && u.password === password
    );

    if (!user) {
      // Return 401 with a generic message (avoid leaking which field was wrong)
      return json(401, {
        ok: false,
        error: 'メールアドレスまたはパスワードが正しくありません',
      });
    }

    const token = createToken(user);
    const { password: _pw, ...safeUser } = user;
    return json(200, { ok: true, token, user: safeUser });
  }

  // ------------------------------------------------------------------
  // GET /api/auth/me
  // Header: Authorization: Bearer <token>
  // Returns: { ok: true, user } | { ok: false, error }
  // ------------------------------------------------------------------
  if (method === 'GET' && subPath === 'me') {
    const authHeader =
      event.headers['authorization'] || event.headers['Authorization'] || '';
    if (!authHeader.startsWith('Bearer ')) {
      return json(401, { ok: false, error: '認証が必要です' });
    }

    const token = authHeader.slice(7);
    const payload = verifyToken(token);
    if (!payload) {
      return json(401, { ok: false, error: 'トークンが無効または期限切れです' });
    }

    const user = DEMO_USERS.find((u) => u.id === payload.id);
    if (!user) return json(401, { ok: false, error: 'ユーザーが見つかりません' });

    const { password: _pw, ...safeUser } = user;
    return json(200, { ok: true, user: safeUser });
  }

  // ------------------------------------------------------------------
  // POST /api/auth/verify
  // Body: { token: string }
  // Returns: { ok: true, payload } | { ok: false, error }
  // ------------------------------------------------------------------
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
