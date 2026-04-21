# Deploying the proxy to Fly.io

One-time setup, then `fly deploy` on every change.

## Prerequisites

- A Fly.io account: https://fly.io/app/sign-up
  - A credit/debit card is required on signup (fraud prevention) — free tier
    usage will not charge it. Use a personal card now; switch to the LLC card
    once it's issued.
- Docker is **not** required locally — Fly builds the image on their remote
  builders by default.

## 1. Install flyctl

```bash
brew install flyctl
```

Verify:

```bash
flyctl version
```

## 2. Sign in

```bash
fly auth login
```

Opens a browser to complete login.

## 3. Launch the app (first deploy only)

From the `backend/` directory:

```bash
cd "/Users/adrienibarra/Desktop/Coding Projects/BJJ/backend"
fly launch --no-deploy
```

Answer the prompts:

- **App name** — pick a globally-unique name. Suggestion: `bjj-companion-proxy`
  (or add a suffix if taken). Your public URL will be
  `https://<app-name>.fly.dev`.
- **Region** — pick `dfw` (Dallas) or the closest airport code.
- **Would you like to tweak these settings?** — `N` (the `fly.toml` in this
  repo already has the right values; Fly will overwrite the app name + region
  but keep everything else).
- **PostgreSQL / Redis / Tigris?** — `N` to each. The proxy is stateless.

Fly writes your chosen `app` name back into `fly.toml`. Commit that change.

## 4. Deploy

```bash
fly deploy
```

First build takes ~2 minutes (builds the image on Fly's remote builder,
pushes, starts a machine). Subsequent deploys are faster.

When it finishes you'll see:

```
Visit your newly deployed app at https://bjj-companion-proxy.fly.dev/
```

## 5. Verify

```bash
# Health check
curl https://<your-app>.fly.dev/health
# → {"status":"ok"}

# Tournaments endpoint (cached 24h)
curl https://<your-app>.fly.dev/tournaments | head -c 500
```

## 6. Point the iOS app at it

Edit `ios/BJJCompanion/Data/Config.swift` — set the release URL to your
`.fly.dev` domain. The `#if DEBUG` block keeps local dev pointing at
`localhost:8000`.

## Everyday operations

| Task | Command |
|------|---------|
| Deploy latest code | `fly deploy` |
| Tail logs | `fly logs` |
| Open dashboard | `fly dashboard` |
| List machines | `fly machine list` |
| SSH into running container | `fly ssh console` |
| Restart | `fly machine restart` |
| Check status | `fly status` |

## Scaling

The app auto-scales to zero when idle (`auto_stop_machines = "stop"` in
`fly.toml`). Cold start is ~1 second. If traffic warrants always-on:

```bash
fly scale count 1 --region dfw
```

To upgrade the machine size (if memory pressure):

```bash
fly scale memory 512
```

## Costs

With `shared-cpu-1x` + 256MB + scale-to-zero, this deployment fits well
inside Fly's free allowance. Watch `fly dashboard` for actual billing.

## Custom domain (optional — do this after LLC/Apple Dev)

```bash
fly certs add api.your-domain.com
```

Fly gives you the DNS records to add at your domain registrar. Once certs
are issued (~30s), you can swap the iOS release URL to the custom domain.
