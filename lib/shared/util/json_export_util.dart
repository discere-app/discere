import 'dart:convert';
import 'dart:io';

import 'package:discere/shared/model/json_encodable.dart';

class JsonExportUtil {
  /// Encodes a [JsonEncodable] object into a compressed Base64 string.
  static String encode(JsonEncodable object) {
    final jsonString = jsonEncode(object.toJson());
    final bytes = utf8.encode(jsonString);
    final compressedBytes = gzip.encode(bytes);
    return base64Encode(compressedBytes);
  }

  /// Decodes a compressed Base64 string into an object of type [T].
  /// [factory] should be the `fromJson` method of the class.
  static T decode<T>(String data, T Function(Map<String, dynamic>) factory) {
    if (data.trim().isEmpty) return factory({});

    final compressedBytes = base64Decode(data.trim());
    final decompressedBytes = gzip.decode(compressedBytes);
    final jsonString = utf8.decode(decompressedBytes);
    final map = jsonDecode(jsonString) as Map<String, dynamic>;

    return factory(map);
  }
}
