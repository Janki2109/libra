# API reference

Base URL: `{host}/api/v1`

## Conventions

Every response uses the same envelope:

```json
{ "success": true,  "message": "Cases fetched", "data": [ ... ] }
{ "success": false, "message": "Not found", "error": "outside caller's firm" }
```

`error` carries internal detail and is **omitted in production** — it is logged
server-side instead.

Authenticated routes take `Authorization: Bearer <token>`.

### Pagination

List endpoints are paginated. They previously returned the firm's entire table
on every request, so the app got slower as the firm grew.

`?page=1&limit=25` — `limit` defaults to 25 and is clamped to 100. `data` stays
a plain array (unchanged shape), and paging info arrives alongside it:

```json
{
  "success": true,
  "data": [ ... ],
  "meta": { "page": 1, "limit": 25, "count": 25, "has_more": true }
}
```

Filters are applied in SQL rather than on the device:
`/cases?status=active&q=sharma`, `/clients?q=ramesh`,
`/hearings?status=scheduled`, `/invoices?status=unpaid`.

### Compression

Send `Accept-Encoding: gzip`. Responses over 1 KB are compressed — list
payloads are mostly repeated keys and UUIDs and shrink by roughly 90%.

### Tenancy

Every record belongs to a firm. A request only ever sees rows whose `firm_id`
matches the caller's token claim; there is no way to widen that from the client.
Asking for another firm's record by id returns **404**, not 403 — a 403 would
confirm the record exists.

Clients and law students carry no firm. Firm-scoped endpoints return 403 for
them; they use `/portal/*` and `/student/*` instead.

### Status codes

| Code | Meaning |
|---|---|
| 400 | Malformed request, or an id that is not a UUID |
| 401 | Missing, invalid or expired token — the app clears the session |
| 403 | Authenticated but not permitted (wrong role, or no firm) |
| 404 | Not found, or outside the caller's firm |
| 409 | Conflict — duplicate email, already-reviewed payment, replayed txn |
| 413 | Body over 12 MB |
| 429 | Rate limited; see `Retry-After` (whole seconds) |
| 503 | An optional integration (payments, court data) is not configured |

### Rate limits

Applied per client IP, per instance.

| Endpoints | Limit |
|---|---|
| `/auth/login`, `/portal/login` | 10 / minute |
| `/auth/send-otp`, `/auth/verify-otp` | 5 / 15 minutes |
| `/auth/register`, `/auth/client/register`, `/auth/student/register` | 5 / hour |

---

## Health

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | Liveness. The process is up. |
| GET | `/ready` | Readiness — pings the database. Point load balancers here. |

## Auth — public

| Method | Path | Notes |
|---|---|---|
| POST | `/auth/login` | Lawyer / staff / student login |
| POST | `/auth/register` | Creates a firm, a trial subscription and its admin user, in one transaction |
| POST | `/auth/client/register` | Self-registering client; no firm until a lawyer adds them |
| POST | `/auth/student/register` | Law student |
| POST | `/auth/send-otp` | Emails a code. Answers identically whether or not the address exists. **The code is never in the response body.** |
| POST | `/auth/verify-otp` | Single-use, 10 minutes, 5 attempts |
| POST | `/auth/logout` | |
| GET | `/auth/plans` | Public plan list |
| POST | `/portal/login` | Client portal only — rejects non-client accounts |

## Auth — authenticated

| Method | Path |
|---|---|
| GET | `/auth/me` |
| GET | `/dashboard` |
| GET | `/subscription` |
| POST | `/users/change-password` (alias: `/auth/change-password`) |

`POST /users/change-password` takes `current_password` and `new_password`
(minimum 8 characters). Requiring the current password is what stops a borrowed
session from locking the owner out. Other signed-in devices stay signed in —
there is no token revocation list yet.

`GET /subscription` is the authority on entitlement:

```json
{
  "status": "trial",
  "is_active": true,
  "requires_plan": false,
  "days_remaining": 9,
  "plan_name": "Free Trial",
  "trial_ends_at": "2026-08-12T00:00:00Z"
}
```

`status` is one of `trial`, `active`, `trial_expired`, `expired`, `cancelled`,
`none`, `not_applicable`.

## Subscription billing

| Method | Path | Notes |
|---|---|---|
| GET | `/subscription` | Current entitlement |
| GET | `/subscription/payments` | What the firm has paid us |
| GET | `/subscription/usage` | Cases/clients/staff used vs the plan's caps |
| POST | `/subscription/checkout` | `{"plan":"solo","billing_cycle":"monthly"}` — firm admin only |
| POST | `/subscription/activate` | Gateway callback: order id, payment id, signature |
| POST | `/subscription/cancel` | Access continues to the end of the paid period |
| POST | `/webhooks/razorpay` | **Public.** HMAC-signed; authoritative |

`POST /subscription/checkout` takes **no amount**. The price is read from the
`plans` table, so a caller cannot buy the top tier for ₹1.

`/webhooks/razorpay` is the authoritative activation path — a user who kills the
app right after paying never reaches `/subscription/activate`. Both funnel
through the same code, and `subscription_payments.payment_id` is unique, so a
replayed webhook or a retried callback cannot grant two billing periods for one
payment. Configure it in the Razorpay dashboard for `payment.captured`,
`payment.failed` and `order.paid`, and set `RAZORPAY_WEBHOOK_SECRET`.

### The paywall

