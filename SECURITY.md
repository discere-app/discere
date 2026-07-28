# Security Policy

## Supported Versions

Discere does not yet maintain parallel release lines. Security fixes are applied
to the latest published version only.

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, use GitHub's Private Vulnerability Reporting: open the
["Report a vulnerability"](https://github.com/discere-app/discere/security/advisories/new)
button on the [Security tab](https://github.com/discere-app/discere/security) of
this repository.

### What to include

- A description of the vulnerability and its potential impact
- Steps to reproduce or a proof of concept
- The version(s) affected
- Any suggested fix, if you have one

### What to expect

- **Acknowledgment** within 48 hours of your report
- **Status update** within 7 days with an initial assessment
- **Resolution target** of 30 days for confirmed vulnerabilities, though critical
  issues will be prioritized for faster fixes
- Credit in the release notes (unless you prefer to remain anonymous)

### Scope

The following are in scope for security reports:

- The Discere application (Android, iOS)
- Data handling: the local user database (`discere_user.db`), deck
  import/export/sharing (QR code, JSON, text)
- Download and verification of the reference species database
  (`ReferenceDatabaseProvisioner`, manifest/checksum handling)
- Network calls to third-party services (iNaturalist API)
- The build and release pipeline (CI/CD), if it could compromise end users

The following are out of scope:

- Vulnerabilities in third-party dependencies (report these to the upstream
  project, but let us know so we can update)
- The read-only species reference data itself (taxonomy content accuracy is not
  a security concern)
- Social engineering attacks
- Denial of service attacks

## Security Practices

- No secrets (signing keys, credentials) are committed to the repository; the
  Android keystore and its passwords are kept outside version control
- GitHub secret scanning and push protection are enabled
- CI (`flutter analyze`, `flutter test`) runs on every push and pull request
- Dependencies are reviewed before adoption