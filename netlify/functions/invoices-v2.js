/**
 * Invoices API v2
 *
 * Routes:
 *   GET  /api/v2/invoices              一覧（RLSにより自組織のみ・neco/allianceは全件）
 *   GET  /api/v2/invoices/:id          詳細（明細付き）
 *
 * 作成・更新は Neco 側オペレーション（社内ツール経由を想定し、ここでは GET のみ）
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

  const auth = await requireAuth(event);
  if (auth.error) return auth.error;

  const pathParts = event.path.replace(/\/+$/, '').split('/');
  const id = pathParts[pathParts.length - 1];
  const isCollection = id === 'invoices' || id === 'invoices-v2' || id === 'v2';

  try {
    switch (event.httpMethod) {
      case 'GET':
        return isCollection ? await listInvoices(event, auth) : await getInvoice(id, auth);
      default:
        return jsonResponse(405, { error: 'Method Not Allowed' });
    }
  } catch (e) {
    console.error('invoices-v2 error:', e);
    return jsonResponse(500, { error: 'Internal error', detail: e.message });
  }
};

async function listInvoices(event, auth) {
  if (auth.mock) {
    return jsonResponse(200, { invoices: getMockInvoices(), source: 'mock' });
  }

  const params = event.queryStringParameters || {};
  const filters = [];
  if (params.status) filters.push(`status=eq.${encodeURIComponent(params.status)}`);
  if (params.organization_id) filters.push(`organization_id=eq.${encodeURIComponent(params.organization_id)}`);
  if (params.from) filters.push(`period_start=gte.${encodeURIComponent(params.from)}`);
  if (params.to) filters.push(`period_end=lte.${encodeURIComponent(params.to)}`);

  const limit = Math.min(parseInt(params.limit, 10) || 50, 200);
  const select = 'id,invoice_number,organization_id,period_start,period_end,subtotal,tax,total,currency,issue_date,due_date,paid_date,status,created_at';
  const qs = [`select=${select}`, ...filters, 'order=period_start.desc', `limit=${limit}`].join('&');

  const res = await pgUserFetch(`/invoices?${qs}`, auth.token);
  if (!res.ok) {
    const detail = await res.text();
    return jsonResponse(res.status, { error: 'DB error', detail });
  }
  const invoices = await res.json();
  return jsonResponse(200, { invoices, total: invoices.length });
}

async function getInvoice(id, auth) {
  if (!isUuid(id)) return jsonResponse(400, { error: 'Invalid id' });
  if (auth.mock) {
    const mock = getMockInvoices().find(i => i.id === id);
    return mock ? jsonResponse(200, { invoice: mock }) : jsonResponse(404, { error: 'Not found' });
  }
  const res = await pgUserFetch(
    `/invoices?id=eq.${id}&select=*,invoice_line_items(*)`,
    auth.token
  );
  if (!res.ok) return jsonResponse(res.status, { error: 'DB error' });
  const rows = await res.json();
  if (!rows.length) return jsonResponse(404, { error: 'Not found' });
  return jsonResponse(200, { invoice: rows[0] });
}

function isUuid(s) {
  return typeof s === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

function getMockInvoices() {
  const monthStart = new Date();
  monthStart.setDate(1);
  const period_start = monthStart.toISOString().slice(0, 10);
  const period_end = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 0).toISOString().slice(0, 10);
  const today = new Date();
  const ymd = (offsetDays) => {
    const d = new Date(today);
    d.setDate(d.getDate() + offsetDays);
    return d.toISOString().slice(0, 10);
  };
  return [
    // 4状態を一通り見られるようにする
    {
      id: '00000000-0000-0000-0000-000000000301',
      invoice_number: 'IN-2026-0001',
      organization_id: 'aaaaaaaa-0000-0000-0000-000000000002',
      period_start, period_end,
      subtotal: 30400, tax: 3040, total: 33440,
      status: 'draft',
    },
    {
      id: '00000000-0000-0000-0000-000000000302',
      invoice_number: 'IN-2026-0002',
      organization_id: 'aaaaaaaa-0000-0000-0000-000000000002',
      period_start, period_end,
      issue_date: ymd(-3), due_date: ymd(27),
      subtotal: 64000, tax: 6400, total: 70400,
      status: 'issued',
    },
    {
      id: '00000000-0000-0000-0000-000000000303',
      invoice_number: 'IN-2026-0003',
      organization_id: 'aaaaaaaa-0000-0000-0000-000000000001',
      period_start, period_end,
      issue_date: ymd(-30), due_date: ymd(-5),
      paid_at: new Date(Date.now() - 4 * 86400000).toISOString(),
      subtotal: 120000, tax: 12000, total: 132000,
      status: 'paid',
    },
    {
      id: '00000000-0000-0000-0000-000000000304',
      invoice_number: 'IN-2026-0004',
      organization_id: 'aaaaaaaa-0000-0000-0000-000000000001',
      period_start, period_end,
      issue_date: ymd(-45), due_date: ymd(-15),
      subtotal: 45000, tax: 4500, total: 49500,
      status: 'overdue',
    },
  ];
}
