/**
 * GET /api/hospital/candidates
 * Supabase アクセストークンを検証し、候補者一覧を返す
 *
 * クエリパラメータ:
 *   tab      - 'pending' | 'screening' | 'done' (省略時は全て)
 *   case_id  - 案件IDで絞り込み
 */

const CORS_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: CORS_HEADERS, body: '' };
  }
  if (event.httpMethod !== 'GET') {
    return { statusCode: 405, headers: CORS_HEADERS, body: JSON.stringify({ error: 'Method Not Allowed' }) };
  }

  const authHeader = event.headers['authorization'] || event.headers['Authorization'] || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) {
    return { statusCode: 401, headers: CORS_HEADERS, body: JSON.stringify({ error: '認証トークンがありません。' }) };
  }

  const supabaseUrl = process.env.SUPABASE_URL;
  const anonKey    = process.env.SUPABASE_ANON_KEY;

  // 環境変数未設定の場合はモックデータを返す
  if (!supabaseUrl || !anonKey || supabaseUrl.includes('YOUR_PROJECT')) {
    const params = event.queryStringParameters || {};
    const data   = getMockCandidates(params.tab, params.case_id);
    return {
      statusCode: 200,
      headers: CORS_HEADERS,
      body: JSON.stringify({ ...data, source: 'mock' }),
    };
  }

  // Supabase Auth でトークン検証
  let user;
  try {
    const res = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { 'Authorization': `Bearer ${token}`, 'apikey': anonKey },
    });
    if (!res.ok) {
      return { statusCode: 401, headers: CORS_HEADERS, body: JSON.stringify({ error: 'セッションが無効です。再ログインしてください。' }) };
    }
    user = await res.json();
  } catch (e) {
    console.error('Supabase auth error:', e);
    return { statusCode: 503, headers: CORS_HEADERS, body: JSON.stringify({ error: '認証サービスへの接続に失敗しました。' }) };
  }

  if (!user || !user.id) {
    return { statusCode: 401, headers: CORS_HEADERS, body: JSON.stringify({ error: '認証に失敗しました。' }) };
  }

  // TODO: Supabase から候補者実データを取得する
  //       現時点はモックデータを返す
  const params = event.queryStringParameters || {};
  const data   = getMockCandidates(params.tab, params.case_id);

  return {
    statusCode: 200,
    headers: CORS_HEADERS,
    body: JSON.stringify({ ...data, user_id: user.id }),
  };
};

/* ─── モックデータ ──────────────────────────────── */
function getMockCandidates(tab, caseId) {
  const ALL = {
    pending: [
      { num:'CAND-047', prof:'看護師',        detail:'経験8年・急性期病棟・夜勤可',            case_id:'SC-2026-007', case_title:'訪問看護師 複数名採用',   proposed_at:'2026-04-25' },
      { num:'CAND-046', prof:'医師（内科）',   detail:'経験12年・内科・在宅医療経験あり',       case_id:'SC-2026-008', case_title:'内科系医師 緊急補充',      proposed_at:'2026-04-24' },
      { num:'CAND-045', prof:'医師（精神科）', detail:'経験6年・精神科専門医資格あり',          case_id:'SC-2026-002', case_title:'精神科専門医 非常勤',      proposed_at:'2026-04-23' },
    ],
    screening: [
      { num:'CAND-044', prof:'理学療法士', detail:'経験5年・整形外科リハビリ専門',  case_id:'SC-2026-004', case_title:'理学療法士 増員',     proposed_at:'2026-04-20' },
      { num:'CAND-043', prof:'理学療法士', detail:'経験3年・神経リハビリ',          case_id:'SC-2026-004', case_title:'理学療法士 増員',     proposed_at:'2026-04-20' },
      { num:'CAND-042', prof:'薬剤師',     detail:'経験7年・調剤薬局・在宅業務経験', case_id:'SC-2026-005', case_title:'薬剤師 パート募集',   proposed_at:'2026-04-18' },
      { num:'CAND-041', prof:'看護師',     detail:'経験10年・訪問看護4年',           case_id:'SC-2026-007', case_title:'訪問看護師 複数名採用', proposed_at:'2026-04-17' },
      { num:'CAND-040', prof:'看護師',     detail:'経験5年・地域包括ケア経験',       case_id:'SC-2026-007', case_title:'訪問看護師 複数名採用', proposed_at:'2026-04-17' },
      { num:'CAND-039', prof:'医療事務',   detail:'経験3年・電子カルテ（NEC）対応可', case_id:'SC-2026-006', case_title:'医療事務員 正職員',   proposed_at:'2026-04-15' },
      { num:'CAND-038', prof:'医療事務',   detail:'経験6年・レセプト業務経験豊富',   case_id:'SC-2026-006', case_title:'医療事務員 正職員',   proposed_at:'2026-04-15' },
      { num:'CAND-037', prof:'医療事務',   detail:'経験2年・医師事務作業補助経験',   case_id:'SC-2026-006', case_title:'医療事務員 正職員',   proposed_at:'2026-04-14' },
    ],
    done: [
      { num:'CAND-036', prof:'ケアマネジャー', detail:'経験8年・居宅介護支援事業所勤務', case_id:'SC-2026-003', case_title:'ケアマネジャー 専任', proposed_at:'2026-04-10' },
      { num:'CAND-035', prof:'介護福祉士',     detail:'経験4年・特養夜勤経験3年',       case_id:'SC-2026-001', case_title:'介護福祉士 夜勤対応可', proposed_at:'2026-04-08' },
      { num:'CAND-034', prof:'看護師',         detail:'経験15年・管理職経験あり',       case_id:'SC-2026-007', case_title:'訪問看護師 複数名採用', proposed_at:'2026-04-05' },
    ],
  };

  // case_id フィルター
  if (caseId) {
    Object.keys(ALL).forEach(k => {
      ALL[k] = ALL[k].filter(c => c.case_id === caseId);
    });
  }

  // tab フィルター
  if (tab && ALL[tab]) {
    return { candidates: ALL[tab], tab, total: ALL[tab].length };
  }

  // 全タブのカウントを返す
  return {
    candidates: [...ALL.pending, ...ALL.screening, ...ALL.done],
    counts: { pending: ALL.pending.length, screening: ALL.screening.length, done: ALL.done.length },
    total: ALL.pending.length + ALL.screening.length + ALL.done.length,
  };
}
