# Discere

Discere is a Flutter-based flashcard application designed to help users learn and memorize information effectively.

## Developer Setup

To get started with the project, please follow the steps below after cloning the repository.

### 1. Prerequisites

Ensure you have a complete Flutter development environment set up. You can verify your setup by running:

```sh
flutter doctor -v
```

### 2. Get Dependencies

Download all the project's dependencies by running the following command from the root of the project:

```sh
flutter pub get
```

### 3. Generate Localization Files

The project uses code generation for localization. To generate the necessary files, run:

```sh
flutter gen-l10n
```

### 4. Generate Code for Serializable Models

The project also uses code generation for JSON serialization. Run the following command to generate the required files:

```sh
dart run build_runner build --delete-conflicting-outputs
```

### 5. Generate Assets (Optional)

If the splash screen or launcher icons need to be updated:

#### Splash Screen
```sh
# Regenerate splash screen assets
dart run flutter_native_splash:create
```

#### Launcher Icons
```sh
# Regenerate launcher icons
dart run flutter_launcher_icons
```

### 6. Run the Application

Once the setup is complete, you can run the application on a connected device or simulator:

```sh
flutter run
```

## Architecture

See [`misc/architecture-overview.md`](misc/architecture-overview.md) for a full architecture overview including module structure, database schema (ERD), FSRS 6 algorithm details, and service wiring.

**In brief:** Discere uses a layered service-repository architecture with two SQLite databases:
- `discere_reference.db` — read-only, bundled as an app asset; contains species taxonomy, reference images, and offline iNaturalist ID mappings
- `discere_user.db` — read-write; contains decks, flashcard review progress, per-deck config, and runtime caches
