# syntax=docker/dockerfile:1.7
#
# BJJ Companion proxy — FastAPI app deployed to Fly.io.
# Serves /tournaments, /bracket, /schedule endpoints to the iOS app.
#
# Keep this image small: the proxy is a thin wrapper over bjjcompsystem.com
# scrapers, with a short-TTL in-process cache. No background workers, no DB.

FROM python:3.12-slim

# Prevent Python from buffering stdout/stderr — Fly's log tail works better
# when FastAPI writes land immediately.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# lxml needs libxml2/libxslt at runtime; everything else is pure Python.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        libxml2 \
        libxslt1.1 \
 && rm -rf /var/lib/apt/lists/*

# Run as a non-root user (fly best practice, and defensive in depth for a
# service that fetches third-party HTML).
RUN useradd --create-home --uid 1000 app
WORKDIR /app

# Install Python deps first so Docker can cache this layer across code changes.
COPY requirements.txt ./
RUN pip install -r requirements.txt

# Copy only the Python modules the proxy actually needs. Leaving out
# scrape.py / backfill_athletes.py / geocode_cache.json / fixtures/ keeps
# the image lean and the attack surface small.
COPY proxy.py compsystem_client.py models.py ./

USER app

# Fly convention: listen on 8080 internally. fly.toml maps public 443 → 8080.
EXPOSE 8080

# One worker is plenty — the cache is in-process and traffic is low.
# --proxy-headers lets uvicorn trust Fly's X-Forwarded-* headers for logging.
CMD ["uvicorn", "proxy:app", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--proxy-headers", \
     "--forwarded-allow-ips", "*"]
