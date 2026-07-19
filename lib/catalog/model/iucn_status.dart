/// IUCN Red List category, as reported by iNaturalist's `conservation_status`
/// taxon field when its authority is "IUCN Red List".
///
/// [extinct] through [leastConcern] form the ordered threat spectrum shown as
/// a colored bar (matching the standard IUCN/Wikipedia badge design);
/// [dataDeficient] and [notEvaluated] fall outside that spectrum and render
/// as a plain neutral label instead.
enum IucnStatus {
  extinct,
  extinctInTheWild,
  criticallyEndangered,
  endangered,
  vulnerable,
  nearThreatened,
  leastConcern,
  dataDeficient,
  notEvaluated;

  static IucnStatus? fromRaw(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'ex':
        return IucnStatus.extinct;
      case 'ew':
        return IucnStatus.extinctInTheWild;
      case 'cr':
        return IucnStatus.criticallyEndangered;
      case 'en':
        return IucnStatus.endangered;
      case 'vu':
        return IucnStatus.vulnerable;
      case 'nt':
        return IucnStatus.nearThreatened;
      case 'lc':
        return IucnStatus.leastConcern;
      case 'dd':
        return IucnStatus.dataDeficient;
      case 'ne':
        return IucnStatus.notEvaluated;
    }

    return null;
  }

  /// Two-letter IUCN abbreviation, as used on the official badge.
  String get code {
    switch (this) {
      case IucnStatus.extinct:
        return 'EX';
      case IucnStatus.extinctInTheWild:
        return 'EW';
      case IucnStatus.criticallyEndangered:
        return 'CR';
      case IucnStatus.endangered:
        return 'EN';
      case IucnStatus.vulnerable:
        return 'VU';
      case IucnStatus.nearThreatened:
        return 'NT';
      case IucnStatus.leastConcern:
        return 'LC';
      case IucnStatus.dataDeficient:
        return 'DD';
      case IucnStatus.notEvaluated:
        return 'NE';
    }
  }

  bool get isOnThreatSpectrum => _threatSpectrum.contains(this);

  /// The ordered threat spectrum, from most to least severe, used to render
  /// the segmented status bar. [dataDeficient]/[notEvaluated] are
  /// deliberately excluded — they're not a position on the threat scale.
  static const List<IucnStatus> _threatSpectrum = [
    IucnStatus.extinct,
    IucnStatus.extinctInTheWild,
    IucnStatus.criticallyEndangered,
    IucnStatus.endangered,
    IucnStatus.vulnerable,
    IucnStatus.nearThreatened,
    IucnStatus.leastConcern,
  ];

  static List<IucnStatus> get threatSpectrum => _threatSpectrum;
}
