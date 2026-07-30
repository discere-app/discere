import 'package:discere/catalog/model/continent.dart';

const Map<String, String> countryCodeNames = {
  '004': 'Afghanistan',
  '008': 'Albania',
  '010': 'Antarctica',
  '012': 'Algeria',
  '016': 'American Samoa',
  '020': 'Andorra',
  '024': 'Angola',
  '028': 'Antigua and Barbuda',
  '031': 'Azerbaijan',
  '032': 'Argentina',
  '036': 'Australia',
  '040': 'Austria',
  '044': 'Bahamas',
  '048': 'Bahrain',
  '050': 'Bangladesh',
  '051': 'Armenia',
  '052': 'Barbados',
  '056': 'Belgium',
  '060': 'Bermuda',
  '064': 'Bhutan',
  '068': 'Bolivia',
  '070': 'Bosnia and Herzegovina',
  '072': 'Botswana',
  '074': 'Bouvet Island',
  '076': 'Brazil',
  '084': 'Belize',
  '086': 'British Indian Ocean Territory',
  '090': 'Solomon Islands',
  '092': 'British Virgin Islands',
  '096': 'Brunei',
  '100': 'Bulgaria',
  '104': 'Myanmar',
  '108': 'Burundi',
  '112': 'Belarus',
  '116': 'Cambodia',
  '120': 'Cameroon',
  '124': 'Canada',
  '132': 'Cabo Verde',
  '136': 'Cayman Islands',
  '140': 'Central African Republic',
  '144': 'Sri Lanka',
  '148': 'Chad',
  '152': 'Chile',
  '156': 'China',
  '158': 'Taiwan',
  '162': 'Christmas Island',
  '166': 'Cocos (Keeling) Islands',
  '170': 'Colombia',
  '174': 'Comoros',
  '175': 'Mayotte',
  '178': 'Republic of the Congo',
  '180': 'Democratic Republic of the Congo',
  '184': 'Cook Islands',
  '188': 'Costa Rica',
  '191': 'Croatia',
  '192': 'Cuba',
  '196': 'Cyprus',
  '203': 'Czechia',
  '204': 'Benin',
  '208': 'Denmark',
  '212': 'Dominica',
  '214': 'Dominican Republic',
  '218': 'Ecuador',
  '222': 'El Salvador',
  '226': 'Equatorial Guinea',
  '231': 'Ethiopia',
  '232': 'Eritrea',
  '233': 'Estonia',
  '234': 'Faroe Islands',
  '238': 'Falkland Islands',
  '239': 'South Georgia and the South Sandwich Islands',
  '242': 'Fiji',
  '246': 'Finland',
  '248': 'Aland Islands',
  '250': 'France',
  '254': 'French Guiana',
  '258': 'French Polynesia',
  '260': 'French Southern Territories',
  '262': 'Djibouti',
  '266': 'Gabon',
  '268': 'Georgia',
  '270': 'Gambia',
  '275': 'Palestine',
  '276': 'Germany',
  '288': 'Ghana',
  '292': 'Gibraltar',
  '296': 'Kiribati',
  '300': 'Greece',
  '304': 'Greenland',
  '308': 'Grenada',
  '312': 'Guadeloupe',
  '316': 'Guam',
  '320': 'Guatemala',
  '324': 'Guinea',
  '328': 'Guyana',
  '332': 'Haiti',
  '334': 'Heard Island and McDonald Islands',
  '336': 'Holy See',
  '340': 'Honduras',
  '344': 'Hong Kong',
  '348': 'Hungary',
  '352': 'Iceland',
  '356': 'India',
  '360': 'Indonesia',
  '364': 'Iran',
  '368': 'Iraq',
  '372': 'Ireland',
  '376': 'Israel',
  '380': 'Italy',
  '384': "Cote d'Ivoire",
  '388': 'Jamaica',
  '392': 'Japan',
  '398': 'Kazakhstan',
  '400': 'Jordan',
  '404': 'Kenya',
  '408': 'North Korea',
  '410': 'South Korea',
  '414': 'Kuwait',
  '417': 'Kyrgyzstan',
  '418': 'Laos',
  '422': 'Lebanon',
  '426': 'Lesotho',
  '428': 'Latvia',
  '430': 'Liberia',
  '434': 'Libya',
  '438': 'Liechtenstein',
  '440': 'Lithuania',
  '442': 'Luxembourg',
  '446': 'Macao',
  '450': 'Madagascar',
  '454': 'Malawi',
  '458': 'Malaysia',
  '462': 'Maldives',
  '466': 'Mali',
  '470': 'Malta',
  '474': 'Martinique',
  '478': 'Mauritania',
  '480': 'Mauritius',
  '484': 'Mexico',
  '492': 'Monaco',
  '496': 'Mongolia',
  '498': 'Moldova',
  '499': 'Montenegro',
  '500': 'Montserrat',
  '504': 'Morocco',
  '508': 'Mozambique',
  '512': 'Oman',
  '516': 'Namibia',
  '520': 'Nauru',
  '524': 'Nepal',
  '528': 'Netherlands',
  '531': 'Curacao',
  '533': 'Aruba',
  '534': 'Sint Maarten',
  '535': 'Bonaire, Sint Eustatius and Saba',
  '540': 'New Caledonia',
  '548': 'Vanuatu',
  '554': 'New Zealand',
  '558': 'Nicaragua',
  '562': 'Niger',
  '566': 'Nigeria',
  '570': 'Niue',
  '574': 'Norfolk Island',
  '578': 'Norway',
  '580': 'Northern Mariana Islands',
  '581': 'United States Minor Outlying Islands',
  '583': 'Micronesia',
  '584': 'Marshall Islands',
  '585': 'Palau',
  '586': 'Pakistan',
  '591': 'Panama',
  '598': 'Papua New Guinea',
  '600': 'Paraguay',
  '604': 'Peru',
  '608': 'Philippines',
  '612': 'Pitcairn Islands',
  '616': 'Poland',
  '620': 'Portugal',
  '624': 'Guinea-Bissau',
  '626': 'Timor-Leste',
  '630': 'Puerto Rico',
  '634': 'Qatar',
  '638': 'Reunion',
  '642': 'Romania',
  '643': 'Russia',
  '646': 'Rwanda',
  '652': 'Saint Barthelemy',
  '654': 'Saint Helena, Ascension and Tristan da Cunha',
  '659': 'Saint Kitts and Nevis',
  '660': 'Anguilla',
  '662': 'Saint Lucia',
  '663': 'Saint Martin',
  '666': 'Saint Pierre and Miquelon',
  '670': 'Saint Vincent and the Grenadines',
  '674': 'San Marino',
  '678': 'Sao Tome and Principe',
  '682': 'Saudi Arabia',
  '686': 'Senegal',
  '688': 'Serbia',
  '690': 'Seychelles',
  '694': 'Sierra Leone',
  '702': 'Singapore',
  '703': 'Slovakia',
  '704': 'Vietnam',
  '705': 'Slovenia',
  '706': 'Somalia',
  '710': 'South Africa',
  '716': 'Zimbabwe',
  '724': 'Spain',
  '728': 'South Sudan',
  '729': 'Sudan',
  '732': 'Western Sahara',
  '740': 'Suriname',
  '744': 'Svalbard and Jan Mayen',
  '748': 'Eswatini',
  '752': 'Sweden',
  '756': 'Switzerland',
  '760': 'Syria',
  '762': 'Tajikistan',
  '764': 'Thailand',
  '768': 'Togo',
  '772': 'Tokelau',
  '776': 'Tonga',
  '780': 'Trinidad and Tobago',
  '784': 'United Arab Emirates',
  '788': 'Tunisia',
  '792': 'Turkey',
  '795': 'Turkmenistan',
  '796': 'Turks and Caicos Islands',
  '798': 'Tuvalu',
  '800': 'Uganda',
  '804': 'Ukraine',
  '807': 'North Macedonia',
  '818': 'Egypt',
  '826': 'United Kingdom',
  '831': 'Guernsey',
  '832': 'Jersey',
  '833': 'Isle of Man',
  '834': 'Tanzania',
  '840': 'United States',
  '850': 'United States Virgin Islands',
  '854': 'Burkina Faso',
  '858': 'Uruguay',
  '860': 'Uzbekistan',
  '862': 'Venezuela',
  '876': 'Wallis and Futuna',
  '882': 'Samoa',
  '887': 'Yemen',
  '894': 'Zambia',
};

