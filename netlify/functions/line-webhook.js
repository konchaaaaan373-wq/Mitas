const crypto = require('crypto');

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
  destination: destination || '',
  webhookEventId: event.webhookEventId || '',
  eventType: event.type || '',
  timestamp: event.timestamp || '',
  mode: event.mode || '',
  sourceType: event.source?.type || '',
  sourceUserId: event.source?.userId || '',
  sourceGroupId: event.source?.groupId || '',
  sourceRoomId: event.source?.roomId || '',
  messageType: event.message?.type || '',
  messageText: event.message?.text || '',
  rawEvent: JSON.stringify(event),
});

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return json(405, { ok: false, error: 'Method Not Allowed' });
  }

  const rawBody = event.isBase64Encoded
    ? Buffer.from(event.body || '', 'base64').toString('utf8')
    : (event.body || '');

  const signature = event.headers['x-line-signature'] || event.headers['X-Line-Signature'];
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

  const gasWebhookUrl = process.env.GAS_WEBHOOK_URL;
  const gasWebhookSecret = process.env.GAS_WEBHOOK_SECRET || '';

  if (!gasWebhookUrl) {
    return json(500, { ok: false, error: 'Missing GAS_WEBHOOK_URL' });
  }

  const receivedAt = new Date().toISOString();
  const records = payload.events.map((evt) => normalizeRecord(evt, payload.destination, receivedAt));

  try {
    const res = await fetch(gasWebhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-neco-secret': gasWebhookSecret,
      },
      body: JSON.stringify({
        source: 'line-webhook',
        receivedAt,
        destination: payload.destination || '',
        secret: gasWebhookSecret,
        records,
      }),
    });

    if (!res.ok) {
      const responseText = await res.text();
      return json(502, {
        ok: false,
        error: 'Failed to write to GAS endpoint',
        status: res.status,
        response: responseText.slice(0, 500),
      });
    }

    return json(200, { ok: true, forwarded: records.length });
  } catch (err) {
    return json(500, {
      ok: false,
      error: 'Unexpected forwarding error',
      message: err?.message || String(err),
    });
  }
};
