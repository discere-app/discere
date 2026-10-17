#!/usr/bin/env bash
# Tests für die Verbreitung je Art und Region (core/sql/distribution_regions.sql),
# über den Export beider Plugins, die sie einbinden. Die Mini-Quellen und
# ihre Exporte kommen aus den Tests der Plugins.

# shellcheck source=./test_fishbase_export.sh
source "$TESTS_DIR/test_fishbase_export.sh"
# shellcheck source=./test_sealifebase_export.sh
source "$TESTS_DIR/test_sealifebase_export.sh"

DISTRIBUTION_PLUGINS="fishbase sealifebase"

# SpecCode der Art, an der die Verbreitung hängt: Amphiprion ocellaris im
# Mini-FishBase, Abra alba im Mini-SeaLifeBase.
distribution_speccode() {
    case "$1" in
        fishbase)    echo 2 ;;
        sealifebase) echo 10 ;;
    esac
}

# Legt die Mini-Quelle von <plugin> an.
create_distribution_source() {
    case "$1" in
        fishbase)    create_fishbase_parquets ;;
        sealifebase) create_sealifebase_parquets ;;
    esac
}

# Ersetzt <table>.parquet (country oder countrysub) von <plugin> durch die
# Zeilen <values> in der Reihenfolge <ASC|DESC>. Je Zeile: Position,
# C_Code, Status, CurrentPresence, Threatened, Abundance, Importance,
# Comments; alle für die Art aus distribution_speccode. Die Spalten sind
# die beider Quellen; countrysub bekommt CSub_Code 1.
write_distribution_rows() {
    local plugin="$1" table="$2" order="$3" values="$4"
    duckdb << SQL
COPY (
    SELECT C_Code, '1' AS CSub_Code, $(distribution_speccode "$plugin") AS SpecCode, Status::VARCHAR AS Status,
           CurrentPresence, 0::TINYINT AS Freshwater, Comments::VARCHAR AS Comments,
           Abundance::VARCHAR AS Abundance, Importance::VARCHAR AS Importance, Threatened::TINYINT AS Threatened
    FROM (VALUES $values)
        AS t(pos, C_Code, Status, CurrentPresence, Threatened, Abundance, Importance, Comments)
    ORDER BY pos $order
) TO '$TEST_TMP/$plugin/$table.parquet' (FORMAT parquet);
SQL
}

run_distribution_export() {
    case "$1" in
        fishbase)    run_fishbase_export ;;
        sealifebase) run_sealifebase_export ;;
    esac
}

# Region, Präsenz, Status, threatened, Häufigkeit, Bedeutung und Kommentar
# je exportierter Zeile der Art, sortiert. Kommentare in den Tests tragen
# kein Komma.
distribution_rows() {
    tail -n +2 "$TEST_TMP/export/taxonomy_distribution_regions.csv" \
        | grep "_species:$(distribution_speccode "$1")," | cut -d , -f 4,5,7-12 | sort
}

# Exportiert <values> als country von <plugin> in beiden Reihenfolgen der
# Eingabe und prüft, dass jede genau <expected> ergibt.
assert_country_export() {
    local plugin="$1" values="$2" expected="$3" label="$4"
    local order
    create_distribution_source "$plugin"
    for order in ASC DESC; do
        write_distribution_rows "$plugin" country "$order" "$values"
        run_distribution_export "$plugin"
        assert_status 0
        assert_eq "$expected" "$(distribution_rows "$plugin")" "$label ($plugin, $order)"
    done
}

# native, sobald eine Zeile native sagt, auch gegen introduced.
test_distribution_native_wins_over_introduced() {
    local plugin
    for plugin in $DISTRIBUTION_PLUGINS; do
        assert_country_export "$plugin" "
            (1, '404', 'introduced', 'present', 0, NULL, NULL, 'Lake Victoria'),
            (2, '404', 'native',     'present', 0, NULL, NULL, 'Lake Turkana')" \
            "country,404,present,native,0,,,Lake Turkana
subregion,276:1,present,native,,,," "native + introduced"
    done
}

# endemic nur, wenn alle Zeilen endemic sagen: neben native gilt native.
test_distribution_native_wins_over_endemic() {
    local plugin
    for plugin in $DISTRIBUTION_PLUGINS; do
        assert_country_export "$plugin" "
            (1, '404', 'endemic', 'present', 0, NULL, NULL, 'Lake Baringo'),
            (2, '404', 'native',  'present', 0, NULL, NULL, 'Lake Turkana'),
            (3, '404', 'endemic', 'present', 0, NULL, NULL, 'Suguta River')" \
            "country,404,present,native,0,,,Lake Turkana
subregion,276:1,present,native,,,," "endemic + native"
    done
}

