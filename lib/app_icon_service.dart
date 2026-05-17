import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
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
    final bool supported =
        await FlutterDynamicIconPlus.supportsAlternateIcons;

    if (!supported) return;

    if (isDark) {
      await FlutterDynamicIconPlus.setAlternateIconName(
        iconName: _darkIcon,
      );
    } else {
      await FlutterDynamicIconPlus.setAlternateIconName(
        iconName: null,
      );
    }
  } on PlatformException {
    //
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