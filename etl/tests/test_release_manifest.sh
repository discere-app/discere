#!/usr/bin/env bash
# Tests für das Manifest der Referenz-DB: core/manifest_newest.sh (das
# neueste Release über alle Schemaversionen) und core/manifest_update.sh
# (ein neues Release eintragen).

# Ein Manifest wie auf discere-data, solange es nur die oberste Ebene gibt:
# v2 mit Schemaversion 1.
write_flat_manifest() {
    cat > "$TEST_TMP/manifest.json" << 'JSON'
{
  "version": 2,
  "schemaVersion": 1,
  "url": "https://example.invalid/refdb-v2.gz",
  "sha256": "sha-v2",
  "compressedSizeBytes": 200,
  "publishedAt": "2026-08-21T15:45:36Z"
}
JSON
}

manifest_newest() {
    run_capture "$ETL_DIR/core/manifest_newest.sh" --manifest "$TEST_TMP/manifest.json"
}

# Trägt v<version> mit Schemaversion <schema> ein.
manifest_update() {
    local schema="$1" version="$2"
    run_capture "$ETL_DIR/core/manifest_update.sh" --manifest "$TEST_TMP/manifest.json" \
        --schema "$schema" --version "$version" \
        --url "https://example.invalid/refdb-v$version.gz" --sha256 "sha-v$version" \
        --size "${version}00" --published-at "2026-10-1${version}T00:00:00Z"
}

manifest_field() {
    jq -c "$1" "$TEST_TMP/manifest.json"
}

test_manifest_newest_without_schemas_is_top_level() {
    write_flat_manifest
    manifest_newest
    assert_status 0
    assert_eq "2 1 sha-v2" "$(jq -r '"\(.version) \(.schemaVersion) \(.sha256)"' <<< "$OUT")" "Release"
}

test_manifest_newest_takes_highest_version_across_schemas() {
    printf '%s' '{"version": 2, "schemaVersion": 1, "url": "u2", "sha256": "sha-v2",
        "schemas": {"1": {"version": 2, "url": "u2", "sha256": "sha-v2"},
                    "2": {"version": 3, "url": "u3", "sha256": "sha-v3"}}}' \
        > "$TEST_TMP/manifest.json"
    manifest_newest
    assert_status 0
    assert_eq '{"version":3,"url":"u3","sha256":"sha-v3","schemaVersion":2}' "$OUT" "Release"
}

# version zählt über alle Schemas: Ein späteres Release mit Schemaversion 1
# ist neuer als ein früheres mit 2.
test_manifest_newest_prefers_version_over_schema() {
    printf '%s' '{"version": 4, "schemaVersion": 1, "url": "u4", "sha256": "sha-v4",
        "schemas": {"1": {"version": 4, "url": "u4", "sha256": "sha-v4"},
                    "2": {"version": 3, "url": "u3", "sha256": "sha-v3"}}}' \
        > "$TEST_TMP/manifest.json"
    manifest_newest
    assert_status 0
    assert_eq "4 1" "$(jq -r '"\(.version) \(.schemaVersion)"' <<< "$OUT")" "Release"
}

test_manifest_newest_rejects_malformed_entries() {
    printf '%s' '{"version": 2, "schemaVersion": 1, "url": "u2", "sha256": "s",
        "schemas": {"zwei": {"version": 3, "url": "u3", "sha256": "s"}}}' > "$TEST_TMP/manifest.json"
    manifest_newest
    assert_status 1
    assert_contains "$ERR" 'Schlüssel "zwei" unter schemas ist keine ganze Zahl'
    printf '%s' '{"schemas": {"2": {"version": 3, "url": "u3"}}}' > "$TEST_TMP/manifest.json"
    manifest_newest
    assert_status 1
    assert_contains "$ERR" 'schemas["2"]: sha256 fehlt'
    printf '%s' '{}' > "$TEST_TMP/manifest.json"
    manifest_newest
    assert_status 1
    assert_contains "$ERR" "kein Release"
}

