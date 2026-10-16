#!/usr/bin/env bash
# Tests für den Build-Vermerk (build.sh) und die Prüfung vor dem
# Veröffentlichen (core/check_publishable.sh): Nur ein vollständiger,
# validierter Build gegen das veröffentlichte Release wird ein Release, und
# nur unter einer höheren Version.
#
# Nutzt publish_mini_release aus test_previous_release.sh; run.sh sourct alle
# Testdateien in dieselbe Shell.

# Kopiert build.sh und core/ nach $TEST_TMP/etl, mit zwei Plugins: fishy
# liefert Entitäten (placement_priority 10, liefert aber keine Zeilen), extra
# ist optional. Stage 01b ist ein Stub, damit der Build kein Netz braucht.
# Jeder Build bricht danach in der Identitäts-Stage ab (keine Entitäten); der
# Build-Vermerk steht dann schon in der DB, build_validated nicht.
create_guarded_etl() {
    mkdir -p "$TEST_TMP/etl"
    cp "$ETL_DIR/build.sh" "$TEST_TMP/etl/"
    cp -R "$ETL_DIR/core" "$TEST_TMP/etl/core"
    printf '#!/usr/bin/env bash\n' > "$TEST_TMP/etl/core/seed_locale_place_mappings.sh"
    make_plugin "$TEST_TMP/etl/plugins" fishy 'placement_priority: 10'
    make_plugin "$TEST_TMP/etl/plugins" extra 'optional: true'
    publish_mini_release 7
}

guarded_build() {
    rm -f "$TEST_TMP/out.db"
    run_capture env DISCERE_RELEASE_MANIFEST_URL="file://$TEST_TMP/published/manifest.json" \
        "$TEST_TMP/etl/build.sh" --output "$TEST_TMP/out.db" --no-download "$@"
}

build_metadata() {
    sqlite3 -separator ' = ' "$TEST_TMP/out.db" "
        SELECT key, value FROM metadata WHERE key LIKE 'build_%' ORDER BY key;"
}

published_sha256() {
    jq -r '.sha256' "$TEST_TMP/published/manifest.json"
}

test_build_records_complete_build_against_published_release() {
    create_guarded_etl
    guarded_build
    assert_status 1
    assert_contains "$ERR" "Identitäts-Stage fehlgeschlagen"
    assert_eq "build_previous_sha256 = $(published_sha256)
build_previous_version = 7
build_scope = complete" "$(build_metadata)" "Build-Vermerk"
}

test_build_records_partial_build_as_incomplete() {
    create_guarded_etl
    guarded_build --plugin fishy
    assert_eq "build_previous_sha256 = $(published_sha256)
build_previous_version = 7
build_scope = incomplete: ohne Plugin extra" "$(build_metadata)" "Build-Vermerk"
    assert_contains "$ERR" "Kein vollständiger Build, nicht veröffentlichbar: ohne Plugin extra"
}

test_build_records_no_enrich_build_as_incomplete() {
    create_guarded_etl
    guarded_build --no-enrich
    assert_eq "build_scope = incomplete: ohne Plugin extra, --no-enrich" \
        "$(build_metadata | grep build_scope)" "Build-Vermerk"
}

test_build_records_accepted_species_loss_as_incomplete() {
    create_guarded_etl
    guarded_build --accept-species-loss fishy
    assert_eq "build_scope = incomplete: --accept-species-loss fishy" \
        "$(build_metadata | grep build_scope)" "Build-Vermerk"
}

# Ein Teilbuild lässt Quellen mit Entitäten absichtlich aus; deren Arten zählt
# die Identitäts-Stage nicht als Einbruch.
test_partial_build_accepts_loss_of_sources_it_skips() {
    create_guarded_etl
    make_plugin "$TEST_TMP/etl/plugins" other 'placement_priority: 20'
    guarded_build --plugin fishy
    assert_contains "$ERR" "Teilbuild: Rückgang angenommen für nicht ausgeführte Quellen: other"
    guarded_build
    assert_not_contains "$ERR" "Rückgang angenommen"
}

test_build_records_initial_build_as_incomplete() {
    create_guarded_etl
    guarded_build --initial
    assert_eq "build_scope = incomplete: --initial" "$(build_metadata)" "Build-Vermerk"
}

