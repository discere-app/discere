# Species ETL Field Candidates

Diese Tabelle sammelt pragmatische Kandidaten auf Species-Ebene aus FishBase / SeaLifeBase, die fuer die App nuetzlich sein koennten. Ich war dabei bewusst eher grosszuegig als streng.

Hinweise:

- Die Abdeckung unten basiert auf `FishBase v24.07` und zaehlt `DISTINCT SpecCode` gegen alle Species aus `species.parquet`.
- SeaLifeBase hat fuer die hier betrachteten Parquets weitgehend dieselben Dateinamen und sehr aehnliche Schemas.
- In der Spalte `parquet` steht jeweils die Datei plus die konkrete Quellspalte.

| Feldname | parquet | wert (einfach ein wert aus dem parquet) | was der wert ausdrueckt | prozentsatz (wie viele species haben hier ein wert) |
|---|---|---|---|---|
| `body_shape` | `species.parquet -> BodyShapeI` | `Elongated` | Morphologischer Koerpertyp; eher Formkategorie als harte Messung. | `100.0%` |
| `environment_type` | `species.parquet -> DemersPelag` | `bathydemersal` | Lage im Wasserkörper bzw. grobe Habitat-Zone der Art. | `100.0%` |
| `vulnerability` | `species.parquet -> Vulnerability` | `10.0` | FishBase-Vulnerabilitaetsscore fuer Befischungs-/Populationsrisiko. | `100.0%` |
| `dangerous_to_humans` | `species.parquet -> Dangerous` | `Harmless` | Kurzlabel zur Relevanz oder Gefaehrlichkeit fuer Menschen. | `99.6%` |
| `native_regions` | `country.parquet -> CurrentPresence` | `Present` | Präsenzstatus pro Laender-/Regionseintrag; nutzbar als Baustein fuer native Verbreitung. | `98.2%` |
| `population_status` | `country.parquet -> Status` | `Native` | Status innerhalb eines Landes, z.B. nativ, eingefuehrt oder unsicher. | `98.2%` |
| `threatened_flag` | `country.parquet -> Threatened` | `0` | Einfaches Bedrohungs-Flag im Country-Kontext, kein IUCN-Status. | `98.2%` |
| `aquarium_suitability` | `species.parquet -> Aquarium` | `commercial` | Eignung oder Einordnung fuer Aquaristik, oft als Markt-/Haltungslabel. | `93.6%` |
| `distribution_summary` | `country.parquet -> Comments` | `Type locality of Bleekeria murtii, off Tuticorin.` | Freitext zur regionalen Verbreitung, Einfuehrung oder Besonderheiten je Land/Region. | `92.8%` |
| `freshwater_stream_association` | `ecology.parquet -> Stream` | `-1` | Bool-/Flag-artiger Hinweis auf Vorkommen in Fluss- oder Bachsystemen. | `35.1%` |
| `lake_association` | `ecology.parquet -> Lakes` | `-1` | Bool-/Flag-artiger Hinweis auf Vorkommen in Seen. | `35.1%` |
| `mangrove_association` | `ecology.parquet -> Mangroves` | `-1` | Bool-/Flag-artiger Hinweis auf Zusammenhang mit Mangrovenhabitaten. | `35.1%` |
| `reef_association` | `ecology.parquet -> CoralReefs` | `-1` | Bool-/Flag-artiger Hinweis auf Riffbindung bzw. Riffvorkommen. | `35.1%` |
| `seagrass_association` | `ecology.parquet -> SeaGrassBeds` | `-1` | Bool-/Flag-artiger Hinweis auf Seegras-Habitate. | `35.1%` |
| `fisheries_importance` | `species.parquet -> Importance` | `bycatch` | Grobe wirtschaftliche oder fischereiliche Bedeutung der Art. | `29.5%` |
| `trophic_level_food` | `ecology.parquet -> FoodTroph` | `2.0` | Numerischer trophischer Level aus Food-Daten. | `22.7%` |
| `feeding_type` | `ecology.parquet -> FeedingType` | `browsing on substrate` | Verbale Beschreibung der Nahrungsaufnahme bzw. Fressweise. | `20.6%` |
| `country_abundance` | `country.parquet -> Abundance` | `abundant (always seen in some numbers)` | Laender-/regionsspezifische qualitative Haeufigkeit. | `16.4%` |
| `country_importance` | `country.parquet -> Importance` | `commercial` | Bedeutung der Art in einem konkreten Laenderkontext. | `14.0%` |
| `diet_summary` | `ecology.parquet -> DietRemark` | `Troph of juv./adults from 1 study.` | Freitextliche Ernaehrungs- oder Trophik-Zusammenfassung aus Studienangaben. | `5.2%` |
| `trophic_level_diet` | `ecology.parquet -> DietTroph` | `1.64` | Numerischer trophischer Level aus Diet-Daten. | `5.2%` |
| `aquarium_breeding` | `aquarium.parquet -> Breeding` | `1` | Aquarium-spezifischer Hinweis, ob bzw. wie Nachzucht bekannt ist. | `4.4%` |
| `aquarium_husbandry` | `aquarium.parquet -> Husbandry` | `?` | Haltungshinweise oder Schwierigkeitsgrad im Aquarium-Kontext. | `4.3%` |
| `longevity_years` | `species.parquet -> LongevityWild` | `0.16` | Beobachtete oder publizierte Lebensdauer in der Wildbahn. | `4.0%` |
| `climate_vulnerability` | `species.parquet -> VulnerabilityClimate` | `10.58` | Klimabezogener Vulnerabilitaets-Score. | `2.3%` |
| `landing_statistics` | `species.parquet -> LandingStatistics` | `from 1,000 to 10,000` | Grobe Fangmengen-/Anlandungs-Kategorie. | `1.6%` |
| `activity_pattern` | `ecology.parquet -> Circadian1` | `diurnal` | Aktivitaetsmuster, z.B. tagaktiv oder nachtaktiv. | `0.6%` |
| `schooling_behavior` | `ecology.parquet -> SchoolingFrequency` | `always` | Angabe zur Schwarm- oder Gruppenbildung. | `0.2%` |
| `life_cycle` | `species.parquet -> LifeCycle` | `life cycle closed in commercial culture` | Freitext zur Vollstaendigkeit bzw. Schliessung des Lebenszyklus, oft im Kultur-/Zuchtkontext. | `0.1%` |

