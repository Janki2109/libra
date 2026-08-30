# Getting Indian court data — for free, and legally

This is the answer to "how do we get court data without paying for it".

Short version: **the data is free and public, but there is no free open REST
API from the government.** You either apply to NIC for API access (free,
takes weeks), use the free tier of a gateway that already holds that access, or
consume the open bulk/aggregate feeds. Scraping the public portal is the one
route you should not take, and the reason is below.

---

## 1. What exists

| Source | Covers | Cost | Access |
|---|---|---|---|
| **eCourts Services** (`services.ecourts.gov.in`) | ~20,000 district & taluka courts: case status, cause lists, orders, CNR lookup | Free | Web form, CAPTCHA-gated. **No public API.** |
| **NJDG** — National Judicial Data Grid (`njdg.ecourts.gov.in`) | Pendency/disposal statistics, some case-level data | Free | Open web + limited open-data endpoints, no key |
| **NJDG API via NIC / API Setu** | Case status by CNR, cause lists | **Free** to approved applicants | Written application to NIC. Weeks. |
| **High Court portals** (each HC has its own) | That court's causelists, orders, judgments | Free | Per-court; formats differ wildly |
| **Supreme Court** (`sci.gov.in`, `judgments.ecourts.gov.in`) | SC case status, judgments | Free | Web; judgment search is bulk-downloadable |
| **India Code / indiankanoon.org** | Bare acts, judgments (full text) | Free to read; API is paid | Kanoon has a paid API; its site is scrapeable only under its ToS |
| **Commercial gateways** (Legalkart, Jarvis, Kleos, apiSetu resellers) | Wraps eCourts | Free tiers typically 100–1,000 calls/month | Instant API key |

### What this app needs

For a practice-management tool, the useful subset is small:

1. **Case status by CNR** — the single most valuable call. Powers "what
   happened in my case" and the client portal.
2. **Cause list by court + date** — powers "what am I in court for tomorrow".
3. **Orders/judgments** — links, not full text.

All three are covered by the eCourts data set.

---

## 2. The route to take: apply to NIC (free, permanent)

This is the answer for a product you intend to run.

1. Write to the **eCourts project team, National Informatics Centre**
   (`ecommittee-sci@nic.in`, cc the eCourts helpdesk) requesting API access to
   NJDG/eCourts Services for a legal-practice application.
2. Include: organisation name, what you are building, expected call volume,
   which data sets (case status by CNR, cause lists), and that you will display
   attribution.
3. Some states additionally route this through **API Setu**
   (`apisetu.gov.in`) — register there as a publisher-consumer; it is free.

Approval is not instant — plan for **4–10 weeks**. There is no fee.

Once approved, set:

```
ECOURTS_API_BASE=https://<endpoint-they-give-you>
ECOURTS_API_KEY=<your key>
```

`backend/services/ecourts.go` will start serving live data with no code change.

## 3. The route to take *today*: a gateway free tier

While the NIC application is pending, point `ECOURTS_API_BASE` at any gateway
that already holds eCourts access and offers a free tier. The client sends the
key as both `Authorization: Bearer` and `X-API-Key`, which covers the common
conventions. Expect 100–1,000 calls/month free — enough for a pilot, and the
6-hour cache below stretches it a long way.

Swapping providers later is a single environment-variable change; the response
normalizer in `ecourts.go` already accepts the field-name variants the
different gateways use.

## 4. Free at zero effort: bulk + manual

Even with no API at all, these work and cost nothing:

- **Court holidays** — `POST /api/v1/court/holidays`. Each High Court publishes
  its annual calendar as a PDF; load it once a year. (The old code hardcoded
  2026's list in Go, which meant a code deploy every January and a wrong list
  for every state but Maharashtra.)
- **Judgments** — `judgments.ecourts.gov.in` allows bulk download by court and
  date range. Fine for a nightly job.
- **NJDG statistics** — open, unauthenticated, no key. Good for dashboards.
- **CNR entry by the lawyer** — the CNR is printed on every filing receipt.
  Storing it (`cases.cnr_number`) costs nothing and makes every later
  integration a one-line lookup.

---

## 5. What NOT to do

**Do not scrape `services.ecourts.gov.in` by defeating its CAPTCHA.**

- The CAPTCHA is an access control. Circumventing it breaches the site's terms
  of use, and under the IT Act 2000 (s.43/s.66) unauthorised access to a
  computer resource is an offence.
- It is also commercially fatal: this product is sold to advocates. A firm
  cannot be seen sourcing court data through a method the court prohibits.
- It breaks constantly. eCourts changes its form markup without notice.

The `ECOURTS_API_BASE` design exists precisely so the lawful path is the easy
one.

---

## 6. How this app uses it

```
GET  /api/v1/court/case-status?cnr=MHAU010012342024   # one case, cached 6h
GET  /api/v1/court/case-status?cnr=...&refresh=true   # force a live fetch
POST /api/v1/court/cases/:id/sync                     # sync a tracked case
GET  /api/v1/court/cause-list?state=..&district=..&date=YYYY-MM-DD
GET  /api/v1/court/holidays
POST /api/v1/court/holidays                           # firm admin loads a year
```

**Caching.** Every fetched record is stored in `court_data` keyed by CNR, and
reads inside 6 hours are served from there. A court record changes at most once
per hearing, so this cuts upstream calls by well over 90% — which is what makes
a 1,000-call free tier viable for a real firm. If the upstream is unreachable,
a stale cached copy is returned, labelled as such, rather than an error.

**Attribution.** Every response carries `attribution_note` crediting eCourts /
NJDG, Department of Justice. Keep it — it is a condition of the data's reuse
and it is what makes the "where did this come from" question answerable.

**Accuracy.** The note also tells the user to verify against the court record.
Do not remove that: eCourts data lags the registry, and a missed hearing date
is a professional-negligence problem for your customer.

---

## 7. Cost summary

| Approach | Cost | Time to live |
|---|---|---|
| NIC/API Setu approval | ₹0 forever | 4–10 weeks |
| Gateway free tier | ₹0 up to the tier | Same day |
| Gateway paid tier | ~₹2–10 per call, or ₹5k–25k/mo | Same day |
| Bulk judgments + manual CNR | ₹0 | Immediate |

Recommended: file the NIC application now, run on a gateway free tier in the
meantime, keep the 6-hour cache either way.
