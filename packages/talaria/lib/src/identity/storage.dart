/// Small key-value port for durable anonymous / session ids.
///
/// The default is in-memory. Flutter provides a SharedPreferences
/// implementation so ids survive process restarts.
abstract class TalariaStorage {
  String? read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Process-local map. Fine for tests and Dart servers; not durable.
class MemoryTalariaStorage implements TalariaStorage {
  MemoryTalariaStorage([Map<String, String>? seed])
      : _data = Map<String, String>.from(seed ?? const {});

  final Map<String, String> _data;

  /// Test inspection of the backing map.
  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_data);

  @override
  String? read(String key) => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}
