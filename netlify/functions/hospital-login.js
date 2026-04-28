/**
 * POST /api/hospital/login
 * 病院管理者ログイン認証
 *
 * 環境変数:
 *   SESSION_SECRET     - JWTの署名キー（必須。未設定時は開発用の固定値を使用）
 *   HOSPITAL_ACCOUNTS  - JSON配列: [{"org_id":"...","name":"...","pwd_hash":"..."}]
 *   DEMO_PASSWORD      - デモアカウントのパスワード（未設定時: mitas-demo-2024）
 *
 * パスワードハッシュの生成方法:
 *   const crypto = require('crypto');
 *   const hash = crypto.createHmac('sha256', SESSION_SECRET).update(password).digest('hex');
 */

const crypto = require('crypto');

const CORS_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

exports.handler = async (event) => {
  // プリフライトリクエスト対応
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: CORS_HEADERS, body: '' };
  }

  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, headers: CORS_HEADERS, body: JSON.stringify({ error: 'Method Not Allowed' }) };
  }

  // リクエストボディのパース
  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return { statusCode: 400, headers: CORS_HEADERS, body: JSON.stringify({ error: 'リクエストの形式が正しくありません。' }) };
  }

  const { org_id, password } = body;

  if (!org_id || !password) {
    return { statusCode: 400, headers: CORS_HEADERS, body: JSON.stringify({ error: '組織IDとパスワードは必須です。' }) };
  }

  const secret = process.env.SESSION_SECRET || 'dev-secret-change-before-production';

  // アカウント一覧の取得
  const accounts = buildAccountList(secret);

  // 組織IDで検索（大文字小文字を区別しない）
  const account = accounts.find(a => a.org_id.toLowerCase() === org_id.toLowerCase());

  // 存在しない場合も「同じ時間」かけて応答する（タイミング攻撃対策）
  const inputHash = hashPassword(password, secret);
  const storedHash = account ? account.pwd_hash : '0'.repeat(64);

  if (!account || !safeCompare(inputHash, storedHash)) {
    return {
      statusCode: 401,
      headers: CORS_HEADERS,
      body: JSON.stringify({ error: '組織IDまたはパスワードが正しくありません。' }),
    };
  }

  // JWTトークンの発行
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    sub:  account.org_id,
    name: account.name,
    role: 'hospital',
    iat:  now,
    exp:  now + 60 * 60 * 24 * 7, // 7日間有効
  };

  const token = signJwt(payload, secret);

  return {
    statusCode: 200,
    headers: CORS_HEADERS,
    body: JSON.stringify({
      token,
      organization: { id: account.org_id, name: account.name },
    }),
  };
};

/* ─── JWTの署名 ─────────────────────────────── */
function signJwt(payload, secret) {
  const header  = toBase64Url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body    = toBase64Url(JSON.stringify(payload));
  const sig     = crypto.createHmac('sha256', secret).update(`${header}.${body}`).digest('base64url');
  return `${header}.${body}.${sig}`;
}

function toBase64Url(str) {
  return Buffer.from(str).toString('base64url');
}

/* ─── パスワードハッシュ ─────────────────────── */
function hashPassword(password, secret) {
  return crypto.createHmac('sha256', secret).update(password).digest('hex');
}

/* ─── 定数時間文字列比較（タイミング攻撃対策） ── */
function safeCompare(a, b) {
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
}

/* ─── アカウント一覧の構築 ─────────────────── */
function buildAccountList(secret) {
  const accounts = [];

  // 本番アカウント（環境変数 HOSPITAL_ACCOUNTS で設定）
  if (process.env.HOSPITAL_ACCOUNTS) {
    try {
      const parsed = JSON.parse(process.env.HOSPITAL_ACCOUNTS);
      accounts.push(...parsed);
    } catch (e) {
      console.error('HOSPITAL_ACCOUNTS のパースに失敗しました:', e.message);
    }
  }

  // デモアカウント（本番環境以外のみ有効）
  if (process.env.NODE_ENV !== 'production') {
    const demoPassword = process.env.DEMO_PASSWORD || 'mitas-demo-2024';
    accounts.push({
      org_id:   'DEMO-001',
      name:     'デモ病院（MITAS検証用）',
      pwd_hash: hashPassword(demoPassword, secret),
    });
  }

  return accounts;
}