/// German equivalents of [countryCodeNames], same keys throughout.
const Map<String, String> countryCodeNamesDe = {
  '004': 'Afghanistan',
  '008': 'Albanien',
  '010': 'Antarktis',
  '012': 'Algerien',
  '016': 'Amerikanisch-Samoa',
  '020': 'Andorra',
  '024': 'Angola',
  '028': 'Antigua und Barbuda',
  '031': 'Aserbaidschan',
  '032': 'Argentinien',
  '036': 'Australien',
  '040': 'Österreich',
  '044': 'Bahamas',
  '048': 'Bahrain',
  '050': 'Bangladesch',
  '051': 'Armenien',
  '052': 'Barbados',
  '056': 'Belgien',
  '060': 'Bermuda',
  '064': 'Bhutan',
  '068': 'Bolivien',
  '070': 'Bosnien und Herzegowina',
  '072': 'Botswana',
  '074': 'Bouvetinsel',
  '076': 'Brasilien',
  '084': 'Belize',
  '086': 'Britisches Territorium im Indischen Ozean',
  '090': 'Salomonen',
  '092': 'Britische Jungferninseln',
  '096': 'Brunei',
  '100': 'Bulgarien',
  '104': 'Myanmar',
  '108': 'Burundi',
  '112': 'Belarus',
  '116': 'Kambodscha',
  '120': 'Kamerun',
  '124': 'Kanada',
  '132': 'Kap Verde',
  '136': 'Kaimaninseln',
  '140': 'Zentralafrikanische Republik',
  '144': 'Sri Lanka',
  '148': 'Tschad',
  '152': 'Chile',
  '156': 'China',
  '158': 'Taiwan',
  '162': 'Weihnachtsinsel',
  '166': 'Kokosinseln',
  '170': 'Kolumbien',
  '174': 'Komoren',
  '175': 'Mayotte',
  '178': 'Kongo (Republik)',
  '180': 'Kongo (Demokratische Republik)',
  '184': 'Cookinseln',
  '188': 'Costa Rica',
  '191': 'Kroatien',
  '192': 'Kuba',
  '196': 'Zypern',
  '203': 'Tschechien',
  '204': 'Benin',
  '208': 'Dänemark',
  '212': 'Dominica',
  '214': 'Dominikanische Republik',
  '218': 'Ecuador',
  '222': 'El Salvador',
  '226': 'Äquatorialguinea',
  '231': 'Äthiopien',
  '232': 'Eritrea',
  '233': 'Estland',
  '234': 'Färöer',
  '238': 'Falklandinseln',
  '239': 'Südgeorgien und die Südlichen Sandwichinseln',
  '242': 'Fidschi',
  '246': 'Finnland',
  '248': 'Åland',
  '250': 'Frankreich',
  '254': 'Französisch-Guayana',
  '258': 'Französisch-Polynesien',
  '260': 'Französische Süd- und Antarktisgebiete',
  '262': 'Dschibuti',
  '266': 'Gabun',
  '268': 'Georgien',
  '270': 'Gambia',
  '275': 'Palästina',
  '276': 'Deutschland',
  '288': 'Ghana',
  '292': 'Gibraltar',
  '296': 'Kiribati',
  '300': 'Griechenland',
  '304': 'Grönland',
  '308': 'Grenada',
  '312': 'Guadeloupe',
  '316': 'Guam',
  '320': 'Guatemala',
  '324': 'Guinea',
  '328': 'Guyana',
  '332': 'Haiti',
  '334': 'Heard und McDonaldinseln',
  '336': 'Heiliger Stuhl',
  '340': 'Honduras',
  '344': 'Hongkong',
  '348': 'Ungarn',
  '352': 'Island',
  '356': 'Indien',
  '360': 'Indonesien',
  '364': 'Iran',
  '368': 'Irak',
  '372': 'Irland',
  '376': 'Israel',
  '380': 'Italien',
  '384': 'Elfenbeinküste',
  '388': 'Jamaika',
  '392': 'Japan',
  '398': 'Kasachstan',
  '400': 'Jordanien',
  '404': 'Kenia',
  '408': 'Nordkorea',
  '410': 'Südkorea',
  '414': 'Kuwait',
  '417': 'Kirgisistan',
  '418': 'Laos',
  '422': 'Libanon',
  '426': 'Lesotho',
  '428': 'Lettland',
  '430': 'Liberia',
  '434': 'Libyen',
  '438': 'Liechtenstein',
  '440': 'Litauen',
  '442': 'Luxemburg',
  '446': 'Macau',
  '450': 'Madagaskar',
  '454': 'Malawi',
  '458': 'Malaysia',
  '462': 'Malediven',
  '466': 'Mali',
  '470': 'Malta',
  '474': 'Martinique',
  '478': 'Mauretanien',
  '480': 'Mauritius',
  '484': 'Mexiko',
  '492': 'Monaco',
  '496': 'Mongolei',
  '498': 'Moldau',
  '499': 'Montenegro',
  '500': 'Montserrat',
  '504': 'Marokko',
  '508': 'Mosambik',
  '512': 'Oman',
  '516': 'Namibia',
  '520': 'Nauru',
  '524': 'Nepal',
  '528': 'Niederlande',
  '531': 'Curaçao',
  '533': 'Aruba',
  '534': 'Sint Maarten',
  '535': 'Bonaire, Sint Eustatius und Saba',
  '540': 'Neukaledonien',
  '548': 'Vanuatu',
  '554': 'Neuseeland',
  '558': 'Nicaragua',
  '562': 'Niger',
  '566': 'Nigeria',
  '570': 'Niue',
  '574': 'Norfolkinsel',
  '578': 'Norwegen',
  '580': 'Nördliche Marianen',
  '581': 'Kleinere Amerikanische Überseeinseln',
  '583': 'Mikronesien',
  '584': 'Marshallinseln',
  '585': 'Palau',
  '586': 'Pakistan',
  '591': 'Panama',
  '598': 'Papua-Neuguinea',
  '600': 'Paraguay',
  '604': 'Peru',
  '608': 'Philippinen',
  '612': 'Pitcairninseln',
  '616': 'Polen',
  '620': 'Portugal',
  '624': 'Guinea-Bissau',
  '626': 'Osttimor',
  '630': 'Puerto Rico',
  '634': 'Katar',
  '638': 'Réunion',
  '642': 'Rumänien',
  '643': 'Russland',
  '646': 'Ruanda',
  '652': 'Saint-Barthélemy',
  '654': 'St. Helena, Ascension und Tristan da Cunha',
  '659': 'St. Kitts und Nevis',
  '660': 'Anguilla',
  '662': 'St. Lucia',
  '663': 'Saint-Martin',
  '666': 'Saint-Pierre und Miquelon',
  '670': 'St. Vincent und die Grenadinen',
  '674': 'San Marino',
  '678': 'São Tomé und Príncipe',
  '682': 'Saudi-Arabien',
  '686': 'Senegal',
  '688': 'Serbien',
  '690': 'Seychellen',
  '694': 'Sierra Leone',
  '702': 'Singapur',
  '703': 'Slowakei',
  '704': 'Vietnam',
  '705': 'Slowenien',
  '706': 'Somalia',
  '710': 'Südafrika',
  '716': 'Simbabwe',
  '724': 'Spanien',
  '728': 'Südsudan',
  '729': 'Sudan',
  '732': 'Westsahara',
  '740': 'Suriname',
  '744': 'Svalbard und Jan Mayen',
  '748': 'Eswatini',
  '752': 'Schweden',
  '756': 'Schweiz',
  '760': 'Syrien',
  '762': 'Tadschikistan',
  '764': 'Thailand',
  '768': 'Togo',
  '772': 'Tokelau',
  '776': 'Tonga',
  '780': 'Trinidad und Tobago',
  '784': 'Vereinigte Arabische Emirate',
  '788': 'Tunesien',
  '792': 'Türkei',
  '795': 'Turkmenistan',
  '796': 'Turks- und Caicosinseln',
  '798': 'Tuvalu',
  '800': 'Uganda',
  '804': 'Ukraine',
  '807': 'Nordmazedonien',
  '818': 'Ägypten',
  '826': 'Vereinigtes Königreich',
  '831': 'Guernsey',
  '832': 'Jersey',
  '833': 'Insel Man',
  '834': 'Tansania',
  '840': 'Vereinigte Staaten',
  '850': 'Amerikanische Jungferninseln',
  '854': 'Burkina Faso',
  '858': 'Uruguay',
  '860': 'Usbekistan',
  '862': 'Venezuela',
  '876': 'Wallis und Futuna',
  '882': 'Samoa',
  '887': 'Jemen',
  '894': 'Sambia',
};

