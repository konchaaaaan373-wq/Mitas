/**
 * Applications Netlify Function – 応募管理
 *
 * Routes (via /api/applications/* → /.netlify/functions/applications/:splat):
 *   POST   /api/applications              – 求人に応募（医師・看護師）
 *   GET    /api/applications              – 応募一覧
 *                                           医師/看護師: 自分の応募履歴
 *                                           医療機関:    受け取った応募一覧
 *   GET    /api/applications/:id         – 応募詳細
 *   PUT    /api/applications/:id/status  – ステータス更新（医療機関のみ）
 *   DELETE /api/applications/:id         – 応募取り下げ（応募者のみ）
 */

const { getDb } = require('./lib/db');
const { verifyToken, json, safeParseJson, getBearerToken, CORS_HEADERS } = require('./lib/auth-utils');

const getSubPath = (path) =>
  (path || '').replace(/\/?\.netlify\/functions\/applications\/?/, '').replace(/^\/+/, '');

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
  const sql     = getDb();

  const payload = authenticate(event);
  if (!payload) return json(401, { ok: false, error: '認証が必要です' });

  // ──────────────────────────────────────────────────────────────────────────
  // POST /api/applications  – 応募
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'POST' && subPath === '') {
    if (!['doctor', 'nurse'].includes(payload.type)) {
      return json(403, { ok: false, error: '医師・看護師アカウントのみ応募できます' });
    }

    const body = safeParseJson(event.body);
    if (!body) return json(400, { ok: false, error: '無効なリクエストです' });

    const { job_id, message } = body;
    if (!job_id) return json(400, { ok: false, error: '求人IDは必須です' });

    try {
      // 求人存在チェック
      const [job] = await sql`
        SELECT id, institution_id, required_type FROM job_listings
        WHERE id = ${job_id} AND is_active = true
      `;
      if (!job) return json(404, { ok: false, error: '求人が見つかりません' });

      // 対象職種チェック
      if (job.required_type !== 'both' && job.required_type !== payload.type) {
        return json(403, { ok: false, error: 'この求人は対象外の職種です' });
      }

      const [app] = await sql`
        INSERT INTO job_applications (job_id, applicant_id, message)
        VALUES (${job_id}, ${payload.id}, ${message || null})
        RETURNING *
      `;
      return json(201, { ok: true, application: app });
    } catch (err) {
      if (err.message && err.message.includes('unique')) {
        return json(409, { ok: false, error: 'すでにこの求人に応募済みです' });
      }
      console.error('[applications] create error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GET /api/applications  – 一覧
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'GET' && subPath === '') {
    try {
      let rows;

      if (payload.type === 'medical') {
        // 医療機関: 自分の求人への応募を取得
        rows = await sql`
          SELECT
            a.*,
            j.title      AS job_title,
            j.specialty  AS job_specialty,
            u.name       AS applicant_name,
            u.user_type  AS applicant_type,
            u.avatar_initial AS applicant_avatar_initial,
            u.avatar_color   AS applicant_avatar_color
          FROM job_applications a
          JOIN job_listings j ON j.id = a.job_id
          JOIN users u ON u.id = a.applicant_id
          WHERE j.institution_id = ${payload.id}
          ORDER BY a.created_at DESC
        `;
      } else {
        // 医師・看護師: 自分の応募履歴
        rows = await sql`
          SELECT
            a.*,
            j.title         AS job_title,
            j.specialty     AS job_specialty,
            j.prefecture    AS job_prefecture,
            j.city          AS job_city,
            u.name          AS institution_name,
            u.avatar_initial AS institution_avatar_initial,
            u.avatar_color   AS institution_avatar_color
          FROM job_applications a
          JOIN job_listings j ON j.id = a.job_id
          JOIN users u ON u.id = j.institution_id
          WHERE a.applicant_id = ${payload.id}
          ORDER BY a.created_at DESC
        `;
      }

      return json(200, { ok: true, applications: rows });
    } catch (err) {
      console.error('[applications] list error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GET /api/applications/:id  – 詳細
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'GET' && subPath && !subPath.includes('/')) {
    try {
      const [app] = await sql`
        SELECT a.*, j.institution_id, j.title AS job_title
        FROM job_applications a
        JOIN job_listings j ON j.id = a.job_id
        WHERE a.id = ${subPath}
      `;
      if (!app) return json(404, { ok: false, error: '応募が見つかりません' });

      // アクセス権チェック: 応募者本人 or 求人の医療機関
      if (app.applicant_id !== payload.id && app.institution_id !== payload.id) {
        return json(403, { ok: false, error: 'この操作は許可されていません' });
      }
      return json(200, { ok: true, application: app });
    } catch (err) {
      console.error('[applications] get error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUT /api/applications/:id/status  – ステータス更新（医療機関）
  // ──────────────────────────────────────────────────────────────────────────
  const statusMatch = subPath.match(/^([^/]+)\/status$/);
  if (method === 'PUT' && statusMatch) {
    if (payload.type !== 'medical') {
      return json(403, { ok: false, error: '医療機関アカウントのみステータスを変更できます' });
    }

    const body = safeParseJson(event.body);
    const { status } = body || {};
    const allowed = ['pending', 'reviewing', 'accepted', 'rejected'];
    if (!status || !allowed.includes(status)) {
      return json(400, { ok: false, error: `statusは ${allowed.join('|')} のいずれかです` });
    }

    const appId = statusMatch[1];
    try {
      const [app] = await sql`
        SELECT a.*, j.institution_id
        FROM job_applications a
        JOIN job_listings j ON j.id = a.job_id
        WHERE a.id = ${appId}
      `;
      if (!app) return json(404, { ok: false, error: '応募が見つかりません' });
      if (app.institution_id !== payload.id) {
        return json(403, { ok: false, error: 'この操作は許可されていません' });
      }

      const [updated] = await sql`
        UPDATE job_applications SET status = ${status} WHERE id = ${appId} RETURNING *
      `;
      return json(200, { ok: true, application: updated });
    } catch (err) {
      console.error('[applications] status update error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DELETE /api/applications/:id  – 取り下げ（応募者）
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'DELETE' && subPath && !subPath.includes('/')) {
    try {
      const [app] = await sql`SELECT * FROM job_applications WHERE id = ${subPath}`;
      if (!app) return json(404, { ok: false, error: '応募が見つかりません' });
      if (app.applicant_id !== payload.id) {
        return json(403, { ok: false, error: 'この操作は許可されていません' });
      }
      if (['accepted', 'rejected'].includes(app.status)) {
        return json(409, { ok: false, error: '選考が進んだ応募は取り下げできません' });
      }

      await sql`UPDATE job_applications SET status = 'withdrawn' WHERE id = ${subPath}`;
      return json(200, { ok: true, message: '応募を取り下げました' });
    } catch (err) {
      console.error('[applications] delete error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  return json(404, { ok: false, error: 'Not found' });
};
