# Launch checklist

Ordered by what blocks a launch, not by effort.

> **Verified against PostgreSQL 18.** All ten migrations apply to a fresh
> database, the server boots, and the flows below were exercised over HTTP:
> two-firm tenant isolation, the paywall, subscription activation by webhook,
> plan limits, chat privilege, and the client portal. Two bugs that unit tests
> could not have caught were found and fixed during that run — see
> "Found by running it" at the end.

---

## Blocking — do these before any real customer data exists

### 1. Rotate every secret that was in `backend/.env`

That file was committed to this repository containing a live `JWT_SECRET`
(`libra_law_super_secret_key_2024`) and a database password. It is untracked
now and `.gitignore` covers it, **but it is still in git history** — anyone with
repo access, past or present, can read it.

Anyone holding that key can mint a valid token for any user id and role,
including `super_admin`.

```sh
openssl rand -base64 48    # new JWT_SECRET
```

Rotate: `JWT_SECRET`, `DB_PASSWORD`, and any AWS/SMTP/Razorpay credential that
was ever in that file. Rotating `JWT_SECRET` invalidates every existing session
— that is the intent.

To scrub history entirely (rewrites commits; coordinate with anyone who has a
clone):

```sh
git filter-repo --path backend/.env --invert-paths
```

### 2. Seed a `super_admin` and verify no one else can become one

`/api/v1/admin/*` acts across every firm on the platform. It used to be guarded
by `RoleMiddleware("admin", "super_admin")`, and `admin` is the role every
lawyer receives at signup — so each customer was a platform administrator able
to list and deactivate other firms' users. It is now `super_admin` only, and
nothing in the signup path can create that role.

Create the first one manually — see `database/seeds/seed_roles.sql`.

### 3. Set the production environment

```sh
APP_ENV=production
DB_SSLMODE=require
JWT_SECRET=<the new one>
SMTP_HOST=... SMTP_USER=... SMTP_PASS=...
CORS_ORIGINS=https://app.yourdomain.com   # or leave empty for a mobile-only API
FORCE_HTTPS=true
```

`config.Validate()` refuses to start the process if any of the security-relevant
values are missing or still the committed defaults. That is deliberate — verify
it by starting with `APP_ENV=production` and a blank `JWT_SECRET`.

### 4. Apply the new migrations

`008` creates ten tables the code queries but that never existed (`firms`,
`plans`, `subscriptions`, `otps`, `consultations`, `chat_rooms`,
`chat_messages`, `case_challenges`, `student_progress`, `payment_orders`).
`009` adds the missing columns and the tenant foreign keys.

The server applies them on boot. **On an existing database, back up first** —
`009` adds CHECK constraints and unique indexes that will fail if current data
violates them (e.g. two users differing only by email case, or an invoice whose
`paid_amount` exceeds `total_amount`). Fix the data, then re-run.

### 5. Force a re-login

Token validation now pins the signing algorithm and requires an issuer claim,
so tokens minted by the old code are rejected. Combined with the secret
rotation, every user signs in again on first launch after deploy. Tell them, or
ship it alongside an app update.

---

## Before charging money

### 6. Configure Razorpay properly

Signature verification used to be skipped entirely when `RAZORPAY_KEY_SECRET`
was empty — the state a fresh deploy starts in — so any client could POST three
arbitrary strings and have an invoice marked paid. Those endpoints now return
503 rather than accept anything unverified. Set both keys or leave online
payment off.

### 7. Configure the webhook, then test a real payment end to end

Billing works now: `/subscription/checkout` opens a gateway order priced from
the `plans` table, the checkout sheet runs in-app, and `/webhooks/razorpay`
activates the subscription.

**Set `RAZORPAY_WEBHOOK_SECRET`.** Startup refuses to boot without it once the
gateway keys are present, because it is the authoritative activation path — a
user who kills the app right after paying never reaches the in-app callback, so
without the webhook you would charge the card and never grant the plan.

In the Razorpay dashboard → Settings → Webhooks:

```
URL:    https://your-api-host/api/v1/webhooks/razorpay
Events: payment.captured, payment.failed, order.paid
```

Then, in test mode, verify each of these by hand:

- [ ] Pay for a plan → `subscriptions.status` becomes `active`, period end is set
- [ ] Kill the app mid-checkout after paying → the webhook still activates it
- [ ] Replay the same webhook → no second billing period granted
- [ ] Renew early → the new period extends from the old expiry, not from today
- [ ] Let a trial lapse → writes return 402, **reads still work**
- [ ] Cancel → access continues to the end of the paid period

### 7a. Review the prices in the `plans` table

