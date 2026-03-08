/**
 * Messages Netlify Function – メッセージ機能
 *
 * Routes (via /api/messages/* → /.netlify/functions/messages/:splat):
 *   GET    /api/messages/conversations              – 会話一覧（要認証）
 *   POST   /api/messages/conversations              – 会話開始（要認証）
 *   GET    /api/messages/conversations/:id          – メッセージ履歴（要認証）
 *   POST   /api/messages/conversations/:id/send     – メッセージ送信（要認証）
 *   POST   /api/messages/conversations/:id/read     – 既読マーク（要認証）
 */

const bcrypt = require('bcryptjs');
const { getDb } = require('./lib/db');
const { verifyToken, json, safeParseJson, getBearerToken, CORS_HEADERS } = require('./lib/auth-utils');

// ── Neco ウェルカム会話の自動補完 ─────────────────────────────────────────────

function getWelcomeMessage(userType) {
  if (userType === 'doctor') {
    return `こんにちは、Necoです。\nこちらはメッセージ画面です。あなたのご経験やスキルに興味がある施設がある場合、医療機関からメッセージが送られてきます。\nまた、Neco運営とやり取りをしたい場合はこのチャットにメッセージをお送りください。返信には時間をいただくことがありますのでご了承ください。`;
  }
  if (userType === 'nurse') {
    return `こんにちは、Necoです。\nこちらはメッセージ画面です。あなたのご経験やスキルに興味がある施設がある場合、医療機関からメッセージが送られてきます。\nまた、Neco運営とやり取りをしたい場合はこのチャットにメッセージをお送りください。返信には時間をいただくことがありますのでご了承ください。`;
  }
  if (userType === 'medical') {
    return `こんにちは、Necoです。\nこちらはメッセージ画面です。登録した医師・看護師から問い合わせのメッセージが届きます。\nまた、Neco運営とやり取りをしたい場合はこのチャットにメッセージをお送りください。返信には時間をいただくことがありますのでご了承ください。`;
  }
  return `こんにちは、Necoです。\nNeco運営とやり取りをしたい場合はこのチャットにメッセージをお送りください。`;
}

async function ensureNecoWelcomeConversation(sql, userId, userType) {
  try {
    // Neco システムユーザーを取得（なければ作成）
    let [necoRow] = await sql`SELECT id FROM users WHERE email = 'neco-system@neco.jp'`;
    if (!necoRow) {
      const adminPassword = process.env.NECO_ADMIN_PASSWORD || ('neco-system-' + Date.now());
      const password_hash = await bcrypt.hash(adminPassword, 10);
      [necoRow] = await sql`
        INSERT INTO users (email, password_hash, user_type, name, avatar_initial, avatar_color, is_active)
        VALUES ('neco-system@neco.jp', ${password_hash}, 'admin', 'Neco', 'N', '#FF6B9D', true)
        RETURNING id
      `;
    }
    const necoId = necoRow.id;

    const p1 = userId < necoId ? userId : necoId;
    const p2 = userId < necoId ? necoId : userId;

    const [existing] = await sql`
      SELECT id FROM conversations WHERE participant1_id = ${p1} AND participant2_id = ${p2}
    `;
    if (existing) return; // すでに存在する

    const [conv] = await sql`
      INSERT INTO conversations (participant1_id, participant2_id, last_message_at)
      VALUES (${p1}, ${p2}, NOW())
      RETURNING id
    `;
    const welcomeMsg = getWelcomeMessage(userType);
    await sql`
      INSERT INTO messages (conversation_id, sender_id, content)
      VALUES (${conv.id}, ${necoId}, ${welcomeMsg})
    `;
    await sql`UPDATE conversations SET last_message_at = NOW() WHERE id = ${conv.id}`;
  } catch (err) {
    console.error('[messages] ensureNecoWelcomeConversation error:', err.message);
  }
}

// ── メール通知送信（Resend API 利用） ────────────────────────────────────────
async function sendEmailNotification({ toEmail, toName, fromName, messagePreview }) {
  const RESEND_API_KEY = process.env.RESEND_API_KEY;
  const EMAIL_FROM = process.env.EMAIL_FROM || 'Neco <noreply@neco.jp>';
  if (!RESEND_API_KEY) return; // 環境変数未設定時はスキップ

  const preview = messagePreview.length > 80
    ? messagePreview.slice(0, 80) + '…'
    : messagePreview;

  try {
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: EMAIL_FROM,
        to: [toEmail],
        subject: `【Neco】${fromName}さんからメッセージが届きました`,
        html: `
          <div style="font-family:'Noto Sans JP',sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;background:#fff;border-radius:12px;">
            <div style="text-align:center;margin-bottom:24px;">
              <span style="font-family:'Zen Kaku Gothic New',sans-serif;font-size:1.8rem;font-weight:900;background:linear-gradient(135deg,#FF6B9D,#A78BFA);-webkit-background-clip:text;-webkit-text-fill-color:transparent;">Neco</span>
            </div>
            <p style="font-size:1rem;color:#2D3142;margin-bottom:8px;">${toName} さん、</p>
            <p style="font-size:1rem;color:#2D3142;margin-bottom:24px;"><strong>${fromName}</strong> さんからメッセージが届きました。</p>
            <div style="background:#F3F4F6;border-radius:8px;padding:16px 20px;margin-bottom:24px;border-left:4px solid #FF6B9D;">
              <p style="font-size:0.9rem;color:#374151;margin:0;">${preview}</p>
            </div>
            <div style="text-align:center;margin-bottom:24px;">
              <a href="https://neco.jp/dashboard.html" style="display:inline-block;background:linear-gradient(135deg,#FF6B9D,#A78BFA);color:#fff;text-decoration:none;padding:12px 32px;border-radius:8px;font-weight:700;font-size:0.95rem;">メッセージを確認する</a>
            </div>
            <hr style="border:none;border-top:1px solid #E5E7EB;margin-bottom:16px;">
            <p style="font-size:0.75rem;color:#9CA3AF;text-align:center;">
              メール通知を停止する場合は、<a href="https://neco.jp/profile-doctor.html" style="color:#9CA3AF;">設定ページ</a>からオフにしてください。
            </p>
          </div>
        `,
      }),
    });
  } catch (err) {
    console.error('[messages] sendEmailNotification error:', err.message);
  }
}

