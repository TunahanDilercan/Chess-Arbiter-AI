# Deployment — Internet-Facing Server

Production stack: nginx (TLS) → FastAPI backend → PostgreSQL + Redis + Celery
worker, all via `docker-compose.prod.yml`.

## 1. Prerequisites

- A Linux VPS (2+ vCPU, 4 GB RAM is plenty — OCR runs via the Claude API, no GPU needed)
- A domain name pointing at the server (A record)
- Docker + Docker Compose plugin
- An Anthropic API key (https://platform.claude.com → API Keys)

## 2. Secrets

Create `.env` next to `docker-compose.prod.yml` (never commit it):

```bash
POSTGRES_PASSWORD=<long random password>      # e.g. openssl rand -hex 24
ANTHROPIC_API_KEY=sk-ant-...
CORS_ORIGINS=["https://app.example.com"]      # web review tool origin(s) — never "*"
SECRET_KEY=<long random value>                # python -c "import secrets;print(secrets.token_urlsafe(48))"
DEBUG=false                                   # disables /docs, /redoc, /openapi.json
ENABLE_HSTS=true                              # serving over HTTPS
TRUST_PROXY_HEADERS=true                      # behind the nginx proxy (real client IPs)
```

## 2a. Security checklist (production)

The backend logs loud warnings at startup (`warn_insecure_config`) if any of
these are wrong — check the logs after the first deploy.

- [ ] `DEBUG=false` — turns off interactive API docs and verbose errors.
- [ ] `CORS_ORIGINS` set to the explicit web origin(s), not `"*"`.
- [ ] `SECRET_KEY` is a strong random value (signs short-lived `/storage` URLs).
- [ ] `POSTGRES_PASSWORD` is not the default `arbiter:arbiter`.
- [ ] TLS terminates at nginx; `ENABLE_HSTS=true`, `TRUST_PROXY_HEADERS=true`.
- [ ] Stored files are only reachable via signed `/storage` URLs (no public mount).
- [ ] Game access/correction is scoped to the owning session (IDOR-safe).
- [ ] Mobile release builds use the HTTPS API URL (cleartext is disabled in
      release; only debug builds permit plain HTTP for LAN development).
- [ ] Run dependency audits before shipping: `cd web && npm audit`,
      and `pip-audit` (or `pip list --outdated`) for the backend. The residual
      Next.js advisories require features this app does not use (next/image,
      WebSocket upgrades, middleware/i18n); upgrade to Next 15+/16 only with a
      planned migration + retest.

## 3. TLS certificates

```bash
sudo apt install certbot
sudo certbot certonly --standalone -d api.example.com
mkdir -p deploy/certs
cp /etc/letsencrypt/live/api.example.com/fullchain.pem deploy/certs/
cp /etc/letsencrypt/live/api.example.com/privkey.pem  deploy/certs/
```

Renewals: re-copy after `certbot renew` (a deploy hook works well), then
`docker compose -f docker-compose.prod.yml restart nginx`.

## 4. Start

```bash
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml logs -f backend   # watch startup
curl https://api.example.com/health                          # → {"status":"ok"}
```

The `migrate` service runs `alembic upgrade head` once on each deploy;
`AUTO_CREATE_TABLES` stays `false` in production.
The backend and worker wait for that service to finish successfully. Production
also sets `ENVIRONMENT=production`; startup rejects a missing/default/short
`SECRET_KEY` instead of signing private image URLs with the public development key.

### Existing database upgrade

Back up the database and storage, and stop backend/worker writers first. This
release requires migration `b2c3d4e5f6a7`: it adds missing crop coordinates,
review reasons and OCR notation locale, and widens session IDs to 64 characters.
Existing games, OCR rows and human review history are retained.

From `backend/`, with the intended database configured, run:

```bash
alembic current
alembic upgrade head
```

If a development database was created by `AUTO_CREATE_TABLES` and has no Alembic
version, do not run the initial migration over existing tables. After backing
up and verifying its tables/columns match `001_initial_schema.py` (additional
crop columns are supported), adopt that baseline, then upgrade:

```bash
alembic stamp a1b2c3d4e5f6
alembic upgrade head
```

Never stamp an unknown or partial schema. `create_all` does not update existing
columns. Restart both API and worker only after the upgrade succeeds. Rebuild
the worker image to install the new PDF dependency.

### Windows local startup

`start-arbiter.ps1` includes `docker-compose.override.yml`, builds the backend
image, and waits for the `migrate` service before starting API/worker. Both use
the same image; PostgreSQL and Redis host ports bind to loopback. The launcher
reuses installed packages from the previous local image and installs any missing
requirements. A clean build uses CPU-only Torch and headless OpenCV.
The launcher rebuilds the web UI when its source files are newer than BUILD_ID.
Build, migration and health-check failures stop startup instead of reporting success.
Use `-Rebuild` to rebuild backend from a clean Python base and force a web
rebuild, `-LocalOnly` to skip ngrok, and `-NoWait`
to skip the final interactive prompt. Legacy databases still require the verified
baseline adoption described above before their first migration.

### Input and model notes

- PDF input currently supports one unencrypted page per upload, rendered at a
  bounded resolution. Multi-page PDFs are rejected explicitly, not truncated.
- Local Compose reads `OCR_BACKEND` from `backend/.env`; it no longer overrides
  that choice with a root-level default. Production uses its separate root env.
- Newly trained TrOCR checkpoints declare `arbiter_output_locale="en"` in their
  model configuration. For an older checkpoint trained on English SAN, add that
  metadata before using Turkish scoresheets; stock handwriting models continue
  to use the scoresheet locale.
- Claude logs token counts and elapsed seconds. No model, confidence threshold
  or paid-request policy changed. Measure accuracy against labeled sheets before
  claiming a percentage or switching providers for cost.

## 5. Security model (what is already handled)

| Layer | Control |
|---|---|
| Transport | TLS 1.2/1.3 at nginx; HSTS emitted by the app (`ENABLE_HSTS=true`) |
| Request size | `client_max_body_size 25m` at nginx + `MAX_UPLOAD_SIZE_MB` in the app |
| Rate limiting | Per-IP, Redis-backed: 120 req/min general, 10 uploads/min (`RATE_LIMIT_*`) |
| Upload content | Magic-byte sniffing — declared Content-Type is never trusted |
| Input validation | session_id charset/length allowlist, locale allowlist, Pydantic schemas everywhere |
| Headers | `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy` |
| Containers | Backend/worker run as non-root (`USER arbiter`); DB/Redis have no public ports |
| Secrets | Via environment / `.env` only; startup logs warn about insecure prod config |
| SQL | SQLAlchemy parameterized queries only — no string-built SQL anywhere |

## 6. Operational notes

- **Claude OCR cost**: `claude-sonnet-4-6` is cheaper than Opus for this OCR path;
  exact cost depends on image size and output length.
  Set `OCR_FALLBACK_TO_TROCR=true` (default) so jobs degrade to local TrOCR if
  the API is unreachable. CPU-only TrOCR is slow (~1–3 s/move) but works.
- **Scaling OCR throughput**: raise the worker `--concurrency`, or run more
  worker containers. The bottleneck is the Claude API call (~10–30 s/sheet).
- **Backups**: `pg_dump` the `postgres_data` volume; uploaded images live in
  the `arbiter_storage` volume (or switch `STORAGE_BACKEND=s3`).
- **Monitoring**: structured JSON logs on stdout — ship with Loki/CloudWatch.
  `GET /health` is the liveness probe.
- **Key rotation**: rotate `ANTHROPIC_API_KEY` in `.env` and
  `docker compose ... up -d backend worker` (no downtime for nginx).
