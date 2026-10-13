#!/usr/bin/env bash
# =============================================================================
# lib.sh — Helfer für die ETL-Tests (wird von run.sh gesourced)
#
# Ein Fall schlägt fehl, sobald eine Prüfung die Subshell des Falls mit
# exit 1 beendet. Prüfungen deshalb nicht in $(...) aufrufen.
# =============================================================================

fail_case() {
    echo "$*" >&2
    exit 1
}

# Führt ein Kommando aus und hält stdout, stderr und Exit-Code in OUT, ERR und
# STATUS fest, ohne dass ein Fehlschlag den Fall beendet.
run_capture() {
    set +e
    "$@" > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr"
    STATUS=$?
    set -e
    OUT="$(cat "$TEST_TMP/stdout")"
    ERR="$(cat "$TEST_TMP/stderr")"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="${3:-Wert}"
    [[ "$actual" == "$expected" ]] \
        || fail_case "$label: erwartet [$expected], erhalten [$actual]"
}

assert_status() {
    local expected="$1"
    [[ "$STATUS" -eq "$expected" ]] \
        || fail_case "Exit-Code: erwartet $expected, erhalten $STATUS"$'\n'"stdout: $OUT"$'\n'"stderr: $ERR"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] \
        || fail_case "erwartet enthalten: [$needle]"$'\n'"in: $haystack"
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" != *"$needle"* ]] \
        || fail_case "nicht erwartet: [$needle]"$'\n'"in: $haystack"
}

# Legt ein Plugin an, das validate_plugin.sh besteht. Weitere Argumente
# werden als Zeilen an plugin.yaml angehängt.
make_plugin() {
    local plugins_dir="$1"
    local name="$2"
    shift 2
    mkdir -p "$plugins_dir/$name/sql"
    printf 'name: %s\nversion: 1\nsource: %s\n' "$name" "$name" > "$plugins_dir/$name/plugin.yaml"
    if [[ $# -gt 0 ]]; then
        printf '%s\n' "$@" >> "$plugins_dir/$name/plugin.yaml"
    fi
    : > "$plugins_dir/$name/sql/source.sql"
    printf '#!/usr/bin/env bash\n' > "$plugins_dir/$name/import.sh"
    chmod +x "$plugins_dir/$name/import.sh"
}

# Legt unter $TEST_TMP/ref.db eine Referenz-DB mit Schema und einer kleinen
# Taxonomie für Abgleich und iNaturalist an:
#
#   Klasse Teleostei › Ordnung Ovalentaria › Familie Pomacentridae
#   › Gattung Amphiprion mit den Arten
#     fishbase_species:1  Amphiprion ocellaris  Synonym Amphiprion bicolor
#     fishbase_species:2  Amphiprion percula    Synonym Amphiprion communis
#     fishbase_species:3  Amphiprion clarkii    Synonym Amphiprion communis
#     fishbase_species:4  Amphiprion vetus      deprecated
#     fishbase_species:5  Amphiprion frenatus   Synonym Amphiprion melanopus
#     fishbase_species:6  Amphiprion ephippium  Synonym Amphiprion frenatus
#   und die Gattung Pomacentridae nicht — den Namen gibt es nur als Familie.
create_mini_reference_db() {
    DB="$TEST_TMP/ref.db"
    "$ETL_DIR/core/create_db.sh" --output "$DB" > /dev/null 2>&1
    sqlite3 "$DB" << 'SQL'
INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
    ('discere:fishbase_class:7', '7', 'fishbase', 'Teleostei', 'Actinopterygii');
INSERT INTO orders (id, external_id, external_source, name, class) VALUES
    ('discere:fishbase_order:1', '1', 'fishbase', 'Ovalentaria', 'discere:fishbase_class:7');
INSERT INTO families (id, external_id, external_source, name, "order") VALUES
    ('discere:fishbase_family:1', '1', 'fishbase', 'Pomacentridae', 'discere:fishbase_order:1');
INSERT INTO genera (id, external_id, external_source, name, family) VALUES
    ('discere:fishbase_genus:1', '1', 'fishbase', 'Amphiprion', 'discere:fishbase_family:1');
INSERT INTO species (id, external_id, external_source, name, genus, status) VALUES
    ('discere:fishbase_species:1', '1', 'fishbase', 'ocellaris', 'discere:fishbase_genus:1', 'active'),
    ('discere:fishbase_species:2', '2', 'fishbase', 'percula',   'discere:fishbase_genus:1', 'active'),
    ('discere:fishbase_species:3', '3', 'fishbase', 'clarkii',   'discere:fishbase_genus:1', 'active'),
    ('discere:fishbase_species:4', '4', 'fishbase', 'vetus',     'discere:fishbase_genus:1', 'deprecated'),
    ('discere:fishbase_species:5', '5', 'fishbase', 'frenatus',  'discere:fishbase_genus:1', 'active'),
    ('discere:fishbase_species:6', '6', 'fishbase', 'ephippium', 'discere:fishbase_genus:1', 'active');
INSERT INTO species_scientific_names (species_id, name, normalized_name, name_status, source, is_preferred) VALUES
    ('discere:fishbase_species:1', 'Amphiprion ocellaris', 'amphiprion ocellaris', 'valid',   'fishbase', 1),
    ('discere:fishbase_species:1', 'Amphiprion bicolor',   'amphiprion bicolor',   'synonym', 'fishbase', 0),
    ('discere:fishbase_species:2', 'Amphiprion percula',   'amphiprion percula',   'valid',   'fishbase', 1),
    ('discere:fishbase_species:2', 'Amphiprion communis',  'amphiprion communis',  'synonym', 'fishbase', 0),
    ('discere:fishbase_species:3', 'Amphiprion clarkii',   'amphiprion clarkii',   'valid',   'fishbase', 1),
    ('discere:fishbase_species:3', 'Amphiprion communis',  'amphiprion communis',  'synonym', 'fishbase', 0),
    ('discere:fishbase_species:4', 'Amphiprion vetus',     'amphiprion vetus',     'valid',   'fishbase', 1),
    ('discere:fishbase_species:5', 'Amphiprion frenatus',  'amphiprion frenatus',  'valid',   'fishbase', 1),
    ('discere:fishbase_species:5', 'Amphiprion melanopus', 'amphiprion melanopus', 'synonym', 'fishbase', 0),
    ('discere:fishbase_species:6', 'Amphiprion ephippium', 'amphiprion ephippium', 'valid',   'fishbase', 1),
    ('discere:fishbase_species:6', 'Amphiprion frenatus',  'amphiprion frenatus',  'synonym', 'fishbase', 0);
SQL
}
