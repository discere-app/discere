# Contributing to Discere

Thank you for your interest in contributing to Discere — a free, open-source
flashcard app for learning marine life and biological species. Contributions of
all kinds are welcome: bug reports, feature ideas, documentation, translations,
and code.

By participating in this project, you agree to abide by our
[Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to Contribute

- **Report a bug** — [open an issue](https://github.com/discere-app/discere/issues/new)
  with clear steps to reproduce, expected vs. actual behavior, and your platform
  and app version.
- **Suggest a feature** — [start a discussion](https://github.com/discere-app/discere/discussions)
  before writing code, so the idea can be discussed first.
- **Improve documentation** — the `docs/` directory holds the architecture
  overview and other developer docs.
- **Report a security issue** — please do *not* open a public issue. Follow the
  [Security Policy](SECURITY.md) instead.
- **Submit code** — see the workflow below.

## Development Setup

Discere is a Flutter application targeting Android and iOS. You will need the
[Flutter SDK](https://docs.flutter.dev/get-started/install) (`>=3.8.0`, see
`pubspec.yaml`) installed.

```bash
# Fork on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/discere.git
cd discere

flutter pub get
flutter gen-l10n                                          # localization
dart run build_runner build --delete-conflicting-outputs  # JSON serialization + test mocks
```

On first run, the app downloads the read-only species reference database at
startup — this needs an internet connection. See the [README](README.md) for
details.

For the architecture (module boundaries, dual-database design, DI wiring,
testing conventions), see [`CLAUDE.md`](CLAUDE.md) and
[`docs/architecture-overview.md`](docs/architecture-overview.md).

## Making Changes

1. **Create a feature branch** off `main`:
   ```bash
   git checkout -b feature/short-description
   ```
2. **Respect the module boundaries.** The app is organized as feature-based
   vertical slices (`catalog`, `enrichment`, `learning`, `app`, ...) with a
   one-directional dependency matrix enforced by
   `test/architecture/module_dependency_test.dart` — run
   `flutter test test/architecture/` after moving code between slices or
   adding a cross-slice import.
3. **Write tests alongside your change**, mirroring the `lib/` structure under
   `test/` (a file under `lib/learning/decks/foo.dart` gets its test at
   `test/learning/decks/foo_test.dart`).
4. **Regenerate code when needed.** Run
   `dart run build_runner build --delete-conflicting-outputs` after touching
   `@JsonSerializable` models, `@GenerateMocks` annotations, or `.arb`
   localization files (`flutter gen-l10n` for the latter).

## Before You Push

Run the same checks CI runs, locally, before opening a PR:

```bash
flutter analyze   # no analyzer warnings or infos
flutter test      # all unit tests must pass
```

## Submitting a Pull Request

1. Push your branch and open a pull request against `main`.
2. Describe what changed and why, and link any related issues.
3. Keep PRs focused and reasonably small — one logical change per PR is easier
   to review and merge.
4. Ensure CI passes (`.github/workflows/flutter_ci.yml`: analyze → test →
   build). Maintainers may request changes; discussion is part of the process.

### Commit messages

Keep commit messages short and focused on the functional/domain-level change —
what changed and why, not mechanical details like line counts or file lists
(`git diff`/`git log --stat` already show that).

## License

Discere is licensed under the [GNU AGPL v3.0](LICENSE), with one documented
exception for a bundled data fixture (see [NOTICE](NOTICE)). By contributing,
you agree that your contributions will be licensed under the same terms.