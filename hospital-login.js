// Supabase 設定（Netlify 環境変数から取得、またはここに直接記入）
const SUPABASE_URL      = window.__SUPABASE_URL__      || 'https://YOUR_PROJECT.supabase.co'
const SUPABASE_ANON_KEY = window.__SUPABASE_ANON_KEY__ || 'YOUR_SUPABASE_ANON_KEY'

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

/** ログイン：成功時は dashboard.html へ遷移 */
async function hospitalLogin(email, password) {
  const { error } = await db.auth.signInWithPassword({ email, password })
  if (error) throw new Error(toJa(error.message))
  location.href = '/dashboard.html'
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
