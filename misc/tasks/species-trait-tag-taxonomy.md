# Species Trait Tag Taxonomy

**Kategorie:** Feature (UI-Polish) · **Priorität:** Niedrig · **Komplexität:** Mittel · **Status:** Backlog, weiterhin relevant

## Kurzbeschreibung

FishBase/SeaLifeBase-Habitat-Felder vermischen unterschiedliche
Informationsarten: echte Habitate (`coral reef`, `mangroves`), Wassersäulen-/
Tiefenzonen (`pelagic`, `demersal`, `benthic`), Substrat (`hard bottom`) und
Lebensweise (`sessile`, `host`, `epiphytic`). Aktuell zeigt ein einziges
`HabitatTag`-Enum alles als gleichwertige Chips — verständlich als erste
Version, aber fachlich ungenau.

## Technisch notwendig

Keine externen Abhängigkeiten. Reine App-/ETL-interne Modellierung.

## Lösungsidee

Strukturierte Trait-Tags statt eines flachen Enums einführen:

```dart
enum SpeciesTraitGroup { habitat, waterColumn, substrate, association, lifestyle }

class SpeciesTraitTag {
  final SpeciesTraitGroup group;
  final String key;
  final String label;
}
```

UI rendert gruppierte Chips pro Kategorie (Lebensraum, Wasserzone, Substrat,
Lebensweise/Assoziation). Rohwerte aus der Quelle bleiben für Debugging und
künftiges Remapping erhalten. Klassifikation entweder in ETL/Repository-
Mapping oder zur Laufzeit im Presenter.

## Probleme / offene Fragen

- Ob Gruppen in einer Sektion oder separaten Subsektionen dargestellt werden.
- Welche Gruppen Icons/Farben bekommen.
- Umgang mit Low-Confidence/Rohwerten: verstecken, als „Sonstiges" zeigen,
  oder Quelltext anzeigen.
- Ob die Klassifikation nur im ETL, nur in der App, oder in beiden erfolgen
  soll.
- `reef-associated` nicht einfach auf `coral reef` mappen — eigener
  Assoziations-Tag sinnvoller.