Migration 008 seeds free/solo/firm/scale at ₹0/499/1999/4999 monthly. Those are
placeholders — set your real prices before launch. They are data, not code, so
changing them does not need an app release.

---

## Before scale

### 8. Move documents out of Postgres

`documents.file_content` holds a base64 payload inline in the row, capped at
8 MB by `maxInlineDocumentBytes`. That works for a pilot and falls over on real
volume — every document read pulls the whole file through the connection pool.
Move to S3 with presigned URLs; the AWS variables are already in `.env.example`.

### 9. Replace the in-process rate limiter

`middleware.RateLimiter` counts per instance. Two replicas means double the
effective limit. Move the counter to Redis or push the limit to the load
balancer before running more than one instance.

### 10. Add the missing indexes for your access patterns

`009` adds the obvious ones (`cases(firm_id, status)`,
`hearings(firm_id, hearing_date)`, partial indexes on live documents and unread
notifications). Check `pg_stat_statements` after a few weeks of real traffic.

---

## Operational

- [ ] Point health checks at `/ready`, not `/health` — `/health` only proves the
      process is alive, `/ready` pings the database.
- [ ] Automated Postgres backups with a tested restore. This is client case
      data; a firm losing it is a professional-liability event for them.
- [ ] Error tracking (Sentry or equivalent) on both the API and the app.
- [ ] TLS everywhere. `FORCE_HTTPS=true` adds HSTS but does not terminate TLS.
- [ ] Log retention that excludes request bodies — they carry case detail.

## Legal / compliance

- [ ] Privacy policy and terms — required for Play Store and App Store listing.
- [ ] Data-retention and deletion policy. Client files are privileged;
      `AdminDeleteUser` deactivates rather than deletes precisely so the
      authorship trail on cases and invoices survives.
- [ ] Bar Council of India advertising rules constrain how a lawyer directory
      may be presented. Have the `find lawyer` screen reviewed before launch.
- [ ] Keep the eCourts attribution string that ships in every court-data
      response.

---

## Known gaps not addressed in this pass

- **No refresh tokens.** Sessions are a single 24h JWT with no revocation list;
  logging out clears the client only, and changing a password does not end other
  sessions. A stolen token is valid until it expires.
- **No GST invoice for subscriptions.** `subscription_payments` records what was
  charged, but nothing issues the firm a tax invoice for it. Indian B2B SaaS
  customers will ask.
- **Chat is polled, not pushed.** No WebSocket; the app re-fetches.
- **No push notifications.** The in-app notification table is populated, but
  nothing reaches a closed app.
- **`invoice_items` is never written.** Invoices carry a single total; the
  line-item table exists but nothing populates it.
- **No dunning emails.** A firm entering `past_due` gets an in-app notification
  but no email, so a lapsed card is easy to miss until access stops.

---

## Found by running it

Two bugs survived a clean build, `go vet`, and a passing unit-test suite. Both
only appeared once the server was talking to a real database over real HTTP.
Recording them because they are the shape of thing to watch for.

### 1. Service clients read config before it was loaded

The gateway, mailer and court-data clients were package-level variables:

```go
var razorpay = services.NewRazorpay()
```

Go runs package-level initialisers **before** `main()`, so each one read its
configuration before `main()` had called `config.LoadConfig()` to populate the
environment from `.env`. Every client captured empty strings and then reported
itself permanently unconfigured — payments returned 503, the webhook rejected
every delivery as "secret unset", court lookups fell through to the placeholder
card, and outbound email silently no-oped, on a deployment where all of it was
configured correctly.

Fixed with `sync.OnceValue`, which defers construction to first use. See
`controllers/clients.go`.

The tests could not have caught this: they construct clients directly, after
`t.Setenv`.

### 2. Clients could read the firm's entire client list

`provisionPortalUser` attaches a client's login to the lawyer's firm, which is
how the portal finds that client's matters. The workspace routes gated on "does
this token carry a firm id" — which a client portal account satisfies.

A signed-in client could therefore call `GET /clients`, `/staff`, `/cases`,
`/invoices`, `/reports/revenue` and `/firm/bank-details`, reading the names,
email addresses and phone numbers of **every other client of that firm**, plus
its staff directory and revenue.

For a legal practice that is a privilege breach: one client must never learn who
else the firm acts for.

Fixed by `middleware.RequireFirmStaff()`, applied to the workspace and
firm-admin route groups. Pinned by `middleware/workspace_test.go`. Clients reach
their own records through `/portal/*`, which scopes on their verified email.

**The lesson for the next change:** "has a tenant id" is not the same question
as "belongs to this tenant's staff". Any new firm-scoped route needs both.
