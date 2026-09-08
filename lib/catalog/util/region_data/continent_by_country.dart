import 'package:discere/catalog/model/continent.dart';

/// Which continent a country code sits on, for grouping the region filter.
/// Keyed by the zero-padded three-digit code.
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
