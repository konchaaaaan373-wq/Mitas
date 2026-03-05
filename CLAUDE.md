# Neco – Claude Code Project Guide

## Project Overview

**Neco** (necofindjob.com) is a Japanese medical job-matching platform connecting doctors and nurses with home-visit medical facilities (在宅医療). The tagline is「あなたの一生物のバイトを、一緒に探す」("Finding your lifelong part-time job, together").

The site is a **static HTML/CSS/JS website** hosted on **Netlify**, with serverless backend logic provided by Netlify Functions (Node.js).

---

## Repository Structure

```
/
├── index.html              # Landing page (top page)
├── nurse.html              # Nurse-focused landing page
├── for-medical.html        # Medical facility landing page
├── company.html            # Company/about page
├── login.html              # Unified login for doctors & facilities
├── dashboard.html          # Doctor dashboard (auth-protected)
├── medical-dashboard.html  # Medical facility dashboard (auth-protected)
├── guide.html              # How-to / usage guide
├── faq.html                # FAQ page
├── license.html            # License page
├── terms.html              # Terms of service
├── privacy-policy.html     # Privacy policy
├── line-consent.html       # LINE data-sharing consent page
├── 404.html                # Custom 404 page
├── sitemap.xml
├── robots.txt
├── netlify.toml            # Netlify build config, headers, redirects
├── netlify/
│   └── functions/
│       ├── auth.js         # POST /api/auth/login, GET /api/auth/me, POST /api/auth/verify
│       └── line-webhook.js # POST /api/line/webhook → forwards events to Google Apps Script
└── docs/
    └── line-webhook-setup.md
```

---

## Tech Stack

- **Frontend**: Vanilla HTML, CSS, JavaScript (no build step)
- **Hosting**: Netlify (static site)
- **Functions**: Netlify Functions (Node.js, bundled with esbuild)
- **Auth**: Custom HMAC-SHA256 signed tokens via `crypto` (Node built-in)
- **LINE integration**: Webhook receiver → Google Apps Script → Google Sheets

---

## API Routes

| Method | Path | Function | Description |
|--------|------|----------|-------------|
| POST | `/api/auth/login` | `auth.js` | Validate credentials, return signed token |
| GET | `/api/auth/me` | `auth.js` | Verify Bearer token, return user profile |
| POST | `/api/auth/verify` | `auth.js` | Verify token string, return payload |
| POST | `/api/line/webhook` | `line-webhook.js` | Receive LINE events, forward to GAS |

---

## Authentication

- **Demo credentials** are hardcoded in `netlify/functions/auth.js` (DEMO_USERS array)
- Doctor login: `dr-demo@neco.jp` / `demo1234`
- Facility login: `facility-demo@neco.jp` / `demo1234`
- Tokens are HMAC-SHA256 signed; secret set via `SESSION_SECRET` environment variable
- Auth checks on protected pages (`dashboard.html`, `medical-dashboard.html`) are client-side JS
- **Production TODO**: Replace hardcoded users with a real DB (e.g. Supabase) and use bcrypt

---

## Environment Variables (Netlify)

| Variable | Purpose |
|----------|---------|
| `SESSION_SECRET` | Secret key for signing auth tokens |
| `LINE_CHANNEL_SECRET` | LINE Messaging API channel secret |
| `GAS_WEBHOOK_URL` | Google Apps Script Web App URL |
| `GAS_WEBHOOK_SECRET` | Shared secret between Netlify and GAS |

---

## Security Headers

Configured in `netlify.toml`. Key headers applied to all routes:

- `Content-Security-Policy` – restricts scripts, styles, fonts, images, connect-src
- `Strict-Transport-Security` – HSTS with preload
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`

When adding third-party scripts or API endpoints, update the CSP in `netlify.toml` accordingly.

---

## Redirects

- HTTP → HTTPS enforced for `necofindjob.com` and `www.necofindjob.com`
- Old page (`/neco-medical-jobs`) → `/` (301)
- `/api/auth/*` → `/.netlify/functions/auth/:splat`
- `/api/line/webhook` → `/.netlify/functions/line-webhook`

---

## Development Notes

- **No build step**: Edit HTML/CSS/JS files directly; Netlify deploys straight from the repo root.
- **No package.json** at the repo root; functions use only Node built-ins (`crypto`) so no `npm install` is needed.
- **Language**: UI and content are in **Japanese**. Maintain Japanese text when editing copy.
- **No test suite** is currently set up. Manual testing in a browser is the current workflow.
- To test Netlify Functions locally, use `netlify dev` (requires Netlify CLI).

---

## Workflow Rules

The owner is a non-engineer. Every task must follow this flow without exception:

1. **Develop** all changes on a dedicated `claude/` branch
2. **Commit** with a clear message describing what changed and why
3. **Push** the branch to origin
4. **Create a Pull Request** via `gh pr create` and return the PR URL to the user
5. **End every session** by posting the PR link so the user can review and merge

Never leave work uncommitted or un-PR'd. The user's only action is clicking "Merge".

---

## Common Tasks

### Add a new page
1. Create `newpage.html` at the repo root.
2. Add a link/redirect in `netlify.toml` if needed.
3. Follow the existing HTML structure (shared `<head>` meta tags, header nav, footer).

### Update the CSP
Edit the `Content-Security-Policy` value in `netlify.toml` under `[[headers]] for = "/*"`.

### Add a new Netlify Function
1. Create `netlify/functions/<name>.js`.
2. Add a redirect in `netlify.toml`: `from = "/api/<path>" to = "/.netlify/functions/<name>"`.
3. Export a `handler` async function: `exports.handler = async (event, context) => { ... }`.
