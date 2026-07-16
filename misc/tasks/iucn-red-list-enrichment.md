# IUCN Red List Enrichment

## Status

Backlog. This is intentionally not part of the current Species Detail enum
localization work.

## Motivation

Discere currently shows FishBase/SeaLifeBase `Vulnerability` as an
overexploitation-oriented vulnerability bucket. This is useful, but it is not
an official conservation status and should not be presented as "endangered".

The IUCN Red List status is the more relevant field for conservation context:
`LC`, `NT`, `VU`, `EN`, `CR`, `EW`, `EX`, `DD`, plus criteria, assessment year,
and population trend where available.

The Species Detail page should eventually be able to show both concepts
separately, for example:

```text
IUCN status: Vulnerable (VU)
Overexploitation vulnerability: Very high
```

## Current Data Situation

- FishBase/SeaLifeBase `species.parquet -> Vulnerability` is imported as
  `species.vulnerability`.
- FishBase/SeaLifeBase `country.parquet -> Threatened` is imported as
  `taxonomy_distribution_regions.threatened_flag`.
- Neither field is an IUCN Red List category.
- The local reference database currently has no IUCN category, criteria,
  assessment year, or population trend fields.

## Candidate Source

Use the official IUCN Red List API:

- API docs: https://api.iucnredlist.org/api-docs
- API sign-up: https://api.iucnredlist.org/users/sign_up
- A personal API key is required and must be kept private.
- Do not ship an IUCN API key in the Flutter app.

The API can provide Red List category, criteria, population trend, assessment
metadata, habitats, threats, and conservation actions.

## Usage Constraints

- Registration/API access appears to be free, but authenticated.
- No hard public request quota was found during initial research.
- `rredlist` documents IUCN guidance that too many frequent calls or too many
  calls per day may be temporarily blocked.
- For bulk use, the documented recommendation is to contact the Red List Unit.
- A conservative batch client should wait at least 2 seconds between requests.
- Cache results aggressively. IUCN assessments change slowly and should not be
  refetched on every app launch or every detail-page view.
- Check current IUCN terms before shipping or redistributing a large derived
  dataset. IUCN spatial downloads are described as free for non-commercial use;
  commercial use points to IBAT.
- Do not blindly call the API once for every FishBase/SeaLifeBase species as a
  normal build step. For full-catalog extraction, contact the Red List Unit or
  clarify a permitted bulk-data path first.

## API Key Strategy

Do not ship the personal IUCN API key inside the Flutter app.

Client-side storage techniques such as `--dart-define`, Flutter Secure
Storage, Android Keystore, JNI/C++ obfuscation, or encrypted assets only raise
the reverse-engineering cost. They do not provide true secrecy because the app
must eventually have enough information to perform the authenticated request.
They are acceptable for private/local test builds, but not for a public app.

Apple App Attest, DeviceCheck, Play Integrity, and Firebase App Check also do
not solve this by themselves. They are useful only when a server verifies the
attestation token and then performs the protected request server-side. IUCN will
not validate Discere-specific attestation tokens directly.

There are two viable deployment options:

1. ~~Offline/batch enrichment before the app build.~~ **Ruled out.** Checked
   against the ETL pipeline; not feasible to produce IUCN fields there. Do not
   revisit this option without a concrete new ETL capability.

2. Minimal serverless proxy.
   - Keep the IUCN key as a server-side secret.
   - The Flutter app calls the proxy, not IUCN directly.
   - The proxy validates inputs, applies rate limits, caches results, and
     returns only normalized fields.
   - Provider-agnostic requirement: something that can hold one secret, expose
     one narrow HTTP endpoint, and cache responses. It does not need to be a
     traditional always-on backend.

3. Client-side obfuscation.
   - Only for private/internal builds.
   - Still requires accepting that the key can be extracted and rotated.
   - Not viable for a public release; listed only for completeness.

With option 1 ruled out and option 3 unsuitable for a public build, **the
serverless proxy is the only remaining viable path** for shipping IUCN data
publicly.

## Serverless Proxy Option

A small proxy is the smallest clean runtime option if Discere should show IUCN
data without embedding the API key and without operating a traditional
backend.

Recommended shape (provider-agnostic):

```text
Flutter app
  -> GET /iucn?species_id=...
Proxy
  -> accept only known Discere species_id values
  -> read cache (KV/D1/SQLite/any small store)
  -> on cache miss, call IUCN with a server-side secret
  -> normalize category/criteria/year/trend
  -> store cache
  -> return normalized JSON
```

