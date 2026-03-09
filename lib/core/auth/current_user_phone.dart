import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CurrentUserPhone {
  static Future<String?> get() async {
    // 1. Firebase (source of truth)
    final user = FirebaseAuth.instance.currentUser;
    if (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty) {
      return user.phoneNumber;
    }

    // 2. Fallback: SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final cachedPhone = prefs.getString('user_phone');
    if (cachedPhone != null && cachedPhone.isNotEmpty) {
      return cachedPhone;
    }

    return null;
  }

  static Future<void> cache(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_phone', phone);
  }
}
