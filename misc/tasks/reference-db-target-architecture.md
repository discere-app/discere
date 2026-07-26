# Reference-DB: Zielbild (Hosting & Automatisierung)

**Kategorie:** Architektur/Entscheidung · **Priorität:** Hoch · **Komplexität:** Mittel · **Status:** In Umsetzung

## Kurzbeschreibung

`discere_reference.db` (ETL-Output, ~400 MB) wird aus dem App-Bundle entfernt
und stattdessen zur Laufzeit heruntergeladen (siehe
[reduce-app-bundle-size.md](reduce-app-bundle-size.md) für den ursprünglichen
Auslöser). Dieses Dokument beschreibt die längerfristige Zielarchitektur, auf
die die aktuelle Umsetzung bewusst hinarbeitet, auch wenn einzelne Teile davon
(z. B. eine mögliche Codeberg→GitHub-Migration von `discere-data`) noch nicht
entschieden sind.

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
  unabhängige Stränge.** Eine mögliche Migration von `discere-data` nach
  GitHub (um `scripts/sync_index.sh` durch einen CI-Trigger zu ersetzen, siehe
  [deck-index-automation.md](deck-index-automation.md)) blockiert die
  Referenz-DB-Arbeit nicht und umgekehrt — beide können unabhängig
  voneinander angegangen werden.
- **Das App-Repo (`discere`) bleibt privat.** Es ist bereits heute auf GitHub
  gehostet und hat damit schon jetzt Zugriff auf GitHub Actions — der Schritt
  „Referenz-DB bauen & veröffentlichen" (`etl/publish_release.sh`) könnte dort
  automatisiert werden (z. B. `workflow_dispatch`), unabhängig davon, wo
  `discere-data` gehostet ist. Veröffentlicht wird nur der ETL-*Output*, nie
  der App-Code.
- **Hosting-Entscheidung ist bewusst spät gebunden.** Die App kennt zur
  Laufzeit nur eine feste Manifest-URL-Konstante (analog zu
  `RemoteDeckService._indexUrl`) und lädt die eigentliche DB-URL sowie
  Checksum aus dem Manifest nach. Ein Hosting-Wechsel (Codeberg → GitHub o. ä.)
  ist damit später nur: neues Release hochladen, Manifest-URL im App-Code
  anpassen — kein Umbau der Download-Logik.
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

Codeberg Releases im bestehenden `discere-data`-Repo (kein neues Repo, keine
neue Infrastruktur). Objektspeicher (Cloudflare R2, Backblaze B2 o. ä.) wäre
für ein Solo-/Nischenprojekt bei aktueller Downloadfrequenz und -größe
Overkill — kommt erst infrage, falls Egress-Kosten oder Zuverlässigkeit von
Git-Forge-Releases mal real zum Problem werden.

## Nicht im Zielbild

- Die `.db`-Datei wird **nie** als normaler Git-Blob committet, egal auf
  welcher Plattform — immer über Releases/Attachments, um unbegrenztes
  Repo-Wachstum über die Zeit zu vermeiden.
- Kein automatisierter ETL-Build in CI geplant (DuckDB-Pipeline mit
  Fishbase/SeaLifeBase-Downloads ist vermutlich zu lang/ressourcenintensiv für
  gehostete Runner) — nur der *Publish*-Schritt eines bereits lokal gebauten
  Outputs ist als Automatisierungskandidat vorgesehen.
