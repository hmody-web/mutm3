// خدمة الأيقونة معطّلة نهائياً.
// لا يوجد أي MethodChannel ولا أي تغيير للأيقونة.
class AppIconService {
  AppIconService._();
  static final AppIconService instance = AppIconService._();

  Future<void> updateIcon({required bool isDark}) async {}
  Future<void> resetIcon() async {}
  Future<void> setDefaultIcon() async {}
}
