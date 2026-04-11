enum HumanRisk {
  harmless,
  venomous,
  traumatogenic,
  ciguateraRisk,
  poisonousToEat,
  potentialPest,
  other;

  static HumanRisk? fromRaw(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'harmless':
        return HumanRisk.harmless;
      case 'venomous':
        return HumanRisk.venomous;
      case 'traumatogenic':
        return HumanRisk.traumatogenic;
      case 'reports of ciguatera poisoning':
        return HumanRisk.ciguateraRisk;
      case 'poisonous to eat':
        return HumanRisk.poisonousToEat;
      case 'potential pest':
        return HumanRisk.potentialPest;
      case 'other':
        return HumanRisk.other;
    }

    return null;
  }

  String get label {
    switch (this) {
      case HumanRisk.harmless:
        return 'Harmless';
      case HumanRisk.venomous:
        return 'Venomous';
      case HumanRisk.traumatogenic:
        return 'Traumatogenic';
      case HumanRisk.ciguateraRisk:
        return 'Reports of ciguatera poisoning';
      case HumanRisk.poisonousToEat:
        return 'Poisonous to eat';
      case HumanRisk.potentialPest:
        return 'Potential pest';
      case HumanRisk.other:
        return 'Other';
    }
  }
}
