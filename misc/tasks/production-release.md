# Production Release Roadmap

**Kategorie:** Roadmap/Checkliste · **Status:** Veraltet — App bereits live (v1.0.3+17)

## Kurzbeschreibung

Ursprünglich die Checkliste für den 1.0-Release. Im Repo verifiziert: die
App ist bereits als `1.0.3+17` released, Android-Signing ist konfiguriert
(`android/app/key.properties` existiert, `build.gradle.kts` referenziert
den `release`-Signing-Config). Die Release-Vorbereitung selbst ist damit
erledigt — dieser Task ist keine aktive Roadmap mehr.

## Gegengeprüfter Status der Einzelpunkte

| Punkt | Status |
|---|---|
| Android Release Signing (Keystore, `key.properties`, `build.gradle.kts`) | ✅ Erledigt |
| `app_constants.dart` für Magic Strings | ✅ Erledigt (`lib/shared/util/constants.dart`) |
| `FavoriteService`/`WatchListService` zusammenführen | ❌ Weiterhin getrennt (`lib/learning/service/favorite_service.dart`, `lib/catalog/service/watchlist_service.dart`) |
| iOS Privacy Manifest (`PrivacyInfo.xcprivacy`) für die App selbst | ❌ Nur in Pods vorhanden, keine App-eigene Datei gefunden |
| Store-Assets, Screenshots, Store-Portale | Nicht code-seitig verifizierbar — vermutlich erledigt, da App live ist |

## Technisch notwendig

Keines mehr für die Release-Vorbereitung selbst.

## Verbleibende offene Punkte (nach architecture-improvements.md verschoben)

Die wenigen noch offenen technischen Punkte sind kein Release-Blocker mehr,
sondern normale Tech-Debt-Posten und werden dort geführt:
- `FavoriteService`/`WatchListService`-Merge
- Weitere SRP-Aufteilung großer Services

## Empfehlung

Datei archivieren oder löschen — als aktive Checkliste nicht mehr
zutreffend. Falls iOS Privacy Manifest für die eigene App tatsächlich noch
fehlt, das als eigenständigen kleinen Task neu aufsetzen statt in dieser
veralteten Roadmap zu belassen.
