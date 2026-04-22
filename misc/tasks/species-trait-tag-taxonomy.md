# Species Trait Tag Taxonomy

## Status

Backlog. The current implementation keeps a pragmatic single `HabitatTag` enum
for clear FishBase/SeaLifeBase habitat and water-zone values.

## Motivation

FishBase/SeaLifeBase habitat-like fields mix different kinds of information:

- actual habitats, for example `coral reef`, `mangroves`, `freshwater lake`
- water-column or depth-zone terms, for example `pelagic`, `demersal`,
  `benthic`, `bathypelagic`
- substrate terms, for example `hard bottom`, `soft bottom`
- life-style or association terms, for example `sessile`, `host`,
  `epiphytic`, `reef-associated`

Showing all of these as equal "habitat" chips is understandable for a first
version, but it is not fully precise.

## Current Behavior

- `HabitatTag` normalizes and localizes clear habitat and water-zone values.
- Values that are not normalized remain visible as raw fallback strings.
- `host`, `sessile`, `epiphytic`, `others`, `unknown`, and `reef-associated`
  are intentionally not normalized into `HabitatTag` yet.

## Future Direction

Introduce structured trait tags instead of one flat habitat enum.

Possible shape:

```dart
enum SpeciesTraitGroup {
  habitat,
  waterColumn,
  substrate,
  association,
  lifestyle,
}

class SpeciesTraitTag {
  final SpeciesTraitGroup group;
  final String key;
  final String label;
}
```

The UI could then render grouped chips:

```text
Lebensraum: Korallenriff, Mangrove
Wasserkörper-Zone: Pelagisch, Demersal
Substrat: Hartboden
Lebensweise/Assoziation: Sessil, Wirt-assoziiert
```

## Implementation Notes

- Move raw FishBase/SeaLifeBase trait classification into repository or ETL
  mapping code.
- Keep display labels localized in the presenter/UI layer.
- Preserve raw source values for debugging and future remapping.
- Avoid silently mapping `reef-associated` to `coral reef`; it may be useful as
  a separate association tag.
- Decide whether `taxonomy_traits` should store typed trait groups, or whether
  the app should classify existing `trait_key` and `species.habitat` values at
  read time.

## Open Questions

- Should grouped tags be shown in one section or separate subsections?
- Which groups should receive icons/colors?
- Should low-confidence/raw values be hidden, shown as "Other", or shown as
  source text?
- Should this be solved in ETL only, app only, or both?