## Taxonomy ETL Field Candidates

Diese Tabelle sammelt Felder oberhalb der Species-Ebene. Der Prozentsatz bezieht sich hier jeweils auf die Entitaeten der betreffenden Rangtabelle, also z.B. alle `families` oder alle `genera` und nicht auf Species.

| Stufe | Feldname | parquet | wert (einfach ein wert aus dem parquet) | was der wert ausdrueckt | prozentsatz (wie viele entities haben hier ein wert) |
|---|---|---|---|---|---|
| `class` | `body_shape` | `classes.parquet -> BodyShapeI` | `eel-like` | Grobe Form- oder Erscheinungskategorie fuer die Klasse. | `100.0%` |
| `class` | `water_salinity` | `classes.parquet -> WaterSalinity` | `all freshwater` | Salinitaetsbezug der Klasse. | `100.0%` |
| `class` | `common_name` | `classes.parquet -> CommonName` | `bichirs` | Alltagsname auf Klassenebene. | `94.1%` |
| `class` | `remarks` | `classes.parquet -> Remarks` | `As Infraclass Dipnomorpha...` | Taxonomischer oder redaktioneller Freitext zur Klasse. | `70.6%` |
| `class` | `species_count` | `classes.parquet -> SpeciesCount` | `1` | Anzahl zugeordneter Species in dieser Klasse. | `58.8%` |
| `order` | `common_name` | `orders.parquet -> CommonName` | `Australian lungfishes` | Alltagsname auf Ordnungsebene. | `100.0%` |
| `order` | `sister_order` | `orders.parquet -> SisterOrder` | `Acipenseriformes` | Schwesterordnung aus der phylogenetischen Einordnung. | `100.0%` |
| `order` | `species_count` | `orders.parquet -> SpeciesCount` | `1` | Anzahl zugeordneter Species in dieser Ordnung. | `100.0%` |
| `order` | `water_salinity` | `orders.parquet -> WaterSalinity` | `all freshwater` | Salinitaetsbezug der Ordnung. | `100.0%` |
| `order` | `classification_remark` | `orders.parquet -> ClassificationRemark` | `In Ref. 114953: Aetobatidae...` | Freitext zur taxonomischen Abgrenzung oder Zusammensetzung der Ordnung. | `47.5%` |
| `order` | `phylogeny_families` | `orders.parquet -> PhylogenyFamilies` | `Gill et al (2019: Ref YYY).` | Referenz oder Kommentar zur phylogenetischen Familienzuordnung. | `2.0%` |
| `family` | `common_name` | `families.parquet -> CommonName` | `"Brycon characins"` | Alltagsname auf Familienebene. | `99.7%` |
| `family` | `water_salinity` | `families.parquet -> WaterSalinity` | `All Freshwater` | Typische Salinitaetsbindung der Familie. | `97.1%` |
| `family` | `species_count` | `families.parquet -> SpeciesCount` | `1` | Anzahl zugeordneter Species in der Familie. | `96.5%` |
| `family` | `body_shape` | `families.parquet -> BodyShapeI` | `eel-like` | Grobe Formkategorie der Familie. | `93.2%` |
| `family` | `division` | `families.parquet -> Division` | `Marine` | Grobe Umwelt- oder Bereichseinordnung der Familie. | `89.1%` |
| `family` | `swim_mode` | `families.parquet -> SwimMode` | `amiiform` | Bewegungs- oder Schwimmtyp auf Familienebene. | `76.6%` |
| `family` | `etymology` | `families.parquet -> Etymology` | `A Burmese local name for a fish` | Herleitung oder Bedeutung des Familiennamens. | `74.5%` |
| `family` | `reproductive_guild` | `families.parquet -> ReprGuild` | `Guarders` | Typischer Fortpflanzungs- oder Brutpflege-Guild der Familie. | `68.4%` |
| `family` | `activity` | `families.parquet -> Activity` | `active` | Grobes Aktivitaetsmuster der Familie. | `29.3%` |
| `genus` | `water_salinity` | `genera.parquet -> WaterSalinity` | `All marine` | Typische Salinitaetsbindung der Gattung. | `45.3%` |
| `genus` | `subfamily` | `genera.parquet -> Subfamily` | `Acanthoclininae` | Zugeordnete Unterfamilie der Gattung. | `43.2%` |
| `genus` | `diagnosis` | `genera.parquet -> Diagnosis` | `size small to moderate...` | Diagnostischer Bestimmungsfreitext fuer die Gattung. | `19.5%` |
| `genus` | `distribution` | `genera.parquet -> Distribution` | `Eastern tropical Atlantic coast.` | Freitext zur geographischen Verbreitung der Gattung. | `8.2%` |
| `genus` | `body_shape` | `genera.parquet -> BodyShapeI` | `eel-like` | Grobe Formkategorie auf Gattungsebene. | `4.4%` |
| `genus` | `tribe` | `genera.parquet -> Tribe` | `120639` | Zugeordneter Stamm/Tribe-Identifikator oder Referenzwert. | `3.9%` |
| `genus` | `habitat` | `genera.parquet -> Habitat` | `0-340 m` | Freitext oder verdichtete Habitat-/Tiefenangabe zur Gattung. | `3.7%` |
| `genus` | `common_name` | `genera.parquet -> GenComName` | `????` | Alltagsname auf Gattungsebene. | `1.6%` |