// FishBase splits some biogeographically distinct territories out of their
// mainland country's C_Code with a letter suffix (e.g. '218A' for the
// Galápagos Islands vs. '218' for mainland Ecuador). Verified against
// FishBase's own country checklist pages (fishbase.se/country/CountryChecklist.php).
const Map<String, String> specialTerritoryNames = {
  '152A': 'Easter Island',
  '152B': 'Juan Fernández Islands',
  '152D': 'Desventuradas Islands',
  '218A': 'Galápagos Islands',
  '250A': 'Society Islands',
  '250C': 'Tuamotu Islands',
  '250D': 'Marquesas Islands',
  '260A': 'Amsterdam Island',
  '392B': 'Ryukyu Islands',
  '554A': 'Kermadec Islands',
  '554C': 'Chatham Islands',
  '598A': 'Admiralty Islands',
  '620A': 'Madeira Islands',
  '620B': 'Azores',
  '724A': 'Canary Islands',
  '826A': 'England and Wales',
  '826B': 'Scotland',
  '840A': 'Alaska',
  '840B': 'Hawaii',
  'I188': 'Cocos Island',
};

/// German equivalents of [specialTerritoryNames], same keys throughout.
const Map<String, String> specialTerritoryNamesDe = {
  '152A': 'Osterinsel',
  '152B': 'Juan-Fernández-Inseln',
  '152D': 'Desventuradas-Inseln',
  '218A': 'Galápagosinseln',
  '250A': 'Gesellschaftsinseln',
  '250C': 'Tuamotu-Archipel',
  '250D': 'Marquesas-Inseln',
  '260A': 'Amsterdaminsel',
  '392B': 'Ryūkyū-Inseln',
  '554A': 'Kermadecinseln',
  '554C': 'Chatham-Inseln',
  '598A': 'Admiralitätsinseln',
  '620A': 'Madeira',
  '620B': 'Azoren',
  '724A': 'Kanarische Inseln',
  '826A': 'England und Wales',
  '826B': 'Schottland',
  '840A': 'Alaska',
  '840B': 'Hawaii',
  'I188': 'Kokos-Insel',
};

