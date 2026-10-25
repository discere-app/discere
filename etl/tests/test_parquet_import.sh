#!/usr/bin/env bash
# Tests für den SQLite-Import der Plugins FishBase und SeaLifeBase
# (import_to_sqlite in plugins/<plugin>/import.sh): Das Plugin läuft gegen die
# Mini-Quellen aus den Tests der Exporte und eine DB aus core/create_db.sh.
#
# Das Plugin läuft als Kopie unter $TEST_TMP/etl: Die Ausnahmen ohne Ordnung
# von SeaLifeBase nennen FamCodes, die die Mini-Quelle nicht führt, und
# brächen den Export ab; die Kopie bekommt eine leere Liste.

# shellcheck source=./test_fishbase_export.sh
source "$TESTS_DIR/test_fishbase_export.sh"
# shellcheck source=./test_sealifebase_export.sh
source "$TESTS_DIR/test_sealifebase_export.sh"

# Legt die Mini-Quelle von <plugin>, die Kopie des Plugins und die DB an und
# lässt das Plugin importieren. In der DB stehen schon die Klasse und die
# Ordnung, die die Quelle exportiert, unter derselben ID, aber einer fremden
# Quelle — das Aufräumen lässt sie stehen, der Import der Klasse scheitert an
# ihr, und ohne Abbruch dort scheiterte auch der der Ordnung. Dazu ein Bild
# der Quelle, das das Aufräumen löscht.
run_conflicting_import() {
    local plugin="$1"
    local class_id order_id dir_flag
    case "$plugin" in
        fishbase)
            create_fishbase_parquets
            class_id='discere:fishbase_class:7'
            order_id='discere:fishbase_order:1'
            dir_flag=--fishbase-dir ;;
        sealifebase)
            create_sealifebase_parquets
            class_id='discere:sealifebase_class:1'
            order_id='discere:sealifebase_order:1'
            dir_flag=--slb-dir ;;
    esac
    mkdir -p "$TEST_TMP/etl/plugins"
    cp -R "$ETL_DIR/core" "$TEST_TMP/etl/core"
    cp -R "$ETL_DIR/plugins/$plugin" "$TEST_TMP/etl/plugins/$plugin"
    if [[ "$plugin" == sealifebase ]]; then
        echo "famcode,family,reason,evidence" > "$TEST_TMP/etl/plugins/sealifebase/data/family_order_exceptions.csv"
    fi
    DB="$TEST_TMP/ref.db"
    "$TEST_TMP/etl/core/create_db.sh" --output "$DB" > /dev/null 2>&1
    sqlite3 -bail "$DB" << SQL
INSERT INTO classes (id, external_id, external_source, name, super_class) VALUES
    ('$class_id', '1', 'curated', 'Fremdklasse', 'Fremd');
INSERT INTO orders (id, external_id, external_source, name, class) VALUES
    ('$order_id', '1', 'curated', 'Fremdordnung', '$class_id');
INSERT INTO pictures (id, picname, origin) VALUES
    ('discere:${plugin}_picture:1', 'alt.jpg', '$plugin');
SQL
    run_capture "$TEST_TMP/etl/plugins/$plugin/import.sh" --db "$DB" "$dir_flag" "$TEST_TMP/$plugin"
    assert_status 1
    assert_contains "$ERR" "[ERROR] [$plugin] SQLite-Import fehlgeschlagen."
}

# Scheitert eine Anweisung, bricht sqlite3 dort ab: keine Art der Quelle in der
# DB, und im Log steht nur der Fehler dieser Anweisung.
assert_import_stops_at_failing_statement() {
    local plugin="$1"
    run_conflicting_import "$plugin"
    assert_eq 0 "$(sqlite3 "$DB" "SELECT COUNT(*) FROM species WHERE external_source = '$plugin';")" \
        "Arten der Quelle nach dem Abbruch"
    assert_contains "$ERR" "UNIQUE constraint failed: classes.id"
    assert_eq 1 "$(grep -c 'error near line' <<< "$ERR")" "sqlite-Fehler im Log"
}

# Das Aufräumen gehört zur Transaktion des Imports: Nach dem Abbruch stehen die
# Daten der Quelle noch so in der DB wie vorher.
assert_import_rolls_back_cleanup() {
    local plugin="$1"
    run_conflicting_import "$plugin"
    assert_eq "alt.jpg" "$(sqlite3 "$DB" "SELECT picname FROM pictures WHERE origin = '$plugin';")" \
        "Bilder der Quelle nach dem Abbruch"
}

test_fishbase_import_stops_at_failing_statement() {
    assert_import_stops_at_failing_statement fishbase
}

test_fishbase_import_rolls_back_cleanup() {
    assert_import_rolls_back_cleanup fishbase
}

test_sealifebase_import_stops_at_failing_statement() {
    assert_import_stops_at_failing_statement sealifebase
}

test_sealifebase_import_rolls_back_cleanup() {
    assert_import_rolls_back_cleanup sealifebase
}
