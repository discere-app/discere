-- Rebuild species_name_lookup — laeuft nach allen Plugins, vor Validierung.
-- Disambiguiert mehrdeutige normalized_names nach:
--   1. is_preferred DESC (kanonischer Name bevorzugt)
--   2. source-Ranking: fishbase=0, sealifebase=1, sonst=2
--   3. species_id (deterministischer Tie-Breaker)
-- Nur aktive Species werden beruecksichtigt.

DELETE FROM species_name_lookup;

INSERT INTO species_name_lookup (normalized_name, species_id)
SELECT normalized_name, species_id
FROM (
    SELECT
        ssn.normalized_name,
        ssn.species_id,
        ROW_NUMBER() OVER (
            PARTITION BY ssn.normalized_name
            ORDER BY
                ssn.is_preferred DESC,
                CASE ssn.source
                    WHEN 'fishbase' THEN 0
                    WHEN 'sealifebase' THEN 1
                    ELSE 2
                END,
                ssn.species_id
        ) AS rn
    FROM species_scientific_names ssn
    JOIN species s ON s.id = ssn.species_id
    WHERE s.status = 'active'
) ranked
WHERE rn = 1;
