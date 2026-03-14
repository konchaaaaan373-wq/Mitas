// auth.js – mitas 認証API
// POST /api/auth/login  → 施設ログイン・トークン発行
// GET  /api/auth/me     → トークン検証・プロフィール取得

const crypto = require('crypto');

const SECRET = process.env.SESSION_SECRET || 'dev-secret-change-in-production';

// デモ用施設アカウント（本番ではDBに移行）
const DEMO_FACILITIES = [
  {
    id: 'facility-001',
    email: 'demo@mitas.jp',
    password: 'demo1234',
    name: 'サンプルクリニック',
    type: 'clinic',
    role: 'facility',
  },
];

function signToken(payload) {
  const data = JSON.stringify(payload);
  const encoded = Buffer.from(data).toString('base64url');
  const sig = crypto.createHmac('sha256', SECRET).update(encoded).digest('base64url');
  return `${encoded}.${sig}`;
}

function verifyToken(token) {
  const [encoded, sig] = token.split('.');
  if (!encoded || !sig) return null;
  const expected = crypto.createHmac('sha256', SECRET).update(encoded).digest('base64url');
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  try {
    return JSON.parse(Buffer.from(encoded, 'base64url').toString());
  } catch {
    return null;
  }
}

exports.handler = async (event) => {
  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers, body: '' };
  }

  const path = event.path.replace('/api/auth/', '').replace(/^\//, '');

  // POST /api/auth/login
  if (event.httpMethod === 'POST' && path === 'login') {
    let body;
    try {
      body = JSON.parse(event.body || '{}');
    } catch {
      return { statusCode: 400, headers, body: JSON.stringify({ error: 'Invalid JSON' }) };
    }

    const facility = DEMO_FACILITIES.find(
      (f) => f.email === body.email && f.password === body.password
    );
    if (!facility) {
      return { statusCode: 401, headers, body: JSON.stringify({ error: 'メールアドレスまたはパスワードが正しくありません' }) };
    }

    const payload = {
      sub: facility.id,
      email: facility.email,
      name: facility.name,
      role: facility.role,
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 7, // 7日間
    };
    const token = signToken(payload);

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({ token, user: { id: facility.id, email: facility.email, name: facility.name, role: facility.role } }),
    };
  }

  // GET /api/auth/me
  if (event.httpMethod === 'GET' && path === 'me') {
    const auth = event.headers['authorization'] || '';
    const token = auth.replace('Bearer ', '');
    const payload = verifyToken(token);
    if (!payload || payload.exp < Math.floor(Date.now() / 1000)) {
      return { statusCode: 401, headers, body: JSON.stringify({ error: 'Unauthorized' }) };
    }
    return { statusCode: 200, headers, body: JSON.stringify({ user: payload }) };
  }

  return { statusCode: 404, headers, body: JSON.stringify({ error: 'Not found' }) };
};
