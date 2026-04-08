-- =============================================================================
-- source.sql — <Plugin-Name>
--
-- Wird von plugin_write_source_metadata() ausgeführt.
--
-- Platzhalter:
--   ${VERSION}   — Versions-String des Imports
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
    'example',
    'Example Source',
    'Biological Data',
    'Bitte Zitierung für ${VERSION} ergänzen.',
    'https://example.org',
    'https://example.org/species/{external_id}',
    'https://example.org/favicon.ico',
    'custom',
    'https://example.org/license',
    '${VERSION}',
    100,
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
