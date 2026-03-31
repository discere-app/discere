# 🚀 Discere: Production Release Roadmap

This document tracks the final remaining tasks for the version 1.0 release and future maintainability improvements.

## 🛠️ Technical Blockers

### 🚨 Android Release Signing
- [ ] **Generate Keystore**: Create a production Java Keystore (`.jks`).
- [ ] **Create key.properties**: Store keystore path and passwords (ensure it's in `.gitignore`).
- [ ] **Update build.gradle.kts**: Configure the `release` build type to use the new signing configuration.

### 🍎 iOS Preparation
- [ ] **Privacy Manifest**: Audit used APIs and ensure `PrivacyInfo.xcprivacy` represents all required declarations (e.g., `path_provider`).

---

## 📸 Store Assets & Metadata

- [ ] **Screenshots**: 
  - [ ] iPhone (6.5" and 5.5")
  - [ ] iPad Pro (12.9")
  - [ ] Android Phone & 10-inch Tablet
- [ ] **Privacy Policy**: 
  - [ ] Create a publicly accessible URL for the privacy policy.
- [ ] **Localized Descriptions**: 
  - [ ] Finalize "What's New" and "Full Description" for German and English.
- [ ] **Store Portals**: 
  - [ ] Register App IDs, Provisioning Profiles, and internal test tracks in App Store Connect and Google Play Console.

---

## 🧹 Technical Debt & Refactoring

- [ ] **ETL Pipeline**:
  - [ ] **Verify Stable UUIDs**: Confirm that the external ETL script uses v5 UUIDs (deterministic) to prevent user data loss during catalog updates.
- [ ] **Service Layer**:
  - [ ] Merge `FavoriteService` and `WatchListService` into a unified UserPreference service.
  - [ ] Split services layer further (SRP) and continue cleaning up `DecksService`.
- [ ] **Code Hygiene**:
  - [ ] Create a centralized `app_constants.dart` for all magic strings/values.
  - [ ] Clean up redundant log files in project root and remove empty/unused files.
  - [ ] Refactor `SpeciesRepository` SQL for improved readability/performance.
  - [ ] Extract frequently reused widgets into a dedicated widget library.
- [ ] **Infrastructure**:
  - [ ] Cleanup `AppHttpOverrides` if no longer required.

---

## 🧪 Final Verification & Polish

- [ ] **Physical Device Testing**:
  - [ ] Verify `flutter run --release` on a real Android device.
  - [ ] Verify `flutter run --release` on a real iOS device.
- [ ] **Bundle Analysis**:
  - [ ] Run `flutter build apk --analyze-size` and verify no unnecessary assets are included.
- [ ] **Code Audit**:
  - [ ] Ensure all `TODO` comments are resolved or tracked as future improvements.
