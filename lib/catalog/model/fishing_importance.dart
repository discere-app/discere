enum FishingImportance {
  commercial,
  highlyCommercial,
  minorCommercial,
  subsistenceFisheries,
  bycatch,
  potentialInterest,
  noInterest,
  industrial;

  static FishingImportance? fromRaw(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'commercial':
        return FishingImportance.commercial;
      case 'highly commercial':
        return FishingImportance.highlyCommercial;
      case 'minor commercial':
        return FishingImportance.minorCommercial;
      case 'subsistence fisheries':
        return FishingImportance.subsistenceFisheries;
      case 'bycatch':
        return FishingImportance.bycatch;
      case 'of potential interest':
        return FishingImportance.potentialInterest;
      case 'of no interest':
      case 'of no interest|':
        return FishingImportance.noInterest;
      case 'industrial':
        return FishingImportance.industrial;
    }

    return null;
  }

  String get label {
    switch (this) {
      case FishingImportance.commercial:
        return 'Commercial';
      case FishingImportance.highlyCommercial:
        return 'Highly commercial';
      case FishingImportance.minorCommercial:
        return 'Minor commercial';
      case FishingImportance.subsistenceFisheries:
        return 'Subsistence fisheries';
      case FishingImportance.bycatch:
        return 'Bycatch';
      case FishingImportance.potentialInterest:
        return 'Of potential interest';
      case FishingImportance.noInterest:
        return 'Of no interest';
      case FishingImportance.industrial:
        return 'Industrial';
    }
  }
}
