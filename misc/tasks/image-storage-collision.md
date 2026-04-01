# Image Storage Filename Collision Bug

## Problem

`ImageService._downloadAndSaveImage()` derives the local filename from the URL's last path segment:

```dart
final String fileName = url.split('/').last;     // e.g. "medium.jpeg"
final String domainName = Uri.parse(url).host...;  // e.g. "static_inaturalist_org"
final String filePath = '$subDirectoryPath/$fileName';
```

**FishBase URLs** have unique filenames: `https://fishbase.net.br/images/species/Cohip_uo.jpg` → `Cohip_uo.jpg` ✅

**iNaturalist URLs** do NOT — the unique part is in the path, not the filename:
- `https://static.inaturalist.org/photos/12345/medium.jpeg` → `medium.jpeg`
- `https://static.inaturalist.org/photos/67890/medium.jpeg` → `medium.jpeg`

### Consequences

1. **Silent overwrite**: Every iNat image gets saved as `static_inaturalist_org/medium.jpeg`. The second download overwrites the first. All species end up showing the same (last-downloaded) photo.
2. **False cache hit**: `if (await file.exists()) return filePath` returns early — a different species' photo is served as if it were the correct one.

## Fix

Replace the filename derivation with a **hash-based or full-path-based** scheme that guarantees uniqueness across all URL structures.

### Option A — URL hash filename (recommended)

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

String _fileNameForUrl(String url) {
  final hash = md5.convert(utf8.encode(url)).toString();
  final ext = p.extension(Uri.parse(url).pathSegments.last);
  final suffix = ext.isNotEmpty ? ext : '.jpg';
  return '$hash$suffix';
}
```

Result: `a1b2c3d4e5f6...7890.jpeg` — unique, deterministic, no collisions.

**Pros:** Short filename, deterministic (same URL → same file = natural dedup), works for any URL structure.
**Cons:** Requires adding the `crypto` package (or using `hashCode`, which is not collision-safe).

### Option B — Encode full path segments

```dart
String _fileNameForUrl(String url) {
  final uri = Uri.parse(url);
  // Join path segments with underscore: "photos_12345_medium.jpeg"
  return uri.pathSegments.join('_');
}
```

Result: `photos_12345_medium.jpeg` — readable, unique.

**Pros:** No extra dependency, human-readable filenames.
**Cons:** Can get long for deeply nested URLs; potential filesystem issues on some platforms.

### Option C — Include path-based subdirectories

```dart
// Use the full URL path as directory structure:
// static_inaturalist_org/photos/12345/medium.jpeg
final segments = uri.pathSegments;
final fileName = segments.last;
final subPath = segments.sublist(0, segments.length - 1).join('/');
```

**Pros:** Mirrors the URL structure exactly.
**Cons:** Deep directory nesting, more filesystem operations.

## Recommendation

**Option A (URL hash)** is the safest and most general. It also naturally handles deduplication: if the same URL appears in multiple species (unlikely but possible), it gets the same hash → same file → downloaded once.

## Impact

- Existing FishBase images work fine today (unique filenames by coincidence)
- This bug **blocks iNaturalist integration from working correctly** — must be fixed before shipping
- Migration: could add a "re-download iNat cache" mechanism, or simply clear the cache on first run after the fix

---

## Status: Resolved ✅ (2026-03-31)

### Implementation
- **Implemented Option A (URL hash)** in `ImageService._downloadAndSaveImage`.
- Added `crypto` package to `pubspec.yaml`.
- Used MD5 hash of the entire URL as the filename, preserving extension with a `.jpg` fallback.
- Kept domain-based subdirectories for organized storage.

### Testing
- Added regression test `test/service/common/image_service_test.dart`: "downloadAndSaveImages handles colliding filenames via hashing".
- Verified that URLs with identical trailing segments (e.g., `medium.jpg`) now save to unique, hash-based filenames.
- All 8 unit tests for `ImageService` passed.

