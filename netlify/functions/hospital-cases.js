/**
 * GET /api/hospital/cases
 * 認証済み病院の案件一覧を返す
 *
 * 現在はモックデータを返す。
 * DB接続後は organizations.id で絞り込んだ staffing_cases を返す。
 */

const { authFromHeaders } = require('./_utils/verify-jwt');

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

  // JWT認証
  let tokenPayload;
  try {
    tokenPayload = authFromHeaders(event.headers);
  } catch (e) {
    return {
      statusCode: 401,
      headers: CORS_HEADERS,
      body: JSON.stringify({ error: e.message || '認証エラー' }),
    };
  }

  // クエリパラメータ（フィルタ）
  const params = event.queryStringParameters || {};
  const { status, priority, profession } = params;

  // モックデータ（DB接続後に実クエリへ置換）
  let cases = getMockCases(tokenPayload.sub);

  if (status)     cases = cases.filter(c => c.case_status === status);
  if (priority)   cases = cases.filter(c => c.priority_level === priority);
  if (profession) cases = cases.filter(c => c.profession_type === profession);

  return {
    statusCode: 200,
    headers: CORS_HEADERS,
    body: JSON.stringify({ cases, total: cases.length }),
  };
};

/* ─── モックデータ ─────────────────────────────────────────── */
function getMockCases(orgId) {
  return [
    {
      id: 'SC-2026-008',
      title: '内科系医師 緊急補充',
      facility: 'さくら病院 本院',
      profession_type: 'physician',
      profession_label: '医師（内科）',
      case_status: 'sourcing',
      priority_level: 'urgent',
      required_by_date: '2026-05-15',
      owner_name: '近藤',
      headcount: 1,
      match_count: 2,
      progressed_count: 0,
      created_at: '2026-04-01',
    },
    {
      id: 'SC-2026-007',
      title: '訪問看護師 複数名採用',
      facility: 'ひまわり訪問看護ステーション',
      profession_type: 'nurse',
      profession_label: '看護師',
      case_status: 'interviewing',
      priority_level: 'high',
      required_by_date: '2026-05-31',
      owner_name: '近藤',
      headcount: 3,
      match_count: 5,
      progressed_count: 2,
      created_at: '2026-03-20',
    },
    {
      id: 'SC-2026-006',
      title: '医療事務員 正職員',
      facility: 'さくら病院 分院',
      profession_type: 'medical_clerk',
      profession_label: '医療事務',
      case_status: 'sourcing',
      priority_level: 'medium',
      required_by_date: '2026-06-30',
      owner_name: '近藤',
      headcount: 1,
      match_count: 3,
      progressed_count: 0,
      created_at: '2026-03-15',
    },
    {
      id: 'SC-2026-005',
      title: '薬剤師 パート募集',
      facility: 'さくら調剤薬局',
      profession_type: 'pharmacist',
      profession_label: '薬剤師',
      case_status: 'offer',
      priority_level: 'medium',
      required_by_date: '2026-06-15',
      owner_name: '近藤',
      headcount: 1,
      match_count: 2,
      progressed_count: 1,
      created_at: '2026-03-10',
    },
    {
      id: 'SC-2026-004',
      title: '理学療法士 増員',
      facility: 'リハビリテーション病院',
      profession_type: 'therapist',
      profession_label: '理学療法士',
      case_status: 'interviewing',
      priority_level: 'high',
      required_by_date: '2026-05-20',
      owner_name: '近藤',
      headcount: 2,
      match_count: 4,
      progressed_count: 1,
      created_at: '2026-03-05',
    },
    {
      id: 'SC-2026-003',
      title: 'ケアマネジャー 専任',
      facility: 'みらい介護センター',
      profession_type: 'care_manager',
      profession_label: 'ケアマネジャー',
      case_status: 'scoping',
      priority_level: 'medium',
      required_by_date: '2026-07-01',
      owner_name: '近藤',
      headcount: 1,
      match_count: 0,
      progressed_count: 0,
      created_at: '2026-02-28',
    },
    {
      id: 'SC-2026-002',
      title: '精神科専門医 非常勤',
      facility: 'こころのクリニック',
      profession_type: 'physician',
      profession_label: '医師（精神科）',
      case_status: 'sourcing',
      priority_level: 'critical',
      required_by_date: '2026-05-10',
      owner_name: '近藤',
      headcount: 1,
      match_count: 1,
      progressed_count: 0,
      created_at: '2026-02-20',
    },
    {
      id: 'SC-2026-001',
      title: '介護福祉士 夜勤対応可',
      facility: 'しおかぜ特養',
      profession_type: 'care_worker',
      profession_label: '介護福祉士',
      case_status: 'intake',
      priority_level: 'low',
      required_by_date: '2026-08-01',
      owner_name: '近藤',
      headcount: 2,
      match_count: 0,
      progressed_count: 0,
      created_at: '2026-02-10',
    },
  ];
}
