#!/usr/bin/env bash
# Tests für die Aufruf-Schnittstelle der Plugins: den gemeinsamen Parser
# plugin_parse_args (core/plugin_api.sh) und die Regel, dass ein lokaler Pfad
# nur gelesen wird — bei fishbase und sealifebase weder geladen noch gelöscht.

# Legt unter $TEST_TMP/plugins/probe ein Plugin an, das plugin_parse_args mit
# dem eigenen Flag --probe-dir aufruft, den Pfad an
# plugin_skip_download_for_local_path gibt und die Ergebnisse auf stdout
# ausgibt.
create_probe_plugin() {
    PROBE="$TEST_TMP/plugins/probe/import.sh"
    make_plugin "$TEST_TMP/plugins" probe
    cat > "$PROBE" << IMPORT
#!/usr/bin/env bash
# =============================================================================
# Hilfe des Probe-Plugins
# =============================================================================
# nach dem Kopf
set -Eeuo pipefail
source "$ETL_DIR/core/plugin_api.sh"
plugin_init "\$(cd "\$(dirname "\$0")" && pwd)"
PROBE_DIR=""
plugin_parse_args --probe-dir=PROBE_DIR -- "\$@"
plugin_skip_download_for_local_path "\$PROBE_DIR"
echo "db=\$DB_PATH download=\$DOWNLOAD keep=\$KEEP_FILES probe_dir=\$PROBE_DIR"
IMPORT
}

test_plugin_args_default_to_download_without_keep() {
    create_probe_plugin
    run_capture env -u DB_PATH "$PROBE"
    assert_status 0
    assert_eq "db= download=true keep=false probe_dir=" "$OUT" "Ergebnis"
}

test_plugin_args_read_no_download_and_keep() {
    create_probe_plugin
    run_capture "$PROBE" --no-download --keep
    assert_status 0
    assert_contains "$OUT" "download=false keep=true "
}

test_plugin_args_take_db_from_flag_over_environment() {
    create_probe_plugin
    run_capture env DB_PATH="$TEST_TMP/env.db" "$PROBE"
    assert_status 0
    assert_contains "$OUT" "db=$TEST_TMP/env.db "
    run_capture env DB_PATH="$TEST_TMP/env.db" "$PROBE" --db "$TEST_TMP/flag.db"
    assert_status 0
    assert_contains "$OUT" "db=$TEST_TMP/flag.db "
}

# Das eigene Flag kommt beim Plugin an; als lokaler Pfad schaltet es den
# Download ab.
test_plugin_args_hand_own_flags_to_the_plugin() {
    create_probe_plugin
    run_capture "$PROBE" --probe-dir "$TEST_TMP/data" --keep
    assert_status 0
    assert_contains "$OUT" "download=false keep=true probe_dir=$TEST_TMP/data"
}

test_plugin_args_abort_on_unknown_flag() {
    create_probe_plugin
    run_capture "$PROBE" --no-dowload
    assert_status 1
    assert_contains "$ERR" "[ERROR] [probe] Unbekanntes Argument: --no-dowload (siehe --help)"
    assert_eq "" "$OUT" "stdout"
}

test_plugin_args_abort_on_flag_without_value() {
    create_probe_plugin
    run_capture "$PROBE" --db
    assert_status 1
    assert_contains "$ERR" "[ERROR] [probe] --db braucht einen Wert."
    run_capture "$PROBE" --probe-dir
    assert_status 1
    assert_contains "$ERR" "[ERROR] [probe] --probe-dir braucht einen Wert."
}

test_plugin_args_print_header_as_help() {
    create_probe_plugin
    run_capture "$PROBE" --help
    assert_status 0
    assert_eq "Hilfe des Probe-Plugins" "$OUT" "Hilfe"
}

# Führt plugins/<plugin>/import.sh gegen ein Verzeichnis mit einer fremden
# Datei und ohne Parquets aus, angegeben über <flag> oder <variable>
# (Aufruf: <plugin> flag <flag> | <plugin> env <variable>), mit curl als
# Stub (stub_curl).
run_plugin_with_local_dir() {
    local plugin="$1" how="$2" name="$3"
    LOCAL_DIR="$TEST_TMP/own parquet"
    mkdir -p "$LOCAL_DIR"
    printf 'eigene Datei\n' > "$LOCAL_DIR/notes.txt"
    : > "$TEST_TMP/ref.db"
    stub_curl
    if [[ "$how" == flag ]]; then
        run_capture "$ETL_DIR/plugins/$plugin/import.sh" --db "$TEST_TMP/ref.db" "$name" "$LOCAL_DIR"
    else
        run_capture env "$name=$LOCAL_DIR" "$ETL_DIR/plugins/$plugin/import.sh" --db "$TEST_TMP/ref.db"
    fi
}

# Das Plugin liest nur: Es bricht an den fehlenden Parquets ab, statt zu laden,
# und das Verzeichnis bleibt samt Datei stehen.
assert_local_dir_only_read() {
    assert_status 1
    assert_contains "$ERR" "Fehlende Parquets: classes.parquet"
    assert_curl_not_called
    assert_eq "eigene Datei" "$(cat "$LOCAL_DIR/notes.txt" 2> /dev/null)" "Datei im lokalen Pfad"
}

test_plugin_args_fishbase_only_reads_dir_given_by_flag() {
    run_plugin_with_local_dir fishbase flag --fishbase-dir
    assert_local_dir_only_read
}

test_plugin_args_fishbase_only_reads_dir_given_by_environment() {
    run_plugin_with_local_dir fishbase env FISHBASE_DIR
    assert_local_dir_only_read
}

test_plugin_args_sealifebase_only_reads_dir_given_by_flag() {
    run_plugin_with_local_dir sealifebase flag --slb-dir
    assert_local_dir_only_read
}

test_plugin_args_sealifebase_only_reads_dir_given_by_environment() {
    run_plugin_with_local_dir sealifebase env SLB_DIR
    assert_local_dir_only_read
}
