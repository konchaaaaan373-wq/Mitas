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

/** ログイン：成功時は redirectTo（または role に応じた既定画面）へ遷移 */
async function hospitalLogin(email, password, redirectTo) {
  const { error } = await db.auth.signInWithPassword({ email, password })
  if (error) throw new Error(toJa(error.message))
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

