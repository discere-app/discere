# Image Storage Filename Collision Bug

**Kategorie:** Bugfix · **Status:** Erledigt ✅ (2026-03-31, im Code verifiziert)

## Kurzbeschreibung

`ImageService._downloadAndSaveImage()` leitete den lokalen Dateinamen aus dem
letzten URL-Pfadsegment ab. Bei FishBase-URLs ist das eindeutig, bei
iNaturalist-URLs nicht (`.../photos/12345/medium.jpeg` vs.
`.../photos/67890/medium.jpeg` → beide `medium.jpeg`). Ergebnis: Fotos
verschiedener Species überschrieben sich gegenseitig im Cache.

## Technisch notwendig

- Paket `crypto` (MD5-Hashing) — bestätigt in `pubspec.yaml` (`crypto: ^3.0.7`).

## Lösungsidee (umgesetzt)

MD5-Hash der vollständigen URL als Dateiname, Dateiendung aus dem
Original-Pfad übernommen (Fallback `.jpg`). Garantiert Eindeutigkeit
unabhängig von der URL-Struktur und dedupliziert identische URLs automatisch.

## Probleme

Keine offenen. Regressionstest vorhanden:
`test/service/common/image_service_test.dart` ("downloadAndSaveImages
handles colliding filenames via hashing").

## Empfehlung

Kein aktiver Task mehr — Datei kann archiviert oder gelöscht werden.