## Taxonomy DuckDB SQL

Dieses SQL erzeugt genau die Kennzahlen fuer die Taxonomietabelle oben.

```sql
WITH class_total AS (
    SELECT COUNT(DISTINCT ClassNum) AS n
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/classes.parquet')
),
order_total AS (
    SELECT COUNT(DISTINCT Ordnum) AS n
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/orders.parquet')
),
family_total AS (
    SELECT COUNT(DISTINCT FamCode) AS n
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/families.parquet')
),
genus_total AS (
    SELECT COUNT(DISTINCT GenCode) AS n
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/genera.parquet')
),
metrics AS (
    SELECT 'class' AS stufe, 'body_shape' AS field_name, 'classes.parquet -> BodyShapeI' AS parquet_name,
           MIN(CAST(BodyShapeI AS VARCHAR)) FILTER (WHERE BodyShapeI IS NOT NULL AND trim(CAST(BodyShapeI AS VARCHAR)) <> '') AS sample_value,
           COUNT(DISTINCT ClassNum) FILTER (WHERE BodyShapeI IS NOT NULL AND trim(CAST(BodyShapeI AS VARCHAR)) <> '') AS entities_with_value,
           (SELECT n FROM class_total) AS total_entities
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/classes.parquet')

    UNION ALL
    SELECT 'class', 'water_salinity', 'classes.parquet -> WaterSalinity',
           MIN(CAST(WaterSalinity AS VARCHAR)) FILTER (WHERE WaterSalinity IS NOT NULL AND trim(CAST(WaterSalinity AS VARCHAR)) <> ''),
           COUNT(DISTINCT ClassNum) FILTER (WHERE WaterSalinity IS NOT NULL AND trim(CAST(WaterSalinity AS VARCHAR)) <> ''),
           (SELECT n FROM class_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/classes.parquet')

    UNION ALL
    SELECT 'class', 'common_name', 'classes.parquet -> CommonName',
           MIN(CAST(CommonName AS VARCHAR)) FILTER (WHERE CommonName IS NOT NULL AND trim(CAST(CommonName AS VARCHAR)) <> ''),
           COUNT(DISTINCT ClassNum) FILTER (WHERE CommonName IS NOT NULL AND trim(CAST(CommonName AS VARCHAR)) <> ''),
           (SELECT n FROM class_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/classes.parquet')

    UNION ALL
    SELECT 'class', 'remarks', 'classes.parquet -> Remarks',
           MIN(CAST(Remarks AS VARCHAR)) FILTER (WHERE Remarks IS NOT NULL AND trim(CAST(Remarks AS VARCHAR)) <> ''),
           COUNT(DISTINCT ClassNum) FILTER (WHERE Remarks IS NOT NULL AND trim(CAST(Remarks AS VARCHAR)) <> ''),
           (SELECT n FROM class_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/classes.parquet')

    UNION ALL
    SELECT 'class', 'species_count', 'classes.parquet -> SpeciesCount',
           MIN(CAST(SpeciesCount AS VARCHAR)) FILTER (WHERE SpeciesCount IS NOT NULL),
           COUNT(DISTINCT ClassNum) FILTER (WHERE SpeciesCount IS NOT NULL),
           (SELECT n FROM class_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/classes.parquet')

    UNION ALL
    SELECT 'order', 'common_name', 'orders.parquet -> CommonName',
           MIN(CAST(CommonName AS VARCHAR)) FILTER (WHERE CommonName IS NOT NULL AND trim(CAST(CommonName AS VARCHAR)) <> ''),
           COUNT(DISTINCT Ordnum) FILTER (WHERE CommonName IS NOT NULL AND trim(CAST(CommonName AS VARCHAR)) <> ''),
           (SELECT n FROM order_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/orders.parquet')

    UNION ALL
    SELECT 'order', 'sister_order', 'orders.parquet -> SisterOrder',
           MIN(CAST(SisterOrder AS VARCHAR)) FILTER (WHERE SisterOrder IS NOT NULL AND trim(CAST(SisterOrder AS VARCHAR)) <> ''),
           COUNT(DISTINCT Ordnum) FILTER (WHERE SisterOrder IS NOT NULL AND trim(CAST(SisterOrder AS VARCHAR)) <> ''),
           (SELECT n FROM order_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/orders.parquet')

    UNION ALL
    SELECT 'order', 'species_count', 'orders.parquet -> SpeciesCount',
           MIN(CAST(SpeciesCount AS VARCHAR)) FILTER (WHERE SpeciesCount IS NOT NULL),
           COUNT(DISTINCT Ordnum) FILTER (WHERE SpeciesCount IS NOT NULL),
           (SELECT n FROM order_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/orders.parquet')

    UNION ALL
    SELECT 'order', 'water_salinity', 'orders.parquet -> WaterSalinity',
           MIN(CAST(WaterSalinity AS VARCHAR)) FILTER (WHERE WaterSalinity IS NOT NULL AND trim(CAST(WaterSalinity AS VARCHAR)) <> ''),
           COUNT(DISTINCT Ordnum) FILTER (WHERE WaterSalinity IS NOT NULL AND trim(CAST(WaterSalinity AS VARCHAR)) <> ''),
           (SELECT n FROM order_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/orders.parquet')

    UNION ALL
    SELECT 'order', 'classification_remark', 'orders.parquet -> ClassificationRemark',
           MIN(CAST(ClassificationRemark AS VARCHAR)) FILTER (WHERE ClassificationRemark IS NOT NULL AND trim(CAST(ClassificationRemark AS VARCHAR)) <> ''),
           COUNT(DISTINCT Ordnum) FILTER (WHERE ClassificationRemark IS NOT NULL AND trim(CAST(ClassificationRemark AS VARCHAR)) <> ''),
           (SELECT n FROM order_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/orders.parquet')

    UNION ALL
    SELECT 'order', 'phylogeny_families', 'orders.parquet -> PhylogenyFamilies',
           MIN(CAST(PhylogenyFamilies AS VARCHAR)) FILTER (WHERE PhylogenyFamilies IS NOT NULL AND trim(CAST(PhylogenyFamilies AS VARCHAR)) <> ''),
           COUNT(DISTINCT Ordnum) FILTER (WHERE PhylogenyFamilies IS NOT NULL AND trim(CAST(PhylogenyFamilies AS VARCHAR)) <> ''),
           (SELECT n FROM order_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/orders.parquet')

    UNION ALL
    SELECT 'family', 'common_name', 'families.parquet -> CommonName',
           MIN(CAST(CommonName AS VARCHAR)) FILTER (WHERE CommonName IS NOT NULL AND trim(CAST(CommonName AS VARCHAR)) <> ''),
           COUNT(DISTINCT FamCode) FILTER (WHERE CommonName IS NOT NULL AND trim(CAST(CommonName AS VARCHAR)) <> ''),
           (SELECT n FROM family_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/families.parquet')

    UNION ALL
    SELECT 'family', 'water_salinity', 'families.parquet -> WaterSalinity',
           MIN(CAST(WaterSalinity AS VARCHAR)) FILTER (WHERE WaterSalinity IS NOT NULL AND trim(CAST(WaterSalinity AS VARCHAR)) <> ''),
           COUNT(DISTINCT FamCode) FILTER (WHERE WaterSalinity IS NOT NULL AND trim(CAST(WaterSalinity AS VARCHAR)) <> ''),
           (SELECT n FROM family_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/families.parquet')

    UNION ALL
    SELECT 'family', 'species_count', 'families.parquet -> SpeciesCount',
           MIN(CAST(SpeciesCount AS VARCHAR)) FILTER (WHERE SpeciesCount IS NOT NULL),
           COUNT(DISTINCT FamCode) FILTER (WHERE SpeciesCount IS NOT NULL),
           (SELECT n FROM family_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/families.parquet')

    UNION ALL
    SELECT 'family', 'body_shape', 'families.parquet -> BodyShapeI',
           MIN(CAST(BodyShapeI AS VARCHAR)) FILTER (WHERE BodyShapeI IS NOT NULL AND trim(CAST(BodyShapeI AS VARCHAR)) <> ''),
           COUNT(DISTINCT FamCode) FILTER (WHERE BodyShapeI IS NOT NULL AND trim(CAST(BodyShapeI AS VARCHAR)) <> ''),
           (SELECT n FROM family_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/families.parquet')

    UNION ALL
    SELECT 'family', 'division', 'families.parquet -> Division',
           MIN(CAST(Division AS VARCHAR)) FILTER (WHERE Division IS NOT NULL AND trim(CAST(Division AS VARCHAR)) <> ''),
           COUNT(DISTINCT FamCode) FILTER (WHERE Division IS NOT NULL AND trim(CAST(Division AS VARCHAR)) <> ''),
           (SELECT n FROM family_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/families.parquet')

    UNION ALL
    SELECT 'family', 'swim_mode', 'families.parquet -> SwimMode',
           MIN(CAST(SwimMode AS VARCHAR)) FILTER (WHERE SwimMode IS NOT NULL AND trim(CAST(SwimMode AS VARCHAR)) <> ''),
           COUNT(DISTINCT FamCode) FILTER (WHERE SwimMode IS NOT NULL AND trim(CAST(SwimMode AS VARCHAR)) <> ''),
           (SELECT n FROM family_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/families.parquet')

    UNION ALL
    SELECT 'family', 'etymology', 'families.parquet -> Etymology',
           MIN(CAST(Etymology AS VARCHAR)) FILTER (WHERE Etymology IS NOT NULL AND trim(CAST(Etymology AS VARCHAR)) <> ''),
           COUNT(DISTINCT FamCode) FILTER (WHERE Etymology IS NOT NULL AND trim(CAST(Etymology AS VARCHAR)) <> ''),
           (SELECT n FROM family_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/families.parquet')

    UNION ALL
    SELECT 'family', 'reproductive_guild', 'families.parquet -> ReprGuild',
           MIN(CAST(ReprGuild AS VARCHAR)) FILTER (WHERE ReprGuild IS NOT NULL AND trim(CAST(ReprGuild AS VARCHAR)) <> ''),
           COUNT(DISTINCT FamCode) FILTER (WHERE ReprGuild IS NOT NULL AND trim(CAST(ReprGuild AS VARCHAR)) <> ''),
           (SELECT n FROM family_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/families.parquet')

    UNION ALL
    SELECT 'family', 'activity', 'families.parquet -> Activity',
           MIN(CAST(Activity AS VARCHAR)) FILTER (WHERE Activity IS NOT NULL AND trim(CAST(Activity AS VARCHAR)) <> ''),
           COUNT(DISTINCT FamCode) FILTER (WHERE Activity IS NOT NULL AND trim(CAST(Activity AS VARCHAR)) <> ''),
           (SELECT n FROM family_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/families.parquet')

    UNION ALL
    SELECT 'genus', 'water_salinity', 'genera.parquet -> WaterSalinity',
           MIN(CAST(WaterSalinity AS VARCHAR)) FILTER (WHERE WaterSalinity IS NOT NULL AND trim(CAST(WaterSalinity AS VARCHAR)) <> ''),
           COUNT(DISTINCT GenCode) FILTER (WHERE WaterSalinity IS NOT NULL AND trim(CAST(WaterSalinity AS VARCHAR)) <> ''),
           (SELECT n FROM genus_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/genera.parquet')

    UNION ALL
    SELECT 'genus', 'subfamily', 'genera.parquet -> Subfamily',
           MIN(CAST(Subfamily AS VARCHAR)) FILTER (WHERE Subfamily IS NOT NULL AND trim(CAST(Subfamily AS VARCHAR)) <> ''),
           COUNT(DISTINCT GenCode) FILTER (WHERE Subfamily IS NOT NULL AND trim(CAST(Subfamily AS VARCHAR)) <> ''),
           (SELECT n FROM genus_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/genera.parquet')

    UNION ALL
    SELECT 'genus', 'diagnosis', 'genera.parquet -> Diagnosis',
           MIN(CAST(Diagnosis AS VARCHAR)) FILTER (WHERE Diagnosis IS NOT NULL AND trim(CAST(Diagnosis AS VARCHAR)) <> ''),
           COUNT(DISTINCT GenCode) FILTER (WHERE Diagnosis IS NOT NULL AND trim(CAST(Diagnosis AS VARCHAR)) <> ''),
           (SELECT n FROM genus_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/genera.parquet')

    UNION ALL
    SELECT 'genus', 'distribution', 'genera.parquet -> Distribution',
           MIN(CAST(Distribution AS VARCHAR)) FILTER (WHERE Distribution IS NOT NULL AND trim(CAST(Distribution AS VARCHAR)) <> ''),
           COUNT(DISTINCT GenCode) FILTER (WHERE Distribution IS NOT NULL AND trim(CAST(Distribution AS VARCHAR)) <> ''),
           (SELECT n FROM genus_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/genera.parquet')

    UNION ALL
    SELECT 'genus', 'body_shape', 'genera.parquet -> BodyShapeI',
           MIN(CAST(BodyShapeI AS VARCHAR)) FILTER (WHERE BodyShapeI IS NOT NULL AND trim(CAST(BodyShapeI AS VARCHAR)) <> ''),
           COUNT(DISTINCT GenCode) FILTER (WHERE BodyShapeI IS NOT NULL AND trim(CAST(BodyShapeI AS VARCHAR)) <> ''),
           (SELECT n FROM genus_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/genera.parquet')

    UNION ALL
    SELECT 'genus', 'tribe', 'genera.parquet -> Tribe',
           MIN(CAST(Tribe AS VARCHAR)) FILTER (WHERE Tribe IS NOT NULL AND trim(CAST(Tribe AS VARCHAR)) <> ''),
           COUNT(DISTINCT GenCode) FILTER (WHERE Tribe IS NOT NULL AND trim(CAST(Tribe AS VARCHAR)) <> ''),
           (SELECT n FROM genus_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/genera.parquet')

    UNION ALL
    SELECT 'genus', 'habitat', 'genera.parquet -> Habitat',
           MIN(CAST(Habitat AS VARCHAR)) FILTER (WHERE Habitat IS NOT NULL AND trim(CAST(Habitat AS VARCHAR)) <> ''),
           COUNT(DISTINCT GenCode) FILTER (WHERE Habitat IS NOT NULL AND trim(CAST(Habitat AS VARCHAR)) <> ''),
           (SELECT n FROM genus_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/genera.parquet')

    UNION ALL
    SELECT 'genus', 'common_name', 'genera.parquet -> GenComName',
           MIN(CAST(GenComName AS VARCHAR)) FILTER (WHERE GenComName IS NOT NULL AND trim(CAST(GenComName AS VARCHAR)) <> ''),
           COUNT(DISTINCT GenCode) FILTER (WHERE GenComName IS NOT NULL AND trim(CAST(GenComName AS VARCHAR)) <> ''),
           (SELECT n FROM genus_total)
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/genera.parquet')
)
SELECT
    stufe,
    field_name,
    parquet_name,
    sample_value,
    ROUND(entities_with_value * 100.0 / total_entities, 1) AS coverage_pct
FROM metrics
ORDER BY stufe, coverage_pct DESC, field_name;
```

