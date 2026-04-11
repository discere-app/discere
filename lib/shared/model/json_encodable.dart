/// Interface for objects that can be serialized to JSON.
abstract interface class JsonEncodable {
  Map<String, dynamic> toJson();
}
