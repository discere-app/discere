#!/usr/bin/env bash
# Tests für die Volksnamen je Schlüssel (core/sql/common_names.sql), über den
# Export beider Plugins, die sie einbinden, und für den Index, der in der DB
# je Schlüssel eine Zeile hält (core/sql/schema.sql). Die Mini-Quellen und
# ihre Exporte kommen aus den Tests der Plugins.

# shellcheck source=./test_fishbase_export.sh
source "$TESTS_DIR/test_fishbase_export.sh"
# shellcheck source=./test_sealifebase_export.sh
source "$TESTS_DIR/test_sealifebase_export.sh"

COMMON_NAME_PLUGINS="fishbase sealifebase"

# SpecCode der Art, an der die Volksnamen hängen: Amphiprion ocellaris im
# Mini-FishBase, Abra alba im Mini-SeaLifeBase.
common_name_speccode() {
    case "$1" in
        fishbase)    echo 2 ;;
        sealifebase) echo 10 ;;
    esac
}

create_common_name_source() {
    case "$1" in
        fishbase)    create_fishbase_parquets ;;
        sealifebase) create_sealifebase_parquets ;;
    esac
}

run_common_name_export() {
    case "$1" in
        fishbase)    run_fishbase_export ;;
        sealifebase) run_sealifebase_export ;;
    esac
}

# Ersetzt comnames.parquet von <plugin> durch die Zeilen <values> in der
# Reihenfolge <ASC|DESC>. Je Zeile: Position, ComName, C_Code, NameType,
# PreferredName, Rank; alle englisch und für die Art aus
# common_name_speccode. Misspelling führt nur FishBase.
write_common_name_rows() {
    local plugin="$1" order="$2" values="$3" misspelling=""
    [[ "$plugin" == fishbase ]] && misspelling="0::TINYINT AS Misspelling,"
    duckdb << SQL
COPY (
    SELECT ComName, $(common_name_speccode "$plugin") AS SpecCode, C_Code, 'English' AS Language, NameType,
           PreferredName::TINYINT AS PreferredName, $misspelling Rank::SMALLINT AS Rank
    FROM (VALUES $values) AS t(pos, ComName, C_Code, NameType, PreferredName, Rank)
    ORDER BY pos $order
) TO '$TEST_TMP/$plugin/comnames.parquet' (FORMAT parquet);
SQL
}

# Land, Name, Rang, Vorzug und Namenstyp je exportierter Zeile der Art,
# sortiert. Namen in den Tests tragen kein Komma.
common_name_rows() {
    tail -n +2 "$TEST_TMP/export/common_names.csv" \
        | grep "_species:$(common_name_speccode "$1")," | cut -d , -f 4,5,7-9 | sort
}

# Exportiert <values> als comnames von <plugin> in beiden Reihenfolgen der
# Eingabe und prüft, dass jede genau <expected> ergibt.
assert_common_name_export() {
    local plugin="$1" values="$2" expected="$3" label="$4"
    local order
    create_common_name_source "$plugin"
    for order in ASC DESC; do
        write_common_name_rows "$plugin" "$order" "$values"
        run_common_name_export "$plugin"
        assert_status 0
        assert_eq "$expected" "$(common_name_rows "$plugin")" "$label ($plugin, $order)"
    done
}

# Gleicher Vorzug und Rang: Der Namenstyp entscheidet, alphabetisch. Drei
# Schlüssel mit dem gewählten Typ an verschiedener Position der Eingabe,
# damit keine Reihenfolge ihn zufällig zuerst liefert.
test_common_names_breaks_tie_by_name_type() {
    local plugin
    for plugin in $COMMON_NAME_PLUGINS; do
        assert_common_name_export "$plugin" "
            (1, 'Clownfish', '9999', 'Vernacular', 1, 1),
            (2, 'Clownfish', '9999', 'AFS',        1, 1),
            (3, 'Clownfish', '9999', 'FAO',        1, 1),
            (4, 'Nemo',      '9999', 'AFS',        1, 1),
            (5, 'Nemo',      '9999', 'Market',     1, 1),
            (6, 'Nemo',      '9999', 'Vernacular', 1, 1),
            (7, 'Anemone',   '9999', 'Market',     1, 1),
            (8, 'Anemone',   '9999', 'Vernacular', 1, 1),
            (9, 'Anemone',   '9999', 'Aquarium',   1, 1)" \
            ",Anemone,1,1,Aquarium
,Clownfish,1,1,AFS
,Nemo,1,1,AFS" "Namenstyp"
    done
}