Do not implement this as an open pass-through proxy to arbitrary IUCN URLs. The
endpoint should accept `species_id` or a tightly validated scientific name, not
arbitrary upstream paths, headers, or query strings.

Abuse controls (apply regardless of provider):

- Hard allowlist of supported parameters.
- Per-IP or per-client rate limit.
- Long cache TTL for successful assessments.
- Negative cache for unresolved species.
- Optional daily hard cap for live IUCN cache misses.
- Return cached data first; do not block app usability on live IUCN failures.

### Provider Options

Any of these can host the proxy; pick based on what else Discere ends up
needing a small always-available endpoint for (see also
`deck-index-automation.md` for a second, unrelated use case that needs similar
serverless infrastructure — worth colocating if both get built).

- **Cloudflare Workers** — good fit because the proxy mostly waits on I/O and
  uses little CPU; waiting on `fetch()`/KV/D1 doesn't count as active CPU
  time. Free plan is likely enough (see cost model below); Paid Workers
  Standard is about `$5/month` if the free daily request cap is exceeded.
- **Deno Deploy** — similar edge-function model, generous free tier, KV
  available.
- **Fly.io** — small always-on container instead of a pure edge function;
  more control, slightly more to operate (own HTTP server, own cache).
- **AWS Lambda + API Gateway** — viable but more setup/IAM overhead for a
  single narrow endpoint than the above.

Cloudflare cost model for a simple IUCN proxy (illustrative; same shape
applies to comparable edge-function providers):

```text
Assume 5 ms CPU per request.

1,000 detail lookups/day:
  30,000 requests/month
  150,000 CPU-ms/month
  likely $0 on Free

10,000 detail lookups/day:
  300,000 requests/month
  1,500,000 CPU-ms/month
  likely $0 on Free

100,000 detail lookups/day:
  3,000,000 requests/month
  15,000,000 CPU-ms/month
  at Free daily request limit; about $5/month on Paid

1,000,000 detail lookups/day:
  30,000,000 requests/month
  150,000,000 CPU-ms/month
  rough Paid estimate: about $13.40/month
```

The main cost risk is not normal Discere usage, but endpoint abuse after the
public proxy URL is extracted from the app. That is why the proxy should be a
narrow cached data service, not a general pass-through.

## Proposed Implementation

Add this as a separate enrichment path, not as part of the FishBase/SeaLifeBase
reference import.

Recommended table shape:

```sql
CREATE TABLE iucn_assessment_cache (
    species_id TEXT NOT NULL PRIMARY KEY,
    scientific_name TEXT NOT NULL,
    iucn_taxon_id TEXT,
    category TEXT,
    criteria TEXT,
    population_trend TEXT,
    assessment_year INTEGER,
    source_url TEXT,
    fetched_at INTEGER NOT NULL
);
```

Recommended lookup flow:

1. Resolve Discere species to binomial scientific name.
2. Query IUCN by scientific name through the serverless proxy. Do not query
   IUCN directly from the Flutter app in public builds.
3. Select the latest global species-level assessment.
4. Store normalized fields in `iucn_assessment_cache`.
5. Present the cached value on Species Detail when available.
6. Fall back to "not available" without blocking the detail page.

For the current no-backend app, prefer this order:

1. Implement the local data model, cache table, repository, presenter, and UI
   using seeded/mock IUCN rows.
2. Pick a proxy provider (see Provider Options above).
3. Build the proxy with caching/rate limiting in place before exposing it to
   the app — never ship a v1 without the abuse controls above.

## UI Notes

Keep labels distinct:

- `IUCN status`: official extinction-risk category.
- `Overexploitation vulnerability`: FishBase/SeaLifeBase vulnerability score
  bucket.

Avoid German labels that imply the FishBase/SeaLifeBase vulnerability score is
an official Red List category. For example, prefer:

```text
IUCN-Status: Gefährdet (VU)
Übernutzungsanfälligkeit: Sehr hoch
```

Do not use:

```text
Gefährdung: Sehr hoch
```

for FishBase/SeaLifeBase vulnerability.

## Open Questions

- Which proxy provider to use (see Provider Options)?
- Should this run only for user deck species, or for the full reference
  database?
- Should the cache live in the reference database, the user database, or both?
- Should threat/habitat/conservation-action details be stored in v1, or only
  category, criteria, trend, and assessment year?
- How should synonym and taxonomic mismatch cases be resolved?
- What citation text should be shown in the Sources page for cached IUCN data?
