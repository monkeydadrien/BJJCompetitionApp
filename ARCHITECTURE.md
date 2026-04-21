# BJJ Companion — Architecture

A single-developer iOS app backed by a scraping pipeline and a thin on-demand
proxy. All infrastructure is free-tier. Nothing stateful runs in production
except the ephemeral Fly proxy — events and athletes are served as static JSON
refreshed daily by CI.

---

## 1. Runtime data flow

How a user launching the app gets fresh data on their screen.

```mermaid
flowchart LR
    user(["👤 User<br/>iOS 26 device"])

    subgraph phone["📱 iPhone"]
        app["BJJCompanion app<br/>(SwiftUI, iOS 26.2)"]
        cache["URLCache +<br/>UserDefaults"]
    end

    subgraph cdn["GitHub Pages (CDN)"]
        events[/"events.json<br/>~700 events"/]
        athletes[/"athletes.json<br/>athlete registry"/]
    end

    subgraph fly["Fly.io — DFW region"]
        proxy["bjj-companion-proxy<br/>FastAPI + slowapi<br/>shared-cpu-1x · 256MB<br/>auto-stop when idle"]
        ttl["in-process TTL cache<br/>tournaments: 24h<br/>brackets: 60s<br/>schedule: 5m"]
        proxy --- ttl
    end

    ibjjf[("bjjcompsystem.com<br/>IBJJF tournament system")]

    sentry(["sentry.io<br/>crash + perf"])

    user --> app
    app -->|"GET events.json<br/>(cacheable, ETag'd)"| events
    app -->|"GET athletes.json"| athletes
    app -->|"GET /bracket<br/>GET /tournaments<br/>GET /schedule"| proxy
    proxy -->|"scrape on demand"| ibjjf
    app -.->|"crash + trace events<br/>release builds only"| sentry
    app <--> cache
```

**Key design choices:**

- **Static JSON for bulk data.** Events and athletes change daily at most, so
  serving them as flat files via GitHub Pages is free, infinitely scalable, and
  has zero operational burden. No database needed.
- **Proxy only for the live path.** Brackets update minute-by-minute during
  tournaments, so they can't be pre-baked. Fly proxy hits IBJJF on demand with
  short TTL caching to protect the upstream.
- **Scale-to-zero.** Fly machine stops when idle. UptimeRobot's 5-min health
  ping keeps one warm during active hours; cold starts are ~2s otherwise.

---

## 2. Build & deploy pipeline

What happens when code changes land on `main`.

```mermaid
flowchart TB
    dev(["💻 Local dev<br/>macOS + Xcode 26"])

    subgraph git["GitHub: monkeydadrien/BJJCompetitionApp"]
        main[["main branch"]]
        actions{{"GitHub Actions"}}
        pages["GitHub Pages<br/>(static hosting)"]
    end

    subgraph cron["Scheduled cron: 11:00 UTC daily"]
        scraper["scrape.py<br/>→ events.json<br/>→ geocode_cache.json"]
    end

    subgraph deploy["Manual deploy"]
        flyctl["fly deploy"]
        registry[("registry.fly.io")]
        flymachine["Fly machine<br/>(rolling update)"]
    end

    hc(["hc-ping.com<br/>dead-man switch"])

    dev -->|"git push"| main
    main -->|"triggers"| actions
    actions -->|"runs daily"| scraper
    scraper -->|"commit events.json<br/>[skip ci]"| main
    main -->|"serves"| pages
    actions -.->|"start / success / fail"| hc

    dev -->|"cd backend<br/>fly deploy"| flyctl
    flyctl -->|"depot build<br/>push image"| registry
    registry --> flymachine
```

**Two separate deploy tracks:**

| Track | Trigger | Cadence | Output |
|---|---|---|---|
| **iOS app** | manual Xcode archive → TestFlight/App Store | per release | `.ipa` to Apple |
| **Data refresh** | GitHub Actions cron | daily 11:00 UTC | `events.json` committed + served via Pages |
| **Proxy** | `fly deploy` from local | on demand | new container on Fly DFW |

The scraper committing to `main` uses `[skip ci]` to avoid infinite loops.

---

## 3. Dev loop

What running the app locally looks like.

```mermaid
flowchart LR
    subgraph mac["💻 macOS dev machine"]
        xcode["Xcode<br/>(DEBUG build)"]
        sim["iOS Simulator"]
        uvicorn["uvicorn proxy:app<br/>--port 8000"]
    end

    cdn[/"GitHub Pages<br/>events.json + athletes.json"/]
    ibjjf[("bjjcompsystem.com")]

    xcode -->|"build & run"| sim
    sim -->|"Config.proxyBaseURL<br/>#if DEBUG → localhost:8000"| uvicorn
    sim -->|"fetch static JSON"| cdn
    uvicorn --> ibjjf
```

- `Config.swift` swaps `proxyBaseURL` between `localhost:8000` (DEBUG) and
  `bjj-companion-proxy.fly.dev` (release). No runtime env vars needed.
- Sentry is `#if canImport(Sentry) && !DEBUG` — debug builds never send events,
  so noisy dev sessions don't pollute the error feed.

