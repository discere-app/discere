#!/usr/bin/env bash
# Tests für den SQLite-Import der Plugins FishBase und SeaLifeBase
# (import_to_sqlite in plugins/<plugin>/import.sh): Das Plugin läuft gegen die
# Mini-Quellen aus den Tests der Exporte und eine DB aus core/create_db.sh.
#
# Das Plugin läuft als Kopie unter $TEST_TMP/etl: Die Ausnahmen ohne Ordnung
# von SeaLifeBase nennen FamCodes, die die Mini-Quelle nicht führt, und
# brächen den Export ab; die Kopie bekommt eine leere Liste. Ein Fall kann so
# auch die source.sql der Kopie ändern.

# shellcheck source=./test_fishbase_export.sh
source "$TESTS_DIR/test_fishbase_export.sh"
# shellcheck source=./test_sealifebase_export.sh
source "$TESTS_DIR/test_sealifebase_export.sh"

# Legt die Mini-Quelle von <plugin>, die Kopie des Plugins und die DB an. In
# der DB stehen schon Daten der Quelle: ein Bild, das das Aufräumen löscht,
# und ihre Quellenangabe in der Version „alt“.
setup_parquet_import() {
    PLUGIN="$1"
    case "$PLUGIN" in
        fishbase)    create_fishbase_parquets ;;
        sealifebase) create_sealifebase_parquets ;;
    esac
    mkdir -p "$TEST_TMP/etl/plugins"
    cp -R "$ETL_DIR/core" "$TEST_TMP/etl/core"
    cp -R "$ETL_DIR/plugins/$PLUGIN" "$TEST_TMP/etl/plugins/$PLUGIN"
    if [[ "$PLUGIN" == sealifebase ]]; then
        echo "famcode,family,reason,evidence" > "$TEST_TMP/etl/plugins/sealifebase/data/family_order_exceptions.csv"
    fi
    DB="$TEST_TMP/ref.db"
    "$TEST_TMP/etl/core/create_db.sh" --output "$DB" > /dev/null 2>&1
    sqlite3 -bail "$DB" << SQL
INSERT INTO pictures (id, picname, origin) VALUES
    ('discere:${PLUGIN}_picture:1', 'alt.jpg', '$PLUGIN');
INSERT INTO sources (id, name, category, citation, url, license_key, version) VALUES
    ('$PLUGIN', 'Alt', 'alt', 'alt', 'alt', 'alt', 'alt');
INSERT INTO metadata (key, value) VALUES ('$PLUGIN', 'alt');
SQL
}

# Die Klasse und die Ordnung, die die Quelle exportiert, stehen schon unter
# derselben ID, aber einer fremden Quelle in der DB — das Aufräumen lässt sie
# stehen, der Import der Klasse scheitert an ihr, und ohne Abbruch dort
# scheiterte auch der der Ordnung.
add_conflicting_taxa() {
    local class_id order_id
    case "$PLUGIN" in
        fishbase)
            class_id='discere:fishbase_class:7'
            order_id='discere:fishbase_order:1' ;;
        sealifebase)
            class_id='discere:sealifebase_class:1'
            order_id='discere:sealifebase_order:1' ;;
    esac
    sqlite3 -bail "$DB" << SQL
INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
    ('$class_id', '1', 'curated', 'Fremdklasse', 'Fremd');
INSERT INTO orders (id, external_id, external_source, name, class) VALUES
    ('$order_id', '1', 'curated', 'Fremdordnung', '$class_id');
SQL
}

run_parquet_import() {
    local dir_flag
    case "$PLUGIN" in
        fishbase)    dir_flag=--fishbase-dir ;;
        sealifebase) dir_flag=--slb-dir ;;
    esac
    run_capture "$TEST_TMP/etl/plugins/$PLUGIN/import.sh" --db "$DB" "$dir_flag" "$TEST_TMP/$PLUGIN"
}

