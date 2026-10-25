#!/usr/bin/env bash
# Tests dafür, was build.sh an die Plugins weitergibt: nur die gemeinsamen
# Flags der Aufruf-Schnittstelle, an die Quellen mit Entitäten (Stage 02) wie
# an die ergänzenden (Stage 02c), dazu seine Umgebung; und dass ein
# unbekanntes Argument abbricht, bevor eine DB angefasst wird.

# Kopiert build.sh und core/ nach $TEST_TMP/flags-etl, ohne Netz: Stage 01b
# und core/validate.sh sind Stubs. Jedes Plugin schreibt seine Argumente,
# eins je Zeile, nach $TEST_TMP/<plugin>.args, addon dazu den Wert von
# FISHBASE_DIR nach $TEST_TMP/addon.env. Plugins:
#   source   liefert Entitäten (placement_priority 10): eine Art samt Kette,
#            damit die Identitäts-Stage und mit ihr Stage 02c durchläuft
#   addon    ergänzt, hängt von source ab
# Gebaut wird mit --initial, ohne Vorgänger.
create_flag_recording_etl() {
    local etl="$TEST_TMP/flags-etl"
    mkdir -p "$etl"
    cp "$ETL_DIR/build.sh" "$etl/"
    cp -R "$ETL_DIR/core" "$etl/core"
    printf '#!/usr/bin/env bash\n' > "$etl/core/seed_locale_place_mappings.sh"
    printf '#!/usr/bin/env bash\n' > "$etl/core/validate.sh"
    make_plugin "$etl/plugins" source 'placement_priority: 10'
    make_plugin "$etl/plugins" addon 'depends_on_sources:' '  - source'
    cat > "$etl/plugins/source/import.sh" << IMPORT
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEST_TMP/source.args"
sqlite3 "\$2" << 'SQL'
INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
    ('discere:source_class:1', '1', 'source', 'Teleostei', 'Actinopterygii');
INSERT INTO orders (id, external_id, external_source, name, class) VALUES
    ('discere:source_order:1', '1', 'source', 'Ovalentaria', 'discere:source_class:1');
INSERT INTO families (id, external_id, external_source, name, "order") VALUES
    ('discere:source_family:1', '1', 'source', 'Pomacentridae', 'discere:source_order:1');
INSERT INTO genera (id, external_id, external_source, name, family) VALUES
    ('discere:source_genus:1', '1', 'source', 'Amphiprion', 'discere:source_family:1');
INSERT INTO species (id, external_id, external_source, name, genus, status) VALUES
    ('discere:source_species:1', '1', 'source', 'ocellaris', 'discere:source_genus:1', 'active');
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:source_species:1', 'Amphiprion ocellaris', 'amphiprion ocellaris', 'valid', 'source', 1);
SQL
IMPORT
    cat > "$etl/plugins/addon/import.sh" << IMPORT
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEST_TMP/addon.args"
printf '%s\n' "\${FISHBASE_DIR-}" > "$TEST_TMP/addon.env"
IMPORT
}

# Baut mit den übergebenen Flags bis zum Ende und setzt SOURCE_ARGS und
# ADDON_ARGS auf die Argumente der beiden Plugins, durch Leerzeichen getrennt.
build_and_capture_plugin_args() {
    run_capture "$TEST_TMP/flags-etl/build.sh" --output "$TEST_TMP/out.db" --initial "$@"
    assert_status 0
    assert_contains "$ERR" "=== Build abgeschlossen"
    SOURCE_ARGS="$(tr '\n' ' ' < "$TEST_TMP/source.args")"
    ADDON_ARGS="$(tr '\n' ' ' < "$TEST_TMP/addon.args")"
}

test_build_flags_pass_only_db_by_default() {
    create_flag_recording_etl
    build_and_capture_plugin_args
    assert_eq "--db $TEST_TMP/out.db " "$SOURCE_ARGS" "Argumente source"
    assert_eq "--db $TEST_TMP/out.db " "$ADDON_ARGS" "Argumente addon"
}

test_build_flags_pass_no_download_to_every_plugin() {
    create_flag_recording_etl
    build_and_capture_plugin_args --no-download
    assert_eq "--db $TEST_TMP/out.db --no-download " "$SOURCE_ARGS" "Argumente source"
    assert_eq "--db $TEST_TMP/out.db --no-download " "$ADDON_ARGS" "Argumente addon"
}

test_build_flags_pass_keep_to_every_plugin() {
    create_flag_recording_etl
    build_and_capture_plugin_args --keep
    assert_eq "--db $TEST_TMP/out.db --keep " "$SOURCE_ARGS" "Argumente source"
    assert_eq "--db $TEST_TMP/out.db --keep " "$ADDON_ARGS" "Argumente addon"
}

# Eigene Einstellungen eines Plugins erreichen es über die Umgebung, nicht
# über build.sh-Flags.
test_build_flags_leave_plugin_settings_to_the_environment() {
    create_flag_recording_etl
    FISHBASE_DIR="$TEST_TMP/parquet" build_and_capture_plugin_args
    assert_eq "$TEST_TMP/parquet" "$(cat "$TEST_TMP/addon.env")" "FISHBASE_DIR im Plugin"
    assert_eq "--db $TEST_TMP/out.db " "$ADDON_ARGS" "Argumente addon"
}

# Ein Tippfehler darf nicht still zum Default werden: Mit --no-dowload
# würden die Plugins laden und danach löschen.
test_build_flags_abort_on_unknown_argument_before_touching_the_db() {
    create_flag_recording_etl
    printf 'bestehend\n' > "$TEST_TMP/out.db"
    run_capture "$TEST_TMP/flags-etl/build.sh" --output "$TEST_TMP/out.db" --initial --force --no-dowload
    assert_status 1
    assert_contains "$ERR" "[ERROR] [build] Unbekanntes Argument: --no-dowload"
    assert_eq "bestehend" "$(cat "$TEST_TMP/out.db")" "bestehende DB"
    [[ ! -e "$TEST_TMP/source.args" && ! -e "$TEST_TMP/addon.args" ]] \
        || fail_case "Plugins liefen trotz Abbruch."
}

# Herunterladen ist der Default; Version und lokale Pfade sind Sache der
# Plugins und ihrer Umgebungsvariablen.
test_build_flags_reject_download_and_plugin_flags() {
    create_flag_recording_etl
    local flag
    for flag in --download --version --fishbase-dir; do
        run_capture "$TEST_TMP/flags-etl/build.sh" --output "$TEST_TMP/out.db" --initial "$flag" x
        assert_status 1
        assert_contains "$ERR" "[ERROR] [build] Unbekanntes Argument: $flag"
    done
    [[ ! -e "$TEST_TMP/out.db" ]] || fail_case "DB trotz Abbruch angelegt."
}

test_build_flags_abort_on_flag_without_value() {
    create_flag_recording_etl
    run_capture "$TEST_TMP/flags-etl/build.sh" --initial --output
    assert_status 1
    assert_contains "$ERR" "[ERROR] [build] --output braucht einen Wert."
    assert_not_contains "$ERR" "unbound variable"
}