Firm-scoped **write** endpoints return **402** with
`{"code":"subscription_required"}` once a plan lapses.

Reads are never gated. A firm whose card expired can still open its own case
files, read documents and export data — those records are theirs, and they may
be needed in court that day. Only creating new work is blocked.

A failed renewal moves the subscription to `past_due` with a 7-day grace window
before access is withdrawn, rather than cutting a practice off the morning their
card expires.

### Plan limits

`POST /cases`, `POST /clients` and `POST /staff` return **402** once the firm
reaches the cap on its plan (`max_cases`, `max_clients`, `max_staff`; `0` means
unlimited). These were stored and shown on the paywall but enforced nowhere, so
every tier was effectively unlimited. Call `/subscription/usage` to warn a user
before they hit the wall rather than at the moment of refusal.

## Clients, Cases, Hearings

| Method | Path |
|---|---|
| GET / POST | `/clients` |
| GET / PUT / DELETE | `/clients/:id` |
| GET / POST | `/cases` |
| GET / PUT / DELETE | `/cases/:id` |
| GET | `/cases/:id/timeline`, `/cases/:id/hearings` |
| GET / POST | `/cases/:id/notes` |
| GET / POST | `/hearings` |
| GET | `/hearings/today` |
| GET / PUT / DELETE | `/hearings/:id` |

`DELETE` is a soft delete throughout — a case closes, a client deactivates, a
hearing cancels. Nothing is destroyed.

Case `status` must be one of `active`, `pending`, `closed`, `won`, `lost`,
`settled`. Private case notes are visible only to their author.

## Documents

| Method | Path |
|---|---|
| GET | `/documents` |
| POST | `/documents/upload` |
| GET / DELETE | `/documents/:id` |

`uploaded_by_role` is taken from the token, not the request body. Inline
`file_content` is capped at 8 MB.

## Billing

| Method | Path |
|---|---|
| GET / POST | `/invoices` |
| GET | `/invoices/pending-verification` |
| GET / PUT | `/invoices/:id` |
| GET / POST | `/payments` |
| POST | `/payments/razorpay/order` |
| POST | `/payments/razorpay/verify` |
| PUT | `/payments/:id/verify` |
| GET / PUT | `/firm/bank-details` |

Notes that matter:

- `PUT /invoices/:id` cannot set `status: "paid"` — record a payment instead.
- `POST /payments/razorpay/order` takes **no amount**. It reads the balance from
  the invoice; passing an amount would let a caller open a ₹1 order against a
  ₹100,000 invoice.
- `POST /payments/razorpay/verify` takes no amount either — it settles against
  the recorded order. It returns 503 if `RAZORPAY_KEY_SECRET` is unset rather
  than skipping signature verification, and 409 on a replayed payment id.
- `PUT /firm/bank-details` is firm-admin only and writes an audit log entry.
  These fields decide where client payments land.

## Court

| Method | Path | Notes |
|---|---|---|
| GET | `/court/case-status?cnr=` | 16-char CNR. Cached 6h; `&refresh=true` forces a fetch |
| POST | `/court/cases/:id/sync` | Syncs a tracked case, records the next listed date as a hearing |
| GET | `/court/cause-list?state=&district=&court_complex=&date=` | |
| GET | `/court/holidays` | |
| POST | `/court/holidays` | Firm admin loads a year's list |

Returns 503 until `ECOURTS_API_BASE` is set — see
[court-data.md](court-data.md). Every response carries an `attribution_note`
crediting eCourts / NJDG; keep it.

## Client portal

| Method | Path |
|---|---|
| GET | `/portal/my-cases`, `/portal/my-hearings`, `/portal/my-documents`, `/portal/my-invoices` |
| POST | `/portal/book-consultation` |
| GET | `/portal/my-consultations`, `/portal/my-consultations/:id` |
| PUT | `/portal/my-consultations/:id/cancel` |

Scoped by the caller's own verified email address, across every firm that has
them as a client.

## Chat

| Method | Path |
|---|---|
| GET / POST | `/chat/rooms` |
| GET / POST | `/chat/rooms/:room_id/messages` |
| DELETE | `/chat/messages/:message_id` |
| GET | `/chat/unread` |

Every room endpoint verifies the caller is a participant — the room's lawyer, or
the client it was opened for.

## Reports, Staff, Notifications

| Method | Path |
|---|---|
| GET | `/reports/cases`, `/reports/revenue` |
| GET / POST | `/staff` |
| GET / PUT | `/staff/:id` |
| GET | `/notifications` |
| PUT | `/notifications/:id/read` |

`POST /staff` adds a member to the **caller's existing firm**. It is firm-admin
only and cannot assign `super_admin`.

## Student

| Method | Path |
|---|---|
| GET | `/student/lawyers`, `/student/lawyer/:id` |
| GET | `/student/progress`, `/student/leaderboard` |
| POST | `/challenges/generate`, `/challenges/:id/submit` |
| GET | `/challenges/:id` |

The lawyer directory exposes name, designation, firm, city and state — not email
or phone. Contact goes through consultation booking.

## Admin — `super_admin` only

| Method | Path |
|---|---|
| GET | `/admin/users`, `/admin/lawyers`, `/admin/stats` |
| PUT / DELETE | `/admin/users/:id` |
| GET | `/admin/subscriptions`, `/admin/revenue`, `/admin/audit-logs` |

These act across every firm. `DELETE` deactivates rather than deletes, and
neither endpoint can touch another `super_admin` or the caller's own account.
