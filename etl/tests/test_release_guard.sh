#!/usr/bin/env bash
# Tests für den Build-Vermerk (build.sh) und die Prüfung vor dem
# Veröffentlichen (core/check_publishable.sh): Nur ein vollständiger,
# validierter Build gegen das veröffentlichte Release wird ein Release.
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

check_publishable() {
    run_capture "$ETL_DIR/core/check_publishable.sh" --db "$TEST_TMP/built.db" \
        --manifest "$TEST_TMP/published/manifest.json"
}

test_publishable_complete_validated_build_against_published_release() {
    publish_mini_release 7
    create_built_db
    check_publishable
    assert_status 0
    assert_contains "$ERR" "Vollständiger Build gegen das veröffentlichte Release v7 — darf veröffentlicht werden."
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
    assert_contains "$ERR" "veröffentlicht ist v8 (0000)"
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
        --manifest "$TEST_TMP/published/manifest.json"
    assert_status 0
    guarded_build --plugin fishy
    sqlite3 "$TEST_TMP/out.db" "INSERT INTO metadata (key, value) VALUES ('build_validated', 'true');"
    run_capture "$ETL_DIR/core/check_publishable.sh" --db "$TEST_TMP/out.db" \
        --manifest "$TEST_TMP/published/manifest.json"
    assert_status 1
}
