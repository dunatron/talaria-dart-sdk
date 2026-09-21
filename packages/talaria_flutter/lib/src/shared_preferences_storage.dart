import 'package:shared_preferences/shared_preferences.dart';
import 'package:talaria/talaria.dart';

/// [SharedPreferences] adapter for durable `anonymousId` / `sessionId`.
class SharedPreferencesTalariaStorage implements TalariaStorage {
  SharedPreferencesTalariaStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPreferencesTalariaStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPreferencesTalariaStorage(prefs);
  }

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> delete(String key) => _prefs.remove(key);
}
