-- =============================================================================
-- source.sql — Kuratierte Ergänzungen
--
-- Von Hand gepflegte Daten im Repository (plugins/curated/data/). Jede Zeile
-- nennt ihren eigenen Beleg in source_url, überwiegend Wikidata (CC0). Die
-- Zusammenstellung selbst steht unter CC BY-NC 4.0 wie FishBase: nutzbar mit
-- Namensnennung, nicht kommerziell.
--
-- Name, Kategorie und Zitierung sind wie bei den übrigen Quellen englisch: Die
-- App zeigt sie unübersetzt. Der Name ist kurz, weil die Quellen-Seite ihn
-- einzeilig zeigt.
--
-- Platzhalter die von import.sh via sed ersetzt werden:
--   ${VERSION}   — Prüfsumme der Daten
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
    'curated',
    'Discere',
    'Curated Additions',
    'Discere contributors. Hand-curated additions to the reference data,
     such as vernacular names of taxa the other sources only name in English.
     Each entry cites its own reference, mostly Wikidata.',
    'https://github.com/discere-app/discere/tree/main/etl/plugins/curated/data',
    NULL,
    NULL,
    'CC BY-NC 4.0',
    'https://creativecommons.org/licenses/by-nc/4.0/',
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