---

## 4. Observability

```mermaid
flowchart LR
    subgraph prod["Production surfaces"]
        app["iOS app<br/>(release builds)"]
        proxy["Fly proxy<br/>/health endpoint"]
        scraper["GitHub Actions<br/>scraper cron"]
    end

    subgraph monitors["Free-tier monitors"]
        sentry(["Sentry<br/>crash + perf"])
        uptime(["UptimeRobot<br/>5-min ping"])
        hc(["Healthchecks.io<br/>dead-man switch"])
    end

    email(["📧 developer@<br/>pinnacleapp.dev"])

    app -->|"errors · traces · breadcrumbs"| sentry
    proxy -->|"HTTP 200 heartbeat"| uptime
    scraper -->|"start / success / fail pings"| hc

    sentry -->|"alert on new issues"| email
    uptime -->|"alert on 5xx / down"| email
    hc -->|"alert on missed cron"| email
```

**Coverage map:**

| What breaks | Who tells you |
|---|---|
| iOS app crashes / handled errors | Sentry |
| Proxy down or unhealthy | UptimeRobot |
| Daily scrape stops running or fails | Healthchecks.io |
| IBJJF changes HTML structure | Healthchecks (fail ping from scraper exception) |
| Fly machine OOM / deploy failure | Fly dashboard + UptimeRobot |

All three monitors email `developer@pinnacleapp.dev`. No SMS or paging.

---

## 5. Component inventory

```mermaid
flowchart TB
    subgraph client["Client"]
        ios["iOS app<br/>─────<br/>SwiftUI · iOS 26.2<br/>Observation framework<br/>URLSession · URLCache"]
    end

    subgraph backend_repo["backend/"]
        scrape_py["scrape.py<br/>─────<br/>Daily IBJJF scraper<br/>BeautifulSoup + lxml"]
        proxy_py["proxy.py<br/>─────<br/>FastAPI + slowapi<br/>on-demand brackets"]
        client_py["compsystem_client.py<br/>─────<br/>httpx + tenacity retries<br/>shared scrape primitives"]
        geocode_py["geocode.py<br/>─────<br/>Nominatim forward geocode<br/>JSON-file cache"]
    end

    subgraph infra["Infrastructure"]
        ghpages[/"GitHub Pages<br/>─────<br/>events.json<br/>athletes.json"/]
        flyio["Fly.io<br/>─────<br/>Docker image<br/>1 shared-cpu-1x machine<br/>fly.toml · Dockerfile"]
        ghactions{{"GitHub Actions<br/>─────<br/>scrape.yml · cron daily<br/>HC_PING_URL secret"}}
    end

    subgraph identity["Business identity"]
        cf["Cloudflare Registrar<br/>pinnacleapp.dev"]
        gws["Google Workspace<br/>developer@pinnacleapp.dev"]
        apple["Apple Developer<br/>(pending LLC/D-U-N-S)"]
        llc["Pinnacle AppDev LLC<br/>(Texas, filed 2026-04-21)"]
    end

    scrape_py --> ghactions
    ghactions --> ghpages
    proxy_py --> flyio
    client_py -.->|shared code| scrape_py
    client_py -.->|shared code| proxy_py
    scrape_py --> geocode_py

    ios -->|fetch| ghpages
    ios -->|fetch| flyio

    cf -.-> gws
    llc -.-> apple
    gws -.-> apple
```

---

## 6. Costs

Everything in production runs on free tiers. Per month:

| Service | Free tier | Current usage | Estimated cap |
|---|---|---|---|
| GitHub Pages | unlimited bandwidth for public repo | ~700 events JSON | ≤1 GB/mo |
| GitHub Actions | 2,000 min/mo private (unlimited public) | ~2 min/day = 60 min/mo | ≤3% of cap |
| Fly.io | $5/mo credit, scale-to-zero | 1 machine · ~0 active hrs/day | $0 realized |
| Sentry | 5K errors + 10K perf events | 0 (new) | well inside |
| UptimeRobot | 50 monitors @ 5-min | 1 | 2% of cap |
| Healthchecks.io | 20 checks free | 1 | 5% of cap |
| Cloudflare Registrar | domain at wholesale cost | `pinnacleapp.dev` | ~$12/yr |
| Google Workspace | paid ($6/user/mo) | 1 user | $72/yr |

**Realized cost today:** ~$84/yr (Workspace + domain). Apple Developer Program
adds $99/yr once Org enrollment completes.

---

## 7. Stack summary

**iOS:** Swift · SwiftUI · iOS 26.2 minimum · Xcode 26 · Observation framework · URLSession · Sentry SDK

**Backend (Python 3.12):** FastAPI · uvicorn · httpx · BeautifulSoup4 · lxml · pydantic · tenacity · slowapi · Nominatim

**Infrastructure:** GitHub (repo + Pages + Actions) · Fly.io (Docker container) · Cloudflare Registrar · Google Workspace

**Observability:** Sentry · UptimeRobot · Healthchecks.io

**Business:** Pinnacle AppDev LLC (Texas) · `pinnacleapp.dev` · bundle ID `dev.pinnacleapp.bjjcompanion`
