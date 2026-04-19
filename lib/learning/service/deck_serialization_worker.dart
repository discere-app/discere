import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:discere/learning/model/create_deck.dart';

class DeckSerializationWorker {
  const DeckSerializationWorker();

  Future<String> encodeJson(Map<String, dynamic> payload) {
    return Isolate.run(() => _encodeJson(payload));
  }

  Future<String> encodeGzipBase64(Map<String, dynamic> payload) {
    return Isolate.run(() => _encodeGzipBase64(payload));
  }

  Future<Map<String, dynamic>> decodeJson(String payload) {
    return Isolate.run(() => _decodeJson(payload));
  }

  Future<Map<String, dynamic>> decodeGzipBase64(String payload) {
    return Isolate.run(() => _decodeGzipBase64(payload));
  }

  Future<Object?> decodeJsonBytes(List<int> bytes) {
    return Isolate.run(() => _decodeJsonBytes(bytes));
  }

  Future<CreateDeck> decodeCreateDeckBytes(List<int> bytes) async {
    final payload = await decodeJsonBytes(bytes);
    return CreateDeck.fromJson(
      Map<String, dynamic>.from((payload as Map).cast<Object?, Object?>()),
    );
  }
}

String _encodeJson(Map<String, dynamic> payload) {
  return jsonEncode(payload);
}

String _encodeGzipBase64(Map<String, dynamic> payload) {
  final jsonString = jsonEncode(payload);
  final bytes = utf8.encode(jsonString);
  final compressedBytes = gzip.encode(bytes);
  return base64Encode(compressedBytes);
}

Map<String, dynamic> _decodeJson(String payload) {
  return Map<String, dynamic>.from(
    (jsonDecode(payload) as Map).cast<Object?, Object?>(),
  );
}

Map<String, dynamic> _decodeGzipBase64(String payload) {
  if (payload.trim().isEmpty) return <String, dynamic>{};

  final compressedBytes = base64Decode(payload.trim());
  final decompressedBytes = gzip.decode(compressedBytes);
  final jsonString = utf8.decode(decompressedBytes);
  return Map<String, dynamic>.from(
    (jsonDecode(jsonString) as Map).cast<Object?, Object?>(),
  );
}

Object? _decodeJsonBytes(List<int> bytes) {
  return jsonDecode(utf8.decode(bytes));
}
