# Nutzer informieren, wenn für eine Species kein Foto gefunden wurde

**Kategorie:** Analyse + Feature-Vorschlag · **Status:** Entwurf (Stand 2026-07-22)

## Kurzbeschreibung

Anlass: Ein Bugfix in `EnrichmentService` (`fetchINatPhotosForSpecies`,
`backfillINatPhotosForSpecies`, `downloadBaseImagesForSpecies`) sorgt jetzt
dafür, dass eine Species erst dann als „fertig" gilt, wenn ihr Bild
tatsächlich lokal gespeichert wurde — nicht schon, wenn nur die Foto-URL von
iNaturalist bekannt war. Damit ist der Fall „Flashcard lädt ohne Bild, obwohl
eines verfügbar wäre" behoben (der Download wird jetzt so lange retried, bis
er klappt oder der Job endgültig fehlschlägt).

Ungelöst bleibt der **legitime** Fall: iNaturalist hat für eine Species
schlicht kein Foto (seltene/wenig beobachtete Art, falscher/unauffindbarer
Taxon-Match). Dieser Fall ist bereits heute als terminal-empty vorgesehen
(`INatPhotoCacheRepository`-Sentinel, `TaxonNotFoundException`-Pfad) — die
Species wird korrekt nicht endlos retried. Aber: **der Nutzer erfährt davon
nichts.** Die Flashcard erscheint beim Review einfach ohne Bild, ohne
Erklärung, warum.

Diese Datei sammelt den Ist-Zustand der relevanten Infrastruktur und
Optionen, wie man das sinnvoll kommunizieren könnte.

## Ist-Zustand

**Die Rohdaten existieren bereits, aber nicht aggregiert:**
- `inat_photo_cache` (`lib/enrichment/repository/inat_photo_cache_repository.dart:10-43`)
  speichert pro Species einen expliziten `__empty__`-Sentinel-Eintrag, wenn
  iNat kein Foto liefern konnte. Das ist die einzige verlässliche
  Wahrheitsquelle für „kein Foto gefunden" — aber es gibt aktuell keine
  Query, die das über die Species eines Decks aggregiert.
- `EnrichmentJobRecord`/`EnrichmentStageState`
  (`lib/enrichment/model/enrichment_job.dart:165-227`) sind **Stage-level für
  den ganzen Job**, nicht pro Species. `everySpeciesHasImage` prüft nur, ob
  die Pipeline für alle Species *fertig ist zu versuchen* — nicht wie viele
  tatsächlich ein Bild bekommen haben.
- `deck_session_presenter.dart` (`filterReviewableCards`) ist die einzige
  Stelle, die pro Karte zur Laufzeit „kein lokales Bild + Enrichment fertig"
  bereits auswertet — aber nur um zu entscheiden, ob die Karte überhaupt
  angezeigt wird, nicht um es zu kommunizieren.

**Bestehende UI-Bausteine, die nah dran sind, aber nicht passen:**
- `DeckEnrichmentHint` (`lib/learning/decks/deck_enrichment_hint.dart`) zeigt
  auf der Deck-Karte einen Status-Icon+Text, u. a. `DeckEnrichmentState.doneWithGaps`
  (`lib/enrichment/model/deck_enrichment_state.dart:29-31`) mit der
  generischen Meldung *„Enrichment complete – with gaps"* /
  *„Complete data could not be found for a few species."*
  (`inatDeckStateDoneWithGaps` / `inatDeckStateDescDoneWithGaps` in
  `lib/l10n/app_de.arb`, `app_en.arb`).
- Dieser Zustand wird aber aus `_sessionFailedDeckIds`
  (`lib/enrichment/service/inat_enrichment_queue_service.dart:143,588-591,696-697`)
  abgeleitet — nur gesetzt, wenn der **ganze Job** in der aktuellen App-Session
  permanent fehlschlägt. **Nicht persistiert**, **nicht pro Species**, und
  vermischt „kein Foto" mit „kein Common Name" in einer Meldung ohne Anzahl.

