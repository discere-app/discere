-- =============================================================================
-- identity_source_loss.sql — Bricht eine Quelle ein, bricht der Build ab
--
-- Teil der Identitäts-Stage (core/identity.sh), nach identity_assign.sql.
-- Erwartet identity_prev_active_species (die Arten-Schlüssel, die im
-- Vorgänger aktiv waren), identity_rows und identity_loss_limits (je Quelle
-- des Vorgängers ihre Schwelle in Prozent und ob ein Rückgang ausdrücklich
-- angenommen ist, aus identity.sh).
--
-- Liefert eine Quelle still nur einen Teil ihrer Arten, liegt der Build mit
-- den übrigen Quellen oft noch über den Mindestzahlen der Validierung. Die
-- fehlenden Arten würden übernommen und, wo ein Name passt, Alias auf eine
-- Art einer anderen Quelle — das schriebe Lernstände in der App endgültig um.
-- Deshalb zählt die Stage je Quelle, wie viele ihrer im Vorgänger aktiven
-- Arten-Schlüssel dieser Build nicht mehr liefert. Liegt der Anteil über der
-- Schwelle (Default 5 %, je Quelle species_loss_limit_percent im Manifest),
-- bricht sie ab — auch wenn die Quelle ganz fehlt —, außer der Rückgang ist
-- ausdrücklich angenommen (--accept-species-loss <quelle>; build.sh vermerkt
-- den Build dann als unvollständig).
-- =============================================================================

CREATE TEMP TABLE identity_source_loss AS
SELECT
    p.source,
    COUNT(*)                         AS previous,
    SUM(r.provisional_id IS NULL)    AS lost,
    COALESCE(l.limit_percent, 5)     AS limit_percent,
    COALESCE(l.accepted, 0)          AS accepted
FROM identity_prev_active_species p
LEFT JOIN identity_rows r
  ON r.entity_type = 'species'
 AND r.source      = p.source
 AND r.external_id = p.external_id
LEFT JOIN identity_loss_limits l ON l.source = p.source
GROUP BY p.source;

INSERT INTO identity_failure (message)
SELECT 'Arten-Rückgang über der Schwelle: '
       || group_concat(source || ' ' || lost || ' von ' || previous
                       || ' (' || printf('%.1f', 100.0 * lost / previous) || ' %, erlaubt '
                       || limit_percent || ' %)', '; ')
       || '. Liefert die Quelle unvollständig? Ein gewollter Rückgang: species_loss_limit_percent'
       || ' im Manifest der Quelle; nur zum Testen: --accept-species-loss <quelle>'
       || ' (der Build ist dann nicht veröffentlichbar).'
FROM identity_source_loss
WHERE accepted = 0
  AND 100.0 * lost > 1.0 * previous * limit_percent
HAVING COUNT(*) > 0;