# Die Daten der Quelle aus setup_parquet_import stehen unverändert in der DB.
assert_source_data_unchanged() {
    assert_eq "alt.jpg" "$(sqlite3 "$DB" "SELECT picname FROM pictures WHERE origin = '$PLUGIN';")" \
        "Bilder der Quelle"
    assert_eq "alt" "$(sqlite3 "$DB" "SELECT version FROM sources WHERE id = '$PLUGIN';")" \
        "Version in sources"
    assert_eq "alt" "$(sqlite3 "$DB" "SELECT value FROM metadata WHERE key = '$PLUGIN';")" \
        "Version in metadata"
}

# Scheitert eine Anweisung, bricht sqlite3 dort ab: keine Art der Quelle in der
# DB, und im Log steht nur der Fehler dieser Anweisung.
assert_import_stops_at_failing_statement() {
    setup_parquet_import "$1"
    add_conflicting_taxa
    run_parquet_import
    assert_status 1
    assert_eq 0 "$(sqlite3 "$DB" "SELECT COUNT(*) FROM species WHERE external_source = '$PLUGIN';")" \
        "Arten der Quelle nach dem Abbruch"
    assert_contains "$ERR" "UNIQUE constraint failed: classes.id"
    assert_eq 1 "$(grep -c 'error near line' <<< "$ERR")" "sqlite-Fehler im Log"
    assert_contains "$ERR" "[ERROR] [$PLUGIN] SQLite-Import fehlgeschlagen."
}

# Das Aufräumen gehört zur Transaktion des Imports: Nach dem Abbruch stehen die
# Daten der Quelle noch so in der DB wie vorher.
assert_import_rolls_back_cleanup() {
    setup_parquet_import "$1"
    add_conflicting_taxa
    run_parquet_import
    assert_status 1
    assert_source_data_unchanged
    assert_contains "$ERR" "[ERROR] [$PLUGIN] SQLite-Import fehlgeschlagen."
}

# Die Quellenangabe gehört zur Transaktion des Imports: Scheitert sie, bleiben
# auch die übrigen Daten der Quelle, wie sie waren.
assert_import_rolls_back_on_failing_source_sql() {
    setup_parquet_import "$1"
    echo "INSERT INTO sources (id, version) VALUES ('$PLUGIN', '\${VERSION}');" \
        > "$TEST_TMP/etl/plugins/$PLUGIN/sql/source.sql"
    run_parquet_import
    assert_status 1
    assert_source_data_unchanged
    assert_contains "$ERR" "NOT NULL constraint failed: sources.name"
    assert_contains "$ERR" "[ERROR] [$PLUGIN] SQLite-Import fehlgeschlagen."
}

# Fehlt source.sql, bricht das Plugin ab, bevor es etwas schreibt.
assert_import_needs_source_sql() {
    setup_parquet_import "$1"
    rm "$TEST_TMP/etl/plugins/$PLUGIN/sql/source.sql"
    run_parquet_import
    assert_status 1
    assert_source_data_unchanged
    assert_contains "$ERR" "[ERROR] [$PLUGIN] source.sql fehlt: $TEST_TMP/etl/plugins/$PLUGIN/sql/source.sql"
}

test_fishbase_import_stops_at_failing_statement() {
    assert_import_stops_at_failing_statement fishbase
}

test_fishbase_import_rolls_back_cleanup() {
    assert_import_rolls_back_cleanup fishbase
}

test_fishbase_import_rolls_back_on_failing_source_sql() {
    assert_import_rolls_back_on_failing_source_sql fishbase
}

test_fishbase_import_needs_source_sql() {
    assert_import_needs_source_sql fishbase
}

test_sealifebase_import_stops_at_failing_statement() {
    assert_import_stops_at_failing_statement sealifebase
}

test_sealifebase_import_rolls_back_cleanup() {
    assert_import_rolls_back_cleanup sealifebase
}

test_sealifebase_import_rolls_back_on_failing_source_sql() {
    assert_import_rolls_back_on_failing_source_sql sealifebase
}

test_sealifebase_import_needs_source_sql() {
    assert_import_needs_source_sql sealifebase
}
