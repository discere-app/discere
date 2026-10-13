# Datenquellen: Konzept

Beschreibt, wie das ETL mit mehreren Datenquellen umgeht, die dieselben Arten
und Taxa betreffen: Quellen, die vorhandene Daten ergänzen (Namen, Synonyme,
Bilder, Merkmale), und Quellen, die zusätzlich eigene Arten mitbringen.

Das Dokument ist ein **Zielbild**. Was davon heute schon gilt, steht in
[Ist-Zustand](#ist-zustand); den Weg dorthin beschreibt
[Umsetzung](#umsetzung). Der aktuelle Plugin-Vertrag steht in
[`plugin-system.md`](plugin-system.md).

---

## Begriffe

- **Quelle** — ein Plugin unter `plugins/<name>/` mit Manifest,
  Strukturprüfung und einem Eintrag in `sources` (Lizenz, Zitierung). Das gilt
  auch für eigene Pflege, etwa von Hand kuratierte Namen: Sie ist eine Quelle
  wie jede andere.
- **Entität** — eine Art oder ein höheres Taxon in der Referenz-DB. Eine
  Entität ist ein **neutraler Anker**: Sie gehört keiner Quelle.
- **Beitrag** — alles, was eine Quelle zu einer Entität liefert: dass es sie
  gibt, ihre Einordnung, Namen, Synonyme, Bilder, Merkmale, Verbreitung,
  externe IDs. Jeder Beitrag trägt die `source` der Quelle, die ihn
  geschrieben hat.

Es gibt nur eine Beziehung: Eine Quelle liefert Beiträge zu Entitäten.
Einen Besitzer, der eine Entität exklusiv hält, gibt es nicht.

---

## Was eine Quelle darf

- **Beiträge zu jeder Entität liefern**, auch zu Entitäten, die andere
  Quellen zuerst geliefert haben. Geschrieben wird nur in Tabellen mit
  `source`-Spalte.
- **Neue Entitäten anlegen**, wenn der [Abgleich](#abgleich) keinen Treffer
  findet. Das Anlegen ist selbst nur ein Beitrag („diese Art gibt es“); die
  neue Entität gehört der Quelle danach nicht.
- **Beim Neuimport nur eigene Beiträge löschen** (`WHERE source = '<quelle>'`).
  Entitäten selbst löscht keine Quelle (siehe [Lebenszyklus](#lebenszyklus)).

---

## Abhängigkeiten und Reihenfolge

- Das Manifest nennt die Quellen, gegen deren Daten abgeglichen wird:

  ```yaml
  requires:
    - fishbase
  ```

- `build.sh` sortiert die Plugins danach und bricht bei einem Zyklus oder
  einer fehlenden Abhängigkeit ab. Ein Teilbuild mit `--plugin <name>` nimmt
  die Abhängigkeiten mit.
- Die Reihenfolge ist zugleich die **Rangfolge**: Eine Quelle, von der eine
  andere abhängt, geht ihr vor (siehe [Einordnung](#einordnung)).
- Quellen, die zur Build-Zeit Netzwerk brauchen, sagen das im Manifest.
  `--no-enrich` überspringt nur diese, nicht alle ergänzenden Quellen.

---

## Abgleich

Ob ein Datensatz einer Quelle eine schon vorhandene Entität meint, entscheidet
eine gemeinsame Funktion in `core/`, nicht jedes Plugin für sich:

1. über eine **externe ID**, die beide Seiten kennen (`entity_external_ids`,
   z. B. eine WoRMS-AphiaID);
2. sonst über den **wissenschaftlichen Namen samt Synonymen**
   (`species_name_lookup`), auf demselben Rang;
3. ist das Ergebnis **mehrdeutig, gibt es keinen Treffer**, sondern einen
   Eintrag im Build-Bericht. Geraten wird nie: Ein sichtbares Doppel lässt sich
   zusammenführen, zwei vermischte Arten lassen sich kaum wieder trennen.

Ein Treffer heißt: Die Quelle hängt ihre Beiträge an. Kein Treffer heißt: Die
Quelle legt die Entität an und hängt sie unter einen Elternteil, den sie über
denselben Abgleich findet oder selbst anlegt.

---

## Identität

### IDs tragen keine Quelle

Eine ID ist ein Name ohne Bedeutung: `discere:species:<nr>`. Sie sagt nicht,
welche Quelle die Entität zuerst geliefert hat, und sie ändert sich nie.

### Das Register vergibt IDs stabil

Das ETL baut die Referenz-DB bei jedem Lauf neu (`create_db.sh --force`).
Stabile IDs kann es deshalb nicht aus dem Datenstand eines Builds ableiten:
Liefert eine zweite Quelle später dieselbe Art und läuft im nächsten Build
zuerst, entstünde sonst eine andere ID.

Ein **ID-Register** hält über alle Releases fest, welcher Quellenschlüssel
(Quelle, Entitätstyp, externe Nummer) zu welcher ID gehört. Ein Build liest
das Register des letzten Releases, vergibt IDs nur für wirklich neue
Entitäten und schreibt das fortgeschriebene Register mit dem Release heraus.

Das Register gehört zum Release: Geht es verloren, werden IDs neu vergeben und
die Lernstände der Nutzer zeigen ins Leere. Ohne gültiges Register bricht der
Build ab.

### Aliase führen Entitäten zusammen

Erweisen sich zwei Entitäten als dieselbe Art — ein Abgleich hat sie verfehlt,
oder eine Quelle schließt die Lücke später —, bleibt eine ID gültig und die
andere wird zum Alias:

- Die Referenz-DB führt `entity_aliases(alias_id → entity_id)`.
- Die App schreibt beim Wechsel auf eine neue Referenz-DB alle Verweise von
  Alias-IDs auf die gültige ID um, bevor sie die neue DB benutzt: in einer
  Transaktion, idempotent, bei angehaltener Anreicherung.
- Die Alias-ID bleibt als weich gelöschte Entität erhalten.

Betroffen sind die Tabellen der Nutzer-DB, die IDs aus der Referenz-DB
speichern: Lernstände und Deck-Zugehörigkeit (`flashcard_stats`), die
Anreicherung (`enrichment_*`), Laufzeitnamen und ihre Suchdokumente, der Cache
externer IDs, der iNat-Foto-Cache und die Quittierungen fehlender Fotos.
Export, Teilen und QR-Codes enthalten nur wissenschaftliche Namen
(`CreateDeck.toJson`) und sind von einem Alias nicht betroffen.

Eine ältere App, die keine Aliase anwenden kann, darf eine solche Referenz-DB
nicht installieren. Das sichert die Schemaversion im Manifest:
`ReferenceDatabaseProvisioner.supportedSchemaVersion` lehnt jede andere
Version ab.

---

## Einordnung

Jede Quelle, die eine Art kennt, kann ihre Einordnung (Gattung, Familie, …)
als Beitrag liefern. Es gilt die Einordnung der ranghöchsten Quelle nach der
[Rangfolge](#abhängigkeiten-und-reihenfolge). Abweichende Einordnungen anderer
Quellen meldet der Build, er übernimmt sie nicht.

## Lebenszyklus

Eine Entität ist aktiv, solange mindestens eine Quelle sie liefert. Liefert
keine Quelle sie mehr, wird sie weich gelöscht (`status = 'deprecated'`), nie
entfernt — Nutzer-Daten können auf sie zeigen. Das entscheidet ein Schritt
nach allen Plugins, nicht jede Quelle für sich.

## Merkmale

Die Spalten mit Merkmalen direkt in `species` (Größe, Tiefe, Lebensraum,
Gefährdung, …) befüllen FishBase und SeaLifeBase. Weitere Quellen schreiben
Merkmale nicht in diese Spalten, sondern nach ihrer Form:

- ein Wert je Entität → `taxonomy_traits` (`source` ist Teil des Schlüssels);
- mehrere Werte je Entität (Länder, Monate, Meeresgebiete) → eine eigene
  Tabelle nach dem Muster von `taxonomy_distribution_regions`;
- sprachabhängige Texte (Beschreibungen) → eine eigene Tabelle nach dem Muster
  von `common_names`.

---

## Lizenz

Eine Quelle wird nur aufgenommen, wenn ihre Lizenz die Weitergabe in der
Referenz-DB erlaubt oder eine schriftliche Erlaubnis vorliegt; die Erlaubnis
wird in `source.sql` vermerkt. Lizenzen je Datensatz (etwa je Bild) führt der
Datensatz selbst, wie heute schon `pictures`.

---

## Ist-Zustand

| Teil des Konzepts | Heute |
|---|---|
| Quelle als Plugin mit Manifest und `sources`-Eintrag | ja, für FishBase und SeaLifeBase |
| Beiträge mit `source` | ja (`common_names`, `pictures`, `taxonomy_traits`, …) |
| Weiches Löschen von Arten | ja, je Quelle für ihre eigenen Arten |
| `requires` und Sortierung | nein — Reihenfolge alphabetisch |
| Abgleich in `core/` | nein — FishBase und SeaLifeBase legen über ihre eigenen Nummern an und überschneiden sich nicht |
| IDs ohne Quelle, Register | nein — IDs werden berechnet und tragen die Quelle (`discere:fishbase_species:<nr>`); `schema.sql` prüft das Format mit `GLOB 'discere:*_*:*'` |
| Aliase | nein |
| Netzwerk-Merkmal im Manifest | nein — `--no-enrich` überspringt die ganze Stage 03 |
| iNaturalist-Zuordnung | als Sonderweg in Stage 03 (`enrichment/inaturalist/`), ohne Manifest und `sources`-Eintrag |

---

## Umsetzung

### Übergang: nur Beiträge

Bis Register und Aliase stehen, dürfen weitere Quellen **nur Beiträge zu
vorhandenen Entitäten** liefern und keine Entitäten anlegen. Fehlt eine
Entität, landet der Datensatz im Build-Bericht.

### Schritte

1. **`requires` und Sortierung** in `build.sh`. Erster Anwendungsfall: die
   kuratierten Klassennamen als eigene Quelle mit `requires: [fishbase]`
   (#298), die nur Beiträge liefert.
2. **Abgleich in `core/`.**
3. **Register und Aliase** — samt Umschreiben in der App und neuer
   Schemaversion.
4. **Umstellung aller IDs** auf das Format ohne Quelle: ein Release, in dem
   jede bisherige ID ein Alias auf ihre neue ist. Es erprobt den
   Alias-Mechanismus einmal vollständig, bevor er für einzelne Doppel gebraucht
   wird. Der `GLOB` in `schema.sql` wird dabei auf `'discere:*:*'` gelockert.
5. **Danach** dürfen Quellen Entitäten anlegen.

Unabhängig davon: Die iNaturalist-Zuordnung wird eine Quelle mit
`requires: [fishbase, sealifebase]` und Netzwerk-Merkmal; Stage 03 entfällt.

### Offen

- **Wo das Register liegt.** Kandidaten: als versionierte Datei im Repo
  (nachvollziehbar, aber mehrere MB, die mit jedem Release wachsen); in
  `discere-data` neben jeder veröffentlichten Referenz-DB (gehört damit zum
  Release); oder aus der zuletzt veröffentlichten Referenz-DB gelesen (kein
  weiteres Artefakt, aber ~400 MB Download je Build). Bevorzugt:
  `discere-data`.
- **Wann die Schritte 2–5 umgesetzt werden.** Nötig werden sie mit der ersten
  Quelle, die Arten anlegen soll.

---

## Beispiele

| Quelle | Liefert | Legt Arten an |
|---|---|---|
| Kuratierte Klassennamen | Namen de/fr/es für FishBase-Klassen ohne iNaturalist-Gegenstück | nein |
| iNaturalist | externe IDs | nein |
| WoRMS | AphiaID, Lebensraum-Flags, gültiger Name | nein |
| Crab Database | englische Namen, Synonyme, Fotos; Krabbenarten, die SeaLifeBase fehlen | ja — erst nach Schritt 5; dazu fehlt heute die Lizenz („All rights reserved“) |
