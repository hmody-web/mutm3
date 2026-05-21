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
  String _playerMode = PlayerModeNotifier.normal; // ✦ طريقة العرض

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
      _playerMode = PlayerModeNotifier.instance.value; // ✦ طريقة العرض
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

                  // ✦✦✦ قسم طريقة العرض ✦✦✦
                  _settingsSection('طريقة العرض', [
                    _displayModeTile(),
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

  // ✦✦✦ بطاقة طريقة العرض ✦✦✦
  Widget _displayModeTile() {
    final isDark = context.isDark;

    // خصائص كل وضع
    final modes = [
      _ModeOption(
        id: PlayerModeNotifier.normal,
        label: 'المشغل الاعتيادي',
        icon: CupertinoIcons.play_circle_fill,
        desc: 'تشغيل عادي مع قائمة الأغاني',
        gradient: [const Color(0xFF1565C0), const Color(0xFF0D47A1)],
      ),
      _ModeOption(
        id: PlayerModeNotifier.reels,
        label: 'مشغل الريلز',
        icon: CupertinoIcons.play_rectangle_fill,
        desc: 'تجربة ريلز انستكرام وتيك توك ✦',
        gradient: [AppColors.primary, AppColors.primaryDark],
        isNew: false,
      ),
      _ModeOption(
        id: PlayerModeNotifier.galactic,
        label: 'الوضع العشوائي',
        icon: CupertinoIcons.sparkles,
        desc: 'اكتشف أغانيك كمجموعة شمسية 🪐',
        gradient: [const Color(0xFF6A1B9A), const Color(0xFF4A148C)],
        isNew: true,
      ),
    ];

    final current = modes.firstWhere(
      (m) => m.id == _playerMode,
      orElse: () => modes[0],
    );

    return GestureDetector(
      onTap: () => _showDisplayModeSheet(modes),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: current.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: current.gradient.first.withOpacity(0.40),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(current.icon, color: Colors.white, size: 20),
          ),
          title: Row(
            children: [
              Text(
                'طريقة العرض',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (current.isNew)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A),
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
            current.label,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              color: current.gradient.first,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${modes.indexOf(current) + 1}/${modes.length}',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11,
                  color: isDark ? AppColors.darkTextSec : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: isDark ? AppColors.darkTextSec : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDisplayModeSheet(List<_ModeOption> modes) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DisplayModeSheet(
        modes: modes,
        currentMode: _playerMode,
        onSelect: (mode) {
          setState(() => _playerMode = mode);
          PlayerModeNotifier.instance.set(mode);
        },
      ),
    );
  }

  // ✦✦✦ بطاقة وضع الريلز القديمة — محذوفة وتم استبدالها ✦✦✦

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

// ═══════════════════════════════════════════════════════════════
//  MODEL — خيار طريقة العرض
// ═══════════════════════════════════════════════════════════════
class _ModeOption {
  final String id;
  final String label;
  final IconData icon;
  final String desc;
  final List<Color> gradient;
  final bool isNew;

  const _ModeOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.desc,
    required this.gradient,
    this.isNew = false,
  });
}

// ═══════════════════════════════════════════════════════════════
//  SHEET — ورقة اختيار طريقة العرض
// ═══════════════════════════════════════════════════════════════
class _DisplayModeSheet extends StatefulWidget {
  final List<_ModeOption> modes;
  final String currentMode;
  final ValueChanged<String> onSelect;

  const _DisplayModeSheet({
    required this.modes,
    required this.currentMode,
    required this.onSelect,
  });

  @override
  State<_DisplayModeSheet> createState() => _DisplayModeSheetState();
}

class _DisplayModeSheetState extends State<_DisplayModeSheet>
    with SingleTickerProviderStateMixin {
  late String _selected;
  late AnimationController _ctrl;
  late List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentMode;
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _anims = List.generate(
      widget.modes.length,
      (i) => CurvedAnimation(
        parent: _ctrl,
        curve: Interval(i * 0.15, 0.6 + i * 0.15, curve: Curves.easeOutBack),
      ),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 40,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── مقبض ──
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkDivider : AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── العنوان ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(CupertinoIcons.tv_fill,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'طريقة العرض',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'اختر طريقة تشغيل الأغاني والمقاطع',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextSec
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Divider(
            height: 1,
            color: isDark ? AppColors.darkDivider : AppColors.divider,
            indent: 20,
            endIndent: 20,
          ),
          const SizedBox(height: 16),

          // ── بطاقات الأوضاع ──
          ...List.generate(widget.modes.length, (i) {
            final mode = widget.modes[i];
            final isSelected = _selected == mode.id;

            return AnimatedBuilder(
              animation: _anims[i],
              builder: (_, child) => Transform.translate(
                offset: Offset(0, 30 * (1 - _anims[i].value)),
                child: Opacity(opacity: _anims[i].value.clamp(0.0, 1.0), child: child),
              ),
              child: GestureDetector(
                onTap: () {
                  setState(() => _selected = mode.id);
                  widget.onSelect(mode.id);
                  Future.delayed(const Duration(milliseconds: 220),
                      () => Navigator.pop(context));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              mode.gradient.first.withOpacity(0.15),
                              mode.gradient.last.withOpacity(0.08),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isSelected
                        ? null
                        : (isDark
                            ? AppColors.darkSurfaceAlt
                            : AppColors.surface),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? mode.gradient.first.withOpacity(0.55)
                          : (isDark
                              ? AppColors.darkDivider
                              : AppColors.divider),
                      width: isSelected ? 1.5 : 0.8,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: mode.gradient.first.withOpacity(0.22),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    children: [
                      // أيقونة
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? LinearGradient(
                                  colors: mode.gradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected ? null : (isDark ? AppColors.darkSurface : Colors.white),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: mode.gradient.first.withOpacity(0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : [],
                        ),
                        child: Icon(
                          mode.icon,
                          color: isSelected
                              ? Colors.white
                              : mode.gradient.first,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),

                      // نص
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  mode.label,
                                  style: TextStyle(
                                    fontFamily: 'Tajawal',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? mode.gradient.first
                                        : (isDark
                                            ? AppColors.darkText
                                            : AppColors.textPrimary),
                                  ),
                                ),
                                if (mode.isNew) ...[
                                  const SizedBox(width: 7),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                          colors: mode.gradient),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'جديد ✨',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Tajawal',
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              mode.desc,
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 12,
                                color: isSelected
                                    ? mode.gradient.first.withOpacity(0.75)
                                    : (isDark
                                        ? AppColors.darkTextSec
                                        : AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // علامة تحديد
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: isSelected
                              ? LinearGradient(colors: mode.gradient)
                              : null,
                          border: Border.all(
                            color: isSelected
                                ? Colors.transparent
                                : (isDark
                                    ? AppColors.darkDivider
                                    : AppColors.divider),
                            width: 1.5,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 14)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 28),
        ],
      ),
    );
  }
}