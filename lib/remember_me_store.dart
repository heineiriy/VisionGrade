import 'package:shared_preferences/shared_preferences.dart';

class RememberMeStore {
  RememberMeStore._();

  static const _roleKey = 'remembered_user_role';

  static Future<String?> getRole() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_roleKey);
  }

  static Future<void> save({
    required bool remember,
    required String role,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (remember) {
      await preferences.setString(_roleKey, role);
    } else {
      await preferences.remove(_roleKey);
    }
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_roleKey);
  }
}
