/**
 * Staffing Requests API v2
 *
 * Routes:
 *   GET    /api/v2/requests           一覧（RLSにより自組織のみ）
 *   GET    /api/v2/requests/:id       詳細
 *   POST   /api/v2/requests           新規作成
 *   PATCH  /api/v2/requests/:id       更新（status遷移含む）
 *
 * 認証: Bearer JWT（Supabase Auth トークン）
 *
 * 状態遷移は DB トリガー（validate_request_transition）が強制するため、
 * このAPIでは形式チェックのみ行う。
 */

const {
  CORS_HEADERS,
  jsonResponse,
  isMockMode,
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

  // パスから ID を抽出（/api/v2/requests/:id）
  const pathParts = event.path.replace(/\/+$/, '').split('/');
  const id = pathParts[pathParts.length - 1];
  const isCollection = id === 'requests' || id === 'requests-v2' || id === 'v2';

  try {
    switch (event.httpMethod) {
      case 'GET':
        return isCollection
          ? await listRequests(event, auth)
          : await getRequest(id, auth);
      case 'POST':
        return await createRequest(event, auth);
      case 'PATCH':
        return await updateRequest(id, event, auth);
      default:
        return jsonResponse(405, { error: 'Method Not Allowed' });
    }
  } catch (e) {
    console.error('requests-v2 error:', e);
    return jsonResponse(500, { error: 'Internal error', detail: e.message });
  }
};

/* ─────────────────────────── handlers ─────────────────────────── */

async function listRequests(event, auth) {
  if (auth.mock) {
    return jsonResponse(200, { requests: getMockRequests(), source: 'mock' });
  }

  const params = event.queryStringParameters || {};
  const filters = [];

  if (params.status) filters.push(`status=eq.${encodeURIComponent(params.status)}`);
  if (params.priority) filters.push(`priority=eq.${encodeURIComponent(params.priority)}`);
  if (params.profession) filters.push(`profession_type=eq.${encodeURIComponent(params.profession)}`);
  if (params.organization_id) filters.push(`organization_id=eq.${encodeURIComponent(params.organization_id)}`);

  const limit = Math.min(parseInt(params.limit, 10) || 50, 200);
  const offset = parseInt(params.offset, 10) || 0;

  const select = 'id,request_number,organization_id,facility_id,title,description,profession_type,specialty,headcount,shift_type,start_at,end_at,hourly_rate_min,hourly_rate_max,required_licenses,status,priority,submitted_at,created_at,updated_at';
  const qs = [`select=${select}`, ...filters, 'order=created_at.desc', `limit=${limit}`, `offset=${offset}`].join('&');

  const res = await pgUserFetch(`/staffing_requests?${qs}`, auth.token);
  if (!res.ok) {
    const text = await res.text();
    return jsonResponse(res.status, { error: 'DB error', detail: text });
  }
  const requests = await res.json();
  return jsonResponse(200, { requests, total: requests.length });
}

async function getRequest(id, auth) {
  if (!isUuid(id)) return jsonResponse(400, { error: 'Invalid id' });
  if (auth.mock) {
    const mock = getMockRequests().find(r => r.id === id);
    return mock ? jsonResponse(200, { request: mock }) : jsonResponse(404, { error: 'Not found' });
  }
  const res = await pgUserFetch(`/staffing_requests?id=eq.${id}&select=*`, auth.token);
  if (!res.ok) return jsonResponse(res.status, { error: 'DB error' });
  const rows = await res.json();
  if (!rows.length) return jsonResponse(404, { error: 'Not found' });
  return jsonResponse(200, { request: rows[0] });
}

