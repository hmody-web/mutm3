import 'main.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dynamic_icon/flutter_dynamic_icon.dart';
import 'package:share_plus/share_plus.dart';

// ═══════════════════════════════════════════════════════════════
//  SETTINGS PAGE
// ═══════════════════════════════════════════════════════════════

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _backgroundPlay = true;
  bool _stopOnClose = false;
  String _downloadQuality = 'medium';
  String _downloadPath = '';
  bool _reelsMode = false; // ✦ وضع الريلز

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationDocumentsDirectory();
    setState(() {
      _backgroundPlay = prefs.getBool('backgroundPlay') ?? true;
      _stopOnClose = prefs.getBool('stopOnClose') ?? false;
      _downloadQuality = prefs.getString('downloadQuality') ?? 'medium';
      _downloadPath = '${dir.path}/dndn';
      _reelsMode = prefs.getBool('reelsMode') ?? false; // ✦ وضع الريلز
    });
  }

  Future<void> _savePref(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
  }

  Future<void> _clearDownloads() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('حذف جميع التنزيلات'),
        content: const Text('هل أنت متأكد؟ سيتم حذف جميع الملفات المحملة.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final dir = Directory(_downloadPath);
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create();
      downloadCompleteNotifier.value = _downloadPath;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 20,
                right: 20,
                bottom: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
child: Transform.translate(
  offset: const Offset(0, 10),
  child: Transform.scale(
    scale: 3.5,
    child: Image.asset(
      'assets/images/jna7.png',
      height: 40,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'الإعدادات',
          style: TextStyle(
            fontSize: 24,
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  ),
),
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _settingsSection('التشغيل', [
                    _switchTile(
                      'التشغيل في الخلفية',
                      'يبقى يعمل عند إغلاق التطبيق',
                      CupertinoIcons.play_circle_fill,
                      _backgroundPlay,
                      (v) {
                        setState(() => _backgroundPlay = v);
                        _savePref('backgroundPlay', v);
                      },
                    ),
                    _switchTile(
                      'إيقاف عند الإغلاق',
                      'يتوقف عند إغلاق شاشة التطبيق',
                      CupertinoIcons.stop_circle_fill,
                      _stopOnClose,
                      (v) {
                        setState(() => _stopOnClose = v);
                        _savePref('stopOnClose', v);
                      },
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // ✦✦✦ قسم مشغل الفيديو ✦✦✦
                  _settingsSection('مشغل الفيديو', [
                    _reelsTile(),
                  ]),
                  const SizedBox(height: 16),

                  _settingsSection('المظهر', [
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: ThemeNotifier.instance,
                      builder: (_, mode, __) {
                        final isDarkNow = mode == ThemeMode.dark;
                        return _switchTile(
                          'الوضع الداكن',
                          'تغيير مظهر التطبيق للوضع الداكن',
                          CupertinoIcons.moon_fill,
                          isDarkNow,
                          (v) => ThemeNotifier.instance.toggle(v),
                        );
                      },
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _settingsSection('التحميل', [
                    _infoTile(
                        'مسار التحميل',
                        _downloadPath.split('/').last,
                        CupertinoIcons.folder_fill),
                    _qualityTile(),
                  ]),
                  const SizedBox(height: 16),
                  _settingsSection('الإدارة', [
                    GestureDetector(
                      onTap: () async {
                        final uri = Uri.parse('https://scrptaty.com');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? AppColors.darkSurface
                              : AppColors.surface,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: context.isDark
                                  ? AppColors.darkDivider
                                  : AppColors.divider,
                              width: 0.5,
                            ),
                            left: BorderSide(
                              color: context.isDark
                                  ? AppColors.darkDivider
                                  : AppColors.divider,
                              width: 0.5,
                            ),
                            right: BorderSide(
                              color: context.isDark
                                  ? AppColors.darkDivider
                                  : AppColors.divider,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: context.isDark
                                  ? const Color(0xFF3A1212)
                                  : const Color(0xFFFFEBEB),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(7),
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.mode(
                                  Color.fromARGB(255, 232, 39, 42),
                                  BlendMode.srcIn,
                                ),
                                child: Image.asset(
                                  'assets/images/scrptaty.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            'سكربتاتي',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.appText,
                            ),
                          ),
                          subtitle: Text(
                            'فريق مطوري تطبيق دندن',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 12,
                              color: context.appTextSec,
                            ),
                          ),
                          trailing: Icon(
                            CupertinoIcons.chevron_left,
                            size: 18,
                            color: context.appTextSec,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        Share.share(
                          'حمّل تطبيق دندن الآن \nhttps://scrptaty.com',
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? AppColors.darkSurface
                              : AppColors.surface,
                          border: Border(
                            left: BorderSide(
                              color: context.isDark
                                  ? AppColors.darkDivider
                                  : AppColors.divider,
                              width: 0.5,
                            ),
                            right: BorderSide(
                              color: context.isDark
                                  ? AppColors.darkDivider
                                  : AppColors.divider,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: context.isDark
                                  ? const Color(0xFF3A1212)
                                  : const Color(0xFFFFEBEB),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.share,
                              color: Color.fromARGB(255, 232, 39, 42),
                              size: 18,
                            ),
                          ),
                          title: Text(
                            'مشاركة التطبيق',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.appText,
                            ),
                          ),
                          subtitle: Text(
                            'شارك التطبيق مع اصدقائك لتجربة أمتع !',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 12,
                              color: context.appTextSec,
                            ),
                          ),
                          trailing: Icon(
                            CupertinoIcons.chevron_left,
                            size: 18,
                            color: context.appTextSec,
                          ),
                        ),
                      ),
                    ),
                    _actionTile(
                      'حذف جميع التنزيلات',
                      'مسح كل الملفات المحملة',
                      CupertinoIcons.trash_fill,
                      Colors.red,
                      _clearDownloads,
                    ),
                  ]),

                  const SizedBox(height: 130),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✦✦✦ بطاقة وضع الريلز الخاصة ✦✦✦
  Widget _reelsTile() {
    final isDark = context.isDark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _reelsMode
                  ? [AppColors.primary, AppColors.primaryDark]
                  : [
                      isDark ? AppColors.darkRedLight : AppColors.redLight,
                      isDark ? AppColors.darkRedLight : AppColors.redLight,
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: _reelsMode
                ? [
                    BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3)),
                  ]
                : [],
          ),
          child: Icon(
            CupertinoIcons.play_rectangle_fill,
            color: _reelsMode ? Colors.white : AppColors.primary,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              'وضع الريلز',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkText : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            // بادج "جديد"
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'جديد',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Tajawal',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          _reelsMode
              ? 'يشغّل الفيديوهات بتجربة ريلز انستكرام ✦'
              : 'تشغيل الفيديو بأسلوب ريلز انستكرام وتيك توك',
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontSize: 12,
            color: _reelsMode
                ? AppColors.primary
                : (isDark ? AppColors.darkTextSec : AppColors.textSecondary),
          ),
        ),
        trailing: CupertinoSwitch(
          value: _reelsMode,
          activeColor: AppColors.primary,
          onChanged: (v) {
            setState(() => _reelsMode = v);
            ReelsModeNotifier.instance.set(v);
          },
        ),
      ),
    );
  }

  Widget _settingsSection(String title, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextSec : AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark ? AppColors.darkDivider : AppColors.divider,
                width: 0.5),
          ),
          child: Column(
            children: children.map((child) {
              final index = children.indexOf(child);
              return Column(
                children: [
                  child,
                  if (index < children.length - 1)
                    Divider(
                        height: 1,
                        color: isDark
                            ? AppColors.darkDivider
                            : AppColors.divider,
                        indent: 16,
                        endIndent: 16),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _switchTile(String title, String subtitle, IconData icon, bool value,
      Function(bool) onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkRedLight : AppColors.redLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child:
            Icon(icon, color: const Color.fromARGB(255, 232, 39, 42), size: 18),
      ),
      title: Text(title,
          style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.darkText : AppColors.textPrimary)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              color:
                  isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
      trailing: CupertinoSwitch(
          value: value, onChanged: onChanged, activeColor: AppColors.primary),
    );
  }

  Widget _infoTile(String title, String value, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3A1212) : AppColors.redLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      title: Text(title,
          style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.darkText : AppColors.textPrimary)),
      trailing: Text(value,
          style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 13,
              color:
                  isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
    );
  }

  Widget _qualityTile() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? const Color.from(
                  alpha: 1, red: 0.227, green: 0.071, blue: 0.071)
              : AppColors.redLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(CupertinoIcons.dial_fill,
            color: AppColors.primary, size: 18),
      ),
      title: Text('جودة التحميل',
          style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.darkText : AppColors.textPrimary)),
      trailing: CupertinoSlidingSegmentedControl<String>(
        groupValue: _downloadQuality,
        thumbColor: AppColors.primary,
        children: const {
          'high': Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('عالية',
                  style:
                      TextStyle(fontSize: 11, fontFamily: 'Tajawal'))),
          'medium': Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('متوسطة',
                  style:
                      TextStyle(fontSize: 11, fontFamily: 'Tajawal'))),
        },
        onValueChanged: (v) {
          if (v != null) {
            setState(() => _downloadQuality = v);
            _savePref('downloadQuality', v);
          }
        },
      ),
    );
  }

  Widget _actionTile(String title, String subtitle, IconData icon, Color color,
      VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(title,
          style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              color:
                  isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
      onTap: onTap,
    );
  }
}