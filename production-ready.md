# Production Readiness Tasks 🚀

Dieses Dokument dient der Verfolgung aller kritischen Punkte, die vor dem Release der App "Discere" behoben werden müssen. 

## Aktuelle Tasks & Findings

| Task / Finding | Beschreibung | Risiko bei Nichtbeachtung | Aufwand | Priorität | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Deprecated Share API** | `Share.share` in `import_export_service.dart` ist veraltet. | App-Crash bei künftigen Flutter-Updates; Inkompatibilität. | 15m | **Hoch** | [x] |
| **Android Import Button Layout** | "Import"-Button wird auf Android von der Navigationsleiste verdeckt. | UI-Fehler; Kernfunktion ist nicht bedienbar. | 10m | **Hoch** | [x] |
| **Dummy Decks in Main** | `createDummyDecks()` wird bedingungslos in `main.dart` aufgerufen. | Echte Nutzer sehen Test-Daten; wirkt unprofessionell. | 10m | **Hoch** | [x] |
| **Auto-Initialisierung** | Decks fragen beim ersten Öffnen nach Aktivierung neuer Karten. | UX-Hürde; Nutzer muss unnötigen Klick machen beim Start. | 15m | **Hoch** | [x] |
| **Notification: Deck-Namen** | Zeigt UUID statt Deck-Namen in der Notification-Anzeige an. | Unprofessionell (UUID unlesbar). | 10m | **Mittel** | [x] |
| **Notification: i18n** | Texte sind statisch auf Deutsch codiert ("Zeit zum lernen"). | Sprachbarriere für internationale Nutzer. | 10m | **Mittel** | [x] |
| **Notification: Deep-Linking** | Notification öffnet nur die App, führt aber nicht direkt ins fällige Deck. | Schlechterer Workflow (Nutzer muss Deck manuell suchen). | 30m | **Gering** | [ ] |
| **Notification: Scheduling** | Rundungs-Logik (30-Min-Intervall) und ID-Generierung sind fehleranfällig. | Benachrichtigungen werden evtl. überschrieben oder nicht korrekt ausgelöst. | 45m | **Mittel** | [ ] |
| **Sprache pro Deck** | Aktuell ist die Sprache global im `LanguageService` konfiguriert. | Fehlende Flexibilität (z.B. Fisch-Arten auf versch. Sprachen pro Deck). | 45m | **Mittel** | [ ] |
| **iOS Permissions** | `Info.plist` fehlen Beschreibungen für Kamera, Galerie und Benachrichtigungen. | Ablehnung durch den App Store; App-Crash bei Zugriff. | 20m | **Hoch** | [x] |
| **Standalone Print-Logs** | Viele `print()` Aufrufe in Repositories und Services (unbewacht). | Informationsabfluss (Logging) in Produktion; unsauberer Code. | 30m | **Mittel** | [x] |
| **FSRS Stabilität** | `FsrsService` mit `_safeStability` und `_safeDifficulty` Guards stabilisiert. | Falsche Intervalle; Inkonsistenz im Lern-Algorithmus. | 20m | **Mittel** | [x] |
| **Remote Sync Error Handling** | `RemoteDeckService` nutzt nun `AppException` für UI-Feedback. | Nutzer-Frustration bei Verbindungsproblemen (leere Liste). | 1h | **Mittel** | [x] |
| **User DB Migration** | `DatabaseHelper` wirft `UnimplementedError` bei `onUpgrade`. | Künftige App-Updates führen zu Datenverlust bei Schema-Änderung. | 2h | **Hoch** | [x] |

## Legende

- **Priorität**: 
    - **Hoch**: Muss vor dem ersten Store-Upload behoben sein (Blocker).
    - **Mittel**: Wichtig für UX/Qualität, sollte kurzfristig behoben werden.
    - **Gering**: Kann nach dem initialen Release nachgereicht werden.
- **Aufwand**: Geschätzte Zeit für Implementierung und Test.

## Bug-Tracking & Priorisierung

Sobald ein neuer Bug gemeldet oder gefunden wird, wird er hier eingetragen und die Prioritäten der bestehenden Tasks werden neu bewertet.

---
*Letzte Aktualisierung: 2026-03-30 12:05*
