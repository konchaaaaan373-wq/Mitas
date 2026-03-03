/**
 * Shared authentication utilities
 *
 * Token format: base64url(JSON payload) + "." + HMAC-SHA256 signature
 * 7-day expiry. Set SESSION_SECRET env var in Netlify dashboard.
 */

const crypto = require('crypto');

const SESSION_SECRET =
  process.env.SESSION_SECRET || 'neco-demo-secret-CHANGE-ME-in-production';

// ── Token helpers ────────────────────────────────────────────────────────────

const sign = (data) =>
  crypto.createHmac('sha256', SESSION_SECRET).update(data).digest('hex');

const toBase64url = (str) =>
  Buffer.from(str)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');

const fromBase64url = (str) => {
  const padded =
    str.replace(/-/g, '+').replace(/_/g, '/') +
    '='.repeat((4 - (str.length % 4)) % 4);
  return Buffer.from(padded, 'base64').toString();
};

/**
 * Creates a signed token for the given user object.
 * Accepts both snake_case (DB rows) and camelCase (legacy) keys.
 */
const createToken = (user) => {
  const payload = {
    id: user.id,
    email: user.email,
    type: user.user_type || user.type,
    name: user.name,
    iat: Date.now(),
    exp: Date.now() + 7 * 24 * 60 * 60 * 1000,
  };
  const payloadStr = toBase64url(JSON.stringify(payload));
  return `${payloadStr}.${sign(payloadStr)}`;
};

/**
 * Verifies a token string. Returns the payload object or null on failure.
 */
const verifyToken = (token) => {
  try {
    const dotIdx = token.lastIndexOf('.');
    if (dotIdx === -1) return null;
    const payloadStr = token.slice(0, dotIdx);
    const signature = token.slice(dotIdx + 1);
    if (sign(payloadStr) !== signature) return null;
    const payload = JSON.parse(fromBase64url(payloadStr));
    if (payload.exp < Date.now()) return null;
    return payload;
  } catch (_) {
    return null;
  }
};

// ── HTTP helpers ─────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
};

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS_HEADERS },
  body: JSON.stringify(body),
});

const safeParseJson = (raw) => {
  try {
    return JSON.parse(raw || '{}');
  } catch (_) {
    return null;
  }
};

/** Extracts Bearer token from Authorization header. Returns null if missing. */
const getBearerToken = (event) => {
  const h = event.headers['authorization'] || event.headers['Authorization'] || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
};

module.exports = {
  createToken,
  verifyToken,
  CORS_HEADERS,
  json,
  safeParseJson,
  getBearerToken,
};
