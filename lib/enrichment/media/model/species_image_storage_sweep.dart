import 'package:discere/enrichment/media/model/species_image_sweep_trigger.dart';
import 'package:json_annotation/json_annotation.dart';

part 'species_image_storage_sweep.g.dart';

/// How a sweep of the species image storage went — kept for the diagnostics
/// page, which shows the last one, and timed, since how long a sweep takes
/// on a device is what decides whether it can stay in the start.
@JsonSerializable(explicitToJson: true)
class SpeciesImageStorageSweep {
  final DateTime sweptAt;

  @JsonKey(fromJson: SpeciesImageSweepTrigger.fromWire, toJson: _triggerToJson)
  final SpeciesImageSweepTrigger trigger;

  /// What was deleted, by storage directory.
  final Map<String, ImageDirectorySweep> directories;

  /// The species whose images are kept.
  final int neededSpeciesCount;

  /// The species whose photos and image work were let go.
  final int releasedSpeciesCount;

  final Duration duration;

  SpeciesImageStorageSweep({
    required this.sweptAt,
    required this.trigger,
    required Map<String, ImageDirectorySweep> directories,
    required this.neededSpeciesCount,
    required this.releasedSpeciesCount,
    required this.duration,
  }) : directories = Map.unmodifiable(directories);

  factory SpeciesImageStorageSweep.fromJson(Map<String, dynamic> json) =>
      _$SpeciesImageStorageSweepFromJson(json);

  Map<String, dynamic> toJson() => _$SpeciesImageStorageSweepToJson(this);

  static String _triggerToJson(SpeciesImageSweepTrigger trigger) =>
      trigger.wireName;
}

/// What a sweep deleted from one storage directory.
@JsonSerializable()
class ImageDirectorySweep {
  final int deletedFiles;
  final int freedBytes;

  const ImageDirectorySweep({
    required this.deletedFiles,
    required this.freedBytes,
  });

  factory ImageDirectorySweep.fromJson(Map<String, dynamic> json) =>
      _$ImageDirectorySweepFromJson(json);

  Map<String, dynamic> toJson() => _$ImageDirectorySweepToJson(this);
}
