/**
 * Proposals API v2
 *
 * Routes:
 *   GET   /api/v2/proposals                  自分が見える提案一覧（RLS適用）
 *   GET   /api/v2/proposals/:id              詳細
 *   PATCH /api/v2/proposals/:id              状態更新
 *
 * worker は自分宛の提案にworker_accepted/worker_declinedで応答可
 * facility_admin は自組織宛の提案に facility_accepted/facility_declined で応答可
 * neco_admin は全操作可
 *
 * 状態遷移は DB トリガーが強制する。
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
  const isCollection = id === 'proposals' || id === 'proposals-v2' || id === 'v2';

  try {
    switch (event.httpMethod) {
      case 'GET':
        return isCollection ? await listProposals(event, auth) : await getProposal(id, auth);
      case 'PATCH':
        return await updateProposal(id, event, auth);
      default:
        return jsonResponse(405, { error: 'Method Not Allowed' });
    }
  } catch (e) {
    console.error('proposals-v2 error:', e);
    return jsonResponse(500, { error: 'Internal error', detail: e.message });
  }
};

async function listProposals(event, auth) {
  if (auth.mock) {
    return jsonResponse(200, { proposals: getMockProposals(), source: 'mock' });
  }

  const params = event.queryStringParameters || {};
  const filters = [];
  if (params.request_id) filters.push(`request_id=eq.${encodeURIComponent(params.request_id)}`);
  if (params.worker_id) filters.push(`worker_id=eq.${encodeURIComponent(params.worker_id)}`);
  if (params.status) filters.push(`status=eq.${encodeURIComponent(params.status)}`);

  const limit = Math.min(parseInt(params.limit, 10) || 50, 200);
  const select = '*,staffing_requests(id,request_number,title,profession_type,organization_id),worker_profiles(id,full_name,profession_type,primary_specialty)';
  const qs = [`select=${select}`, ...filters, 'order=created_at.desc', `limit=${limit}`].join('&');

  const res = await pgUserFetch(`/proposals?${qs}`, auth.token);
  if (!res.ok) {
    const detail = await res.text();
    return jsonResponse(res.status, { error: 'DB error', detail });
  }
  const proposals = await res.json();
  return jsonResponse(200, { proposals, total: proposals.length });
}

async function getProposal(id, auth) {
  if (!isUuid(id)) return jsonResponse(400, { error: 'Invalid id' });
  if (auth.mock) {
    const mock = getMockProposals().find(p => p.id === id);
    return mock ? jsonResponse(200, { proposal: mock }) : jsonResponse(404, { error: 'Not found' });
  }
  const res = await pgUserFetch(
    `/proposals?id=eq.${id}&select=*,staffing_requests(*),worker_profiles(*)`,
    auth.token
  );
  if (!res.ok) return jsonResponse(res.status, { error: 'DB error' });
  const rows = await res.json();
  if (!rows.length) return jsonResponse(404, { error: 'Not found' });
  return jsonResponse(200, { proposal: rows[0] });
}

async function updateProposal(id, event, auth) {
  if (!isUuid(id)) return jsonResponse(400, { error: 'Invalid id' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return jsonResponse(400, { error: 'Invalid JSON' }); }

  const allowed = [
    'status',
    'worker_response_note',
    'facility_response_note',
    'proposed_hourly_rate',
    'proposed_total_compensation',
    'proposed_start_at',
    'proposed_end_at',
    'expires_at',
    'match_score',
    'match_reason',
  ];
  const update = {};
  for (const k of allowed) {
    if (k in body) update[k] = body[k];
  }
  if (!Object.keys(update).length) {
    return jsonResponse(400, { error: '更新項目がありません' });
  }

  // facility 側の応答時は facility_responded_by を自動設定
  if (update.status && (update.status === 'facility_accepted' || update.status === 'facility_declined')) {
    update.facility_responded_by = auth.user.id;
  }

  if (auth.mock) {
    return jsonResponse(200, { proposal: { id, ...update } });
  }

  const beforeRes = await pgUserFetch(`/proposals?id=eq.${id}&select=status,request_id`, auth.token);
  const before = beforeRes.ok ? (await beforeRes.json())[0] : null;

  const res = await pgUserFetch(`/proposals?id=eq.${id}`, auth.token, {
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

  await logActivity({
    actor_user_id: auth.user.id,
    action: update.status ? `proposal.${update.status}` : 'proposal.updated',
    entity_type: 'proposal',
    entity_id: id,
    before: before ? { status: before.status } : null,
    after: { status: rows[0].status },
    headers: event.headers,
  });

  return jsonResponse(200, { proposal: rows[0] });
}

function isUuid(s) {
  return typeof s === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

function getMockProposals() {
  // デモで主要ステータスを一通り見られるように9件
  const iso = (offsetMs) => new Date(Date.now() + offsetMs).toISOString();
  const wp = (n, name, prof) => ({ id: 'wp-' + n, full_name: name, profession_type: prof, primary_specialty: '' });
  const sr = (n, t) => ({ id: 'sr-' + n, request_number: 'SR-2026-' + n, title: t, organization_id: 'aaaaaaaa-0000-0000-0000-000000000001' });
  return [
    { id: '00000000-0000-0000-0000-000000000101', proposal_number: 'PR-2026-0001', status: 'created',
      created_at: iso(-30*3600000), updated_at: iso(-30*3600000),
      proposed_hourly_rate: 9000, match_score: 80, match_reason: '専門領域一致',
      worker_profiles: wp('w001','山田 健司','physician'), staffing_requests: sr('001','内科外来 当直医（応援勤務）') },
    { id: '00000000-0000-0000-0000-000000000102', proposal_number: 'PR-2026-0002', status: 'worker_contacted',
      created_at: iso(-72*3600000), updated_at: iso(-50*3600000),
      proposed_hourly_rate: 8500, match_score: 78,
      worker_profiles: wp('w002','加藤 大輔','physician'), staffing_requests: sr('002','透析クリニック 常勤医') },
    { id: '00000000-0000-0000-0000-000000000103', proposal_number: 'PR-2026-0003', status: 'worker_accepted',
      created_at: iso(-96*3600000), updated_at: iso(-26*3600000),
      worker_responded_at: iso(-26*3600000),
      proposed_hourly_rate: 12000, match_score: 88,
      worker_profiles: wp('w003','大塚 健司','physician'), staffing_requests: sr('004','リハビリ専門 PT/OT') },
    { id: '00000000-0000-0000-0000-000000000104', proposal_number: 'PR-2026-0004', status: 'worker_declined',
      created_at: iso(-100*3600000), updated_at: iso(-50*3600000),
      worker_responded_at: iso(-50*3600000), worker_response_note: '希望勤務地と異なるため辞退',
      proposed_hourly_rate: 7500, match_score: 60,
      worker_profiles: wp('w004','木村 さくら','nurse'), staffing_requests: sr('003','訪問看護 週末スポット') },
    { id: '00000000-0000-0000-0000-000000000105', proposal_number: 'PR-2026-0005', status: 'proposed_to_facility',
      created_at: iso(-72*3600000), updated_at: iso(-50*3600000),
      proposed_hourly_rate: 3800, match_score: 92.5, match_reason: '訪問看護経験8年・希望エリア一致',
      worker_profiles: wp('w005','鈴木 美咲','nurse'), staffing_requests: sr('003','訪問看護 週末スポット') },
    { id: '00000000-0000-0000-0000-000000000106', proposal_number: 'PR-2026-0006', status: 'facility_accepted',
      created_at: iso(-96*3600000), updated_at: iso(-12*3600000),
      worker_responded_at: iso(-50*3600000), facility_responded_at: iso(-12*3600000),
      proposed_hourly_rate: 4200, match_score: 95,
      worker_profiles: wp('w006','吉田 典子','nurse'), staffing_requests: sr('005','健診センター GW') },
    { id: '00000000-0000-0000-0000-000000000107', proposal_number: 'PR-2026-0007', status: 'facility_declined',
      created_at: iso(-120*3600000), updated_at: iso(-24*3600000),
      facility_responded_at: iso(-24*3600000), facility_response_note: '今回は別候補で進めます',
      proposed_hourly_rate: 6500, match_score: 70,
      worker_profiles: wp('w007','森 紗奈','nurse'), staffing_requests: sr('006','夜勤専従ナース') },
    { id: '00000000-0000-0000-0000-000000000108', proposal_number: 'PR-2026-0008', status: 'withdrawn',
      created_at: iso(-150*3600000), updated_at: iso(-72*3600000),
      proposed_hourly_rate: 8000, match_score: 65,
      worker_profiles: wp('w008','長谷川 茂','physician'), staffing_requests: sr('001','内科外来 当直医（応援勤務）') },
    { id: '00000000-0000-0000-0000-000000000109', proposal_number: 'PR-2026-0009', status: 'expired',
      created_at: iso(-200*3600000), updated_at: iso(-100*3600000), expires_at: iso(-50*3600000),
      proposed_hourly_rate: 7800, match_score: 72,
      worker_profiles: wp('w009','小池 拓郎','physician'), staffing_requests: sr('002','透析クリニック 常勤医') },
  ];
}
