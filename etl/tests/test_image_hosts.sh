#!/usr/bin/env bash
# Tests für die Prüfung der Bild-Hosts vor dem Veröffentlichen
# (core/check_image_hosts.sh): Jeder Host mit nutzbaren Bildern muss seine
# Stichprobe so liefern, wie die App sie lädt.
#
# Ohne Netz: Vorne im PATH stehen ein curl, das je URL eine vorgegebene
# Antwort ausgibt und seine Argumente protokolliert, und ein sleep, das
# nicht wartet. Das Skript selbst kennt die Tests nicht.

# Legt $TEST_TMP/ref.db mit leerem Schema an und die Fakes unter
# $TEST_TMP/bin. curl schreibt jede Argumentliste nach $TEST_TMP/curl.log und
# antwortet mit der ersten Zeile aus $TEST_TMP/responses, deren Muster auf
# die URL (das letzte Argument) passt; ohne passende Zeile wie bei einem
# unbekannten Host mit Exit 6.
create_image_host_env() {
    DB="$TEST_TMP/ref.db"
    "$ETL_DIR/core/create_db.sh" --output "$DB" > /dev/null 2>&1
    mkdir -p "$TEST_TMP/bin"
    : > "$TEST_TMP/responses"
    : > "$TEST_TMP/curl.log"
    cat > "$TEST_TMP/bin/curl" << EOF
#!/usr/bin/env bash
echo "\$*" >> "$TEST_TMP/curl.log"
url="\${!#}"
while IFS=\$'\t' read -r pattern headers; do
    if [[ "\$url" == \$pattern ]]; then
        printf '%b\r\n' "\$headers"
        exit 0
    fi
done < "$TEST_TMP/responses"
exit 6
EOF
    printf '#!/usr/bin/env bash\n' > "$TEST_TMP/bin/sleep"
    chmod +x "$TEST_TMP/bin/curl" "$TEST_TMP/bin/sleep"
}

# add_picture <url> [is_usable] — is_usable ist 1, wenn nicht angegeben.
add_picture() {
    local n
    n="$(sqlite3 "$DB" "SELECT COUNT(*) + 1 FROM pictures;")"
    sqlite3 "$DB" "INSERT INTO pictures (id, url, origin, is_usable)
                   VALUES ('discere:test_pic:$n', '$1', 'test', ${2:-1});"
}

# respond <url-muster> <header> — Header als printf-%b-Text, Zeilen mit \n.
respond() {
    printf '%s\t%s\n' "$1" "$2" >> "$TEST_TMP/responses"
}

respond_image() {
    respond "$1" 'HTTP/2 200\ncontent-type: image/jpeg\n'
}

check_image_hosts() {
    run_capture env PATH="$TEST_TMP/bin:$PATH" "$ETL_DIR/core/check_image_hosts.sh" --db "$DB"
}

# Der Teil von stderr ab der Fehlermeldung, ohne die Protokollzeilen davor.
failure_message() {
    sed -n '/^\[ERROR\]/,$p' <<< "$ERR"
}

test_image_hosts_pass_when_every_host_delivers_images() {
    create_image_host_env
    add_picture 'https://a.example/images/species/Abc_u0.jpg'
    add_picture 'https://b.example/pics/Xyz_u1.jpg'
    respond_image 'https://a.example/*'
    respond_image 'https://b.example/*'
    check_image_hosts
    assert_status 0
    assert_contains "$ERR" "a.example: 1 von 1 Bildern geladen."
    assert_contains "$ERR" "b.example: 1 von 1 Bildern geladen."
    # Die URLs unverändert aus der DB, mit dem User-Agent der App.
    assert_contains "$(cat "$TEST_TMP/curl.log")" "https://a.example/images/species/Abc_u0.jpg"
    assert_contains "$(cat "$TEST_TMP/curl.log")" "https://b.example/pics/Xyz_u1.jpg"
    assert_contains "$(cat "$TEST_TMP/curl.log")" \
        "DiscereApp/1.1 (ch.feberle.discere; https://github.com/discere-app/discere)"
}

test_image_hosts_fail_on_cloudflare_challenge() {
    create_image_host_env
    add_picture 'https://a.example/images/species/Abc_u0.jpg'
    respond 'https://a.example/*' 'HTTP/2 403\ncf-mitigated: challenge\ncontent-type: text/html\n'
    check_image_hosts
    assert_status 1
    assert_contains "$(failure_message)" \
        "a.example: https://a.example/images/species/Abc_u0.jpg → Status 403: Cloudflare-Challenge (cf-mitigated: challenge)"
}