**Notifications:**
- Es gibt aktuell **keine** „Job fertig"-Benachrichtigung. Der
  Fortschritt läuft nur als Text in der Foreground-Service-Keepalive-Notification
  (`EnrichmentForegroundServiceKeeper`, „Loading (x/y species)"), die beim
  Jobende einfach verschwindet.
- `NotificationService.showNotification` (One-Shot-API,
  `lib/shared/service/notification_service.dart:205-218`) ist bereits
  implementiert, aber im gesamten `lib/`-Baum **ungenutzt** — ließe sich für
  eine Abschluss-Meldung wiederverwenden.

**Diagnostics:** `RunCompletionSummaryCollector` (dev-only, standardmäßig aus
in Release-Builds) zählt zwar Stage-Erfolge/-Fehler, behandelt aber ein
terminal-empty-Ergebnis explizit als „fully enriched" — kann die Frage „wie
viele Species ohne Foto" also auch für Entwickler heute nicht beantworten.

## Optionen (nicht priorisiert — zur Diskussion)

### A — Platzhalter-Hinweis direkt in der Flashcard
**Komplexität:** Niedrig · **Neue Persistenz nötig:** Nein

Wenn eine fällige Karte kein lokales Bild hat und `imageStagesComplete` auf
Deck-Ebene bereits `true` ist (das ist exakt der Zustand, den
`filterReviewableCards` schon heute unterscheidet), zeigt die Flashcard statt
eines leeren/generischen Platzhalters einen expliziten Hinweis („Für diese
Art ist kein Foto verfügbar" + kleines Icon). Nutzt ausschließlich bereits
berechneten State in `DeckPage`/`DeckSessionPresenter`, keine neue Query, kein
neues Model.

**Nachteil:** Rein reaktiv — der Nutzer erfährt es erst mitten im Review,
nicht vorher, und es gibt keine Deck-weite Übersicht, wie viele Arten
betroffen sind.

### B — Deck-Karte: `doneWithGaps` photo-spezifisch und persistent machen
**Komplexität:** Mittel · **Neue Persistenz nötig:** Ja (aggregierte Zählung)

Eine neue Repository-Query (z. B. in `SpeciesMediaService` oder einem neuen
`EnrichmentJobRepository`-Aufruf) ermittelt für ein Deck, wie viele Species
weder ein Referenzbild noch einen `inat_photo_cache`-Treffer haben (Join
gegen den Sentinel). Wird einmalig berechnet, sobald die Bild-Stages
(`base`, `inatPrimary`, ggf. `inatBackfill`) terminal sind — z. B. getriggert
aus `EnrichmentJobExecutor` beim Stage-Übergang, Ergebnis in
`enrichment_jobs` oder einer neuen Spalte/Tabelle abgelegt, damit es
Session-Neustarts übersteht (anders als das aktuelle `_sessionFailedDeckIds`).

`DeckEnrichmentHint` bekäme eine eigene, photo-spezifische Meldung mit
Zahl, z. B. *„Für 3 von 42 Arten wurde kein Foto gefunden"* statt der
generischen Gaps-Meldung. Neue `l10n`-Strings nötig (aktuell existiert dafür
noch keine Kopie).

**Nachteil:** Größerer Schnitt — neue Query, neue Persistenz, Änderung an
`DeckEnrichmentState`/`INatEnrichmentQueueService`, mehr Testfläche.

### C — Einmalige Abschluss-Notification
**Komplexität:** Mittel-Hoch · **Neue Persistenz nötig:** Ja (für die
Aggregation, s. Option B — Voraussetzung für sinnvollen Inhalt)

Beim Abschluss der Bild-Stages eine echte System-Notification via des
bereits vorhandenen, aber toten `NotificationService.showNotification`
schicken: *„Anreicherung von [Deckname] abgeschlossen — für 3 Arten kein
Foto gefunden"*. Baut auf derselben Aggregations-Query wie Option B auf,
braucht zusätzlich einen Trigger-Punkt im Job-Lifecycle
(`INatEnrichmentQueueService`/`EnrichmentJobExecutor`) und Notification-
Permission-Handling (bereits vorhanden für die tägliche Lern-Erinnerung,
aber bisher nicht für Enrichment genutzt).

**Nachteil:** Größter Aufwand; Gefahr von Notification-Müdigkeit, wenn
Nutzer viele Decks importieren (ggf. bündeln/debouncen nötig). Für Nutzer,
die die App gerade offen haben, redundant zu Option A/B.

### D — Species-Liste/Watchlist-Badge
**Komplexität:** Mittel · **Neue Persistenz nötig:** Ja (wie B)

Kleines Icon in der Species-Zeile innerhalb der Deck-Detailansicht (nicht
nur beim Review), das anzeigt „kein Foto gefunden" — analog zu bestehenden
Rang-/Status-Icons. Nutzt dieselbe Aggregation wie Option B, aber pro
Species statt als Deck-Summe. Sinnvoll kombinierbar mit B, eher redundant
ohne sie.

## Einschätzung

Die Rohdaten (Sentinel-Einträge pro Species) sind schon da — der fehlende
Teil ist durchgängig die **Aggregation auf Deck-Ebene** und deren
**Persistenz über Sessions hinweg** (aktuell nur `_sessionFailedDeckIds`,
flüchtig). Das ist der gemeinsame Kern von B, C und D; A kommt ohne aus.

Empfehlung als Einstieg: **A zuerst** (kleiner, unabhängiger Fix mit
sofortigem Nutzen, macht das „kein Foto"-Silent-Verhalten wenigstens
sichtbar), danach **B**, weil es die einzige Stelle ist, die dem Nutzer vor
dem Review eine ehrliche Deck-weite Aussage gibt und die bestehende
`doneWithGaps`-UI ohnehin schon fast das Richtige tut, nur zu ungenau. C nur
in Erwägung ziehen, falls Nutzer-Feedback zeigt, dass A+B nicht ausreichen
(Notifications sind teurer zu pflegen und leichter nervig).
