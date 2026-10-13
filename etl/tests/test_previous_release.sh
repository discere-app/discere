#!/usr/bin/env bash
# Tests für core/previous_release.sh und den Abbruch von build.sh ohne
# Vorgänger — ohne Netzwerk: Manifest und Release liegen als file://-URLs vor.

# Legt ein Release aus der Mini-DB unter $TEST_TMP/published an, samt
# Manifest mit Version <version> und Prüfsumme <sha256> (Default: die
# richtige).
publish_mini_release() {
    local version="$1"
    local sha256="${2:-}"
    create_mini_reference_db
    mkdir -p "$TEST_TMP/published"
    gzip --stdout "$DB" > "$TEST_TMP/published/discere_reference.db.gz"
    if [[ -z "$sha256" ]]; then
        sha256="$(shasum -a 256 "$TEST_TMP/published/discere_reference.db.gz" | cut -d ' ' -f 1)"
    fi
    printf '{"version": %s, "schemaVersion": 2, "url": "file://%s", "sha256": "%s"}\n' \
        "$version" "$TEST_TMP/published/discere_reference.db.gz" "$sha256" \
        > "$TEST_TMP/published/manifest.json"
}

previous_release() {
    run_capture "$ETL_DIR/core/previous_release.sh" --cache-dir "$TEST_TMP/cache" \
        --manifest-url "file://$TEST_TMP/published/manifest.json" "$@"
}

test_previous_release_downloads_verifies_and_caches() {
    publish_mini_release 7
    previous_release
    assert_status 0
    assert_eq "$TEST_TMP/cache/v7/discere_reference.db" "$OUT" "Pfad"
    assert_contains "$ERR" "Vorgänger v7 zwischengespeichert"
    assert_eq "Amphiprion" "$(sqlite3 "$OUT" "SELECT name FROM genera;")" "Inhalt"
    assert_eq "delete" "$(sqlite3 "$OUT" "PRAGMA journal_mode;")" "Journal"
    rm "$TEST_TMP/published/discere_reference.db.gz"
    previous_release
    assert_status 0
    assert_contains "$ERR" "Vorgänger v7 aus dem Cache"
}

test_previous_release_rejects_wrong_checksum() {
    publish_mini_release 7 0000
    previous_release
    assert_status 1
    assert_contains "$ERR" "Prüfsumme falsch"
    assert_eq "" "$(ls "$TEST_TMP/cache" 2> /dev/null || true)" "Cache"
}

test_previous_release_without_manifest_fails() {
    previous_release
    assert_status 1
    assert_contains "$ERR" "Manifest nicht lesbar"
}

test_previous_release_takes_local_path() {
    create_mini_reference_db
    previous_release --path "$DB"
    assert_status 0
    assert_eq "$DB" "$OUT" "Pfad"
    echo "keine Datenbank" > "$TEST_TMP/broken.db"
    previous_release --path "$TEST_TMP/broken.db"
    assert_status 1
    assert_contains "$ERR" "Keine lesbare Referenz-DB"
}

# Ohne Vorgänger bricht der Build vor Stage 01 ab; eine bestehende DB bleibt.
test_build_without_previous_release_keeps_existing_db() {
    echo "bestehende DB" > "$TEST_TMP/existing.db"
    run_capture env DISCERE_RELEASE_MANIFEST_URL="file://$TEST_TMP/missing.json" \
        "$ETL_DIR/build.sh" --output "$TEST_TMP/existing.db" --force --plugin curated
    assert_status 1
    assert_contains "$ERR" "Kein gültiges Vorgänger-Release — Build abgebrochen"
    assert_not_contains "$ERR" "Stage 01:"
    assert_eq "bestehende DB" "$(cat "$TEST_TMP/existing.db")" "bestehende DB"
}

test_build_rejects_initial_with_previous_release() {
    run_capture "$ETL_DIR/build.sh" --output "$TEST_TMP/out.db" --initial --previous-release "$TEST_TMP/x.db"
    assert_status 1
    assert_contains "$ERR" "--initial und --previous-release schließen sich aus."
    [[ ! -e "$TEST_TMP/out.db" ]] || fail_case "DB angelegt"
}
