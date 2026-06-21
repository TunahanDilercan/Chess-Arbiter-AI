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