const Map<String, String> subdivisionCodeNames = {
  'AU-ACT': 'Australian Capital Territory',
  'AU-NSW': 'New South Wales',
  'AU-NT': 'Northern Territory',
  'AU-QLD': 'Queensland',
  'AU-SA': 'South Australia',
  'AU-TAS': 'Tasmania',
  'AU-VIC': 'Victoria',
  'AU-WA': 'Western Australia',
  'BR-AC': 'Acre',
  'BR-AL': 'Alagoas',
  'BR-AM': 'Amazonas',
  'BR-AP': 'Amapa',
  'BR-BA': 'Bahia',
  'BR-CE': 'Ceara',
  'BR-DF': 'Distrito Federal',
  'BR-ES': 'Espirito Santo',
  'BR-GO': 'Goias',
  'BR-MA': 'Maranhao',
  'BR-MG': 'Minas Gerais',
  'BR-MS': 'Mato Grosso do Sul',
  'BR-MT': 'Mato Grosso',
  'BR-PA': 'Para',
  'BR-PB': 'Paraiba',
  'BR-PE': 'Pernambuco',
  'BR-PI': 'Piaui',
  'BR-PR': 'Parana',
  'BR-RJ': 'Rio de Janeiro',
  'BR-RN': 'Rio Grande do Norte',
  'BR-RO': 'Rondonia',
  'BR-RR': 'Roraima',
  'BR-RS': 'Rio Grande do Sul',
  'BR-SC': 'Santa Catarina',
  'BR-SE': 'Sergipe',
  'BR-SP': 'Sao Paulo',
  'BR-TO': 'Tocantins',
  'CA-AB': 'Alberta',
  'CA-BC': 'British Columbia',
  'CA-MB': 'Manitoba',
  'CA-NB': 'New Brunswick',
  'CA-NL': 'Newfoundland and Labrador',
  'CA-NS': 'Nova Scotia',
  'CA-NT': 'Northwest Territories',
  'CA-NU': 'Nunavut',
  'CA-ON': 'Ontario',
  'CA-PE': 'Prince Edward Island',
  'CA-QC': 'Quebec',
  'CA-SK': 'Saskatchewan',
  'CA-YT': 'Yukon',
  'CN-11': 'Beijing',
  'CN-12': 'Tianjin',
  'CN-13': 'Hebei',
  'CN-14': 'Shanxi',
  'CN-15': 'Inner Mongolia',
  'CN-21': 'Liaoning',
  'CN-22': 'Jilin',
  'CN-23': 'Heilongjiang',
  'CN-31': 'Shanghai',
  'CN-32': 'Jiangsu',
  'CN-33': 'Zhejiang',
  'CN-34': 'Anhui',
  'CN-35': 'Fujian',
  'CN-36': 'Jiangxi',
  'CN-37': 'Shandong',
  'CN-41': 'Henan',
  'CN-42': 'Hubei',
  'CN-43': 'Hunan',
  'CN-44': 'Guangdong',
  'CN-45': 'Guangxi',
  'CN-46': 'Hainan',
  'CN-50': 'Chongqing',
  'CN-51': 'Sichuan',
  'CN-52': 'Guizhou',
  'CN-53': 'Yunnan',
  'CN-54': 'Tibet',
  'CN-61': 'Shaanxi',
  'CN-62': 'Gansu',
  'CN-63': 'Qinghai',
  'CN-64': 'Ningxia',
  'CN-65': 'Xinjiang',
  'PF-AU': 'Austral Islands',
  'PF-GA': 'Gambier Islands',
  'PF-MA': 'Marquesas Islands',
  'PF-SO': 'Society Islands',
  'PF-TU': 'Tuamotu Archipelago',
  'IN-AN': 'Andaman and Nicobar Islands',
  'IN-AP': 'Andhra Pradesh',
  'IN-AR': 'Arunachal Pradesh',
  'IN-AS': 'Assam',
  'IN-BR': 'Bihar',
  'IN-DL': 'Delhi',
  'IN-DN': 'Dadra and Nagar Haveli and Daman and Diu',
  'IN-GA': 'Goa',
  'IN-GJ': 'Gujarat',
  'IN-HP': 'Himachal Pradesh',
  'IN-HR': 'Haryana',
  'IN-JK': 'Jammu and Kashmir',
  'IN-KA': 'Karnataka',
  'IN-KL': 'Kerala',
  'IN-LD': 'Lakshadweep',
  'IN-MH': 'Maharashtra',
  'IN-ML': 'Meghalaya',
  'IN-OD': 'Odisha',
  'IN-PB': 'Punjab',
  'IN-TN': 'Tamil Nadu',
  'IN-WB': 'West Bengal',
  'US-AK': 'Alaska',
  'US-AL': 'Alabama',
  'US-AR': 'Arkansas',
  'US-CA': 'California',
  'US-FL': 'Florida',
  'US-GA': 'Georgia',
  'US-HI': 'Hawaii',
  'US-LA': 'Louisiana',
  'US-MA': 'Massachusetts',
  'US-MS': 'Mississippi',
  'US-NC': 'North Carolina',
  'US-NJ': 'New Jersey',
  'US-NY': 'New York',
  'US-OR': 'Oregon',
  'US-RI': 'Rhode Island',
  'US-SC': 'South Carolina',
  'US-TX': 'Texas',
  'US-VA': 'Virginia',
  'US-WA': 'Washington',
};

