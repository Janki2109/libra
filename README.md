# Libra — Law Practice Management

Case, client, hearing, billing and document management for Indian law firms,
with a client portal, in-app chat, court-record lookup and a law-student
learning module.

- **Backend** — Go 1.26 + Gin + PostgreSQL (`backend/`)
- **Frontend** — Flutter (Android, iOS, web) (`frontend/`)

---

## Running it

### 1. Configure

```sh
cp .env.example backend/.env
```

Then fill in at minimum:

```sh
# A fresh secret — the server refuses to start in production without one.
openssl rand -base64 48
```

`JWT_SECRET`, `DB_PASSWORD` and the `SMTP_*` block are required. Razorpay and
eCourts are optional; their endpoints return 503 until configured.

### 2. Start

With Docker:

```sh
docker compose -f docker/docker-compose.yml up --build
```

Or locally, against your own Postgres:

```sh
cd backend && go run .
```

The server applies any unapplied migration on startup and records what it ran
in `schema_migrations`. Set `RUN_MIGRATIONS=false` to handle that in a separate
deploy step.

Then seed the roles once:

```sh
psql "$DATABASE_URL" -f database/seeds/seed_roles.sql
```

### 3. Run the app

The API URL is a build-time define, not a source constant:

```sh
cd frontend
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1   # Android emulator
flutter run --dart-define=API_BASE_URL=http://localhost:8080/api/v1  # iOS sim / desktop
```

Release build:

```sh
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1
```

---

## Checks

```sh
cd backend  && go build ./... && go vet ./... && go test ./...
cd frontend && flutter analyze && flutter test
```

---

## Layout

```
backend/
  main.go            server lifecycle: config validation, migrations, graceful shutdown
  config/            env loading, validation, database pool
  routes/            route table, rate limits, middleware wiring
  middleware/        auth, roles, CORS, rate limiting, security headers, body limit
  controllers/       HTTP handlers
  services/          outbound integrations (SMTP, eCourts)
  utils/             JWT, password hashing, OTP, request-context helpers
  migrations/        embedded SQL schema, applied on startup
frontend/lib/
  core/              constants, HTTP client, storage, theme, router
  features/          one folder per feature: screens, providers, models
docker/              Dockerfiles, compose stack, nginx config
docs/                court-data.md (free court data), api.md, security.md
database/seeds/      role seeding
```

---

## Before you launch

Read [`docs/launch-checklist.md`](docs/launch-checklist.md). The short version:

1. **Rotate every secret.** `backend/.env` was committed to this repository with
   a live JWT signing key in it. It is untracked now, but it remains in git
   history — treat the old key, database password and any other value that was
   in it as public.
2. Seed a `super_admin` account (see `database/seeds/seed_roles.sql`). The
   `/api/v1/admin/*` routes are restricted to that role and nothing in the
   signup flow can create one.
3. Set `APP_ENV=production`, `DB_SSLMODE=require`, and a real `CORS_ORIGINS` if
   a browser client exists.
4. Configure SMTP. Without it, OTP login and client-portal invitations do not
   work.

---

## Court data

Case status, cause lists and orders come from India's eCourts platform. It is
free, but there is no open public API — see
[`docs/court-data.md`](docs/court-data.md) for the three lawful ways to get
access and what each costs.
