/**
 * Assignments API v2
 *
 * Routes:
 *   GET   /api/v2/assignments              一覧（RLS適用）
 *   GET   /api/v2/assignments/:id          詳細
 *   POST  /api/v2/assignments              施設承認済み proposal から確定アサインを生成（neco_admin）
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
      case 'POST':
        return await createAssignment(event, auth);
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

// 施設承認済み（facility_accepted）の proposal から確定アサインを作成する
// neco_admin 専用。proposal は施設承認済みである必要がある。
async function createAssignment(event, auth) {
  // 権限はRLS（assignments_insert ポリシー）で neco_admin に限定されている前提。
  // 追加で proposal が facility_accepted であることも下で検証する。
  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return jsonResponse(400, { error: 'Invalid JSON' }); }

  const proposalId = body.proposal_id;
  if (!isUuid(proposalId)) return jsonResponse(400, { error: 'proposal_id が不正です' });

  // モックモード時は擬似的にアサインを返す
  if (auth.mock) {
    const now = Date.now();
    return jsonResponse(201, {
      assignment: {
        id: '00000000-0000-0000-0000-' + String(now).padStart(12, '0').slice(-12),
        assignment_number: `AS-${new Date().getFullYear()}-${String(Math.floor(Math.random() * 9999)).padStart(4, '0')}`,
        proposal_id: proposalId,
        status: 'confirmed',
        scheduled_start_at: body.scheduled_start_at || new Date(now + 7 * 86400000).toISOString(),
        scheduled_end_at: body.scheduled_end_at || new Date(now + 7 * 86400000 + 8 * 3600000).toISOString(),
        hourly_rate: body.hourly_rate ?? 8000,
        total_compensation: body.total_compensation ?? 64000,
        source: 'mock',
      },
    });
  }

  // proposal を取得して必要項目を確認
  const propRes = await pgUserFetch(
    `/proposals?id=eq.${proposalId}&select=id,status,request_id,worker_id,proposed_hourly_rate,proposed_total_compensation,proposed_start_at,proposed_end_at,staffing_requests(id,organization_id,start_at,end_at,hourly_rate_min,hourly_rate_max,shift_type)`,
    auth.token
  );
  if (!propRes.ok) {
    return jsonResponse(propRes.status, { error: '提案の取得に失敗しました' });
  }
  const propRows = await propRes.json();
  if (!propRows.length) return jsonResponse(404, { error: '提案が見つかりません' });
  const proposal = propRows[0];

  if (proposal.status !== 'facility_accepted') {
    return jsonResponse(409, {
      error: '勤務確定は施設承認済み（facility_accepted）の提案からのみ作成できます',
      current_status: proposal.status,
    });
  }

  const sr = proposal.staffing_requests || {};
  const scheduledStart = body.scheduled_start_at || proposal.proposed_start_at || sr.start_at;
  const scheduledEnd   = body.scheduled_end_at   || proposal.proposed_end_at   || sr.end_at;
  const hourlyRate     = body.hourly_rate ?? proposal.proposed_hourly_rate
                          ?? sr.hourly_rate_min ?? sr.hourly_rate_max;
  const totalCompensation = body.total_compensation ?? proposal.proposed_total_compensation ?? null;

  const missing = [];
  if (!scheduledStart) missing.push('勤務開始予定');
  if (!scheduledEnd)   missing.push('勤務終了予定');
  if (hourlyRate == null) missing.push('時給');
  if (missing.length) {
    return jsonResponse(400, { error: `必要な項目が不足しています：${missing.join('、')}`, missing });
  }
  if (new Date(scheduledEnd).getTime() <= new Date(scheduledStart).getTime()) {
    return jsonResponse(400, { error: '勤務終了予定は開始予定より後である必要があります' });
  }

  // assignment_number を YYYY ベースで採番（既存と整合する形式）
  const year = new Date().getFullYear();
  const seqRes = await pgUserFetch(
    `/assignments?assignment_number=like.AS-${year}-*&select=assignment_number&order=assignment_number.desc&limit=1`,
    auth.token
  );
  let nextSeq = 1;
  if (seqRes.ok) {
    const last = (await seqRes.json())[0];
    if (last && last.assignment_number) {
      const m = /AS-\d{4}-(\d+)/.exec(last.assignment_number);
      if (m) nextSeq = parseInt(m[1], 10) + 1;
    }
  }
  const assignmentNumber = `AS-${year}-${String(nextSeq).padStart(4, '0')}`;

  const insertBody = {
    assignment_number: assignmentNumber,
    proposal_id: proposal.id,
    request_id: proposal.request_id,
    worker_id: proposal.worker_id,
    organization_id: sr.organization_id,
    scheduled_start_at: scheduledStart,
    scheduled_end_at: scheduledEnd,
    hourly_rate: Number(hourlyRate),
    total_compensation: totalCompensation != null ? Number(totalCompensation) : null,
    status: 'confirmed',
  };

  const ins = await pgUserFetch('/assignments', auth.token, {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify(insertBody),
  });
  if (!ins.ok) {
    const detail = await ins.text();
    if (ins.status === 409) {
      return jsonResponse(409, { error: '既に確定アサインが存在します', detail });
    }
    return jsonResponse(ins.status, { error: '確定アサインの作成に失敗しました', detail });
  }
  const created = (await ins.json())[0];

  // 関連する request の状態（partially_assigned / fully_assigned）はDBトリガーが
  // 自動で進めるか、neco_admin が必要に応じて手動で更新する想定。
  // ここでは activity_log だけ記録する。
  await logActivity({
    actor_user_id: auth.user.id,
    action: 'assignment.created',
    entity_type: 'assignment',
    entity_id: created.id,
    organization_id: created.organization_id,
    after: { status: created.status, proposal_id: proposal.id },
    headers: event.headers,
  });

  return jsonResponse(201, { assignment: created });
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
