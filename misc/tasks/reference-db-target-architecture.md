# Reference-DB: Zielbild (Hosting & Automatisierung)

**Kategorie:** Architektur/Entscheidung · **Priorität:** Hoch · **Komplexität:** Mittel · **Status:** In Umsetzung

## Kurzbeschreibung

`discere_reference.db` (ETL-Output, ~400 MB) wird aus dem App-Bundle entfernt
und stattdessen zur Laufzeit heruntergeladen (siehe
[reduce-app-bundle-size.md](reduce-app-bundle-size.md) für den ursprünglichen
Auslöser). Dieses Dokument beschreibt die Zielarchitektur, auf die die
Umsetzung hinarbeitet. Die zunächst offene Frage einer Codeberg→GitHub-
Migration von `discere-data` ist inzwischen entschieden und umgesetzt (siehe
„Hosting heute" unten) — `discere-data` liegt jetzt auf
[github.com/feberle/discere-data](https://github.com/feberle/discere-data).

## Zielarchitektur

- **`etl/` bleibt dauerhaft im `discere`-App-Repo.** `etl/core/sql/schema.sql`
  und die raw-SQL-Queries in `lib/catalog/repository/` sind eng gekoppelt —
  Schema- und Query-Änderungen sollen atomar im selben PR landen. Eine
  Aufteilung in ein separates ETL-Repo würde diese Kopplung nur künstlich
  auseinanderreißen.
- **`discere-data` wird zum Daten-Hub:** `data/decks/*.json` + `index.json`
  (wie heute) **plus** `data/reference-db/manifest.json` (Version,
  `schemaVersion`, Download-URL, SHA-256-Checksum) daneben. Für
  Deck-Contributor:innen ändert sich nichts sichtbar — sie sehen weiterhin nur
  den Decks-Ordner und müssen nie mit ETL oder DB-Publishing in Berührung
  kommen.
- **Deck-Index-Automatisierung und Referenz-DB-Publishing sind zwei
  unabhängige Stränge.** Die Migration von `discere-data` nach GitHub ist
  inzwischen erfolgt; ob `scripts/generate-index.sh` durch einen
  GitHub-Actions-Trigger ersetzt wird (siehe
  [deck-index-automation.md](deck-index-automation.md)), ist trotzdem separat
  von der Referenz-DB-Arbeit zu entscheiden.
- **Das App-Repo (`discere`) ist auf GitHub** und hat damit Zugriff auf GitHub
  Actions — der Schritt „Referenz-DB bauen & veröffentlichen"
  (`etl/publish_release.sh`) könnte dort automatisiert werden (z. B.
  `workflow_dispatch`). Veröffentlicht wird nur der ETL-*Output*, nie der
  App-Code selbst.
- **Hosting-Entscheidung war bewusst spät gebunden.** Die App kennt zur
  Laufzeit nur eine feste Manifest-URL-Konstante (analog zu
  `RemoteDeckService._indexUrl`) und lädt die eigentliche DB-URL sowie
  Checksum aus dem Manifest nach. Der tatsächliche Wechsel von Codeberg zu
  GitHub war dadurch nur: neues Release hochladen, die eine Konstante im
  App-Code anpassen — kein Umbau der Download-Logik nötig. Das bleibt so für
  jeden zukünftigen Hosting-Wechsel.
- **`manifest.json` führt ein `schemaVersion`-Feld**, getrennt von `version`
  (reine Datenupdates). `ReferenceDatabaseProvisioner` vergleicht es aktiv
  gegen `supportedSchemaVersion` und lehnt ein Manifest mit abweichender
  Schema-Version ab, statt es zu installieren — eine ältere App-Version
  würde sonst ein inkompatibles Schema übernehmen und erst später mit
  Laufzeitfehlern in `lib/catalog/repository/` scheitern (fehlende/umbenannte
  Tabellen/Spalten), statt mit einem klaren Fehler beim Download selbst.
- **GZIP-Dekompression großer Downloads läuft in einem Isolate**, analog zum
  bestehenden Muster in `lib/learning/service/deck_serialization_worker.dart`
  (`Isolate.run(...)` für GZIP/JSON), um den UI-Isolate bei einem ~200 MB
  großen Download nicht zu blockieren.

## Hosting heute

GitHub Releases im `discere-data`-Repo
([github.com/feberle/discere-data](https://github.com/feberle/discere-data)),
Manifest unter `data/reference-db/manifest.json`, Deck-Index unter
`data/decks/index.json` — beide über `raw.githubusercontent.com` abgerufen.
Ursprünglich auf Codeberg gehostet; migriert, nachdem ein frisch geänderter
`raw/branch/...`-Pfad dort wiederholt mit `504`/Cache-Miss-Fehlern
fehlschlug (transient, aber auf Codebergs deutlich kleinerer Infrastruktur
plausibler als auf GitHubs Fastly-CDN) — zusätzlich zum ursprünglichen Grund
(GitHub Actions für die Index-Automatisierung). Publishing läuft über
`etl/publish_release.sh` mit der `gh`-CLI statt manuellem curl gegen die
Forgejo-API.

Objektspeicher (Cloudflare R2, Backblaze B2 o. ä.) wäre für ein
Solo-/Nischenprojekt bei aktueller Downloadfrequenz und -größe weiterhin
Overkill.

## Nicht im Zielbild

- Die `.db`-Datei wird **nie** als normaler Git-Blob committet, egal auf
  welcher Plattform — immer über Releases/Attachments, um unbegrenztes
  Repo-Wachstum über die Zeit zu vermeiden.
- Kein automatisierter ETL-Build in CI geplant (DuckDB-Pipeline mit
  Fishbase/SeaLifeBase-Downloads ist vermutlich zu lang/ressourcenintensiv für
  gehostete Runner) — nur der *Publish*-Schritt eines bereits lokal gebauten
  Outputs ist als Automatisierungskandidat vorgesehen.