## Weitere Joinbare Parquets

Diese Parquets lassen sich ebenfalls sinnvoll auf Species-Ebene andocken, auch wenn sie eher regionen-, management- oder krankheitsbezogene Zusatzkontexte liefern. Die Spaltenlisten unten sind vollstaendig fuer die jeweils gepruefte FishBase-Datei.

### `aquamaps.parquet`

Joinbar ueber: `speccode`

Spalten:

- `FAOAreaIn`
- `database_id`
- `expert_id`
- `genus`
- `speccode`
- `species`
- `speciesid`

### `countrysub.parquet`

Joinbar ueber: `SpecCode`

Spalten:

- `Abundance`
- `CSubRefNo`
- `CSub_Code`
- `C_Code`
- `Comments`
- `CurrentPresence`
- `DateChecked`
- `DateEntered`
- `DateModified`
- `Entered`
- `Expert`
- `Modified`
- `RefAbundance`
- `SpecCode`
- `Status`
- `Stockcode`
- `TS`
- `autoctr`

### `alieninvasive.parquet`

Joinbar ueber: `Speccode`

Spalten:

- `Autoctr`
- `Checked`
- `DateChecked`
- `DateEntered`
- `DateModified`
- `Description`
- `Entered`
- `Genus`
- `Modified`
- `NameofDatabase`
- `Speccode`
- `Species`
- `TS`
- `URL`

