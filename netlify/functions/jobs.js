/**
 * Jobs Netlify Function – 求人情報 CRUD
 *
 * Routes (via /api/jobs/* → /.netlify/functions/jobs/:splat):
 *   GET    /api/jobs                – 求人一覧（公開、フィルタあり）
 *   GET    /api/jobs/:id           – 求人詳細
 *   POST   /api/jobs               – 求人作成（医療機関のみ）
 *   PUT    /api/jobs/:id           – 求人更新（作成者のみ）
 *   DELETE /api/jobs/:id           – 求人削除（ソフトデリート、作成者のみ）
 *
 * クエリパラメータ (GET /api/jobs):
 *   ?type=doctor|nurse|both   必要職種フィルタ
 *   ?prefecture=東京都          都道府県フィルタ
 *   ?specialty=内科             専門フィルタ
 *   ?limit=20                  件数 (max 100)
 *   ?offset=0                  オフセット
 */

const { getDb } = require('./lib/db');
const { verifyToken, json, safeParseJson, getBearerToken, CORS_HEADERS } = require('./lib/auth-utils');

const getSubPath = (path) =>
  (path || '').replace(/\/?\.netlify\/functions\/jobs\/?/, '').replace(/^\/+/, '');

const authenticate = (event) => {
  const token = getBearerToken(event);
  if (!token) return null;
  return verifyToken(token);
};

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: CORS_HEADERS, body: '' };
  }

  const method  = event.httpMethod;
  const subPath = getSubPath(event.path);
  const params  = event.queryStringParameters || {};
  const sql     = getDb();

  // ──────────────────────────────────────────────────────────────────────────
  // GET /api/jobs  – 求人一覧
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'GET' && subPath === '') {
    const limit  = Math.min(parseInt(params.limit  || '20', 10), 100);
    const offset = Math.max(parseInt(params.offset || '0',  10), 0);

    try {
      // 動的フィルタはパラメータ展開で注入インジェクション防止
      const rows = await sql`
        SELECT
          j.*,
          u.name           AS institution_name,
          u.avatar_initial AS institution_avatar_initial,
          u.avatar_color   AS institution_avatar_color,
          mip.facility_type,
          mip.city
        FROM job_listings j
        JOIN users u ON u.id = j.institution_id
        LEFT JOIN medical_institution_profiles mip ON mip.user_id = j.institution_id
        WHERE j.is_active = true
          AND (${params.type        || null} IS NULL OR j.required_type  = ${params.type        || null})
          AND (${params.prefecture  || null} IS NULL OR j.prefecture      = ${params.prefecture  || null})
          AND (${params.specialty   || null} IS NULL OR j.specialty ILIKE ${'%' + (params.specialty || '') + '%'})
        ORDER BY j.created_at DESC
        LIMIT ${limit} OFFSET ${offset}
      `;

      const [{ count }] = await sql`
        SELECT COUNT(*) FROM job_listings
        WHERE is_active = true
          AND (${params.type       || null} IS NULL OR required_type = ${params.type       || null})
          AND (${params.prefecture || null} IS NULL OR prefecture     = ${params.prefecture || null})
          AND (${params.specialty  || null} IS NULL OR specialty ILIKE ${'%' + (params.specialty || '') + '%'})
      `;

      return json(200, { ok: true, jobs: rows, total: Number(count), limit, offset });
    } catch (err) {
      console.error('[jobs] list error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // POST /api/jobs  – 求人作成
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'POST' && subPath === '') {
    const payload = authenticate(event);
    if (!payload) return json(401, { ok: false, error: '認証が必要です' });
    if (payload.type !== 'medical') {
      return json(403, { ok: false, error: '医療機関アカウントのみ求人を作成できます' });
    }

    const body = safeParseJson(event.body);
    if (!body) return json(400, { ok: false, error: '無効なリクエストです' });

    const {
      title, description, required_type, specialty,
      employment_type, work_days, hourly_rate_min, hourly_rate_max,
      prefecture, city,
    } = body;

    if (!title) return json(400, { ok: false, error: 'タイトルは必須です' });

    try {
      const [job] = await sql`
        INSERT INTO job_listings
          (institution_id, title, description, required_type, specialty,
           employment_type, work_days, hourly_rate_min, hourly_rate_max,
           prefecture, city)
        VALUES
          (${payload.id}, ${title}, ${description || null},
           ${required_type || null}, ${specialty || null},
           ${employment_type || null}, ${work_days || null},
           ${hourly_rate_min || null}, ${hourly_rate_max || null},
           ${prefecture || null}, ${city || null})
        RETURNING *
      `;
      return json(201, { ok: true, job });
    } catch (err) {
      console.error('[jobs] create error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GET /api/jobs/:id  – 求人詳細
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'GET' && subPath && !subPath.includes('/')) {
    try {
      const [job] = await sql`
        SELECT
          j.*,
          u.name           AS institution_name,
          u.avatar_initial AS institution_avatar_initial,
          u.avatar_color   AS institution_avatar_color,
          mip.facility_type,
          mip.city         AS institution_city
        FROM job_listings j
        JOIN users u ON u.id = j.institution_id
        LEFT JOIN medical_institution_profiles mip ON mip.user_id = j.institution_id
        WHERE j.id = ${subPath} AND j.is_active = true
      `;
      if (!job) return json(404, { ok: false, error: '求人が見つかりません' });
      return json(200, { ok: true, job });
    } catch (err) {
      console.error('[jobs] get error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUT /api/jobs/:id  – 求人更新
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'PUT' && subPath && !subPath.includes('/')) {
    const payload = authenticate(event);
    if (!payload) return json(401, { ok: false, error: '認証が必要です' });

    const body = safeParseJson(event.body);
    if (!body) return json(400, { ok: false, error: '無効なリクエストです' });

    try {
      const [existing] = await sql`SELECT * FROM job_listings WHERE id = ${subPath}`;
      if (!existing) return json(404, { ok: false, error: '求人が見つかりません' });
      if (existing.institution_id !== payload.id) {
        return json(403, { ok: false, error: 'この操作は許可されていません' });
      }

      const [updated] = await sql`
        UPDATE job_listings SET
          title            = COALESCE(${body.title            || null}, title),
          description      = COALESCE(${body.description      || null}, description),
          required_type    = COALESCE(${body.required_type    || null}, required_type),
          specialty        = COALESCE(${body.specialty        || null}, specialty),
          employment_type  = COALESCE(${body.employment_type  || null}, employment_type),
          work_days        = COALESCE(${body.work_days        || null}, work_days),
          hourly_rate_min  = COALESCE(${body.hourly_rate_min  ?? null}, hourly_rate_min),
          hourly_rate_max  = COALESCE(${body.hourly_rate_max  ?? null}, hourly_rate_max),
          prefecture       = COALESCE(${body.prefecture       || null}, prefecture),
          city             = COALESCE(${body.city             || null}, city),
          is_active        = COALESCE(${body.is_active        ?? null}, is_active)
        WHERE id = ${subPath}
        RETURNING *
      `;
      return json(200, { ok: true, job: updated });
    } catch (err) {
      console.error('[jobs] update error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DELETE /api/jobs/:id  – ソフトデリート
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'DELETE' && subPath && !subPath.includes('/')) {
    const payload = authenticate(event);
    if (!payload) return json(401, { ok: false, error: '認証が必要です' });

    try {
      const [existing] = await sql`SELECT * FROM job_listings WHERE id = ${subPath}`;
      if (!existing) return json(404, { ok: false, error: '求人が見つかりません' });
      if (existing.institution_id !== payload.id) {
        return json(403, { ok: false, error: 'この操作は許可されていません' });
      }

      await sql`UPDATE job_listings SET is_active = false WHERE id = ${subPath}`;
      return json(200, { ok: true, message: '求人を削除しました' });
    } catch (err) {
      console.error('[jobs] delete error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  return json(404, { ok: false, error: 'Not found' });
};
