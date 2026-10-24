import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/repository/external_id_rejection_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_provenance_planner.dart';
import 'package:discere/enrichment/pipeline/repository/inat_provenance_repository.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Discards the iNaturalist data whose taxon an entity no longer maps to, once
/// per installed reference database (docs/enrichment.md, "Herkunft der
/// iNat-Daten").
///
/// The stored photos and names carry the iNat taxon they were fetched from;
/// this holds every stamp against the reference database's ids and
/// rejections and the cached ids ([INatProvenancePlanner] has the rules).
/// What goes is fetched again by the workers, or by the species page, under
/// the checked resolution.
///
/// Must run before anything fetches or reads iNat data — the bootstrap runs
/// it after the reference IDs are rewritten (`ReferenceIdMigration`), so the
/// stored ids match the database they are held against, and before it
/// builds any service.
///
/// Safe to repeat and to interrupt: the plan is applied in one transaction,
/// and the reference-database version is recorded under
/// [prefKeyReconciledVersion] only after it succeeded. Until then the next
/// start reconciles again.
class INatProvenanceReconciler {
  static final _log = Logger.forType(INatProvenanceReconciler);

  /// The reference-database version the stored iNat data was last reconciled
  /// with. Absent before the first run, which is what tells rows written
  /// without a stamp from a marker that found no taxon
  /// ([INatProvenanceRun.first]).
  static const prefKeyReconciledVersion = 'inat_provenance_reconciled_version';

  static const _planner = INatProvenancePlanner();

  final INatProvenanceRepository _provenance;
  final ExternalIdRepository _referenceIds;
  final ExternalIdRejectionRepository _rejections;
  final SharedPreferences _preferences;

  const INatProvenanceReconciler({
    required INatProvenanceRepository provenance,
    required ExternalIdRepository referenceIds,
    required ExternalIdRejectionRepository rejections,
    required SharedPreferences preferences,
  }) : _provenance = provenance,
       _referenceIds = referenceIds,
       _rejections = rejections,
       _preferences = preferences;

  /// Reconciles with the reference database at [installedVersion], unless
  /// that already happened.
  Future<void> reconcileIfNeeded({required int installedVersion}) async {
    final reconciledVersion = _preferences.getInt(prefKeyReconciledVersion);
    if (reconciledVersion == installedVersion) return;
    final run = reconciledVersion == null
        ? INatProvenanceRun.first
        : INatProvenanceRun.later;
    final stopwatch = Stopwatch()..start();

    final photoStamps = await _provenance.photoStamps();
    final nameStamps = await _provenance.nameStamps();
    final cachedTaxonIds = await _provenance.cachedTaxonIds();
    final entityIds = {
      ...photoStamps.keys,
      ...nameStamps.keys,
      ...cachedTaxonIds.keys,
    };
    final referenceTaxonIds = await _referenceIds.getExternalIdsForProvider(
      entityIds,
      ExternalIdProvider.inaturalist,
    );
    final rejected = await _rejections.rejectedAmong(
      entityIds,
      ExternalIdProvider.inaturalist,
    );

    final plan = _planner.plan([
      for (final entityId in entityIds)
        INatProvenanceFacts(
          entityId: entityId,
          referenceTaxonId: referenceTaxonIds[entityId],
          cachedTaxonId: cachedTaxonIds[entityId],
          isRejected: rejected.contains(entityId),
          photos: photoStamps.containsKey(entityId)
              ? INatDataStamp(photoStamps[entityId])
              : null,
          names: nameStamps.containsKey(entityId)
              ? INatDataStamp(nameStamps[entityId])
              : null,
        ),
    ], run);
    if (!plan.isEmpty) await _provenance.apply(plan);

    await _preferences.setInt(prefKeyReconciledVersion, installedVersion);
    _log.info(
      'iNat data reconciled with reference database $installedVersion '
      '(${run.name} run, ${entityIds.length} entities, '
      '${stopwatch.elapsedMilliseconds}ms): '
      'photos stamped ${plan.photosToStamp.length}, '
      'discarded ${plan.photosToDiscard.length}; '
      'names stamped ${plan.namesToStamp.length}, '
      'discarded ${plan.namesToDiscard.length}; '
      'cached ids dropped ${plan.cachedTaxonIdsToDrop.length}',
    );
  }
}
