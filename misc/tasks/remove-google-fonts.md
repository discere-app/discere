# Remove Runtime Google Fonts

## Context

The app currently uses `google_fonts` to apply Lexend in the ocean theme. When
Lexend is not bundled as a local asset, the package can fetch font files at
runtime and cache them on the device.

That adds an external Google dependency for typography, makes tests more
fragile when network access is intentionally blocked, and is awkward from a
privacy/DSGVO perspective.

## Proposed Change

Remove the `google_fonts` dependency and use the platform/system font instead.

For this app, Lexend is not essential to the product identity. The UI is carried
more by layout, colors, cards, lists, and interaction patterns than by a specific
web font.

## Implementation Notes

- Remove `google_fonts` from `pubspec.yaml`.
- Remove `package:google_fonts/google_fonts.dart` imports.
- Simplify `lib/theme/ocean_theme/ocean_theme.dart` to use the existing
  `TextTheme` directly, without `GoogleFonts.lexendTextTheme`.
- Remove `GoogleFonts.config.allowRuntimeFetching = false` from integration
  test setup.
- Run `flutter pub get`, `flutter analyze`, and the integration smoke test.

## Alternative

If Lexend becomes important for brand consistency, bundle the Lexend `.ttf`
files locally under `assets/fonts/`, register them in `pubspec.yaml`, and use
`fontFamily: 'Lexend'` without runtime fetching.
