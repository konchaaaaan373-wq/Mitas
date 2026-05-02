/**
 * Me API v2 — 自分の組織情報を返す
 *
 * Route: GET /api/v2/me/org
 *
 * 背景:
 *   PostgREST 経由で `organization_members` を直接 SELECT すると、
 *   同テーブルの SELECT RLS が自己参照サブセレクト
 *   （organization_id IN (SELECT organization_id FROM organization_members ...)）
 *   を含むため、RLS 評価が再帰し 500 を返すケースがある
 *   （クライアント側 hospital-login.js で再現）。
 *
 * 解決:
 *   サーバー側で JWT を verifyAccessToken し、確定した auth.user.id を
 *   service_role でクエリする。RLS をバイパスするが、返すのは
 *   「ログインユーザー本人の組織」だけなので情報漏洩リスクは無い。
 *
 * 返却: { organization: { id, name } | null, role: string | null }
 */

const {
  CORS_HEADERS,
  jsonResponse,
  requireAuth,
  pgServiceFetch,
} = require('./_utils/supabase');

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: CORS_HEADERS, body: '' };
  }
  if (event.httpMethod !== 'GET') {
    return jsonResponse(405, { error: 'Method Not Allowed' });
  }

  const auth = await requireAuth(event);
  if (auth.error) return auth.error;

  // mock mode: 固定のデモ組織を返す
  if (auth.mock) {
    return jsonResponse(200, {
      organization: { id: 'mock-org-id', name: 'デモ病院' },
      role: 'facility_admin',
    });
  }

  const userId = auth.user.id;

  try {
    // Step 1: organization_members から自組織 id を取得（service_role で RLS バイパス）
    const memberRes = await pgServiceFetch(
      `/organization_members?user_id=eq.${encodeURIComponent(userId)}&is_active=eq.true&select=organization_id&limit=1`
    );
    if (!memberRes.ok) {
      const detail = await memberRes.text();
      return jsonResponse(memberRes.status, { error: 'DB error (member)', detail });
    }
    const memberRows = await memberRes.json();
    const orgId = memberRows[0]?.organization_id || null;

    // Step 2: user_roles から role を取得
    let role = null;
    try {
      const roleRes = await pgServiceFetch(
        `/user_roles?user_id=eq.${encodeURIComponent(userId)}&select=role&limit=1`
      );
      if (roleRes.ok) {
        const roleRows = await roleRes.json();
        role = roleRows[0]?.role || null;
      }
    } catch (_) { /* role 取得失敗は致命的ではない */ }

    // 組織未所属（worker / neco_admin / alliance_admin など）はそのまま null を返す
    if (!orgId) {
      return jsonResponse(200, { organization: null, role });
    }

    // Step 3: organizations から name を取得（補助情報）
    let orgName = '';
    try {
      const orgRes = await pgServiceFetch(
        `/organizations?id=eq.${encodeURIComponent(orgId)}&select=name&limit=1`
      );
      if (orgRes.ok) {
        const orgRows = await orgRes.json();
        orgName = orgRows[0]?.name || '';
      }
    } catch (_) { /* name 取得失敗は無視（id があれば下流の機能は動く） */ }

    return jsonResponse(200, {
      organization: { id: orgId, name: orgName },
      role,
    });
  } catch (e) {
    console.error('me-v2 error:', e);
    return jsonResponse(500, { error: 'Internal error', detail: e.message });
  }
};
