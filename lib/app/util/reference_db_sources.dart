import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/shared/persistence/closed_database_tolerance.dart';
import 'package:discere/shared/util/logger.dart';

/// The data sources of the installed reference database that name their
/// release, for the pages that show which database is installed.
///
/// A database that cannot be read costs that line, not the page: the
/// answer is then empty, and the failure is logged on [log] as a warning.
/// A database closed underneath the call by an in-app restart is not a
/// failure — the page is on its way out — and is not logged.
Future<List<Source>> loadReferenceDbSources(
  SourceService sourceService,
  ScopedLogger log,
) async {
  try {
    return await sourceService.getVersionedSources();
  } catch (error, stackTrace) {
    if (isClosedDatabaseError(error)) return const [];
    log.warn(
      'Reference DB sources unavailable',
      error: error,
      stackTrace: stackTrace,
    );
    return const [];
  }
}
