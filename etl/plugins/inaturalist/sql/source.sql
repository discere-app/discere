-- =============================================================================
-- source.sql — iNaturalist
--
-- Zitierung, Lizenz und Darstellung wie der Eintrag, den die App ohne diesen
-- Datensatz selbst anfügt (lib/catalog/service/source_service.dart): Die
-- Quellen-Seite soll mit und ohne ihn gleich aussehen.
--
-- Platzhalter die von import.sh via sed ersetzt werden:
--   ${VERSION}   — Datum der taxa.csv.gz
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
    'inaturalist',
    'iNaturalist',
    'Community Photos',
    'iNaturalist. (2026). iNaturalist Research-grade Observations. Occurrences retrieved from https://www.inaturalist.org. Photos curated by the community and licensed under CC BY, CC-BY-SA, CC-BY-NC, or CC0.',
    'https://www.inaturalist.org',
    'https://www.inaturalist.org/taxa/{external_id}',
    'https://www.inaturalist.org/favicon.ico',
    'CC BY / CC0',
    'https://www.inaturalist.org/pages/help#licenses',
    '${VERSION}',
    30,
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