test_distribution_keeps_endemic_when_all_rows_say_endemic() {
    local plugin
    for plugin in $DISTRIBUTION_PLUGINS; do
        assert_country_export "$plugin" "
            (1, '404', 'endemic', 'present', 0, NULL, NULL, 'Suguta River'),
            (2, '404', 'endemic', 'present', 0, NULL, NULL, 'Lake Baringo')" \
            "country,404,present,endemic,0,,,Lake Baringo
subregion,276:1,present,native,,,," "nur endemic"
    done
}

# introduced, wenn keine Zeile native oder endemic sagt.
test_distribution_introduced_wins_over_questionable() {
    local plugin
    for plugin in $DISTRIBUTION_PLUGINS; do
        assert_country_export "$plugin" "
            (1, '524', 'questionable', 'possible', 0, NULL, NULL, 'Unconfirmed'),
            (2, '524', 'introduced',   'present',  0, NULL, NULL, 'Stocked')" \
            "country,524,present,introduced,0,,,Stocked
subregion,276:1,present,native,,,," "introduced + questionable"
    done
}

# Ohne native, endemic und introduced gilt der erste Status der Rangfolge
# questionable, error, misidentification, extirpated, stray, not established,
# reintroduced, established, ohne Status — je Land ein Paar benachbarter
# Ränge, der vordere jeweils an zweiter Position der Eingabe. Groß- und
# Kleinschreibung zählen nicht, gewählt wird die Zeile in ihrer Schreibweise.
test_distribution_ranks_remaining_statuses() {
    local plugin
    for plugin in $DISTRIBUTION_PLUGINS; do
        assert_country_export "$plugin" "
            (1,  '101', 'error',             'absent',   0, NULL, NULL, NULL),
            (2,  '101', 'questionable',      'possible', 0, NULL, NULL, NULL),
            (3,  '102', 'misidentification', 'absent',   0, NULL, NULL, NULL),
            (4,  '102', 'error',             'absent',   0, NULL, NULL, NULL),
            (5,  '103', 'extirpated',        'absent',   0, NULL, NULL, NULL),
            (6,  '103', 'misidentification', 'absent',   0, NULL, NULL, NULL),
            (7,  '104', 'stray',             'present',  0, NULL, NULL, NULL),
            (8,  '104', 'extirpated',        'absent',   0, NULL, NULL, NULL),
            (9,  '105', 'not established',   'absent',   0, NULL, NULL, NULL),
            (10, '105', 'Stray',             'present',  0, NULL, NULL, NULL),
            (11, '106', 'reintroduced',      'present',  0, NULL, NULL, NULL),
            (12, '106', 'not established',   'absent',   0, NULL, NULL, NULL),
            (13, '107', 'established',       'present',  0, NULL, NULL, NULL),
            (14, '107', 'reintroduced',      'present',  0, NULL, NULL, NULL),
            (15, '108', NULL,                'present',  0, NULL, NULL, NULL),
            (16, '108', 'established',       'present',  0, NULL, NULL, NULL)" \
            "country,101,possible,questionable,0,,,
country,102,absent,error,0,,,
country,103,absent,misidentification,0,,,
country,104,absent,extirpated,0,,,
country,105,present,Stray,0,,,
country,106,absent,not established,0,,,
country,107,present,reintroduced,0,,,
country,108,present,established,0,,,
subregion,276:1,present,native,,,," "Rangfolge"
    done
}

# Präsenz, threatened, Häufigkeit, Bedeutung und Kommentar kommen aus der
# Zeile, die den Status liefert. Unter gleichrangigen Zeilen entscheiden
# Präsenz, Status, threatened, Häufigkeit, Bedeutung und Kommentar, leere
# Werte zuletzt: im Land 404 die native-Zeile mit threatened 0, im Land 405
# bei gleichem threatened die mit Häufigkeit.
test_distribution_takes_columns_from_chosen_row() {
    local plugin
    for plugin in $DISTRIBUTION_PLUGINS; do
        assert_country_export "$plugin" "
            (1, '404', 'introduced', 'present', 1, 'abundant', 'highly commercial', 'Lake Victoria'),
            (2, '404', 'native',     'present', 1, NULL,       NULL,                'Endangered population'),
            (3, '404', 'native',     'present', 0, 'scarce',   'commercial',        'Lake Turkana'),
            (4, '405', 'native',     'present', 0, NULL,       'minor commercial',  'Coast'),
            (5, '405', 'native',     'present', 0, 'common',   NULL,                'Rivers')" \
            "country,404,present,native,0,scarce,commercial,Lake Turkana
country,405,present,native,0,common,,Rivers
subregion,276:1,present,native,,,," "Spalten"
    done
}