### `countfao.parquet`

Joinbar ueber: `SpecCode`

Spalten:

- `AreaCode`
- `C_Code`
- `DateEntered`
- `SpecCode`
- `StockCode`
- `TS`
- `autoctr`

### `countecosystem.parquet`

Joinbar ueber: `Speccode`

Spalten:

- `C_Code`
- `CurrentPresence`
- `E_CODE`
- `Speccode`
- `Stockcode`
- `autoctr`

### `diseases.parquet`

Joinbar ueber: `SpecCode`

Spalten:

- `C_Code`
- `Culture`
- `DateChecked`
- `DateEntered`
- `DateModified`
- `DisCode`
- `DiseasesRefNo`
- `Eggs`
- `Entered`
- `Expert`
- `Females`
- `Fry`
- `Intensity`
- `Juveniles`
- `Larvae`
- `Locality`
- `Males`
- `Modified`
- `Mortality`
- `Prevalence`
- `Remark`
- `SpecCode`
- `StockCode`
- `TS`
- `TypeofCulture`
- `WaterTemp`
- `Wild`
- `Year`

### `citesfb.parquet`

Nicht direkt species-joinbar ueber `SpecCode`, aber potenziell ueber Referenz-/Themenlogik interessant.

Spalten:

- `CitationType`
- `Data`
- `DateEntered`
- `DateModified`
- `Entered`
- `Impact`
- `Modified`
- `PageNo`
- `RefNo`
- `Referred`
- `Remarks`
- `Subject`
- `TS`
- `Topic`

