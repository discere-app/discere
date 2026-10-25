#!/usr/bin/env bash
# Tests für --help aller ETL-Skripte: Jedes gibt seinen Kopfkommentar
# zwischen den ersten beiden '# ===…'-Linien aus (plugin_print_help in
# core/plugin_api.sh), vollständig und ohne die Linien.

# Gibt die ausführbaren ETL-Skripte aus, deren Argumente --help kennen —
# über eine eigene Argument-Schleife oder plugin_parse_args —, eines je Zeile.
help_scripts() {
    local script
    find "$ETL_DIR" -name '*.sh' -not -path '*/tests/*' -not -path '*/cache/*' | sort \
        | while IFS= read -r script; do
            [[ -x "$script" ]] || continue
            grep -Eq -e '^[[:space:]]*--help\|-h\)' -e '^plugin_parse_args ' "$script" && echo "$script"
        done
}

# Letzte Zeile vor der zweiten '# ===…'-Linie, ohne das Kommentarzeichen.
last_header_line() {
    local second_rule
    second_rule="$(grep -n '^# =*$' "$1" | sed -n '2s/:.*//p')"
    [[ -n "$second_rule" ]] || return 1
    sed -n "$((second_rule - 1))p" "$1" | sed 's/^# \{0,1\}//'
}

test_help_prints_the_whole_header_of_every_script() {
    local scripts script name expected count=0 failures=""
    scripts="$(help_scripts)"
    while IFS= read -r script; do
        [[ -n "$script" ]] || continue
        count=$((count + 1))
        name="${script#"$ETL_DIR"/}"
        run_capture "$script" --help
        if [[ "$STATUS" -ne 0 || -z "$OUT" ]]; then
            failures+=$'\n'"$name: Exit $STATUS, Ausgabe: [${OUT:0:80}] ${ERR:0:200}"
            continue
        fi
        if printf '%s\n' "$OUT" | grep -q '^=\{3,\}$'; then
            failures+=$'\n'"$name: Linie in der Hilfe"
        fi
        expected="$(last_header_line "$script")" \
            || { failures+=$'\n'"$name: keine zweite '# ===…'-Linie"; continue; }
        [[ "$(printf '%s\n' "$OUT" | tail -n 1)" == "$expected" ]] \
            || failures+=$'\n'"$name: letzte Zeile [$(printf '%s\n' "$OUT" | tail -n 1)], erwartet [$expected]"
    done <<< "$scripts"
    [[ $count -ge 20 ]] || fail_case "Nur $count Skripte mit --help gefunden, erwartet mindestens 20."
    [[ -z "$failures" ]] || fail_case "Hilfe unvollständig oder mit Linie:$failures"
}