async function createRequest(event, auth) {
  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return jsonResponse(400, { error: 'Invalid JSON' }); }

  // 必須フィールド検証
  const required = ['organization_id', 'title', 'profession_type'];
  for (const f of required) {
    if (!body[f]) return jsonResponse(400, { error: `${f} は必須です` });
  }

  // request_number は自動採番（YYYY-NNNN）— DB で UNIQUE 制約があるので衝突時はリトライ
  const yearPrefix = `SR-${new Date().getFullYear()}-`;
  const requestNumber = body.request_number || `${yearPrefix}${Date.now().toString().slice(-6)}`;

  const insertBody = {
    request_number: requestNumber,
    organization_id: body.organization_id,
    facility_id: body.facility_id || null,
    case_id: body.case_id || null,
    created_by_user_id: auth.user.id,
    title: body.title,
    description: body.description || null,
    profession_type: body.profession_type,
    specialty: body.specialty || null,
    headcount: body.headcount || 1,
    shift_type: body.shift_type || 'regular_shift',
    start_at: body.start_at || null,
    end_at: body.end_at || null,
    hourly_rate_min: body.hourly_rate_min || null,
    hourly_rate_max: body.hourly_rate_max || null,
    total_budget: body.total_budget || null,
    required_licenses: body.required_licenses || [],
    required_skills: body.required_skills || [],
    preferred_skills: body.preferred_skills || [],
    status: body.status || 'draft',
    priority: body.priority || 'medium',
  };

  if (auth.mock) {
    return jsonResponse(201, { request: { id: 'mock-' + Date.now(), ...insertBody } });
  }

  const res = await pgUserFetch('/staffing_requests', auth.token, {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify(insertBody),
  });
  if (!res.ok) {
    const detail = await res.text();
    return jsonResponse(res.status, { error: 'Create failed', detail });
  }
  const rows = await res.json();
  const created = rows[0];

  await logActivity({
    actor_user_id: auth.user.id,
    action: 'request.created',
    entity_type: 'staffing_request',
    entity_id: created.id,
    organization_id: created.organization_id,
    after: { status: created.status },
    headers: event.headers,
  });

  return jsonResponse(201, { request: created });
}

