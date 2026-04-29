/**
 * Assignments API v2
 *
 * Routes:
 *   GET   /api/v2/assignments              一覧（RLS適用）
 *   GET   /api/v2/assignments/:id          詳細
 *   PATCH /api/v2/assignments/:id          状態更新（check-in/out, completion）
 *
 * worker は自分のアサインに check_in/check_out/completion_reported 可
 * facility_admin は自組織のアサインを completion_confirmed に変更可
 * neco_admin は全操作可
 *
 * 状態遷移は DB トリガーが強制し、対応するタイムスタンプも自動補完される。
 */

const {
  CORS_HEADERS,
  jsonResponse,
  requireAuth,
  pgUserFetch,
  logActivity,
} = require('./_utils/supabase');

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: CORS_HEADERS, body: '' };
  }

  const auth = await requireAuth(event);
  if (auth.error) return auth.error;

  const pathParts = event.path.replace(/\/+$/, '').split('/');
  const id = pathParts[pathParts.length - 1];
  const isCollection = id === 'assignments' || id === 'assignments-v2' || id === 'v2';

  try {
    switch (event.httpMethod) {
      case 'GET':
        return isCollection ? await listAssignments(event, auth) : await getAssignment(id, auth);
      case 'PATCH':
        return await updateAssignment(id, event, auth);
      default:
        return jsonResponse(405, { error: 'Method Not Allowed' });
    }
  } catch (e) {
    console.error('assignments-v2 error:', e);
    return jsonResponse(500, { error: 'Internal error', detail: e.message });
  }
};

async function listAssignments(event, auth) {
  if (auth.mock) {
    return jsonResponse(200, { assignments: getMockAssignments(), source: 'mock' });
  }

  const params = event.queryStringParameters || {};
  const filters = [];
  if (params.status) filters.push(`status=eq.${encodeURIComponent(params.status)}`);
  if (params.worker_id) filters.push(`worker_id=eq.${encodeURIComponent(params.worker_id)}`);
  if (params.organization_id) filters.push(`organization_id=eq.${encodeURIComponent(params.organization_id)}`);
  if (params.from) filters.push(`scheduled_start_at=gte.${encodeURIComponent(params.from)}`);
  if (params.to) filters.push(`scheduled_start_at=lte.${encodeURIComponent(params.to)}`);

  const limit = Math.min(parseInt(params.limit, 10) || 50, 200);
  const select = '*,staffing_requests(id,request_number,title),worker_profiles(id,full_name,profession_type)';
  const qs = [`select=${select}`, ...filters, 'order=scheduled_start_at.desc', `limit=${limit}`].join('&');

  const res = await pgUserFetch(`/assignments?${qs}`, auth.token);
  if (!res.ok) {
    const detail = await res.text();
    return jsonResponse(res.status, { error: 'DB error', detail });
  }
  const assignments = await res.json();
  return jsonResponse(200, { assignments, total: assignments.length });
}

async function getAssignment(id, auth) {
  if (!isUuid(id)) return jsonResponse(400, { error: 'Invalid id' });
  if (auth.mock) {
    const mock = getMockAssignments().find(a => a.id === id);
    return mock ? jsonResponse(200, { assignment: mock }) : jsonResponse(404, { error: 'Not found' });
  }
  const res = await pgUserFetch(
    `/assignments?id=eq.${id}&select=*,staffing_requests(*),worker_profiles(*)`,
    auth.token
  );
  if (!res.ok) return jsonResponse(res.status, { error: 'DB error' });
  const rows = await res.json();
  if (!rows.length) return jsonResponse(404, { error: 'Not found' });
  return jsonResponse(200, { assignment: rows[0] });
}

async function updateAssignment(id, event, auth) {
  if (!isUuid(id)) return jsonResponse(400, { error: 'Invalid id' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return jsonResponse(400, { error: 'Invalid JSON' }); }

  const allowed = [
    'status',
    'worker_completion_note',
    'facility_completion_note',
    'check_in_lat', 'check_in_lng',
    'check_out_lat', 'check_out_lng',
    'dispute_reason',
    'cancelled_reason',
  ];
  const update = {};
  for (const k of allowed) {
    if (k in body) update[k] = body[k];
  }
  if (!Object.keys(update).length) {
    return jsonResponse(400, { error: '更新項目がありません' });
  }

  // 完了確認時は facility_confirmed_by を自動設定
  if (update.status === 'completion_confirmed') {
    update.facility_confirmed_by = auth.user.id;
  }
  // キャンセル時は cancelled_by を自動設定
  if (update.status === 'cancelled') {
    update.cancelled_by = auth.user.id;
  }

  if (auth.mock) {
    return jsonResponse(200, { assignment: { id, ...update } });
  }

  const beforeRes = await pgUserFetch(`/assignments?id=eq.${id}&select=status,organization_id`, auth.token);
  const before = beforeRes.ok ? (await beforeRes.json())[0] : null;

  const res = await pgUserFetch(`/assignments?id=eq.${id}`, auth.token, {
    method: 'PATCH',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify(update),
  });
  if (!res.ok) {
    const detail = await res.text();
    if (detail.includes('Invalid') && detail.includes('transition')) {
      return jsonResponse(409, { error: '不正な状態遷移です', detail });
    }
    return jsonResponse(res.status, { error: 'Update failed', detail });
  }
  const rows = await res.json();
  if (!rows.length) return jsonResponse(404, { error: 'Not found' });

  // check-in/out の場合は work_logs に追記
  if (update.status === 'checked_in' || update.status === 'checked_out') {
    await pgUserFetch('/work_logs', auth.token, {
      method: 'POST',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({
        assignment_id: id,
        log_type: update.status === 'checked_in' ? 'check_in' : 'check_out',
        recorded_by: auth.user.id,
        detail: {
          lat: update.status === 'checked_in' ? update.check_in_lat : update.check_out_lat,
          lng: update.status === 'checked_in' ? update.check_in_lng : update.check_out_lng,
        },
      }),
    });
  }

  await logActivity({
    actor_user_id: auth.user.id,
    action: update.status ? `assignment.${update.status}` : 'assignment.updated',
    entity_type: 'assignment',
    entity_id: id,
    organization_id: rows[0].organization_id,
    before: before ? { status: before.status } : null,
    after: { status: rows[0].status },
    headers: event.headers,
  });

  return jsonResponse(200, { assignment: rows[0] });
}

function isUuid(s) {
  return typeof s === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

function getMockAssignments() {
  return [
    {
      id: '00000000-0000-0000-0000-000000000201',
      assignment_number: 'AS-2026-0001',
      status: 'confirmed',
      scheduled_start_at: new Date(Date.now() + 7 * 86400000).toISOString(),
      scheduled_end_at: new Date(Date.now() + 7 * 86400000 + 8 * 3600000).toISOString(),
      hourly_rate: 3800,
      total_compensation: 30400,
    },
  ];
}
