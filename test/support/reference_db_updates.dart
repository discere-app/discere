import 'dart:async';
import 'dart:io';

import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/reference_db_manifest.dart';
import 'package:discere/shared/persistence/reference_db_update_service.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:discere/shared/service/network_availability.dart';

/// Offers version 3 of about 90 MB, and "downloads" it by reporting
/// [progressSteps], waiting for [release] and writing a file — or failing
/// with [downloadError].
class FakeReferenceDbDownloader implements ReferenceDbDownloader {
  int manifestVersion = 3;
  Object? manifestError;
  Object? downloadError;
  Completer<void>? release;
  List<double> progressSteps = const [];
  int downloads = 0;

  @override
  Future<ReferenceDbManifest> fetchManifest() async {
    if (manifestError case final error?) throw error;
    return ReferenceDbManifest([_releaseOf(manifestVersion)]);
  }

  @override
  Future<void> downloadAndInstall(
    ReferenceDbRelease offered,
    String destinationPath, {
    required void Function(double progress)? onProgress,
  }) async {
    downloads++;
    for (final step in progressSteps) {
      onProgress?.call(step);
    }
    await release?.future;
    if (downloadError case final error?) throw error;
    await File(destinationPath).writeAsString('staged database');
  }
}

class FakeNetworkAvailability implements NetworkAvailability {
  bool onWifi = true;

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get onlineStatusChanges => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isOnWifi() async => onWifi;
}

ReferenceDbUpdateService buildReferenceDbUpdates(
  FakeReferenceDbDownloader downloader,
) => ReferenceDbUpdateService(
  provisioner: ReferenceDatabaseProvisioner(
    downloader: downloader,
    closeOpenDatabases: () async {},
  ),
  networkAvailability: FakeNetworkAvailability(),
);

/// Holds whatever state a widget test sets, without running anything.
class FixedReferenceDbUpdates extends ReferenceDbUpdateService {
  FixedReferenceDbUpdates(this._fixed)
    : super(
        provisioner: ReferenceDatabaseProvisioner(
          downloader: FakeReferenceDbDownloader(),
          closeOpenDatabases: () async {},
        ),
        networkAvailability: FakeNetworkAvailability(),
      );

  ReferenceDbUpdateState _fixed;
  int downloadCalls = 0;
  int checkCalls = 0;

  @override
  ReferenceDbUpdateState get state => _fixed;

  set fixed(ReferenceDbUpdateState state) {
    _fixed = state;
    notifyListeners();
  }

  @override
  Future<void> download() async => downloadCalls++;

  @override
  Future<void> checkNow() async => checkCalls++;
}

/// An update to [version] as the manifest offers it, of about 90 MB.
ReferenceDbUpdateInfo referenceDbUpdateOf(int version) =>
    ReferenceDbUpdateInfo.ofRelease(_releaseOf(version));

ReferenceDbRelease _releaseOf(int version) => ReferenceDbRelease(
  version: version,
  schemaVersion: 2,
  url: 'https://example.invalid/reference.db.gz',
  sha256: '',
  compressedSizeBytes: 90 * 1024 * 1024,
);
