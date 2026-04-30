/**
 * GET /api/hospital/cases
 * Supabase アクセストークンを検証し、組織に紐づく案件を返す
 *
 * 環境変数:
 *   SUPABASE_URL              - Supabase プロジェクト URL
 *   SUPABASE_ANON_KEY         - anon キー（ユーザー認証検証用）
 *   SUPABASE_SERVICE_ROLE_KEY - service_role キー（DB直接アクセス用、将来的に使用）
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

  // Bearer トークンの取り出し
  const authHeader = event.headers['authorization'] || event.headers['Authorization'] || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) {
    return { statusCode: 401, headers: CORS_HEADERS, body: JSON.stringify({ error: '認証トークンがありません。' }) };
  }

  const supabaseUrl = process.env.SUPABASE_URL;
  const anonKey     = process.env.SUPABASE_ANON_KEY;

  // Supabase が未設定の場合はモックデータを返す（開発環境向け）
  if (!supabaseUrl || !anonKey || supabaseUrl.includes('YOUR_PROJECT')) {
    return {
      statusCode: 200,
      headers: CORS_HEADERS,
      body: JSON.stringify({ cases: getMockCases(), total: getMockCases().length, source: 'mock' }),
    };
  }

  // Supabase Auth でトークン検証（fetch は Node 18+ で利用可）
  let user;
  try {
    const res = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'apikey': anonKey,
      },
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

  // TODO: user.id を organization_members テーブルで organization_id に変換し、
  //       staffing_cases テーブルから実データを取得する。
  //       現時点はモックデータを返す。
  const params    = event.queryStringParameters || {};
  let   cases     = getMockCases(user.id);
  if (params.status)     cases = cases.filter(c => c.case_status === params.status);
  if (params.priority)   cases = cases.filter(c => c.priority_level === params.priority);
  if (params.profession) cases = cases.filter(c => c.profession_type === params.profession);

  return {
    statusCode: 200,
    headers: CORS_HEADERS,
    body: JSON.stringify({ cases, total: cases.length, user_id: user.id }),
  };
};

/* ─── モックデータ（DB接続後に Supabase クエリへ置換） ───── */
function getMockCases() {
  return [
    { id:'SC-2026-008', title:'内科系医師 緊急補充',     facility:'さくら病院 本院',               profession_type:'physician',    profession_label:'医師（内科）',   case_status:'sourcing',     priority_level:'urgent',   headcount:1, deadline:'2026-05-15', owner:'近藤', match_total:2, match_interview:0 },
    { id:'SC-2026-007', title:'訪問看護師 複数名採用',   facility:'ひまわり訪問看護ステーション',   profession_type:'nurse',        profession_label:'看護師',         case_status:'interviewing', priority_level:'high',     headcount:3, deadline:'2026-05-31', owner:'近藤', match_total:5, match_interview:2 },
    { id:'SC-2026-006', title:'医療事務員 正職員',       facility:'さくら病院 分院',               profession_type:'medical_clerk', profession_label:'医療事務',       case_status:'sourcing',     priority_level:'medium',   headcount:1, deadline:'2026-06-30', owner:'近藤', match_total:3, match_interview:0 },
    { id:'SC-2026-005', title:'薬剤師 パート募集',       facility:'さくら調剤薬局',               profession_type:'pharmacist',   profession_label:'薬剤師',         case_status:'offer',        priority_level:'medium',   headcount:1, deadline:'2026-06-15', owner:'近藤', match_total:2, match_interview:1 },
    { id:'SC-2026-004', title:'理学療法士 増員',         facility:'リハビリテーション病院',       profession_type:'therapist',    profession_label:'理学療法士',     case_status:'interviewing', priority_level:'high',     headcount:2, deadline:'2026-05-20', owner:'近藤', match_total:4, match_interview:1 },
    { id:'SC-2026-003', title:'ケアマネジャー 専任',     facility:'みらい介護センター',           profession_type:'care_manager', profession_label:'ケアマネジャー', case_status:'scoping',      priority_level:'medium',   headcount:1, deadline:'2026-07-01', owner:'近藤', match_total:0, match_interview:0 },
    { id:'SC-2026-002', title:'精神科専門医 非常勤',     facility:'こころのクリニック',           profession_type:'physician',    profession_label:'医師（精神科）', case_status:'sourcing',     priority_level:'critical', headcount:1, deadline:'2026-05-10', owner:'近藤', match_total:1, match_interview:0 },
    { id:'SC-2026-001', title:'介護福祉士 夜勤対応可',   facility:'しおかぜ特養',                 profession_type:'care_worker',  profession_label:'介護福祉士',     case_status:'intake',       priority_level:'low',      headcount:2, deadline:'2026-08-01', owner:'近藤', match_total:0, match_interview:0 },
  ];
}