test_build_records_local_predecessor_as_incomplete() {
    create_guarded_etl
    guarded_build --previous-release "$DB"
    assert_eq "build_scope = incomplete: lokaler Vorgänger (--previous-release)" \
        "$(build_metadata)" "Build-Vermerk"
}

# Eine DB mit Build-Vermerk: vollständig und validiert gegen das Mini-Release
# v7, sofern die Argumente (key=value) nichts anderes sagen.
create_built_db() {
    local entry
    "$ETL_DIR/core/create_db.sh" --output "$TEST_TMP/built.db" > /dev/null 2>&1
    sqlite3 "$TEST_TMP/built.db" "INSERT INTO metadata (key, value) VALUES
        ('build_scope', 'complete'), ('build_validated', 'true'),
        ('build_previous_version', '7'), ('build_previous_sha256', '$(published_sha256)');"
    for entry in "$@"; do
        sqlite3 "$TEST_TMP/built.db" "UPDATE metadata SET value = '${entry#*=}' WHERE key = '${entry%%=*}';"
    done
}

# Prüft $TEST_TMP/built.db für die Version $1 (Vorgabe 8, eins über dem
# Mini-Release v7).
check_publishable() {
    run_capture "$ETL_DIR/core/check_publishable.sh" --db "$TEST_TMP/built.db" \
        --manifest "$TEST_TMP/published/manifest.json" --version "${1:-8}"
}

test_publishable_complete_validated_build_against_published_release() {
    publish_mini_release 7
    create_built_db
    check_publishable
    assert_status 0
    assert_contains "$ERR" "Vollständiger Build gegen das neueste veröffentlichte Release v7 — darf als v8 veröffentlicht werden."
}

test_publishable_rejects_incomplete_build() {
    publish_mini_release 7
    create_built_db 'build_scope=incomplete: ohne Plugin extra'
    check_publishable
    assert_status 1
    assert_contains "$ERR" "Kein vollständiger Build: incomplete: ohne Plugin extra"
}

test_publishable_rejects_build_that_failed_validation() {
    publish_mini_release 7
    create_built_db 'build_validated=false'
    check_publishable
    assert_status 1
    assert_contains "$ERR" "Der Build hat die Validierung nicht bestanden."
}

# Seit dem Build ist ein neueres Release erschienen: Seine Aliase fehlten.
test_publishable_rejects_build_against_outdated_predecessor() {
    publish_mini_release 7
    create_built_db
    jq '.version = 8 | .sha256 = "0000"' "$TEST_TMP/published/manifest.json" > "$TEST_TMP/manifest.json"
    mv "$TEST_TMP/manifest.json" "$TEST_TMP/published/manifest.json"
    check_publishable
    assert_status 1
    assert_contains "$ERR" "Gebaut gegen Vorgänger v7"
    assert_contains "$ERR" "das neueste veröffentlichte ist v8 (0000)"
}

# Nach einem Release mit Schemaversion 2 nennt die oberste Ebene weiter das
# ältere mit 1. Maßgeblich ist das neueste Release (v8 unter schemas["2"]):
# ein Build dagegen darf erscheinen, einer gegen die oberste Ebene (v7)
# nicht, und die Version muss über v8 liegen.
test_publishable_checks_against_newest_release_across_schemas() {
    publish_schema_2_release
    local newest_sha256
    newest_sha256="$(jq -r '.schemas["2"].sha256' "$TEST_TMP/published/manifest.json")"
    create_built_db build_previous_version=8 "build_previous_sha256=$newest_sha256"
    check_publishable 9
    assert_status 0
    assert_contains "$ERR" "Vollständiger Build gegen das neueste veröffentlichte Release v8 — darf als v9 veröffentlicht werden."
    check_publishable 8
    assert_status 1
    assert_contains "$ERR" "Version v8 ist nicht größer als die des neuesten veröffentlichten Releases v8."
    rm "$TEST_TMP/built.db"
    create_built_db build_previous_version=7 build_previous_sha256=sha-v7
    check_publishable 9
    assert_status 1
    assert_contains "$ERR" "Gebaut gegen Vorgänger v7 (sha-v7), das neueste veröffentlichte ist v8 ($newest_sha256)."
}