# Ein Release mit Schemaversion 2 erreicht nur Apps, die "schemas" lesen;
# die oberste Ebene bleibt für die übrigen beim Release mit 1.
test_manifest_update_schema_2_keeps_top_level() {
    write_flat_manifest
    local top_level_before
    top_level_before="$(manifest_field 'del(.schemas)')"
    manifest_update 2 3
    assert_status 0
    assert_eq "$top_level_before" "$(manifest_field 'del(.schemas)')" "oberste Ebene"
    assert_eq '{"version":3,"url":"https://example.invalid/refdb-v3.gz","sha256":"sha-v3","compressedSizeBytes":300,"publishedAt":"2026-10-13T00:00:00Z"}' \
        "$(manifest_field '.schemas["2"]')" "schemas[2]"
}

# Ohne "schemas" wird die bisherige oberste Ebene schemas["1"], damit beide
# Darstellungen übereinstimmen.
test_manifest_update_moves_flat_top_level_into_schemas() {
    write_flat_manifest
    manifest_update 2 3
    assert_status 0
    assert_eq '{"version":2,"url":"https://example.invalid/refdb-v2.gz","sha256":"sha-v2","compressedSizeBytes":200,"publishedAt":"2026-08-21T15:45:36Z"}' \
        "$(manifest_field '.schemas["1"]')" "schemas[1]"
    assert_eq '["1","2"]' "$(manifest_field '.schemas | keys_unsorted')" "Schlüssel"
}

test_manifest_update_schema_1_updates_both_places() {
    write_flat_manifest
    manifest_update 2 3
    manifest_update 1 4
    assert_status 0
    local expected='{"version":4,"url":"https://example.invalid/refdb-v4.gz","sha256":"sha-v4","compressedSizeBytes":400,"publishedAt":"2026-10-14T00:00:00Z"}'
    assert_eq "$expected" "$(manifest_field '.schemas["1"]')" "schemas[1]"
    assert_eq "$expected" "$(manifest_field 'del(.schemas, .schemaVersion)')" "oberste Ebene"
    assert_eq "1" "$(manifest_field '.schemaVersion')" "schemaVersion oben"
    assert_eq "3" "$(manifest_field '.schemas["2"].version')" "schemas[2] bleibt"
}

test_manifest_update_keeps_other_entries() {
    write_flat_manifest
    manifest_update 2 3
    manifest_update 3 5
    manifest_update 2 6
    assert_status 0
    assert_eq '["1","2","3"]' "$(manifest_field '.schemas | keys_unsorted')" "Schlüssel"
    assert_eq "2 6 5" "$(manifest_field '[.schemas[] | .version] | map(tostring) | join(" ")' | tr -d '"')" "Versionen"
    assert_eq "2" "$(manifest_field '.version')" "oberste Ebene"
}

# Fortschreiben und Auswählen passen zusammen: Nach einem Release mit
# Schemaversion 2 ist es das neueste, obwohl oben weiter v2 steht.
test_manifest_update_then_newest_finds_schema_2_release() {
    write_flat_manifest
    manifest_update 2 3
    manifest_newest
    assert_status 0
    assert_eq "3 2 sha-v3" "$(jq -r '"\(.version) \(.schemaVersion) \(.sha256)"' <<< "$OUT")" "Release"
}

test_manifest_update_rejects_bad_arguments() {
    write_flat_manifest
    run_capture "$ETL_DIR/core/manifest_update.sh" --manifest "$TEST_TMP/manifest.json" \
        --schema zwei --version 3 --url u --sha256 s --size 1 --published-at t
    assert_status 1
    assert_contains "$ERR" "--schema muss eine ganze Zahl sein, erhalten: 'zwei'."
    run_capture "$ETL_DIR/core/manifest_update.sh" --manifest "$TEST_TMP/missing.json" \
        --schema 2 --version 3 --url u --sha256 s --size 1 --published-at t
    assert_status 1
    assert_contains "$ERR" "Manifest nicht gefunden"
}
