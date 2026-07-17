import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/service/enrichment_job_ports.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/util/logger.dart';

class INatNameResolutionService implements ScientificNameResolutionPort {
  static final _log = Logger.forType(INatNameResolutionService);

  final SpeciesRepository _speciesRepository;
  final INaturalistService _iNatService;

  const INatNameResolutionService(this._speciesRepository, this._iNatService);

  @override
  Future<Map<String, String>> resolveNames(List<String> names) async {
    final result = <String, String>{};

    for (final originalName in names) {
      final normalizedQuery = _normalizeToBinomial(originalName);
      if (normalizedQuery.isEmpty) continue;

      try {
        final taxa = await _iNatService.searchTaxa(normalizedQuery);
        final candidateBinomials = taxa
            .map((row) => row['scientific_name'] as String?)
            .whereType<String>()
            .map(_normalizeToBinomial)
            .where((name) => name.isNotEmpty)
            .toList();
        if (candidateBinomials.isEmpty) continue;

        final resolvedCandidates = await _speciesRepository.resolveFullNames(
          candidateBinomials,
        );

        for (final candidate in candidateBinomials) {
          final speciesId = resolvedCandidates[candidate];
          if (speciesId != null) {
            result[originalName] = speciesId;
            _log.debug(
              'Resolved "$originalName" via iNat candidate "$candidate"',
            );
            break;
          }
        }
      } catch (error) {
        _log.warn('iNat name resolution failed for "$originalName": $error');
      }
    }

    return result;
  }

  String _normalizeToBinomial(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) return '';
    return '${parts[0]} ${parts[1]}';
  }
}
