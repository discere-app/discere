-- =============================================================================
-- source.sql — SeaLifeBase
--
-- Zitierung und Lizenz gemäss https://www.sealifebase.org/search.php
-- (Stand: 11/2025)
--
-- Platzhalter die von import.sh via sed ersetzt werden:
--   ${VERSION}   — Versions-String des Imports (z.B. "11/2025")
--   ${NOW}       — ISO-8601 Zeitstempel des Imports
-- =============================================================================

INSERT INTO sources (
    id,
    name,
    category,
    citation,
    url,
    species_url_template,
    favicon_url,
    license_key,
    license_url,
    version,
    display_order,
    last_imported
) VALUES (
    'sealifebase',
    'SeaLifeBase',
    'Biological Data',
    'Palomares, M.L.D. and D. Pauly. Editors. ${VERSION}. SeaLifeBase.
     World Wide Web electronic publication.
     www.sealifebase.org, version (${VERSION}).',
    'https://www.sealifebase.org',
    'https://www.sealifebase.org/summary/SpeciesSummary.php?genusname={genus}&speciesname={species}',
    'https://sealifebase.org/favicon.ico',
    'CC BY-NC 4.0',
    'https://creativecommons.org/licenses/by-nc/4.0/',
    '${VERSION}',
    10,
    '${NOW}'
)
ON CONFLICT (id) DO UPDATE SET
    name          = excluded.name,
    category      = excluded.category,
    citation      = excluded.citation,
    url           = excluded.url,
    species_url_template = excluded.species_url_template,
    favicon_url   = excluded.favicon_url,
    license_key   = excluded.license_key,
    license_url   = excluded.license_url,
    version       = excluded.version,
    display_order = excluded.display_order,
    last_imported = excluded.last_imported;
