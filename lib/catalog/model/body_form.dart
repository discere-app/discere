enum BodyForm {
  elongated,
  fusiformNormal,
  shortOrDeep,
  eelLike,
  other;

  static BodyForm? fromRaw(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'elongated':
        return BodyForm.elongated;
      case 'fusiform / normal':
        return BodyForm.fusiformNormal;
      case 'short and / or deep':
        return BodyForm.shortOrDeep;
      case 'eel-like':
        return BodyForm.eelLike;
      case 'other':
      case 'other (see remarks)':
        return BodyForm.other;
    }

    return null;
  }

  String get label {
    switch (this) {
      case BodyForm.elongated:
        return 'Elongated';
      case BodyForm.fusiformNormal:
        return 'Fusiform / normal';
      case BodyForm.shortOrDeep:
        return 'Short and / or deep';
      case BodyForm.eelLike:
        return 'Eel-like';
      case BodyForm.other:
        return 'Other';
    }
  }
}
