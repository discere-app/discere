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
2. Query IUCN by scientific name with the private API key.
3. Select the latest global species-level assessment.
4. Store normalized fields in `iucn_assessment_cache`.
5. Present the cached value on Species Detail when available.
6. Fall back to "not available" without blocking the detail page.

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

- Should this run only for user deck species, or for the full reference
  database?
- Should the cache live in the reference database, the user database, or both?
- Should threat/habitat/conservation-action details be stored in v1, or only
  category, criteria, trend, and assessment year?
- How should synonym and taxonomic mismatch cases be resolved?
- What citation text should be shown in the Sources page for cached IUCN data?