final RegExp _leadingDigits = RegExp(r'^(\d+)');

/// Best-effort, never-wrong fallback for a FishBase territory code that isn't
/// curated in [specialTerritoryNames]: if its leading numeric prefix matches
/// a known mainland country, qualify that country's name with the raw code
/// instead of showing the code alone.
String? _fallbackTerritoryName(String rawCode, {required bool german}) {
  final prefix = _leadingDigits.firstMatch(rawCode)?.group(1);
  if (prefix == null) return null;
  final names = german ? countryCodeNamesDe : countryCodeNames;
  final countryName = names[prefix.padLeft(3, '0')];
  if (countryName == null) return null;
  return '$countryName ($rawCode)';
}

/// Resolves a raw `taxonomy_distribution_regions.region_key`/`region_label`
/// value (a country code, optionally `country:subdivision`) to a display
/// name. Country-level names are translated when [german] is true (falling
/// back to English for any code without a curated German entry); subdivision
/// names (US states, Australian territories, etc.) stay English-only — there
/// are far more of them and they're a much smaller share of what users
/// actually pick in the region filter.
///
/// A subdivision code without a curated name (e.g. FishBase-internal codes
/// like "I557" that don't correspond to any real administrative division) is
/// dropped rather than shown raw — callers get just the country name back,
/// same as if no subdivision had been recorded at all.
String resolveCountryRegionLabel(String rawLabel, {bool german = false}) {
  final normalized = rawLabel.trim();
  if (normalized.isEmpty) return normalized;

  final parts = normalized.split(':');
  final rawCountryCode = parts.first;
  final countryCode = rawCountryCode.padLeft(3, '0');
  final territoryNames = german
      ? specialTerritoryNamesDe
      : specialTerritoryNames;
  final countryNames = german ? countryCodeNamesDe : countryCodeNames;
  final countryName =
      territoryNames[rawCountryCode] ??
      countryNames[countryCode] ??
      _fallbackTerritoryName(rawCountryCode, german: german);
  if (countryName == null) return normalized;

  if (parts.length == 1) {
    return countryName;
  }

  final subdivisionCode = parts.sublist(1).join(':');
  final subdivisionName = subdivisionCodeNames[subdivisionCode];
  if (subdivisionName == null) return countryName;

  return '$countryName · $subdivisionName';
}

