import 'dart:convert';
import 'dart:isolate';

class BackgroundJson {
  const BackgroundJson._();

  static Future<Object?> decodeBytes(List<int> bytes) {
    return Isolate.run(() => jsonDecode(utf8.decode(bytes)));
  }
}