# Zeilen gleichen Status, die sich nur im Kommentar unterscheiden: Welche
# gewählt wird, hängt nicht von der Reihenfolge der Eingabe ab.
test_distribution_choice_does_not_depend_on_input_order() {
    local plugin
    for plugin in $DISTRIBUTION_PLUGINS; do
        assert_country_export "$plugin" "
            (1, '392', 'native', 'present', 0, NULL, NULL, 'Hokkaido'),
            (2, '392', 'native', 'present', 0, NULL, NULL, 'Honshu'),
            (3, '392', 'native', 'present', 0, NULL, NULL, 'Biwa')" \
            "country,392,present,native,0,,,Biwa
subregion,276:1,present,native,,,," "Reihenfolge"
    done
}

# Teilregionen folgen derselben Regel.
test_distribution_merges_subregion_rows() {
    local plugin order
    for plugin in $DISTRIBUTION_PLUGINS; do
        create_distribution_source "$plugin"
        for order in ASC DESC; do
            write_distribution_rows "$plugin" countrysub "$order" "
                (1, '276', 'introduced', 'present', NULL, NULL, NULL, 'Rhine'),
                (2, '276', 'native',     'present', NULL, NULL, NULL, 'Danube')"
            run_distribution_export "$plugin"
            assert_status 0
            assert_eq "country,276,present,native,0,,,
subregion,276:1,present,native,,,,Danube" "$(distribution_rows "$plugin")" "Teilregion ($plugin, $order)"
        done
    done
}

# Der Bericht nennt jeden Schlüssel mit mehreren Zeilen, den Status seiner
# Zeilen, das Ergebnis und die Spalten, in denen die Zeilen abweichen;
# Schlüssel mit einer Zeile nicht.
test_distribution_reports_merged_keys() {
    local plugin name
    for plugin in $DISTRIBUTION_PLUGINS; do
        case "$plugin" in
            fishbase)    name="Amphiprion ocellaris" ;;
            sealifebase) name="Abra alba" ;;
        esac
        create_distribution_source "$plugin"
        write_distribution_rows "$plugin" country ASC "
            (1, '404', 'endemic',    'present', 0, NULL, NULL, 'Lake Baringo'),
            (2, '404', 'native',     'present', 0, NULL, NULL, 'Lake Turkana'),
            (3, '404', 'introduced', 'present', 1, NULL, NULL, 'Lake Victoria'),
            (4, '404', 'native',     'present', 0, NULL, NULL, 'Turkana'),
            (5, '392', 'native',     'present', 0, NULL, NULL, 'Hokkaido'),
            (6, '392', 'native',     'present', 0, NULL, NULL, 'Honshu'),
            (7, '276', 'native',     'present', 0, NULL, NULL, NULL)"
        run_distribution_export "$plugin"
        assert_status 0
        local speccode
        speccode="$(distribution_speccode "$plugin")"
        assert_eq "distribution_rows_merged	SpecCode $speccode, country 392	$name	2 Zeilen (native 2) → native; abweichend: comment
distribution_status_merged	SpecCode $speccode, country 404	$name	4 Zeilen (endemic 1, introduced 1, native 2) → native; abweichend: establishment_status, threatened_flag, comment" \
            "$(cat "$TEST_TMP/export/distribution_report.tsv")" "Bericht ($plugin)"
    done
}

# Endemic neben einem anderen Status als native und ein Status, den die
# Rangfolge nicht kennt, brechen den Export ab, sobald ihr Schlüssel mehrere
# Zeilen hat; allein in seinem Schlüssel wird ein unbekannter Status
# übernommen.
test_distribution_fails_on_key_without_rule() {
    local plugin
    for plugin in $DISTRIBUTION_PLUGINS; do
        create_distribution_source "$plugin"
        write_distribution_rows "$plugin" country ASC "
            (1, '404', 'endemic',    'present', 0, NULL, NULL, NULL),
            (2, '404', 'introduced', 'present', 0, NULL, NULL, NULL)"
        run_distribution_export "$plugin"
        assert_status 1
        assert_contains "$ERR" "Verbreitung: keine Regel für SpecCode $(distribution_speccode "$plugin"), country 404: endemic neben einem anderen Status als native"

        write_distribution_rows "$plugin" country ASC "
            (1, '404', 'native',     'present', 0, NULL, NULL, NULL),
            (2, '404', 'vagrant',    'present', 0, NULL, NULL, NULL)"
        run_distribution_export "$plugin"
        assert_status 1
        assert_contains "$ERR" "country 404: unbekannter Status"

        write_distribution_rows "$plugin" country ASC "
            (1, '404', 'vagrant',    'present', 0, NULL, NULL, NULL)"
        run_distribution_export "$plugin"
        assert_status 0
        assert_eq "country,404,present,vagrant,0,,,
subregion,276:1,present,native,,,," "$(distribution_rows "$plugin")" "unbekannter Status allein ($plugin)"
    done
}