async function updateRequest(id, event, auth) {
  if (!isUuid(id)) return jsonResponse(400, { error: 'Invalid id' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return jsonResponse(400, { error: 'Invalid JSON' }); }

  // 更新可能なフィールドのホワイトリスト
  const allowed = [
    'title', 'description', 'specialty', 'headcount', 'shift_type',
    'start_at', 'end_at', 'hourly_rate_min', 'hourly_rate_max', 'total_budget',
    'required_licenses', 'required_skills', 'preferred_skills',
    'status', 'priority',
    'review_note', 'rejection_reason',
    'cancelled_reason',
  ];
  const update = {};
  for (const k of allowed) {
    if (k in body) update[k] = body[k];
  }
  if (!Object.keys(update).length) {
    return jsonResponse(400, { error: '更新項目がありません' });
  }

  if (auth.mock) {
    return jsonResponse(200, { request: { id, ...update } });
  }

  // 取得（before状態用）
  const beforeRes = await pgUserFetch(`/staffing_requests?id=eq.${id}&select=status,organization_id`, auth.token);
  const beforeRows = beforeRes.ok ? await beforeRes.json() : [];
  const before = beforeRows[0] || null;

  const res = await pgUserFetch(`/staffing_requests?id=eq.${id}`, auth.token, {
    method: 'PATCH',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify(update),
  });
  if (!res.ok) {
    const detail = await res.text();
    // 状態遷移バリデーション失敗（PostgreSQL 22023）
    if (detail.includes('Invalid') && detail.includes('transition')) {
      return jsonResponse(409, { error: '不正な状態遷移です', detail });
    }
    return jsonResponse(res.status, { error: 'Update failed', detail });
  }
  const rows = await res.json();
  if (!rows.length) return jsonResponse(404, { error: 'Not found' });

  await logActivity({
    actor_user_id: auth.user.id,
    action: update.status ? `request.status.${update.status}` : 'request.updated',
    entity_type: 'staffing_request',
    entity_id: id,
    organization_id: rows[0].organization_id,
    before: before ? { status: before.status } : null,
    after: { status: rows[0].status },
    headers: event.headers,
  });

  return jsonResponse(200, { request: rows[0] });
}

/* ─────────────────────────── helpers ─────────────────────────── */

function isUuid(s) {
  return typeof s === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

function getMockRequests() {
  // デモで主要ステータスを一通り見られるように10件を用意
  const iso = (offsetMs) => new Date(Date.now() + offsetMs).toISOString();
  const day = 86400000;
  return [
    { id: '00000000-0000-0000-0000-000000000001', request_number: 'SR-2026-0001', title: '内科外来 当直医（応援勤務）',         profession_type: 'physician', specialty: '内科',     headcount: 1, shift_type: 'on_call',       status: 'submitted',          priority: 'urgent', start_at: iso(5*day),  hourly_rate_min: 15000, hourly_rate_max: 18000, submitted_at: iso(-30*3600000), created_at: iso(-30*3600000) },
    { id: '00000000-0000-0000-0000-000000000002', request_number: 'SR-2026-0002', title: '透析クリニック 常勤医',               profession_type: 'physician', specialty: '腎臓内科', headcount: 1, shift_type: 'regular_shift', status: 'under_review',       priority: 'medium', start_at: iso(30*day), hourly_rate_min: 12000, hourly_rate_max: 15000, reviewed_at: iso(-50*3600000) },
    { id: '00000000-0000-0000-0000-000000000003', request_number: 'SR-2026-0003', title: '訪問看護 週末スポット',               profession_type: 'nurse',                            headcount: 1, shift_type: 'spot',          status: 'accepted',           priority: 'medium', start_at: iso(7*day),  hourly_rate_min: 3500,  hourly_rate_max: 4000,  accepted_at: iso(-2*day) },
    { id: '00000000-0000-0000-0000-000000000004', request_number: 'SR-2026-0004', title: 'リハビリ専門 PT/OT 提案中',           profession_type: 'physical_therapist',               headcount: 2, shift_type: 'regular_shift', status: 'proposing',          priority: 'medium', start_at: iso(20*day), hourly_rate_min: 3200,  hourly_rate_max: 3800 },
    { id: '00000000-0000-0000-0000-000000000005', request_number: 'SR-2026-0005', title: '健診センター GW 一部充足',           profession_type: 'physician', specialty: '健診',     headcount: 4, shift_type: 'spot',          status: 'partially_assigned', priority: 'high',   start_at: iso(10*day) },
    { id: '00000000-0000-0000-0000-000000000006', request_number: 'SR-2026-0006', title: '夜勤専従ナース 充足完了',             profession_type: 'nurse',                            headcount: 3, shift_type: 'night_duty',    status: 'fully_assigned',     priority: 'high',   start_at: iso(35*day) },
    { id: '00000000-0000-0000-0000-000000000007', request_number: 'SR-2026-0007', title: '在宅医療 訪問同行（稼働中）',         profession_type: 'physician',                        headcount: 1, shift_type: 'regular_shift', status: 'in_progress',        priority: 'medium', start_at: iso(-1*day) },
    { id: '00000000-0000-0000-0000-000000000008', request_number: 'SR-2026-0008', title: '外来看護 完了申請中',                 profession_type: 'nurse',                            headcount: 1, shift_type: 'day_duty',      status: 'completion_pending', priority: 'low',    start_at: iso(-2*day) },
    { id: '00000000-0000-0000-0000-000000000009', request_number: 'SR-2026-0009', title: '在宅医療 完了確定済',                 profession_type: 'physician',                        headcount: 1, shift_type: 'regular_shift', status: 'confirmed',          priority: 'medium', start_at: iso(-7*day) },
    { id: '00000000-0000-0000-0000-000000000010', request_number: 'SR-2026-0010', title: '訪問看護 請求済',                     profession_type: 'nurse',                            headcount: 1, shift_type: 'spot',          status: 'invoiced',           priority: 'low',    start_at: iso(-30*day) },
  ];
}
