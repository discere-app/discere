import 'package:package_info_plus/package_info_plus.dart';

/// What `main()` would have read from the platform, which a host test has
/// not got. The version is deliberately not the one in pubspec.yaml, so a
/// test cannot pass by finding that number somewhere else.
final installedPackage = PackageInfo(
  appName: 'Discere',
  packageName: 'ch.feberle.discere',
  version: '2.3.4',
  buildNumber: '56',
);
