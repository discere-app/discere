import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/media/service/local_species_image_service.dart';
import 'package:discere/enrichment/media/service/species_photo_service.dart';

/// Orchestriert [SpeciesPhotoService] und [LocalSpeciesImageService] für
/// UI-seitige Use-Cases und ist der Einstiegspunkt für Species-Medien
/// ausserhalb dieses Ordners.
class SpeciesMediaService {
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

  /// Wie [resolveFromCache] für mehrere Species, aber mit einem gebündelten
  /// Species-Load, einem gebündelten Foto-Cache-Read und einer gebündelten
  /// Pfadauflösung: der Aufwand hängt an der Zahl der Abfragen, nicht an der
  /// Zahl der Species. Das ist der Pfad, über den eine Lernsession ihre
  /// fälligen Karten auflöst und eine Liste ihr erstes Rendering bekommt.
  Future<List<SpeciesWithLocalImages>> resolveAllFromCache(
    Set<String> speciesIds,
  ) => _resolveAll(speciesIds, download: false);

  /// Wie [resolveAllFromCache], lädt aber fehlende Bilder herunter — in einem
  /// einzigen Durchgang für die ganze Menge, nicht einem pro Species. Die
  /// externen (iNaturalist-)Downloads laufen darin strikt seriell, wie es die
  /// Rate-Limit-Regel in [LocalSpeciesImageService] verlangt. Das kostet hier
  /// nichts, weil kein Bildschirm auf diesen Aufruf wartet: ein Listen-Use-Case
  /// rendert aus [resolveAllFromCache] und übernimmt dieses Ergebnis nach,
  /// sobald es da ist.
  Future<List<SpeciesWithLocalImages>> resolveAllWithDownload(
    Set<String> speciesIds,
  ) => _resolveAll(speciesIds, download: true);

  /// Wie [resolveAllFromCache] für einen Aufrufer, der seine Species schon in
  /// der Hand hat: der Species-Load mit seinen Joins entfällt, es bleiben der
  /// gebündelte Foto-Cache-Read und die gebündelte Pfadauflösung. Das Ergebnis
  /// folgt der Reihenfolge von [species].
  ///
  /// [species] müssen so übergeben werden, wie der Species-Load sie liefert,
  /// also nur mit ihren Referenzbildern. Die Species in einem Ergebnis tragen
  /// die iNat-Fotos bereits in ihren `pictures`; wer sie erneut hier
  /// hineinreicht, bekommt jedes iNat-Foto doppelt.
  Future<List<SpeciesWithLocalImages>> resolveSpeciesFromCache(
    List<Species> species,
  ) => _resolveSpecies(species, download: false);

  Future<List<SpeciesWithLocalImages>> _resolveAll(
    Set<String> speciesIds, {
    required bool download,
  }) async {
    if (speciesIds.isEmpty) return [];
    final speciesById = {
      for (final species in await _speciesRepository.getSpecies(speciesIds))
        species.id: species,
    };

    // In der Reihenfolge der Anfrage, nicht in der taxonomischen des
    // Species-Loads: eine Liste zeigt ihre Einträge so, wie der Aufrufer sie
    // übergibt. Und weil beide Varianten dieselbe Reihenfolge liefern, kann ein
    // Aufrufer erst aus dem Cache rendern und das Download-Ergebnis später
    // übernehmen, ohne dass sich die Liste dabei umsortiert.
    final ordered = speciesIds
        .map((id) => speciesById[id])
        .whereType<Species>()
        .toList();

    return _resolveSpecies(ordered, download: download);
  }

  /// Der gemeinsame Kern aller gebündelten Auflösungen: ein Foto-Cache-Read
  /// und eine Pfadauflösung für die ganze Liste, in ihrer Reihenfolge.
  Future<List<SpeciesWithLocalImages>> _resolveSpecies(
    List<Species> species, {
    required bool download,
  }) async {
    if (species.isEmpty) return [];
    final picturesBySpeciesId = await _speciesPhotoService.getPhotosBySpeciesId(
      species,
    );

    return _localSpeciesImageService.resolveAll([
      for (final entry in species)
        (species: entry, pictures: picturesBySpeciesId[entry.id]!),
    ], download: download);
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

  /// Die Species aus [speciesIds], zu denen keine Bilddatei lokal liegt.
  ///
  /// Beantwortet nur diese Frage und lädt die Species dafür nicht: es genügen
  /// die Kandidaten-URLs — verwendbare Referenzbilder plus die Zeilen im
  /// iNat-Cache — und eine gebündelte Pfadauflösung. Beides sind indizierte
  /// Batch-Abfragen ohne Joins, während der volle [Species] mit Joins,
  /// Volksnamen, Traits und Regionen ein Vielfaches kostet.
  ///
  /// Ob „liegt nicht lokal" auch „gibt es nicht" heißt, entscheidet der
  /// Aufrufer: erst wenn die Bild-Stufen eines Decks abgeschlossen sind, ist
  /// ein fehlendes Bild eine Lücke und nicht bloß noch nicht geladen.
  Future<Set<String>> findSpeciesWithoutLocalImage(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return const {};
    final referencePictures = await _speciesRepository.getPicturesBySpeciesId(
      speciesIds,
    );
    final cachedPhotos = await _speciesPhotoService.getCachedPhotosBySpeciesId(
      speciesIds,
    );
    final candidatesBySpeciesId = {
      for (final speciesId in speciesIds)
        speciesId: [
          ...?referencePictures[speciesId],
          ...?cachedPhotos[speciesId],
        ],
    };

    final localPaths = await _localSpeciesImageService.resolveLocalPaths(
      candidatesBySpeciesId.values.expand((pictures) => pictures).toList(),
    );

    return {
      for (final entry in candidatesBySpeciesId.entries)
        if (!entry.value.any(
          (picture) => localPaths.containsKey(picture.url),
        ))
          entry.key,
    };
  }

  /// Prüft ob ein iNat-Cache-Eintrag für die Species vorhanden ist.
  /// Wird von der Species-Detailansicht genutzt um zu entscheiden, ob ein
  /// iNat-Fetch ausgelöst werden soll.
  Future<bool> hasEnrichedPhotos(String speciesId) {
    return _speciesPhotoService.hasCachedPhotos(speciesId);
  }
}
