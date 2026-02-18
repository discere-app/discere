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

### 5. Run the Application

Once the setup is complete, you can run the application on a connected device or simulator:

```sh
flutter run
```