const getSubPath = (path) =>
  (path || '').replace(/\/?\.netlify\/functions\/messages\/?/, '').replace(/^\/+/, '');

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
  // GET /api/messages/conversations  – 会話一覧
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'GET' && subPath === 'conversations') {
    try {
      const rows = await sql`
        SELECT
          c.id,
          c.last_message_at,
          c.created_at,
          -- 相手ユーザー情報
          CASE WHEN c.participant1_id = ${payload.id}
               THEN c.participant2_id ELSE c.participant1_id END AS other_user_id,
          u.name           AS other_user_name,
          u.user_type      AS other_user_type,
          u.avatar_initial AS other_user_avatar_initial,
          u.avatar_color   AS other_user_avatar_color,
          -- 最新メッセージ
          m.content        AS last_message_content,
          m.sender_id      AS last_message_sender_id,
          -- 未読数
          (SELECT COUNT(*) FROM messages
           WHERE conversation_id = c.id AND is_read = false AND sender_id != ${payload.id}
          )::int            AS unread_count
        FROM conversations c
        JOIN users u ON u.id = CASE WHEN c.participant1_id = ${payload.id}
                                    THEN c.participant2_id ELSE c.participant1_id END
        LEFT JOIN LATERAL (
          SELECT content, sender_id FROM messages
          WHERE conversation_id = c.id
          ORDER BY created_at DESC LIMIT 1
        ) m ON true
        WHERE c.participant1_id = ${payload.id} OR c.participant2_id = ${payload.id}
        ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
      `;

      // Neco ウェルカム会話が存在しない場合は自動作成してリストに反映
      const hasNeco = rows.some(r => r.other_user_type === 'admin' && r.other_user_name === 'Neco');
      if (!hasNeco) {
        await ensureNecoWelcomeConversation(sql, payload.id, payload.type);
        // 作成後に再取得
        const updated = await sql`
          SELECT
            c.id,
            c.last_message_at,
            c.created_at,
            CASE WHEN c.participant1_id = ${payload.id}
                 THEN c.participant2_id ELSE c.participant1_id END AS other_user_id,
            u.name           AS other_user_name,
            u.user_type      AS other_user_type,
            u.avatar_initial AS other_user_avatar_initial,
            u.avatar_color   AS other_user_avatar_color,
            m.content        AS last_message_content,
            m.sender_id      AS last_message_sender_id,
            (SELECT COUNT(*) FROM messages
             WHERE conversation_id = c.id AND is_read = false AND sender_id != ${payload.id}
            )::int            AS unread_count
          FROM conversations c
          JOIN users u ON u.id = CASE WHEN c.participant1_id = ${payload.id}
                                      THEN c.participant2_id ELSE c.participant1_id END
          LEFT JOIN LATERAL (
            SELECT content, sender_id FROM messages
            WHERE conversation_id = c.id
            ORDER BY created_at DESC LIMIT 1
          ) m ON true
          WHERE c.participant1_id = ${payload.id} OR c.participant2_id = ${payload.id}
          ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
        `;
        return json(200, { ok: true, conversations: updated });
      }

      return json(200, { ok: true, conversations: rows });
    } catch (err) {
      console.error('[messages] conversations list error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // POST /api/messages/conversations  – 会話開始
  // ──────────────────────────────────────────────────────────────────────────
  if (method === 'POST' && subPath === 'conversations') {
    const body = safeParseJson(event.body);
    if (!body) return json(400, { ok: false, error: '無効なリクエストです' });

    const { recipient_id } = body;
    if (!recipient_id) return json(400, { ok: false, error: 'recipient_id は必須です' });
    if (recipient_id === payload.id) {
      return json(400, { ok: false, error: '自分自身には送れません' });
    }

    try {
      // 相手ユーザーが存在するか確認
      const [other] = await sql`SELECT id FROM users WHERE id = ${recipient_id} AND is_active = true`;
      if (!other) return json(404, { ok: false, error: '相手ユーザーが見つかりません' });

      // 既存の会話を探す（participant順序を正規化）
      const p1 = payload.id < recipient_id ? payload.id : recipient_id;
      const p2 = payload.id < recipient_id ? recipient_id : payload.id;

      let [conv] = await sql`
        SELECT * FROM conversations
        WHERE participant1_id = ${p1} AND participant2_id = ${p2}
      `;

      if (!conv) {
        [conv] = await sql`
          INSERT INTO conversations (participant1_id, participant2_id)
          VALUES (${p1}, ${p2})
          RETURNING *
        `;
      }

      return json(200, { ok: true, conversation: conv });
    } catch (err) {
      console.error('[messages] conversation create error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GET /api/messages/conversations/:id  – メッセージ履歴
  // ──────────────────────────────────────────────────────────────────────────
  const convMatch = subPath.match(/^conversations\/([^/]+)$/);
  if (method === 'GET' && convMatch) {
    const convId = convMatch[1];
    const params  = event.queryStringParameters || {};
    const limit   = Math.min(parseInt(params.limit || '50', 10), 200);
    const before  = params.before || null; // ISO timestamp カーソル

    try {
      const [conv] = await sql`SELECT * FROM conversations WHERE id = ${convId}`;
      if (!conv) return json(404, { ok: false, error: '会話が見つかりません' });
      if (conv.participant1_id !== payload.id && conv.participant2_id !== payload.id) {
        return json(403, { ok: false, error: 'この操作は許可されていません' });
      }

      const rows = await sql`
        SELECT m.*, u.name AS sender_name, u.avatar_initial, u.avatar_color
        FROM messages m
        JOIN users u ON u.id = m.sender_id
        WHERE m.conversation_id = ${convId}
          AND (${before} IS NULL OR m.created_at < ${before}::timestamptz)
        ORDER BY m.created_at DESC
        LIMIT ${limit}
      `;

      return json(200, { ok: true, messages: rows.reverse() });
    } catch (err) {
      console.error('[messages] history error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // POST /api/messages/conversations/:id/send  – メッセージ送信
  // ──────────────────────────────────────────────────────────────────────────
  const sendMatch = subPath.match(/^conversations\/([^/]+)\/send$/);
  if (method === 'POST' && sendMatch) {
    const convId = sendMatch[1];
    const body   = safeParseJson(event.body);
    if (!body) return json(400, { ok: false, error: '無効なリクエストです' });

    const { content } = body;
    if (!content || !String(content).trim()) {
      return json(400, { ok: false, error: 'メッセージ内容は必須です' });
    }

    try {
      const [conv] = await sql`SELECT * FROM conversations WHERE id = ${convId}`;
      if (!conv) return json(404, { ok: false, error: '会話が見つかりません' });
      if (conv.participant1_id !== payload.id && conv.participant2_id !== payload.id) {
        return json(403, { ok: false, error: 'この操作は許可されていません' });
      }

      const [msg] = await sql`
        INSERT INTO messages (conversation_id, sender_id, content)
        VALUES (${convId}, ${payload.id}, ${String(content).trim()})
        RETURNING *
      `;

      // 会話の last_message_at を更新
      await sql`UPDATE conversations SET last_message_at = NOW() WHERE id = ${convId}`;

      // 受信者のメール通知設定を確認して送信
      const recipientId = conv.participant1_id === payload.id
        ? conv.participant2_id
        : conv.participant1_id;
      const [recipient] = await sql`
        SELECT email, name, email_notification FROM users WHERE id = ${recipientId}
      `;
      if (recipient?.email_notification) {
        const [sender] = await sql`SELECT name FROM users WHERE id = ${payload.id}`;
        sendEmailNotification({
          toEmail: recipient.email,
          toName: recipient.name,
          fromName: sender?.name || 'Necoユーザー',
          messagePreview: String(content).trim(),
        }).catch(() => {});
      }

      return json(201, { ok: true, message: msg });
    } catch (err) {
      console.error('[messages] send error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // POST /api/messages/conversations/:id/read  – 既読マーク
  // ──────────────────────────────────────────────────────────────────────────
  const readMatch = subPath.match(/^conversations\/([^/]+)\/read$/);
  if (method === 'POST' && readMatch) {
    const convId = readMatch[1];

    try {
      const [conv] = await sql`SELECT * FROM conversations WHERE id = ${convId}`;
      if (!conv) return json(404, { ok: false, error: '会話が見つかりません' });
      if (conv.participant1_id !== payload.id && conv.participant2_id !== payload.id) {
        return json(403, { ok: false, error: 'この操作は許可されていません' });
      }

      const result = await sql`
        UPDATE messages
        SET is_read = true
        WHERE conversation_id = ${convId}
          AND sender_id != ${payload.id}
          AND is_read = false
      `;

      return json(200, { ok: true, updated: result.count ?? 0 });
    } catch (err) {
      console.error('[messages] read error:', err.message);
      return json(500, { ok: false, error: 'サーバーエラーが発生しました' });
    }
  }

  return json(404, { ok: false, error: 'Not found' });
};