## DuckDB SQL

Dieses SQL spannt fuer drei Beispielarten die wichtigsten species-nahen Parquets gemeinsam auf und zeigt damit praktisch alle andockbaren Spalten in einer breiten Explorationsansicht. Fuer SeaLifeBase muessen nur die URLs von `data/fb/...` auf `data/slb/...` angepasst werden.

```sql
WITH sample_species AS (
    SELECT SpecCode, Genus, Species
    FROM read_parquet('https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/species.parquet')
    WHERE Genus <> 'Genus'
      AND Species NOT IN ('Sp', 'Species')
    ORDER BY SpecCode
    LIMIT 3
)
SELECT
    ss.SpecCode,
    ss.Genus,
    ss.Species,

    s.* EXCLUDE (SpecCode, Genus, Species),
    e.* EXCLUDE (SpecCode),
    c.* EXCLUDE (SpecCode),
    cs.* EXCLUDE (SpecCode),
    a.* EXCLUDE (SpecCode),
    d.* EXCLUDE (SpecCode),
    am.* EXCLUDE (speccode, genus, species),
    ai.* EXCLUDE (Speccode, Genus, Species),
    cf.* EXCLUDE (SpecCode),
    ce.* EXCLUDE (Speccode),
    dis.* EXCLUDE (SpecCode)

FROM sample_species ss

LEFT JOIN read_parquet(
    'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/species.parquet'
) s USING (SpecCode)

LEFT JOIN LATERAL (
    SELECT *
    FROM read_parquet(
        'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/ecology.parquet'
    ) e
    WHERE e.SpecCode = ss.SpecCode
    LIMIT 1
) e ON TRUE

LEFT JOIN LATERAL (
    SELECT *
    FROM read_parquet(
        'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/country.parquet'
    ) c
    WHERE c.SpecCode = ss.SpecCode
    LIMIT 1
) c ON TRUE

LEFT JOIN LATERAL (
    SELECT *
    FROM read_parquet(
        'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/countrysub.parquet'
    ) cs
    WHERE cs.SpecCode = ss.SpecCode
    LIMIT 1
) cs ON TRUE

LEFT JOIN LATERAL (
    SELECT *
    FROM read_parquet(
        'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/aquarium.parquet'
    ) a
    WHERE a.SpecCode = ss.SpecCode
    LIMIT 1
) a ON TRUE

LEFT JOIN LATERAL (
    SELECT *
    FROM read_parquet(
        'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/diet.parquet'
    ) d
    WHERE d.SpecCode = ss.SpecCode
    LIMIT 1
) d ON TRUE

LEFT JOIN LATERAL (
    SELECT *
    FROM read_parquet(
        'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/aquamaps.parquet'
    ) am
    WHERE am.speccode = ss.SpecCode
    LIMIT 1
) am ON TRUE

LEFT JOIN LATERAL (
    SELECT *
    FROM read_parquet(
        'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/alieninvasive.parquet'
    ) ai
    WHERE ai.Speccode = ss.SpecCode
    LIMIT 1
) ai ON TRUE

LEFT JOIN LATERAL (
    SELECT *
    FROM read_parquet(
        'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/countfao.parquet'
    ) cf
    WHERE cf.SpecCode = ss.SpecCode
    LIMIT 1
) cf ON TRUE

LEFT JOIN LATERAL (
    SELECT *
    FROM read_parquet(
        'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/countecosystem.parquet'
    ) ce
    WHERE ce.Speccode = ss.SpecCode
    LIMIT 1
) ce ON TRUE

LEFT JOIN LATERAL (
    SELECT *
    FROM read_parquet(
        'https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v24.07/parquet/diseases.parquet'
    ) dis
    WHERE dis.SpecCode = ss.SpecCode
    LIMIT 1
) dis ON TRUE;
```
