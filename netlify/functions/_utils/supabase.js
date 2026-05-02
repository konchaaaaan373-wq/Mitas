/**
 * Supabase REST (PostgREST) ユーティリティ
 *
 * - Bearer JWT を検証してユーザー情報を取得
 * - 取得した JWT を使ってユーザー権限で PostgREST を呼ぶ
 *   → RLS が自動で適用される
 * - 必要に応じて service_role キーで RLS をバイパスするヘルパーも提供
 *
 * 環境変数:
 *   SUPABASE_URL              - Supabase プロジェクト URL
 *   SUPABASE_ANON_KEY         - anon キー（クライアント側公開可）
 *   SUPABASE_SERVICE_ROLE_KEY - service_role キー（サーバー側のみ）
 */

const CORS_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function jsonResponse(statusCode, body) {
  return { statusCode, headers: CORS_HEADERS, body: JSON.stringify(body) };
}

function isMockMode() {
  const url = process.env.SUPABASE_URL || '';
  return !url || url.includes('YOUR_PROJECT');
}

function extractBearer(headers) {
  const h = headers['authorization'] || headers['Authorization'] || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}

/**
 * Supabase Auth でアクセストークンを検証
 * 成功時は { id, email, ... } を返す
 */
async function verifyAccessToken(token) {
  const url = process.env.SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY;
  if (!url || !anon) throw new Error('Supabase が設定されていません');

  const res = await fetch(`${url}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: anon },
  });
  if (!res.ok) throw new Error('セッション無効');
  return res.json();
}

/**
 * リクエストを認証し、ユーザー情報とJWTを返す
 * 失敗時はレスポンスを返す（呼び出し側でそのまま return する想定）
 */
async function requireAuth(event) {
  const token = extractBearer(event.headers);
  if (!token) {
    return { error: jsonResponse(401, { error: '認証トークンがありません。' }) };
  }
  if (isMockMode()) {
    return { user: { id: 'mock-user', email: 'mock@example.com' }, token, mock: true };
  }
  try {
    const user = await verifyAccessToken(token);
    if (!user || !user.id) {
      return { error: jsonResponse(401, { error: '認証に失敗しました。' }) };
    }
    return { user, token };
  } catch (e) {
    return { error: jsonResponse(401, { error: 'セッションが無効です。' }) };
  }
}

/**
 * ユーザーJWTでPostgRESTを呼ぶ（RLSが効く）
 * @param {string} path '/staffing_requests?select=*'
 */
async function pgUserFetch(path, token, init = {}) {
  const url = process.env.SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY;
  const headers = {
    apikey: anon,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    Accept: 'application/json',
    ...(init.headers || {}),
  };
  const res = await fetch(`${url}/rest/v1${path}`, { ...init, headers });
  return res;
}

/**
 * service_role でPostgRESTを呼ぶ（RLSをバイパス・使用は最小限に）
 */
async function pgServiceFetch(path, init = {}) {
  const url = process.env.SUPABASE_URL;
  const sr = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!sr) throw new Error('SERVICE_ROLE_KEY 未設定');
  const headers = {
    apikey: sr,
    Authorization: `Bearer ${sr}`,
    'Content-Type': 'application/json',
    Accept: 'application/json',
    ...(init.headers || {}),
  };
  const res = await fetch(`${url}/rest/v1${path}`, { ...init, headers });
  return res;
}

/**
 * 監査ログを書き込む（service_role 使用）
 *
 * actor_role が未指定で actor_user_id が指定されている場合、
 * user_roles から role を取得して記録する（呼び出し側の引数省略を許容）。
 */
async function logActivity({ actor_user_id, actor_role, action, entity_type, entity_id, organization_id, before, after, headers = {} }) {
  if (isMockMode()) return;
  try {
    let role = actor_role || null;
    if (!role && actor_user_id) {
      try {
        const res = await pgServiceFetch(`/user_roles?user_id=eq.${encodeURIComponent(actor_user_id)}&select=role&limit=1`);
        if (res.ok) {
          const rows = await res.json();
          if (Array.isArray(rows) && rows[0] && rows[0].role) role = rows[0].role;
        }
      } catch (_) { /* role 取得失敗は致命的ではないので無視 */ }
    }
    await pgServiceFetch('/activity_log', {
      method: 'POST',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({
        actor_user_id,
        actor_role: role,
        action,
        entity_type,
        entity_id,
        organization_id,
        before_state: before || null,
        after_state: after || null,
        ip_address: headers['x-forwarded-for']?.split(',')[0]?.trim() || null,
        user_agent: headers['user-agent'] || null,
      }),
    });
  } catch (e) {
    console.error('activity_log write failed:', e.message);
  }
}

module.exports = {
  CORS_HEADERS,
  jsonResponse,
  isMockMode,
  extractBearer,
  verifyAccessToken,
  requireAuth,
  pgUserFetch,
  pgServiceFetch,
  logActivity,
};