# Der ganze Weg mit einem Release unter schemas["2"]: build.sh vermerkt es
# als Vorgänger, und die Prüfung nimmt den Build an.
test_build_records_newest_release_across_schemas() {
    create_guarded_etl
    publish_schema_2_release
    guarded_build
    assert_contains "$(build_metadata)" "build_previous_version = 8" "Build-Vermerk"
    sqlite3 "$TEST_TMP/out.db" "INSERT INTO metadata (key, value) VALUES ('build_validated', 'true');"
    run_capture "$ETL_DIR/core/check_publishable.sh" --db "$TEST_TMP/out.db" \
        --manifest "$TEST_TMP/published/manifest.json" --version 9
    assert_status 0
}

# Die App lädt nur eine höhere Version als die installierte; dieselbe oder
# eine kleinere erreichte niemanden.
test_publishable_rejects_version_equal_to_published() {
    publish_mini_release 7
    create_built_db
    check_publishable 7
    assert_status 1
    assert_contains "$ERR" "Version v7 ist nicht größer als die des neuesten veröffentlichten Releases v7."
}

test_publishable_rejects_version_below_published() {
    publish_mini_release 7
    create_built_db
    check_publishable 6
    assert_status 1
    assert_contains "$ERR" "Version v6 ist nicht größer als die des neuesten veröffentlichten Releases v7."
}

test_publishable_rejects_non_numeric_version() {
    publish_mini_release 7
    create_built_db
    check_publishable 8a
    assert_status 1
    assert_contains "$ERR" "--version muss eine ganze Zahl sein, erhalten: '8a'."
}

test_publishable_rejects_db_without_build_record() {
    publish_mini_release 7
    "$ETL_DIR/core/create_db.sh" --output "$TEST_TMP/built.db" > /dev/null 2>&1
    check_publishable
    assert_status 1
    assert_contains "$ERR" "trägt keinen Build-Vermerk (build_scope)"
}

# Der ganze Weg: Vermerk aus build.sh, dann die Prüfung. Validiert wird hier
# von Hand, weil der Mini-Build die Mindestzahlen nicht erreicht.
test_publishable_accepts_record_written_by_build() {
    create_guarded_etl
    guarded_build
    sqlite3 "$TEST_TMP/out.db" "INSERT INTO metadata (key, value) VALUES ('build_validated', 'true');"
    run_capture "$ETL_DIR/core/check_publishable.sh" --db "$TEST_TMP/out.db" \
        --manifest "$TEST_TMP/published/manifest.json" --version 8
    assert_status 0
    guarded_build --plugin fishy
    sqlite3 "$TEST_TMP/out.db" "INSERT INTO metadata (key, value) VALUES ('build_validated', 'true');"
    run_capture "$ETL_DIR/core/check_publishable.sh" --db "$TEST_TMP/out.db" \
        --manifest "$TEST_TMP/published/manifest.json" --version 8
    assert_status 1
}

schema_version() {
    run_capture "$ETL_DIR/core/schema_version.sh" --db "$1"
}

# Die Schemaversion folgt aus der DB: IDs ohne Quelle mit Register sind 2,
# IDs mit Quelle ohne Register 1 (wie refdb-v2). Helfer aus test_identity.sh.
test_schema_version_follows_from_ids_and_register() {
    create_initial_release "$TEST_TMP/v2.db"
    schema_version "$TEST_TMP/v2.db"
    assert_status 0
    assert_eq "2" "$OUT" "mit Register"
    create_release_without_register "$TEST_TMP/v1.db"
    schema_version "$TEST_TMP/v1.db"
    assert_status 0
    assert_eq "1" "$OUT" "ohne Register"
}

# Ein Register neben IDs mit Quelle (die Ausgabe der Quellen vor der
# Identitäts-Stage) ist keine veröffentlichbare Form.
test_schema_version_rejects_mixed_form() {
    create_identity_build_db "$TEST_TMP/build.db"
    schema_version "$TEST_TMP/build.db"
    assert_status 1
    assert_contains "$ERR" "hat keine bekannte Schemaform: Register/Aliase 2 von 2, 0 IDs ohne Quelle, 4 mit Quelle, 4 Arten."
}

test_publish_release_takes_no_schema_version() {
    run_capture "$ETL_DIR/publish_release.sh" --version 3 --schema-version 1
    assert_status 1
    assert_contains "$ERR" "--schema-version gibt es nicht mehr: Die Schemaversion wird aus der DB abgeleitet"
}
