-- =============================================================================
-- source.sql — FishBase
--
-- Zitierung und Lizenz gemäss https://www.fishbase.org/search.php
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
    favicon_url,
    license_key,
    license_url,
    version,
    display_order,
    last_imported
) VALUES (
    'fishbase',
    'FishBase',
    'Biological Data',
    'Froese, R. and D. Pauly. Editors. ${VERSION}. FishBase.
     World Wide Web electronic publication.
     www.fishbase.org, version (${VERSION}).',
    'https://www.fishbase.org',
    'https://www.fishbase.org/favicon.ico',
    'CC BY-NC 4.0',
    'https://creativecommons.org/licenses/by-nc/4.0/',
    '${VERSION}',
    20,
    '${NOW}'
)
ON CONFLICT (id) DO UPDATE SET
    name          = excluded.name,
    category      = excluded.category,
    citation      = excluded.citation,
    url           = excluded.url,
    favicon_url   = excluded.favicon_url,
    license_key   = excluded.license_key,
    license_url   = excluded.license_url,
    version       = excluded.version,
    display_order = excluded.display_order,
    last_imported = excluded.last_imported;
