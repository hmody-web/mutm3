import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_dynamic_icon/flutter_dynamic_icon.dart';

// ─────────────────────────────────────────────
//  APP ICON SERVICE — تغيير أيقونة التطبيق حسب الثيم
// ─────────────────────────────────────────────
//
//  iOS:  يستخدم flutter_dynamic_icon مع Alternate Icons المُعرَّفة في Info.plist
//  Android: يستخدم activity-alias في AndroidManifest.xml
//
class AppIconService {
  AppIconService._();
  static final AppIconService instance = AppIconService._();

  // أسماء الأيقونات
  static const String _defaultIcon = 'Default'; // الأيقونة الافتراضية (فاتح)
  static const String _darkIcon = 'AppIconDark'; // أيقونة الوضع الداكن

  // اسم الـ package لـ Android
  static const String _packageName = 'com.example.mustm3'; // غيّر هذا لـ package name الفعلي

  // أسماء activity-alias في Android
  static const String _androidDefaultAlias = '.MainActivityDefault';
  static const String _androidDarkAlias = '.MainActivityDark';

  /// تغيير أيقونة التطبيق حسب الثيم
  Future<void> updateIcon({required bool isDark}) async {
    try {
      if (Platform.isIOS) {
        await _updateIconIOS(isDark: isDark);
      } else if (Platform.isAndroid) {
        await _updateIconAndroid(isDark: isDark);
      }
    } catch (e) {
      // تجاهل الأخطاء — تغيير الأيقونة ليس ضرورياً للتطبيق
      debugPrintAppIcon('AppIconService error: $e');
    }
  }

  /// تغيير الأيقونة على iOS
  Future<void> _updateIconIOS({required bool isDark}) async {
    try {
      final bool supported = await FlutterDynamicIcon.supportsAlternateIcons;
      if (!supported) return;

      if (isDark) {
        // تغيير للأيقونة الداكنة
        await FlutterDynamicIcon.setAlternateIconName(_darkIcon);
      } else {
        // العودة للأيقونة الافتراضية
        await FlutterDynamicIcon.setAlternateIconName(null);
      }
    } on PlatformException {
      // الجهاز لا يدعم تغيير الأيقونة
    }
  }

  /// تغيير الأيقونة على Android عبر activity-alias
  Future<void> _updateIconAndroid({required bool isDark}) async {
    try {
      const platform = MethodChannel('com.mustm3/app_icon');
      await platform.invokeMethod('setIcon', {
        'isDark': isDark,
        'defaultAlias': _androidDefaultAlias,
        'darkAlias': _androidDarkAlias,
      });
    } on PlatformException {
      // المكتبة غير متوفرة أو الجهاز لا يدعمها
    }
  }
}

void debugPrintAppIcon(String msg) {
  // ignore: avoid_print
  print(msg);
}