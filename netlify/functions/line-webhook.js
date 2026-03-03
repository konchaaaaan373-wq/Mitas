/**
 * LINE Webhook Netlify Function
 *
 * LINE Messaging API からの Webhook を受け取り:
 *   1. Neon DB の line_events テーブルに保存（プライマリ）
 *   2. GAS_WEBHOOK_URL が設定されていれば Google Apps Script に転送（オプション）
 */

const crypto = require('crypto');
const { getDb } = require('./lib/db');

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: JSON.stringify(body),
});

const safeParseJson = (raw) => {
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
};

const verifyLineSignature = (rawBody, signature, channelSecret) => {
  const mac = crypto
    .createHmac('sha256', channelSecret)
    .update(rawBody, 'utf8')
    .digest('base64');
  return mac === signature;
};

const normalizeRecord = (event, destination, receivedAt) => ({
  receivedAt,
  destination:    destination || '',
  webhookEventId: event.webhookEventId || '',
  eventType:      event.type           || '',
  timestamp:      event.timestamp      || null,
  mode:           event.mode           || '',
  sourceType:     event.source?.type   || '',
  sourceUserId:   event.source?.userId || '',
  sourceGroupId:  event.source?.groupId || '',
  sourceRoomId:   event.source?.roomId  || '',
  messageType:    event.message?.type  || '',
  messageText:    event.message?.text  || '',
  rawEvent:       JSON.stringify(event),
});

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return json(405, { ok: false, error: 'Method Not Allowed' });
  }

  const rawBody = event.isBase64Encoded
    ? Buffer.from(event.body || '', 'base64').toString('utf8')
    : (event.body || '');

  const signature       = event.headers['x-line-signature'] || event.headers['X-Line-Signature'];
  const lineChannelSecret = process.env.LINE_CHANNEL_SECRET || '';

  if (lineChannelSecret) {
    if (!signature || !verifyLineSignature(rawBody, signature, lineChannelSecret)) {
      return json(401, { ok: false, error: 'Invalid LINE signature' });
    }
  }

  const payload = safeParseJson(rawBody);
  if (!payload || !Array.isArray(payload.events)) {
    return json(400, { ok: false, error: 'Invalid webhook payload' });
  }

  const receivedAt = new Date().toISOString();
  const records    = payload.events.map((evt) => normalizeRecord(evt, payload.destination, receivedAt));

  // ── 1. DB 保存 ───────────────────────────────────────────────────────────
  let dbSaved = 0;
  try {
    const sql = getDb();
    for (const r of records) {
      await sql`
        INSERT INTO line_events
          (received_at, destination, webhook_event_id, event_type, ts, mode,
           source_type, source_user_id, source_group_id, source_room_id,
           message_type, message_text, raw_event)
        VALUES
          (${r.receivedAt}, ${r.destination}, ${r.webhookEventId || null},
           ${r.eventType || null}, ${r.timestamp || null}, ${r.mode || null},
           ${r.sourceType || null}, ${r.sourceUserId || null},
           ${r.sourceGroupId || null}, ${r.sourceRoomId || null},
           ${r.messageType || null}, ${r.messageText || null},
           ${r.rawEvent}::jsonb)
      `;
      dbSaved++;
    }
  } catch (dbErr) {
    console.error('[line-webhook] DB save error:', dbErr.message);
    // DB エラーでも LINE には 200 を返してリトライを防ぐ
  }

  // ── 2. GAS 転送（オプション） ─────────────────────────────────────────────
  const gasWebhookUrl    = process.env.GAS_WEBHOOK_URL;
  const gasWebhookSecret = process.env.GAS_WEBHOOK_SECRET || '';

  if (gasWebhookUrl) {
    try {
      const res = await fetch(gasWebhookUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-neco-secret': gasWebhookSecret,
        },
        body: JSON.stringify({
          source:      'line-webhook',
          receivedAt,
          destination: payload.destination || '',
          secret:      gasWebhookSecret,
          records,
        }),
      });
      if (!res.ok) {
        console.warn('[line-webhook] GAS forward non-2xx:', res.status);
      }
    } catch (gasErr) {
      console.warn('[line-webhook] GAS forward error:', gasErr.message);
    }
  }

  return json(200, { ok: true, saved: dbSaved, forwarded: gasWebhookUrl ? records.length : 0 });
};
