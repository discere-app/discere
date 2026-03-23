-- ---------------------------------------------------------------------------
-- validate.sql — Mindest-Zeilenzahlen nach dem Import
-- Wird von build.sh nach allen Plugins ausgeführt.
-- Bei Unterschreitung bricht das Script ab.
-- ---------------------------------------------------------------------------

SELECT
    'classes'  AS tbl, COUNT(*) AS n, 10     AS min FROM classes  UNION ALL
SELECT 'orders',                       COUNT(*), 50    FROM orders   UNION ALL
SELECT 'families',                     COUNT(*), 400   FROM families UNION ALL
SELECT 'genera',                       COUNT(*), 5000  FROM genera   UNION ALL
SELECT 'species',                      COUNT(*), 30000 FROM species  UNION ALL
SELECT 'pictures',                     COUNT(*), 10000 FROM pictures;