# Die bevorzugte Zeile bleibt, auch gegen eine mit niedrigerem Rang: So
# liest die App die Zeilen eines Schlüssels.
test_common_names_keeps_preferred_row_over_lower_rank() {
    local plugin
    for plugin in $COMMON_NAME_PLUGINS; do
        assert_common_name_export "$plugin" "
            (1, 'Clownfish', '276', 'Vernacular', 0, 1),
            (2, 'Clownfish', '276', 'FAO ctry',   1, 2),
            (3, 'Clownfish', '276', 'Market',     0, 3)" \
            "276,Clownfish,2,1,FAO ctry" "Vorzug"
    done
}

# Ohne Rang steht vor Rang 1, wie SQLite in der App aufsteigend sortiert:
# Bei gleichem Vorzug bleibt die Zeile ohne Rang.
test_common_names_keeps_row_without_rank_over_ranked_row() {
    local plugin
    for plugin in $COMMON_NAME_PLUGINS; do
        assert_common_name_export "$plugin" "
            (1, 'Clownfish', '276', 'Vernacular', 1, 1),
            (2, 'Clownfish', '276', 'FAO ctry',   1, NULL),
            (3, 'Clownfish', '276', 'AFS',        1, 2)" \
            "276,Clownfish,,1,FAO ctry" "ohne Rang"
    done
}

# Ohne Land (C_Code 9999) gilt als ein Land: zwei globale Zeilen desselben
# Namens werden eine, die mit dem niedrigsten Rang.
test_common_names_merges_global_rows() {
    local plugin
    for plugin in $COMMON_NAME_PLUGINS; do
        assert_common_name_export "$plugin" "
            (1, 'Clownfish', '9999', 'Vernacular', 1, 2),
            (2, 'Clownfish', '9999', 'Vernacular', 1, 1)" \
            ",Clownfish,1,1,Vernacular" "ohne Land"
    done
}

# Derselbe Name in verschiedenen Ländern und global sind drei Schlüssel.
test_common_names_keeps_name_in_each_country() {
    local plugin
    for plugin in $COMMON_NAME_PLUGINS; do
        assert_common_name_export "$plugin" "
            (1, 'Clownfish', '276',  'Vernacular', 1, 1),
            (2, 'Clownfish', '250',  'Vernacular', 1, 1),
            (3, 'Clownfish', '9999', 'Vernacular', 1, 1)" \
            ",Clownfish,1,1,Vernacular
250,Clownfish,1,1,Vernacular
276,Clownfish,1,1,Vernacular" "Länder"
    done
}

# Die Zählung fürs Log: Schlüssel mit mehreren Zeilen, davon mit der
# bevorzugten Zeile vor einer, die nach Rang allein vorn stünde (auch einer
# ohne Rang), davon ohne Land.
test_common_names_counts_merged_keys() {
    local plugin
    for plugin in $COMMON_NAME_PLUGINS; do
        create_common_name_source "$plugin"
        write_common_name_rows "$plugin" ASC "
            (1, 'Clownfish', '9999', 'Vernacular', 0, 1),
            (2, 'Clownfish', '9999', 'FAO',        1, 2),
            (3, 'Nemo',      '9999', 'AFS',        1, 1),
            (4, 'Nemo',      '9999', 'Market',     1, 1),
            (5, 'Nemo',      '276',  'Market',     1, 1),
            (6, 'Nemo',      '276',  'Market',     0, 2),
            (7, 'Anemone',   '276',  'Market',     1, 1),
            (8, 'Reef',      '9999', 'FAO',        1, 2),
            (9, 'Reef',      '9999', 'Vernacular', 0, NULL)"
        run_common_name_export "$plugin"
        assert_status 0
        assert_eq "common_names_merged	4
common_names_preferred_over_rank	2
common_names_global	3" "$(cat "$TEST_TMP/export/common_names_summary.tsv")" "Zählung ($plugin)"
    done
}

# Der Index hält je Schlüssel eine Zeile, auch ohne Land; ein anderes Land
# ist ein anderer Schlüssel.
test_common_names_index_rejects_duplicate_without_country() {
    local db="$TEST_TMP/schema.db"
    "$ETL_DIR/core/create_db.sh" --output "$db" > /dev/null 2>&1
    sqlite3 "$db" "INSERT INTO common_names (entity_id, entity_type, language, country, name, source) VALUES
        ('discere:species:1', 'species', 'en', NULL,  'Clownfish', 'fishbase'),
        ('discere:species:1', 'species', 'en', '276', 'Clownfish', 'fishbase');"
    run_capture sqlite3 "$db" "INSERT INTO common_names (entity_id, entity_type, language, country, name, source, rank)
        VALUES ('discere:species:1', 'species', 'en', NULL, 'Clownfish', 'fishbase', 2);"
    [[ "$STATUS" -ne 0 ]] || fail_case "zweite Zeile ohne Land angenommen"
    assert_contains "$ERR" "UNIQUE constraint failed: index 'idx_common_names_key'"
    assert_eq "2" "$(sqlite3 "$db" "SELECT COUNT(*) FROM common_names;")" "Zeilen"
}
