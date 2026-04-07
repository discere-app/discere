# Species ETL Field Candidates

Diese Tabelle sammelt weitere potenziell interessante Artenfelder aus FishBase, SeaLifeBase und angrenzenden Enrichment-Quellen. Sie dient als Arbeitsgrundlage für weitere ETL-Schritte nach `size`, `depth`, `habitat` und `vulnerability`.

| Feldname | Beschreibung der Daten |
|---|---|
| `environment_type` | Grundtyp des Lebensraums, z.B. marin, brackig oder suesswasserbasiert. Nuetzlich fuer Filter, Suche und Deck-Zuschnitt. |
| `water_column_zone` | Lage in der Wassersaeule, z.B. benthisch, demersal, pelagisch, epipelagisch oder mesopelagisch. Praeziser als ein einziges Habitat-Label. |
| `substrate_type` | Typischer Untergrund wie Hartboden, Weichboden, Korallenriff, Seegras oder Mangroven. Gute Ergaenzung zu `habitat`. |
| `climate_zone` | Klimatische Einordnung wie tropical, subtropical, temperate oder polar. Hilfreich fuer thematische Lernsets. |
| `salinity_preference` | Bevorzugter Salzgehalt bzw. Toleranz gegenueber Suess-, Brack- oder Meerwasser. |
| `temperature_min_c` | Untere bekannte oder empfohlene Temperaturgrenze in Grad Celsius. |
| `temperature_max_c` | Obere bekannte oder empfohlene Temperaturgrenze in Grad Celsius. |
| `distribution_summary` | Verdichtete Beschreibung des geographischen Vorkommens, z.B. Indopazifik, Mittelmeer oder weltweit tropisch. |
| `native_regions` | Strukturierte Regionen oder Ozeanbecken, in denen die Art nativ vorkommt. |
| `introduced_regions` | Regionen, in denen die Art eingeschleppt oder invasiv ist. Fuer oekologische Einordnung und Quizlogik interessant. |
| `iucn_status` | Formeller Gefaehrdungsstatus wie LC, NT, VU, EN oder CR. Fachlich sauberer als der FishBase-`Vulnerability`-Score, falls verlässlich verfuegbar. |
| `resilience` | FishBase-typische Einschaetzung, wie schnell sich eine Population nach Rueckgang erholen kann. |
| `population_trend` | Richtung der Bestandsentwicklung, z.B. stabil, abnehmend oder zunehmend. |
| `diet_summary` | Grobe Ernaehrungsbeschreibung, z.B. Planktivore, Herbivore, Piscivore oder Omnivore. |
| `trophic_level` | Numerischer trophischer Level fuer die Einordnung in Nahrungsnetze. |
| `feeding_time` | Aktivitaetszeit der Nahrungsaufnahme, z.B. tagaktiv, nachtaktiv oder daemmerungsaktiv. Kandidat fuer das spaetere `activity`-Thema. |
| `reproduction_mode` | Fortpflanzungstyp wie ovipar, vivipar, ovovivipar, brooding oder vegetative Vermehrung. |
| `fecundity` | Angaben zur Anzahl von Eiern, Larven oder Nachkommen pro Reproduktionszyklus. |
| `longevity_years` | Typische oder maximale Lebensdauer in Jahren. |
| `size_at_maturity_cm` | Groesse bei Geschlechtsreife. Relevant fuer Biologie-Kontext und Lernkarten mit Fakten. |
| `migration_type` | Wanderverhalten wie resident, migratory, amphidromous, catadromous oder anadromous. |
| `schooling_behavior` | Ob die Art einzeln, paarweise oder in Gruppen bzw. Schwärmen lebt. |
| `dangerous_to_humans` | Hinweise auf Giftigkeit, Stachel, Bissrisiko oder sonstige Relevanz fuer Menschen. |
| `aquarium_suitability` | Ob und wie gut sich die Art fuer Aquarienhaltung eignet, inklusive Robustheit oder Haltungsanspruch. |
| `fisheries_importance` | Bedeutung fuer Fischerei oder kommerzielle Nutzung. |
| `aquaculture_use` | Relevanz der Art fuer Aquakultur oder Zucht. |
| `gamefish_importance` | Bedeutung fuer Sportfischerei bzw. Freizeitnutzung. |
| `body_shape` | Morphologische Kurzklassifikation, z.B. eel-like, laterally compressed oder ray-like. |
| `diagnostic_features` | Kurze, strukturierte Merkmale zur Bestimmung, etwa markante Flossen, Zeichnung oder Koerperform. |
