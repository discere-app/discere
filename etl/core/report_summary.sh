#!/usr/bin/env bash
# =============================================================================
# report_summary.sh — Fasst den Build-Bericht zusammen
#
# Usage:
#   ./core/report_summary.sh <bericht-verzeichnis>
#
# Liest die <quelle>.tsv-Dateien, die plugin_report (core/plugin_api.sh)
# schreibt, und gibt je Quelle eine Zeile mit der Anzahl je Kategorie aus:
#
#   inaturalist: ambiguous 12 none 3
#
# Ohne Einträge: „keine Einträge“.
# =============================================================================

set -Eeuo pipefail

REPORT_DIR="${1:-}"
[[ -d "$REPORT_DIR" ]] || { echo "[ERROR] [report_summary] Verzeichnis nicht gefunden: '$REPORT_DIR'" >&2; exit 1; }

report_files=("$REPORT_DIR"/*.tsv)
if [[ ! -f "${report_files[0]}" ]]; then
    echo "keine Einträge"
    exit 0
fi

awk -F '\t' '
    FNR > 1 { count[$1 "\t" $2]++ }
    END { for (key in count) print key "\t" count[key] }
' "${report_files[@]}" \
| LC_ALL=C sort \
| awk -F '\t' '
    $1 != source { if (line != "") print line; source = $1; line = source ":" }
    { line = line " " $2 " " $3 }
    END { if (line != "") print line }
'