# Eine Challenge ist keine fehlende Datei, auch wenn sie mit 404 kommt: Der
# Host fällt durch, obwohl ein einzelnes fehlendes Bild geduldet wäre.
test_image_hosts_treat_challenge_as_failure_whatever_the_status() {
    create_image_host_env
    add_picture 'https://a.example/images/species/Gate_u0.jpg'
    add_picture 'https://a.example/images/species/Abc_u0.jpg'
    add_picture 'https://a.example/images/species/Def_u0.jpg'
    respond 'https://a.example/images/species/Gate_*' 'HTTP/2 404\ncf-mitigated: challenge\ncontent-type: text/html\n'
    respond_image 'https://a.example/*'
    check_image_hosts
    assert_status 1
    assert_contains "$(failure_message)" \
        "a.example: https://a.example/images/species/Gate_u0.jpg → Status 404: Cloudflare-Challenge (cf-mitigated: challenge)"
}

test_image_hosts_fail_on_html_with_status_200() {
    create_image_host_env
    add_picture 'https://a.example/images/species/Abc_u0.jpg'
    respond 'https://a.example/*' 'HTTP/2 200\ncontent-type: text/html; charset=utf-8\n'
    check_image_hosts
    assert_status 1
    assert_contains "$(failure_message)" \
        "a.example: https://a.example/images/species/Abc_u0.jpg → Status 200: Content-Type 'text/html; charset=utf-8' statt image/*"
}

test_image_hosts_ignore_hosts_without_usable_pictures() {
    create_image_host_env
    add_picture 'https://a.example/images/species/Abc_u0.jpg'
    add_picture 'https://blocked.example/images/species/Abc_u0.jpg' 0
    respond_image 'https://a.example/*'
    respond 'https://blocked.example/*' 'HTTP/2 403\ncf-mitigated: challenge\n'
    check_image_hosts
    assert_status 0
    assert_not_contains "$(cat "$TEST_TMP/curl.log")" "blocked.example"
}

test_image_hosts_name_only_the_failing_host() {
    create_image_host_env
    add_picture 'https://good.example/images/species/Abc_u0.jpg'
    add_picture 'https://blocked.example/images/species/Abc_u0.jpg'
    respond_image 'https://good.example/*'
    respond 'https://blocked.example/*' 'HTTP/2 403\ncf-mitigated: challenge\n'
    check_image_hosts
    assert_status 1
    assert_contains "$(failure_message)" "blocked.example: https://blocked.example/images/species/Abc_u0.jpg"
    assert_not_contains "$(failure_message)" "good.example"
}

# Einzelne fehlende Bilder kommen in den Quellen vor und sind keine Sperre.
test_image_hosts_tolerate_a_single_missing_picture() {
    create_image_host_env
    add_picture 'https://a.example/images/species/Gone_u0.jpg'
    add_picture 'https://a.example/images/species/Abc_u0.jpg'
    add_picture 'https://a.example/images/species/Def_u0.jpg'
    respond 'https://a.example/images/species/Gone_*' 'HTTP/2 404\ncontent-type: text/html\n'
    respond_image 'https://a.example/*'
    check_image_hosts
    assert_status 0
    assert_contains "$ERR" "a.example: Bild fehlt (404): https://a.example/images/species/Gone_u0.jpg"
    assert_contains "$ERR" "a.example: 2 von 3 Bildern geladen."
}

# Fehlt die Mehrheit, stimmt der Bildpfad nicht.
test_image_hosts_fail_when_most_pictures_are_missing() {
    create_image_host_env
    add_picture 'https://a.example/images/species/Gone_u0.jpg'
    add_picture 'https://a.example/images/species/Gone_u1.jpg'
    add_picture 'https://a.example/images/species/Abc_u0.jpg'
    respond 'https://a.example/images/species/Gone_*' 'HTTP/2 404\ncontent-type: text/html\n'
    respond_image 'https://a.example/*'
    check_image_hosts
    assert_status 1
    assert_contains "$(failure_message)" "a.example: nur 1 von 3 Bildern geladen"
}

test_image_hosts_judge_the_last_response_of_a_redirect() {
    create_image_host_env
    add_picture 'https://a.example/images/species/Abc_u0.jpg'
    respond 'https://a.example/*' \
        'HTTP/1.1 301 Moved Permanently\ncontent-type: text/html\nlocation: https://cdn.example/Abc_u0.jpg\n\nHTTP/2 200\ncontent-type: image/jpeg\n'
    check_image_hosts
    assert_status 0
}

test_image_hosts_fail_when_host_does_not_answer() {
    create_image_host_env
    add_picture 'https://unknown.example/images/species/Abc_u0.jpg'
    check_image_hosts
    assert_status 1
    assert_contains "$(failure_message)" "unknown.example: https://unknown.example/images/species/Abc_u0.jpg → Status –: keine Antwort (curl-Exit 6)"
}

test_image_hosts_load_a_small_sample_per_host() {
    create_image_host_env
    for n in 1 2 3 4 5 6 7; do
        add_picture "https://a.example/images/species/Abc_u$n.jpg"
    done
    respond_image 'https://a.example/*'
    check_image_hosts
    assert_status 0
    assert_eq 5 "$(wc -l < "$TEST_TMP/curl.log" | tr -d ' ')" "Anfragen"
}
