/**
 * Alliance Dashboard KPI API v2
 *
 * Route: GET /api/v2/dashboard/kpi
 *
 * v_alliance_dashboard ビューを参照し、総合KPIを1行で返す。
 * RLS により alliance_admin / neco_admin にしか結果が返らない（他ロールは空配列）。
 */

const {
  CORS_HEADERS,
  jsonResponse,
  requireAuth,
  pgUserFetch,
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

  if (auth.mock) {
    return jsonResponse(200, { kpi: getMockKpi(), source: 'mock' });
  }

  try {
    const res = await pgUserFetch('/v_alliance_dashboard?select=*', auth.token);
    if (!res.ok) {
      const detail = await res.text();
      return jsonResponse(res.status, { error: 'DB error', detail });
    }
    const rows = await res.json();
    if (!rows.length) {
      return jsonResponse(403, { error: 'KPIへのアクセス権がありません' });
    }
    return jsonResponse(200, { kpi: rows[0] });
  } catch (e) {
    console.error('dashboard-kpi-v2 error:', e);
    return jsonResponse(500, { error: 'Internal error', detail: e.message });
  }
};

function getMockKpi() {
  return {
    open_requests: 12,
    open_headcount: 18,
    urgent_open: 4,
    active_assignments: 23,
    open_disputes: 1,
    completed_30d: 47,
    lost_30d: 3,
    active_workers: 86,
    pending_onboarding: 5,
    pending_credentials: 8,
    expiring_credentials: 11,
    revenue_this_month: 4250000,
    outstanding_amount: 1820000,
    generated_at: new Date().toISOString(),
  };
}
