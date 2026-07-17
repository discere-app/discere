import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/service/local_species_image_service.dart';
import 'package:discere/enrichment/service/species_photo_service.dart';
import 'package:discere/shared/util/concurrency_utils.dart';

/// Orchestriert [SpeciesPhotoService] und [LocalSpeciesImageService] für
/// UI-seitige Use-Cases. Ist der einzige Einstiegspunkt für Species-Medien
/// ausserhalb von catalog/service und enrichment/service.
class SpeciesMediaService {
  // Matches ImageService's own download concurrency cap — resolveAllWithDownload
  // fans out over a whole watchlist/deck, each entry potentially triggering a
  // real network download, so it needs the same bound.
  static const _maxConcurrentDownloads = 6;

  final SpeciesRepository _speciesRepository;
  final SpeciesPhotoService _speciesPhotoService;
  final LocalSpeciesImageService _localSpeciesImageService;

  const SpeciesMediaService(
    this._speciesRepository,
    this._speciesPhotoService,
    this._localSpeciesImageService,
  );

  /// Gibt Species mit lokal gecachten Bildern zurück. Kein Netzwerkzugriff,
  /// kein Download fehlender Bilder — schnell für initiales Rendering.
  Future<SpeciesWithLocalImages?> resolveFromCache(String speciesId) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    final pictures = await _speciesPhotoService.getPhotos(species);
    return _localSpeciesImageService.resolve(
      species,
      pictures,
      download: false,
    );
  }

  /// Wie [resolveFromCache], fetcht aber live von iNat wenn kein Cache-Eintrag
  /// vorhanden ist. Für den iNat-Refresh in der Species-Detailansicht.
  Future<SpeciesWithLocalImages?> resolveWithFetch(String speciesId) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    final pictures = await _speciesPhotoService.getPhotosWithFallback(species);
    return _localSpeciesImageService.resolve(
      species,
      pictures,
      download: false,
    );
  }

  /// Gibt Species mit Bildern zurück und lädt fehlende Bilder herunter.
  /// Für Flashcard-Ladevorgang, bei dem Bilder vollständig verfügbar sein
  /// müssen.
  Future<SpeciesWithLocalImages?> resolveWithDownload(String speciesId) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    final pictures = await _speciesPhotoService.getPhotos(species);
    return _localSpeciesImageService.resolve(
      species,
      pictures,
      download: true,
    );
  }

  /// Returns cached media immediately and downloads at most one missing image
  /// for the currently focused flashcard when needed.
  Future<SpeciesWithLocalImages?> resolveEnsuringSingleImage(
    String speciesId,
  ) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    final pictures = await _speciesPhotoService.getPhotos(species);
    return _localSpeciesImageService.resolveEnsuringSingleImage(
      species,
      pictures,
    );
  }

  /// Gibt mehrere Species mit Bildern zurück und lädt fehlende Bilder herunter.
  /// Für Watchlist und andere Listen-Use-Cases.
  Future<List<SpeciesWithLocalImages>> resolveAllWithDownload(
    Set<String> speciesIds,
  ) async {
    final results = await runWithConcurrency<String, SpeciesWithLocalImages?>(
      speciesIds.toList(),
      maxConcurrent: _maxConcurrentDownloads,
      task: resolveWithDownload,
    );
    return results.whereType<SpeciesWithLocalImages>().toList();
  }

  /// Prüft ob ein iNat-Cache-Eintrag für die Species vorhanden ist.
  /// Wird von der Species-Detailansicht genutzt um zu entscheiden, ob ein
  /// iNat-Fetch ausgelöst werden soll.
  Future<bool> hasEnrichedPhotos(String speciesId) {
    return _speciesPhotoService.hasCachedPhotos(speciesId);
  }
}
