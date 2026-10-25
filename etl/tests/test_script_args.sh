#!/usr/bin/env bash
# Tests für die Argumente aller ETL-Skripte: --help gibt den Kopfkommentar
# zwischen den ersten beiden '# ===…'-Linien aus (plugin_print_help in
# core/plugin_api.sh), vollständig und ohne die Linien; ein Flag ohne Wert
# bricht mit eigener Meldung unter dem Kürzel des Skripts ab
# (plugin_require_value). Die Skripte werden aus den Dateien ermittelt.

# Gibt die ausführbaren ETL-Skripte aus, eines je Zeile.
etl_scripts() {
    local script
    find "$ETL_DIR" -name '*.sh' -not -path '*/tests/*' -not -path '*/cache/*' | sort \
        | while IFS= read -r script; do
            [[ -x "$script" ]] && echo "$script"
        done
}

# Gibt die ETL-Skripte aus, deren Argumente --help kennen — über eine eigene
# Argument-Schleife oder plugin_parse_args —, eines je Zeile.
help_scripts() {
    local script
    etl_scripts | while IFS= read -r script; do
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

test_script_args_help_prints_the_whole_header_of_every_script() {
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

# Legt $TEST_TMP/probe_values.sh an: ein Skript ohne PLUGIN_SOURCE, dessen
# Flag --name einen Wert verlangt und ihn auf stdout ausgibt.
create_value_probe() {
    PROBE="$TEST_TMP/probe_values.sh"
    cat > "$PROBE" << SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail
source "$ETL_DIR/core/plugin_api.sh"
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        --name) plugin_require_value "\$@"; echo "name=\$2"; shift ;;
    esac
    shift
done
SCRIPT
    chmod +x "$PROBE"
}

test_script_args_require_value_passes_a_given_value() {
    create_value_probe
    run_capture "$PROBE" --name ""
    assert_status 0
    assert_eq "name=" "$OUT" "Ausgabe"
}

# Ohne PLUGIN_SOURCE gilt der Dateiname als Kürzel.
test_script_args_require_value_aborts_under_the_script_name() {
    create_value_probe
    run_capture "$PROBE" --name
    assert_status 1
    assert_eq "[ERROR] [probe_values] --name braucht einen Wert." "$ERR" "stderr"
}

# Gibt je Flag mit Wert aus einer Argument-Schleife eine Zeile
# "<skript> <flag>" aus — jeder case-Zweig, der "$2" liest.
value_flags() {
    local script
    etl_scripts | while IFS= read -r script; do
        sed -n 's/^[[:space:]]*\(--[a-z0-9-]*\)).*"\$2".*/\1/p' "$script" | sed "s|^|$script |"
    done
}

# Jeder Zweig, der "$2" liest, prüft vorher mit plugin_require_value, dass es
# den Wert gibt; ohne Wert bricht das Skript unter seinem Kürzel ab statt mit
# "unbound variable".
test_script_args_flag_without_value_aborts_in_every_script() {
    local flags script flag name tag line count=0 failures=""
    flags="$(value_flags)"
    while read -r script flag; do
        [[ -n "$script" ]] || continue
        count=$((count + 1))
        name="${script#"$ETL_DIR"/}"
        tag="$(basename "$script" .sh)"
        line="$(grep -E "^[[:space:]]*$flag\)" "$script")"
        [[ "$line" == *'plugin_require_value "$@";'*'"$2"'* ]] \
            || failures+=$'\n'"$name $flag: liest \"\$2\" ohne plugin_require_value davor"
        run_capture "$script" "$flag"
        [[ "$STATUS" -eq 1 && "$ERR" == *"[ERROR] [$tag] $flag braucht einen Wert."* && "$ERR" != *"unbound variable"* ]] \
            || failures+=$'\n'"$name $flag: Exit $STATUS, ${ERR:0:200}"
    done <<< "$flags"
    [[ $count -ge 30 ]] || fail_case "Nur $count Flags mit Wert gefunden, erwartet mindestens 30."
    [[ -z "$failures" ]] || fail_case "Flag ohne Wert nicht abgefangen:$failures"
}