const Map<String, Continent> continentByCountryCode = {
  '004': Continent.asia, // Afghanistan
  '008': Continent.europe, // Albania
  '010': Continent.antarctica, // Antarctica
  '012': Continent.africa, // Algeria
  '016': Continent.oceania, // American Samoa
  '020': Continent.europe, // Andorra
  '024': Continent.africa, // Angola
  '028': Continent.northAmerica, // Antigua and Barbuda
  '031': Continent.asia, // Azerbaijan
  '032': Continent.southAmerica, // Argentina
  '036': Continent.oceania, // Australia
  '040': Continent.europe, // Austria
  '044': Continent.northAmerica, // Bahamas
  '048': Continent.asia, // Bahrain
  '050': Continent.asia, // Bangladesh
  '051': Continent.asia, // Armenia
  '052': Continent.northAmerica, // Barbados
  '056': Continent.europe, // Belgium
  '060': Continent.northAmerica, // Bermuda
  '064': Continent.asia, // Bhutan
  '068': Continent.southAmerica, // Bolivia
  '070': Continent.europe, // Bosnia and Herzegovina
  '072': Continent.africa, // Botswana
  '074': Continent.antarctica, // Bouvet Island
  '076': Continent.southAmerica, // Brazil
  '084': Continent.northAmerica, // Belize
  '086': Continent.africa, // British Indian Ocean Territory
  '090': Continent.oceania, // Solomon Islands
  '092': Continent.northAmerica, // British Virgin Islands
  '096': Continent.asia, // Brunei
  '100': Continent.europe, // Bulgaria
  '104': Continent.asia, // Myanmar
  '108': Continent.africa, // Burundi
  '112': Continent.europe, // Belarus
  '116': Continent.asia, // Cambodia
  '120': Continent.africa, // Cameroon
  '124': Continent.northAmerica, // Canada
  '132': Continent.africa, // Cabo Verde
  '136': Continent.northAmerica, // Cayman Islands
  '140': Continent.africa, // Central African Republic
  '144': Continent.asia, // Sri Lanka
  '148': Continent.africa, // Chad
  '152': Continent.southAmerica, // Chile
  '156': Continent.asia, // China
  '158': Continent.asia, // Taiwan
  '162': Continent.oceania, // Christmas Island
  '166': Continent.oceania, // Cocos (Keeling) Islands
  '170': Continent.southAmerica, // Colombia
  '174': Continent.africa, // Comoros
  '175': Continent.africa, // Mayotte
  '178': Continent.africa, // Republic of the Congo
  '180': Continent.africa, // Democratic Republic of the Congo
  '184': Continent.oceania, // Cook Islands
  '188': Continent.northAmerica, // Costa Rica
  '191': Continent.europe, // Croatia
  '192': Continent.northAmerica, // Cuba
  '196': Continent.asia, // Cyprus
  '203': Continent.europe, // Czechia
  '204': Continent.africa, // Benin
  '208': Continent.europe, // Denmark
  '212': Continent.northAmerica, // Dominica
  '214': Continent.northAmerica, // Dominican Republic
  '218': Continent.southAmerica, // Ecuador
  '222': Continent.northAmerica, // El Salvador
  '226': Continent.africa, // Equatorial Guinea
  '231': Continent.africa, // Ethiopia
  '232': Continent.africa, // Eritrea
  '233': Continent.europe, // Estonia
  '234': Continent.europe, // Faroe Islands
  '238': Continent.southAmerica, // Falkland Islands
  '239': Continent.antarctica, // South Georgia and the South Sandwich Islands
  '242': Continent.oceania, // Fiji
  '246': Continent.europe, // Finland
  '248': Continent.europe, // Aland Islands
  '250': Continent.europe, // France
  '254': Continent.southAmerica, // French Guiana
  '258': Continent.oceania, // French Polynesia
  '260': Continent.antarctica, // French Southern Territories
  '262': Continent.africa, // Djibouti
  '266': Continent.africa, // Gabon
  '268': Continent.asia, // Georgia
  '270': Continent.africa, // Gambia
  '275': Continent.asia, // Palestine
  '276': Continent.europe, // Germany
  '288': Continent.africa, // Ghana
  '292': Continent.europe, // Gibraltar
  '296': Continent.oceania, // Kiribati
  '300': Continent.europe, // Greece
  '304': Continent.northAmerica, // Greenland
  '308': Continent.northAmerica, // Grenada
  '312': Continent.northAmerica, // Guadeloupe
  '316': Continent.oceania, // Guam
  '320': Continent.northAmerica, // Guatemala
  '324': Continent.africa, // Guinea
  '328': Continent.southAmerica, // Guyana
  '332': Continent.northAmerica, // Haiti
  '334': Continent.antarctica, // Heard Island and McDonald Islands
  '336': Continent.europe, // Holy See
  '340': Continent.northAmerica, // Honduras
  '344': Continent.asia, // Hong Kong
  '348': Continent.europe, // Hungary
  '352': Continent.europe, // Iceland
  '356': Continent.asia, // India
  '360': Continent.asia, // Indonesia
  '364': Continent.asia, // Iran
  '368': Continent.asia, // Iraq
  '372': Continent.europe, // Ireland
  '376': Continent.asia, // Israel
  '380': Continent.europe, // Italy
  '384': Continent.africa, // Cote d'Ivoire
  '388': Continent.northAmerica, // Jamaica
  '392': Continent.asia, // Japan
  '398': Continent.asia, // Kazakhstan
  '400': Continent.asia, // Jordan
  '404': Continent.africa, // Kenya
  '408': Continent.asia, // North Korea
  '410': Continent.asia, // South Korea
  '414': Continent.asia, // Kuwait
  '417': Continent.asia, // Kyrgyzstan
  '418': Continent.asia, // Laos
  '422': Continent.asia, // Lebanon
  '426': Continent.africa, // Lesotho
  '428': Continent.europe, // Latvia
  '430': Continent.africa, // Liberia
  '434': Continent.africa, // Libya
  '438': Continent.europe, // Liechtenstein
  '440': Continent.europe, // Lithuania
  '442': Continent.europe, // Luxembourg
  '446': Continent.asia, // Macao
  '450': Continent.africa, // Madagascar
  '454': Continent.africa, // Malawi
  '458': Continent.asia, // Malaysia
  '462': Continent.asia, // Maldives
  '466': Continent.africa, // Mali
  '470': Continent.europe, // Malta
  '474': Continent.northAmerica, // Martinique
  '478': Continent.africa, // Mauritania
  '480': Continent.africa, // Mauritius
  '484': Continent.northAmerica, // Mexico
  '492': Continent.europe, // Monaco
  '496': Continent.asia, // Mongolia
  '498': Continent.europe, // Moldova
  '499': Continent.europe, // Montenegro
  '500': Continent.northAmerica, // Montserrat
  '504': Continent.africa, // Morocco
  '508': Continent.africa, // Mozambique
  '512': Continent.asia, // Oman
  '516': Continent.africa, // Namibia
  '520': Continent.oceania, // Nauru
  '524': Continent.asia, // Nepal
  '528': Continent.europe, // Netherlands
  '531': Continent.northAmerica, // Curacao
  '533': Continent.northAmerica, // Aruba
  '534': Continent.northAmerica, // Sint Maarten
  '535': Continent.northAmerica, // Bonaire, Sint Eustatius and Saba
  '540': Continent.oceania, // New Caledonia
  '548': Continent.oceania, // Vanuatu
  '554': Continent.oceania, // New Zealand
  '558': Continent.northAmerica, // Nicaragua
  '562': Continent.africa, // Niger
  '566': Continent.africa, // Nigeria
  '570': Continent.oceania, // Niue
  '574': Continent.oceania, // Norfolk Island
  '578': Continent.europe, // Norway
  '580': Continent.oceania, // Northern Mariana Islands
  '581': Continent.oceania, // United States Minor Outlying Islands
  '583': Continent.oceania, // Micronesia
  '584': Continent.oceania, // Marshall Islands
  '585': Continent.oceania, // Palau
  '586': Continent.asia, // Pakistan
  '591': Continent.northAmerica, // Panama
  '598': Continent.oceania, // Papua New Guinea
  '600': Continent.southAmerica, // Paraguay
  '604': Continent.southAmerica, // Peru
  '608': Continent.asia, // Philippines
  '612': Continent.oceania, // Pitcairn Islands
  '616': Continent.europe, // Poland
  '620': Continent.europe, // Portugal
  '624': Continent.africa, // Guinea-Bissau
  '626': Continent.asia, // Timor-Leste
  '630': Continent.northAmerica, // Puerto Rico
  '634': Continent.asia, // Qatar
  '638': Continent.africa, // Reunion
  '642': Continent.europe, // Romania
  '643': Continent.europe, // Russia
  '646': Continent.africa, // Rwanda
  '652': Continent.northAmerica, // Saint Barthelemy
  '654': Continent.africa, // Saint Helena, Ascension and Tristan da Cunha
  '659': Continent.northAmerica, // Saint Kitts and Nevis
  '660': Continent.northAmerica, // Anguilla
  '662': Continent.northAmerica, // Saint Lucia
  '663': Continent.northAmerica, // Saint Martin
  '666': Continent.northAmerica, // Saint Pierre and Miquelon
  '670': Continent.northAmerica, // Saint Vincent and the Grenadines
  '674': Continent.europe, // San Marino
  '678': Continent.africa, // Sao Tome and Principe
  '682': Continent.asia, // Saudi Arabia
  '686': Continent.africa, // Senegal
  '688': Continent.europe, // Serbia
  '690': Continent.africa, // Seychelles
  '694': Continent.africa, // Sierra Leone
  '702': Continent.asia, // Singapore
  '703': Continent.europe, // Slovakia
  '704': Continent.asia, // Vietnam
  '705': Continent.europe, // Slovenia
  '706': Continent.africa, // Somalia
  '710': Continent.africa, // South Africa
  '716': Continent.africa, // Zimbabwe
  '724': Continent.europe, // Spain
  '728': Continent.africa, // South Sudan
  '729': Continent.africa, // Sudan
  '732': Continent.africa, // Western Sahara
  '740': Continent.southAmerica, // Suriname
  '744': Continent.europe, // Svalbard and Jan Mayen
  '748': Continent.africa, // Eswatini
  '752': Continent.europe, // Sweden
  '756': Continent.europe, // Switzerland
  '760': Continent.asia, // Syria
  '762': Continent.asia, // Tajikistan
  '764': Continent.asia, // Thailand
  '768': Continent.africa, // Togo
  '772': Continent.oceania, // Tokelau
  '776': Continent.oceania, // Tonga
  '780': Continent.northAmerica, // Trinidad and Tobago
  '784': Continent.asia, // United Arab Emirates
  '788': Continent.africa, // Tunisia
  '792': Continent.asia, // Turkey
  '795': Continent.asia, // Turkmenistan
  '796': Continent.northAmerica, // Turks and Caicos Islands
  '798': Continent.oceania, // Tuvalu
  '800': Continent.africa, // Uganda
  '804': Continent.europe, // Ukraine
  '807': Continent.europe, // North Macedonia
  '818': Continent.africa, // Egypt
  '826': Continent.europe, // United Kingdom
  '831': Continent.europe, // Guernsey
  '832': Continent.europe, // Jersey
  '833': Continent.europe, // Isle of Man
  '834': Continent.africa, // Tanzania
  '840': Continent.northAmerica, // United States
  '850': Continent.northAmerica, // United States Virgin Islands
  '854': Continent.africa, // Burkina Faso
  '858': Continent.southAmerica, // Uruguay
  '860': Continent.asia, // Uzbekistan
  '862': Continent.southAmerica, // Venezuela
  '876': Continent.oceania, // Wallis and Futuna
  '882': Continent.oceania, // Samoa
  '887': Continent.asia, // Yemen
  '894': Continent.africa, // Zambia
};

/// Resolves the continent for a raw FishBase/SeaLifeBase region code
/// (country- or subregion-scope, e.g. '218A' or '840:US-WA'). Mirrors the
/// code parsing in [resolveCountryRegionLabel]: an exact match on the special
/// territory code wins, otherwise its leading numeric country prefix is used
/// -- so territories like Galápagos ('218A') inherit their mainland's
/// continent without a dedicated entry.
Continent? continentForCountryCode(String rawLabel) {
  final normalized = rawLabel.trim();
  if (normalized.isEmpty) return null;

  final rawCountryCode = normalized.split(':').first;
  final continent = continentByCountryCode[rawCountryCode.padLeft(3, '0')];
  if (continent != null) return continent;

  final prefix = _leadingDigits.firstMatch(rawCountryCode)?.group(1);
  if (prefix == null) return null;
  return continentByCountryCode[prefix.padLeft(3, '0')];
}
