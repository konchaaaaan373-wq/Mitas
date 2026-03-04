/**
 * 管理者用統計 API
 *
 * Neon DB の各テーブルを集計して、会社ダッシュボード向けのデータを返す。
 *
 * Route (netlify.toml で設定):
 *   GET /api/admin/stats
 *
 * 認証:
 *   Header: x-admin-secret: <ADMIN_SECRET 環境変数>
 *
 * クエリパラメータ:
 *   ?days=30  → 直近 N 日間のトレンドデータ（デフォルト: 30）
 */

const { getDb } = require('./lib/db');
const { json, CORS_HEADERS } = require('./lib/auth-utils');

const ADMIN_SECRET = process.env.ADMIN_SECRET || '';

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: CORS_HEADERS, body: '' };
  }

  if (event.httpMethod !== 'GET') {
    return json(405, { ok: false, error: 'Method Not Allowed' });
  }

  // 管理者シークレット認証
  const secret = event.headers['x-admin-secret'] || '';
  if (!ADMIN_SECRET || secret !== ADMIN_SECRET) {
    return json(401, { ok: false, error: '管理者シークレットが無効です' });
  }

  const params = event.queryStringParameters || {};
  const days = Math.min(Math.max(parseInt(params.days) || 30, 1), 365);

  const sql = getDb();

  try {
    // ── ユーザー統計 ──────────────────────────────────────────────────────────
    const [userCounts] = await sql`
      SELECT
        COUNT(*)                                              AS total,
        COUNT(*) FILTER (WHERE user_type = 'doctor')         AS doctors,
        COUNT(*) FILTER (WHERE user_type = 'nurse')          AS nurses,
        COUNT(*) FILTER (WHERE user_type = 'medical')        AS medical_institutions,
        COUNT(*) FILTER (WHERE is_active = true)             AS active_users,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')  AS new_this_week,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS new_this_month
      FROM users
      WHERE user_type != 'admin'
    `;

    // ── 求人統計 ──────────────────────────────────────────────────────────────
    const [jobCounts] = await sql`
      SELECT
        COUNT(*)                                           AS total,
        COUNT(*) FILTER (WHERE is_active = true)           AS active,
        COUNT(*) FILTER (WHERE is_active = false)          AS closed,
        COUNT(*) FILTER (WHERE required_type = 'doctor')   AS for_doctors,
        COUNT(*) FILTER (WHERE required_type = 'nurse')    AS for_nurses,
        COUNT(*) FILTER (WHERE required_type = 'both')     AS for_both,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')  AS new_this_week,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS new_this_month
      FROM job_listings
    `;

    // ── 応募統計 ──────────────────────────────────────────────────────────────
    const [appCounts] = await sql`
      SELECT
        COUNT(*)                                                AS total,
        COUNT(*) FILTER (WHERE status = 'pending')              AS pending,
        COUNT(*) FILTER (WHERE status = 'reviewing')            AS reviewing,
        COUNT(*) FILTER (WHERE status = 'accepted')             AS accepted,
        COUNT(*) FILTER (WHERE status = 'rejected')             AS rejected,
        COUNT(*) FILTER (WHERE status = 'withdrawn')            AS withdrawn,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')  AS new_this_week,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS new_this_month
      FROM job_applications
    `;

    // ── メッセージ統計 ────────────────────────────────────────────────────────
    const [msgCounts] = await sql`
      SELECT
        COUNT(*)                                              AS total_messages,
        COUNT(*) FILTER (WHERE is_read = false)               AS unread,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')  AS new_this_week,
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS new_this_month,
        (SELECT COUNT(*) FROM conversations)                  AS total_conversations
      FROM messages
    `;

    // ── LINE イベント統計 ─────────────────────────────────────────────────────
    const [lineCounts] = await sql`
      SELECT
        COUNT(*)                                                     AS total,
        COUNT(*) FILTER (WHERE event_type = 'follow')                AS follows,
        COUNT(*) FILTER (WHERE event_type = 'unfollow')              AS unfollows,
        COUNT(*) FILTER (WHERE event_type = 'message')               AS messages,
        COUNT(*) FILTER (WHERE received_at >= NOW() - INTERVAL '7 days')  AS new_this_week,
        COUNT(*) FILTER (WHERE received_at >= NOW() - INTERVAL '30 days') AS new_this_month
      FROM line_events
    `;

    // ── 日次トレンド（直近 N 日） ─────────────────────────────────────────────
    const userTrend = await sql`
      SELECT
        DATE(created_at AT TIME ZONE 'Asia/Tokyo') AS date,
        COUNT(*) FILTER (WHERE user_type = 'doctor') AS doctors,
        COUNT(*) FILTER (WHERE user_type = 'nurse')  AS nurses,
        COUNT(*) FILTER (WHERE user_type = 'medical') AS medical,
        COUNT(*) AS total
      FROM users
      WHERE created_at >= NOW() - (${days} || ' days')::INTERVAL
        AND user_type != 'admin'
      GROUP BY DATE(created_at AT TIME ZONE 'Asia/Tokyo')
      ORDER BY date ASC
    `;

    const appTrend = await sql`
      SELECT
        DATE(created_at AT TIME ZONE 'Asia/Tokyo') AS date,
        COUNT(*) AS applications,
        COUNT(*) FILTER (WHERE status = 'accepted') AS accepted
      FROM job_applications
      WHERE created_at >= NOW() - (${days} || ' days')::INTERVAL
      GROUP BY DATE(created_at AT TIME ZONE 'Asia/Tokyo')
      ORDER BY date ASC
    `;

    // ── 都道府県別ユーザー分布 ────────────────────────────────────────────────
    const doctorsByPref = await sql`
      SELECT dp.prefecture, COUNT(*) AS count
      FROM doctor_profiles dp
      JOIN users u ON u.id = dp.user_id
      WHERE u.is_active = true AND dp.prefecture IS NOT NULL
      GROUP BY dp.prefecture
      ORDER BY count DESC
      LIMIT 10
    `;

    const nursesByPref = await sql`
      SELECT np.prefecture, COUNT(*) AS count
      FROM nurse_profiles np
      JOIN users u ON u.id = np.user_id
      WHERE u.is_active = true AND np.prefecture IS NOT NULL
      GROUP BY np.prefecture
      ORDER BY count DESC
      LIMIT 10
    `;

    // ── 求人カテゴリ別上位 ────────────────────────────────────────────────────
    const topSpecialties = await sql`
      SELECT specialty, COUNT(*) AS count
      FROM job_listings
      WHERE is_active = true AND specialty IS NOT NULL
      GROUP BY specialty
      ORDER BY count DESC
      LIMIT 10
    `;

    // ── 最近の応募アクティビティ ──────────────────────────────────────────────
    const recentApplications = await sql`
      SELECT
        ja.id,
        ja.status,
        ja.created_at,
        u.name       AS applicant_name,
        u.user_type  AS applicant_type,
        jl.title     AS job_title,
        inst.name    AS institution_name
      FROM job_applications ja
      JOIN users u    ON u.id = ja.applicant_id
      JOIN job_listings jl ON jl.id = ja.job_id
      JOIN users inst  ON inst.id = jl.institution_id
      ORDER BY ja.created_at DESC
      LIMIT 10
    `;

    // ── 最近登録したユーザー ──────────────────────────────────────────────────
    const recentUsers = await sql`
      SELECT id, name, user_type, created_at, is_active
      FROM users
      WHERE user_type != 'admin'
      ORDER BY created_at DESC
      LIMIT 10
    `;

    // ── 最近の LINE イベント ──────────────────────────────────────────────────
    const recentLineEvents = await sql`
      SELECT
        id, event_type, source_type, source_user_id,
        message_text, received_at
      FROM line_events
      ORDER BY received_at DESC
      LIMIT 20
    `;

    return json(200, {
      ok: true,
      generated_at: new Date().toISOString(),
      days_range: days,
      users: {
        total:                parseInt(userCounts.total),
        doctors:              parseInt(userCounts.doctors),
        nurses:               parseInt(userCounts.nurses),
        medical_institutions: parseInt(userCounts.medical_institutions),
        active:               parseInt(userCounts.active_users),
        new_this_week:        parseInt(userCounts.new_this_week),
        new_this_month:       parseInt(userCounts.new_this_month),
      },
      jobs: {
        total:         parseInt(jobCounts.total),
        active:        parseInt(jobCounts.active),
        closed:        parseInt(jobCounts.closed),
        for_doctors:   parseInt(jobCounts.for_doctors),
        for_nurses:    parseInt(jobCounts.for_nurses),
        for_both:      parseInt(jobCounts.for_both),
        new_this_week: parseInt(jobCounts.new_this_week),
        new_this_month: parseInt(jobCounts.new_this_month),
      },
      applications: {
        total:         parseInt(appCounts.total),
        pending:       parseInt(appCounts.pending),
        reviewing:     parseInt(appCounts.reviewing),
        accepted:      parseInt(appCounts.accepted),
        rejected:      parseInt(appCounts.rejected),
        withdrawn:     parseInt(appCounts.withdrawn),
        new_this_week: parseInt(appCounts.new_this_week),
        new_this_month: parseInt(appCounts.new_this_month),
        acceptance_rate: appCounts.total > 0
          ? Math.round(parseInt(appCounts.accepted) / parseInt(appCounts.total) * 1000) / 10
          : 0,
      },
      messages: {
        total:               parseInt(msgCounts.total_messages),
        unread:              parseInt(msgCounts.unread),
        total_conversations: parseInt(msgCounts.total_conversations),
        new_this_week:       parseInt(msgCounts.new_this_week),
        new_this_month:      parseInt(msgCounts.new_this_month),
      },
      line_events: {
        total:         parseInt(lineCounts.total),
        follows:       parseInt(lineCounts.follows),
        unfollows:     parseInt(lineCounts.unfollows),
        messages:      parseInt(lineCounts.messages),
        new_this_week: parseInt(lineCounts.new_this_week),
        new_this_month: parseInt(lineCounts.new_this_month),
      },
      trends: {
        user_registrations: userTrend.map((r) => ({
          date:    r.date,
          doctors: parseInt(r.doctors),
          nurses:  parseInt(r.nurses),
          medical: parseInt(r.medical),
          total:   parseInt(r.total),
        })),
        applications: appTrend.map((r) => ({
          date:         r.date,
          applications: parseInt(r.applications),
          accepted:     parseInt(r.accepted),
        })),
      },
      distributions: {
        doctors_by_prefecture:  doctorsByPref.map((r) => ({ name: r.prefecture, count: parseInt(r.count) })),
        nurses_by_prefecture:   nursesByPref.map((r) => ({ name: r.prefecture, count: parseInt(r.count) })),
        top_job_specialties:    topSpecialties.map((r) => ({ name: r.specialty, count: parseInt(r.count) })),
      },
      recent: {
        applications: recentApplications.map((r) => ({
          id:               r.id,
          status:           r.status,
          created_at:       r.created_at,
          applicant_name:   r.applicant_name,
          applicant_type:   r.applicant_type,
          job_title:        r.job_title,
          institution_name: r.institution_name,
        })),
        users: recentUsers.map((r) => ({
          id:         r.id,
          name:       r.name,
          user_type:  r.user_type,
          created_at: r.created_at,
          is_active:  r.is_active,
        })),
        line_events: recentLineEvents.map((r) => ({
          id:             r.id,
          event_type:     r.event_type,
          source_type:    r.source_type,
          source_user_id: r.source_user_id,
          message_text:   r.message_text,
          received_at:    r.received_at,
        })),
      },
    });
  } catch (err) {
    console.error('[admin-stats] DB error:', err.message);
    return json(500, {
      ok: false,
      error: '統計データの取得に失敗しました',
      detail: err.message,
    });
  }
};
