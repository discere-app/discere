# Reduce App Bundle Size

## Context

The Android app bundle is currently about 94 MB. That is large for the current
scope of the app and should be investigated before production release.

The likely contributors are bundled assets, especially the reference database,
image/media assets, native dependencies, and generated Flutter build artifacts.

## Goal

Reduce the release app bundle size without removing required offline
functionality.

## Investigation

- Build a release app bundle and inspect the size:
  `flutter build appbundle --release`
- Generate a size analysis report:
  `flutter build appbundle --release --analyze-size`
- Inspect the Flutter size report for:
  - asset contribution
  - native library contribution per ABI
  - Dart AOT snapshot size
  - package-level code size
- Check whether `assets/database/discere_reference.db` dominates the bundle.
- Check whether unused assets are included via broad asset declarations such as
  `assets/`.
- Compare APK splits / ABI splits against the app bundle contents.

## Possible Improvements

- Replace broad asset includes with explicit asset paths where possible.
- Compress or restructure the bundled reference database.
- Remove unused generated data or columns from the reference database.
- Consider shipping the reference database as a compressed asset and unpacking
  it on first run if startup cost is acceptable.
- Review native dependencies and plugins for avoidable platform payload.
- Remove runtime Google Fonts or other optional dependencies if they contribute
  meaningfully to size.

## Acceptance Criteria

- Document the main size contributors.
- Produce before/after bundle sizes.
- Keep offline startup and reference search working.
- Keep integration smoke test passing after any packaging changes.
