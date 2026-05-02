// Supabase 設定（Netlify 環境変数から取得、またはここに直接記入）
const SUPABASE_URL      = window.__SUPABASE_URL__      || 'https://cztoepghaimofqjnuvou.supabase.co'
const SUPABASE_ANON_KEY = window.__SUPABASE_ANON_KEY__ || 'sb_publishable_Fc1Dp1Daj-GeHRlSmCR4ow_rFahzKql'

const { createClient } = supabase  // CDN（@supabase/supabase-js）でロード済み
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

// Supabase エラー → 日本語
const ERR_MAP = {
  'Invalid login credentials':  'メールアドレスまたはパスワードが正しくありません。',
  'Email not confirmed':         'メールアドレスの確認が完了していません。',
  'Too many requests':           'ログイン試行が多すぎます。しばらくお待ちください。',
  'User not found':              'アカウントが見つかりません。',
}
function toJa(msg = '') {
  for (const [k, v] of Object.entries(ERR_MAP)) {
    if (msg.includes(k)) return v
  }
  return 'ログインに失敗しました。担当者にお問い合わせください。'
}

/**
 * リダイレクト先の安全性を検証
 * 相対パス（/ で始まり、//や :// を含まない）のみ許可（open redirect 防止）
 */
function safeRedirectPath(path, fallback = '/dashboard.html') {
  if (typeof path !== 'string' || !path) return fallback
  // 絶対 URL や protocol-relative URL は拒否
  if (/^https?:\/\//i.test(path)) return fallback
  if (path.startsWith('//')) return fallback
  // 相対パス（/ で始まる）のみ許可
  if (!path.startsWith('/')) return fallback
  return path
}

/**
 * user_roles.role からデフォルト遷移先を返す
 * 未知のロール／取得失敗時は /dashboard.html にフォールバック
 */
const ROLE_HOME = {
  worker:         '/worker-app.html',
  facility_admin: '/dashboard.html',
  neco_admin:     '/neco-console.html',
  alliance_admin: '/alliance-dashboard.html',
}
async function fetchUserRole() {
  try {
    const { data: sess } = await db.auth.getSession()
    const userId = sess?.session?.user?.id
    if (!userId) return null
    const { data, error } = await db
      .from('user_roles')
      .select('role')
      .eq('user_id', userId)
      .maybeSingle()
    if (error || !data) return null
    return data.role || null
  } catch (_) { return null }
}
async function defaultPathForRole() {
  const role = await fetchUserRole()
  return ROLE_HOME[role] || '/dashboard.html'
}

/**
 * 現在のユーザーが所属する組織を取得し、sessionStorage に
 * `mitas_org`（{ id, name } の JSON）として保存する。
 *
 * dashboard.html 等が `sessionStorage.getItem('mitas_org')` から
 * organization_id を読むため、ログイン直後／checkAuth で必ず一度
 * 呼んで保存しておく必要がある。
 *
 * 取得失敗・対応行なし（worker / neco_admin / alliance_admin など、
 * 組織に紐付かないロール）の場合は何もしない（null を返す）。
 *
 * 実装注意: PostgREST から `organization_members` を直接 SELECT すると、
 * 同テーブルの SELECT RLS が自己参照サブセレクト
 * （organization_id IN (SELECT organization_id FROM organization_members ...)）
 * を含むため、PostgREST 経由では Postgres が RLS を評価しきれず 500 を
 * 返すことがある。そのためサーバー側 Function `/api/v2/me/org` を経由し、
 * service_role で安全に取得した結果（本人の組織のみ）を受け取る。
 */
async function fetchAndStoreUserOrg() {
  try {
    const { data: sess } = await db.auth.getSession()
    const token = sess?.session?.access_token
    if (!token) return null

    const res = await fetch('/api/v2/me/org', {
      headers: { Authorization: `Bearer ${token}` },
    })
    if (!res.ok) return null
    const data = await res.json()
    if (!data || !data.organization || !data.organization.id) return null

    const org = { id: data.organization.id, name: data.organization.name || '' }
    try { sessionStorage.setItem('mitas_org', JSON.stringify(org)) } catch (_) { /* sessionStorage 不可は無視 */ }
    return org
  } catch (_) { return null }
}

/** ログイン：成功時は redirectTo（または role に応じた既定画面）へ遷移 */
async function hospitalLogin(email, password, redirectTo) {
  const { error } = await db.auth.signInWithPassword({ email, password })
  if (error) throw new Error(toJa(error.message))
  // 組織情報を sessionStorage に保存（facility_admin の勤務枠登録等で使用）
  // 失敗しても遷移自体は続行（dashboard 側でフォールバック取得する）
  await fetchAndStoreUserOrg()
  // redirectTo が明示されていればそれを優先（next= パラメータ等）
  // 未指定／無効な場合は user_roles.role から既定画面を選ぶ
  const roleHome = await defaultPathForRole()
  location.href = safeRedirectPath(redirectTo, roleHome)
}

/** セッション取得（dashboard.html の認証確認に使用） */
async function getSession() {
  const { data } = await db.auth.getSession()
  return data.session
}

/** ログアウト */
async function hospitalLogout() {
  await db.auth.signOut()
  location.href = '/login.html'
}

/**
 * パスワードリセットメールを送信する
 * forgot-password.html から呼び出す
 */
async function resetPassword(email) {
  const { error } = await db.auth.resetPasswordForEmail(email, {
    redirectTo: `${location.origin}/reset-password.html`,
  })
  if (error) throw new Error(toJa(error.message))
}

/**
 * セッション監視：他タブでのログアウト時に即座に login.html へ遷移
 * dashboard.html の initApp() 内から一度だけ呼び出す
 */
function watchSession() {
  // SIGNED_OUT イベントで即座にログイン画面へ
  db.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT' || (event !== 'INITIAL_SESSION' && !session)) {
      // 既に login.html にいる場合は無限ループを避ける
      if (!location.pathname.endsWith('/login.html')) {
        location.href = '/login.html'
      }
    }
  })
  // 定期的にセッション期限切れも確認（30分ごと）
  setInterval(async () => {
    const { data, error } = await db.auth.getSession()
    if (error || !data.session) {
      if (!location.pathname.endsWith('/login.html')) {
        location.href = '/login.html'
      }
    }
  }, 30 * 60 * 1000)
}

