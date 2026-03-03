/**
 * Shared Neon DB client
 *
 * Uses NETLIFY_DATABASE_URL automatically via @netlify/neon.
 * Import getDb() in any Netlify function to get the sql tag.
 */

const { neon } = require('@netlify/neon');

let _sql = null;

/**
 * Returns the neon SQL tag. Lazily initialised once per cold-start.
 * @returns {import('@neondatabase/serverless').NeonQueryFunction}
 */
const getDb = () => {
  if (!_sql) _sql = neon();
  return _sql;
};

module.exports = { getDb };
