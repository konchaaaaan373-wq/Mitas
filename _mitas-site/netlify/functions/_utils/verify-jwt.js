/**
 * JWT検証ユーティリティ
 * hospital-login.js と同じ署名方式（HMAC-SHA256）で検証する
 */

const crypto = require('crypto');

/**
 * JWTを検証してペイロードを返す
 * @param {string} token - Authorization: Bearer <token> から取り出したトークン
 * @param {string} secret - SESSION_SECRET 環境変数
 * @returns {{ sub: string, name: string, role: string, exp: number }}
 * @throws エラー（invalid / expired）
 */
function verifyJwt(token, secret) {
  if (!token || typeof token !== 'string') throw new Error('トークンがありません');

  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('トークン形式が無効です');

  const [header, payload, sig] = parts;

  // 署名検証
  const expected = crypto
    .createHmac('sha256', secret)
    .update(`${header}.${payload}`)
    .digest('base64url');

  if (sig.length !== expected.length) throw new Error('署名が無効です');
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) {
    throw new Error('署名が無効です');
  }

  // ペイロードデコード
  const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));

  // 有効期限チェック
  if (data.exp && data.exp < Math.floor(Date.now() / 1000)) {
    throw new Error('セッションが期限切れです');
  }

  return data;
}

/**
 * リクエストヘッダーからBearerトークンを抽出して検証する
 * @param {object} headers - event.headers
 * @returns {{ sub: string, name: string, role: string }}
 */
function authFromHeaders(headers) {
  const authHeader = headers['authorization'] || headers['Authorization'] || '';
  if (!authHeader.startsWith('Bearer ')) throw new Error('認証ヘッダーがありません');
  const token = authHeader.slice(7);
  const secret = process.env.SESSION_SECRET || 'dev-secret-change-before-production';
  return verifyJwt(token, secret);
}

module.exports = { verifyJwt, authFromHeaders };
