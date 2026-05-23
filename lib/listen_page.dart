import 'main.dart';
import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:photo_manager/photo_manager.dart';
import 'app_icon_service.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'listen_page.dart';
import 'browse_page.dart';
import 'settings_page.dart';
import 'reels_player.dart';


// ═══════════════════════════════════════════════════════════
//  MODEL — مجلد موسيقى
// ═══════════════════════════════════════════════════════════
class MusicFolder {
  final String id;
  String name;
  Color color;
  List<String> songPaths; // مسارات الأغاني داخل المجلد

  MusicFolder({
    required this.id,
    required this.name,
    required this.color,
    List<String>? songPaths,
  }) : songPaths = songPaths ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color.value,
        'songPaths': songPaths,
      };

  factory MusicFolder.fromJson(Map<String, dynamic> json) => MusicFolder(
        id: json['id'],
        name: json['name'],
        color: Color(json['color']),
        songPaths: List<String>.from(json['songPaths'] ?? []),
      );
}

// ═══════════════════════════════════════════════════════════
//  PAGE 1 — استمع (Listen)
// ═══════════════════════════════════════════════════════════
class ListenPage extends StatefulWidget {
  const ListenPage({super.key});

  @override
  State<ListenPage> createState() => _ListenPageState();
}

class _ListenPageState extends State<ListenPage> with TickerProviderStateMixin {
  List<LocalMediaItem> _localItems = [];
  List<MusicFolder> _folders = [];

  // ── البحث ──
  bool _searchActive = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // ── وضع التحديد ──
  bool _selectionMode = false;

  // ── نوع العرض ──
  bool _gridView = false; // سيُحمَّل من SharedPreferences
  bool _reelsMode = false; // وضع الريلز
  final Set<String> _selectedPaths = {};

  // ── أنيميشن وضع التحديد ──
  late AnimationController _selectionBarCtrl;
  late Animation<double> _selectionBarAnim;

  List<LocalMediaItem> get _filteredItems {
    if (_searchQuery.isEmpty) return _localItems;
    final q = _searchQuery.toLowerCase();
    return _localItems
        .where((e) => e.title.toLowerCase().contains(q))
        .toList();
  }

  // الأغاني غير المصنّفة في أي مجلد
  List<LocalMediaItem> get _unfolderiedItems {
    final allFoldered = _folders.expand((f) => f.songPaths).toSet();
    return _localItems.where((i) => !allFoldered.contains(i.path)).toList();
  }

  @override
  void initState() {
    super.initState();
    _selectionBarCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _selectionBarAnim = CurvedAnimation(
        parent: _selectionBarCtrl, curve: Curves.easeOutBack);
    _loadViewMode();
    _loadFiles();
    _loadFolders();
    downloadCompleteNotifier.addListener(_onDownloadComplete);
  }

  void _onDownloadComplete() {
    if (downloadCompleteNotifier.value != null) {
      _loadFiles();
      downloadCompleteNotifier.value = null;
    }
  }

  @override
  void dispose() {
    downloadCompleteNotifier.removeListener(_onDownloadComplete);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _selectionBarCtrl.dispose();
    super.dispose();
  }

  // ─── تحميل/حفظ المجلدات ───
  Future<void> _loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('music_folders');
    if (raw != null) {
      final List<dynamic> list = jsonDecode(raw);
      setState(() {
        _folders = list.map((e) => MusicFolder.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'music_folders', jsonEncode(_folders.map((f) => f.toJson()).toList()));
  }

Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('listen_grid_view') ?? false;
    final reels = prefs.getBool('reelsMode') ?? false;
    if (mounted) setState(() {
      _gridView = saved;
      _reelsMode = reels;
    });
  }

  Future<void> _saveViewMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('listen_grid_view', value);
  }

  Future<void> _loadFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${dir.path}/dndn');
    if (!await musicDir.exists()) await musicDir.create(recursive: true);

    final entities = musicDir
        .listSync()
        .where((e) => e is File && !e.path.split('/').last.startsWith('.'))
        .toList();

    final withStat = entities.map((e) => MapEntry(e, e.statSync())).toList()
      ..sort((a, b) => b.value.modified.compareTo(a.value.modified));

    final items = <LocalMediaItem>[];
    for (final entry in withStat) {
      final path = entry.key.path;
      final name = path.split('/').last.toLowerCase();
      final isVideo = name.endsWith('.mp4') ||
          name.endsWith('.webm') ||
          name.endsWith('.mkv') ||
          name.endsWith('.mov');
      final isAudio = name.endsWith('.mp3') ||
          name.endsWith('.m4a') ||
          name.endsWith('.aac') ||
          name.endsWith('.opus') ||
          name.endsWith('.flac') ||
          name.endsWith('.wav');
      if (isVideo || isAudio) {
        items.add(LocalMediaItem(
            path: path, title: path.split('/').last, isVideo: isVideo));
      }
    }

    if (mounted) {
      setState(() {
        _localItems = items;
      });
    }

    for (final item in items) {
      final existing = await ThumbnailManager.getLocalThumbnail(item.path);
      if (existing != null) continue;
      ThumbnailManager.generateLocalThumbnail(item.path).then((result) {
        if (result != null && mounted) setState(() {});
      });
    }
  }

  // ─── إنشاء مجلد جديد ───
  Future<void> _createFolder() async {
    final nameCtrl = TextEditingController();
    Color selectedColor = AppColors.primary;

    final List<Color> folderColors = [
      AppColors.primary,
      const Color(0xFF1565C0),
      const Color(0xFF2E7D32),
      const Color(0xFFF57F17),
      const Color(0xFF6A1B9A),
      const Color(0xFF00838F),
      const Color(0xFFAD1457),
      const Color(0xFF4527A0),
    ];

    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (ctx, anim, _, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (ctx, _, __) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          // ── يتحرك الديالوج فوق الكيبورد تلقائياً ──
          return AnimatedPadding(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── رأس الديالوج ──
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [selectedColor, selectedColor.withValues(alpha: 0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(CupertinoIcons.folder_fill,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          const Text(
                            'مجلد جديد',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'اسم المجلد',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.darkTextSec
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: nameCtrl,
                            textDirection: TextDirection.rtl,
                            autofocus: true,
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 15,
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'مثال: المفضلة، جيم…',
                              hintStyle: TextStyle(
                                fontFamily: 'Tajawal',
                                color: isDark
                                    ? AppColors.darkTextSec
                                    : AppColors.textSecondary,
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? AppColors.darkSurfaceAlt
                                  : AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: selectedColor, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'لون المجلد',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.darkTextSec
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            children: folderColors.map((c) {
                              final isSelected = selectedColor == c;
                              return GestureDetector(
                                onTap: () =>
                                    setDialogState(() => selectedColor = c),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: isSelected
                                        ? Border.all(
                                            color: Colors.white, width: 2.5)
                                        : null,
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color:
                                                  c.withValues(alpha: 0.6),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check,
                                          color: Colors.white, size: 16)
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(ctx),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppColors.darkSurfaceAlt
                                          : AppColors.surfaceAlt,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'إلغاء',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppColors.darkTextSec
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    final n = nameCtrl.text.trim();
                                    if (n.isNotEmpty) {
                                      Navigator.pop(ctx, n);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          selectedColor,
                                          selectedColor
                                              .withValues(alpha: 0.8)
                                        ],
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: selectedColor
                                              .withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Text(
                                      'إنشاء',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ), // Center
          ); // AnimatedPadding
        },
      ),
    );

    if (result != null && result.isNotEmpty) {
      final folder = MusicFolder(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result,
        color: selectedColor,
      );
      setState(() => _folders.add(folder));
      await _saveFolders();
    }
  }

  // ─── تغيير لون المجلد + حذفه ───
  Future<void> _changeFolderColor(MusicFolder folder) async {
    final List<Color> folderColors = [
      AppColors.primary,
      const Color(0xFF1565C0),
      const Color(0xFF2E7D32),
      const Color(0xFFF57F17),
      const Color(0xFF6A1B9A),
      const Color(0xFF00838F),
      const Color(0xFFAD1457),
      const Color(0xFF4527A0),
      const Color(0xFF00695C),
      const Color(0xFF558B2F),
    ];

    Color chosen = folder.color;

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setBS) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── رأس النافذة ──
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: chosen,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(CupertinoIcons.folder_fill,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      folder.name,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkText
                            : AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    // ── زر حذف المجلد ──
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, 'delete'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB71C1C).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFB71C1C)
                                .withValues(alpha: 0.30),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.trash_fill,
                                size: 14, color: Color(0xFFEF5350)),
                            const SizedBox(width: 5),
                            const Text(
                              'حذف المجلد',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFEF5350),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(
                  color: isDark ? AppColors.darkDivider : AppColors.divider,
                  height: 1,
                ),
                const SizedBox(height: 16),
                Text(
                  'لون المجلد',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextSec
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: folderColors.map((c) {
                    final isSel = chosen == c;
                    return GestureDetector(
                      onTap: () => setBS(() => chosen = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: isSel
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                          boxShadow: isSel
                              ? [
                                  BoxShadow(
                                    color: c.withValues(alpha: 0.55),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : null,
                        ),
                        child: isSel
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 20)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkSurfaceAlt
                                : AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('إلغاء',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, 'color'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: chosen,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: chosen.withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Text('تطبيق اللون',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result == 'color') {
      setState(() => folder.color = chosen);
      await _saveFolders();
    } else if (result == 'delete') {
      // ── تأكيد حذف المجلد ──
      final confirmDelete = await showCupertinoDialog<bool>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('حذف المجلد'),
          content: Text(
              'هل تريد حذف مجلد "${folder.name}"؟\nستبقى الأغاني في قائمة الاستماع.'),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف المجلد'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      );
      if (confirmDelete == true) {
        setState(() => _folders.remove(folder));
        await _saveFolders();
        _showSnack('🗑️ تم حذف المجلد "${folder.name}"');
      }
    }
  }

  // ─── نقل المحدد إلى مجلد ───
  Future<void> _moveSelectedToFolder() async {
    if (_selectedPaths.isEmpty) return;

    if (_folders.isEmpty) {
      // لا توجد مجلدات — عرض خيار الإنشاء
      final create = await showCupertinoDialog<bool>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('لا توجد مجلدات'),
          content: const Text('هل تريد إنشاء مجلد جديد ونقل المحدد إليه؟'),
          actions: [
            CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(context, true),
                child: const Text('إنشاء مجلد')),
          ],
        ),
      );
      if (create == true) {
        await _createFolder();
        if (_folders.isNotEmpty) {
          await _moveSelectedToFolder();
        }
      }
      return;
    }

    // عرض قائمة المجلدات
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chosen = await showModalBottomSheet<MusicFolder>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Text(
                    'نقل إلى مجلد',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkText : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_selectedPaths.length} عنصر',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ..._folders.map((f) => GestureDetector(
                  onTap: () => Navigator.pop(context, f),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 5),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceAlt
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: f.color.withValues(alpha: 0.3), width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [f.color, f.color.withValues(alpha: 0.7)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(CupertinoIcons.folder_fill,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.name,
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.darkText
                                      : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '${f.songPaths.length} أغنية',
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
                        ),
                        Icon(CupertinoIcons.chevron_left,
                            size: 16, color: f.color),
                      ],
                    ),
                  ),
                )),
            Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  await _createFolder();
                  if (_folders.isNotEmpty) await _moveSelectedToFolder();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.add_circled,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'إنشاء مجلد جديد',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (chosen != null) {
      // ── نقل حقيقي: إزالة من جميع المجلدات الأخرى أولاً ──
      for (final path in _selectedPaths) {
        // إزالة من أي مجلد آخر قد يحتوي عليها
        for (final folder in _folders) {
          if (folder.id != chosen.id) {
            folder.songPaths.remove(path);
          }
        }
        // إضافة للمجلد المختار إن لم تكن موجودة
        if (!chosen.songPaths.contains(path)) {
          chosen.songPaths.add(path);
        }
      }
      setState(() {
        _selectedPaths.clear();
        _selectionMode = false;
      });
      _selectionBarCtrl.reverse();
      await _saveFolders();
      // تحديث قائمة الملفات لإخفاء المنقولة من قسم "جميع الأغاني"
      setState(() {});
      _showSnack('✅ تم نقل العناصر إلى "${chosen.name}"');
    }
  }

  // ─── حذف المحدد ───
  Future<void> _deleteSelected() async {
    if (_selectedPaths.isEmpty) return;
    final count = _selectedPaths.length;
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('حذف الملفات'),
        content: Text('هل تريد حذف $count ملف/ملفات؟'),
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
    for (final path in _selectedPaths) {
      try {
        await File(path).delete();
        ThumbnailManager.clearCache(path);
        // إزالته من جميع المجلدات
        for (final folder in _folders) {
          folder.songPaths.remove(path);
        }
      } catch (_) {}
    }
    await _saveFolders();
    setState(() {
      _selectedPaths.clear();
      _selectionMode = false;
    });
    _selectionBarCtrl.reverse();
    _loadFiles();
  }

  // ─── تبديل وضع التحديد ───
  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedPaths.clear();
    });
    if (_selectionMode) {
      _selectionBarCtrl.forward();
    } else {
      _selectionBarCtrl.reverse();
    }
  }

  Future<void> _deleteItem(LocalMediaItem item) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('حذف الملف'),
        content: Text(
            'هل تريد حذف "${item.title.replaceAll(RegExp(r'\.\w+$'), '')}"؟'),
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
      await File(item.path).delete();
      ThumbnailManager.clearCache(item.path);
      for (final folder in _folders) {
        folder.songPaths.remove(item.path);
      }
      await _saveFolders();
      // ── إزالة فورية من القائمة بدون إعادة تحميل ──
      if (mounted) {
        setState(() {
          _localItems.removeWhere((i) => i.path == item.path);
        });
      }
    } catch (_) {}
  }

  Future<void> _saveToGallery(LocalMediaItem item) async {
    // ── التحقق من وجود الملف أولاً ──
    final sourceFile = File(item.path);
    if (!await sourceFile.exists()) {
      _showSnack('الملف غير موجود!');
      return;
    }

    if (Platform.isAndroid) {
      await _saveToGalleryAndroid(item, sourceFile);
    } else {
      await _saveToGalleryIOS(item, sourceFile);
    }
  }

  /// حفظ الملف على Android مع التعامل الصحيح مع إصدارات API المختلفة
  Future<void> _saveToGalleryAndroid(LocalMediaItem item, File sourceFile) async {
    final androidInfo = await _getAndroidSdkVersion();

    PermissionStatus status;

    if (androidInfo >= 30) {
      // Android 11+ (API 30+): نطلب MANAGE_EXTERNAL_STORAGE لكتابة Movies/Music
      status = await Permission.manageExternalStorage.request();
    } else if (androidInfo >= 29) {
      // Android 10 (API 29): يعمل بدون صلاحية عبر MediaStore (scoped storage)
      // لكن الكتابة المباشرة تحتاج WRITE_EXTERNAL_STORAGE — نطلبها
      status = await Permission.storage.request();
    } else {
      // Android 9 وأقل: WRITE_EXTERNAL_STORAGE كافية
      status = await Permission.storage.request();
    }

    if (!mounted) return;

    if (status.isPermanentlyDenied) {
      await showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('صلاحية مطلوبة'),
          content: const Text(
              'تم رفض الإذن نهائياً. افتح الإعدادات لتفعيل الوصول إلى التخزين.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('الإعدادات'),
            ),
          ],
        ),
      );
      return;
    }

    if (!status.isGranted) {
      _showSnack('لم يتم منح الإذن. حاول مجدداً.');
      return;
    }

    try {
      final destDir = item.isVideo
          ? Directory('/storage/emulated/0/Movies/دندن')
          : Directory('/storage/emulated/0/Music/دندن');

      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      final destPath = '${destDir.path}/${item.title}';
      await sourceFile.copy(destPath);
      await _scanFile(destPath);

      if (!mounted) return;
      _showSnack(item.isVideo
          ? '✅ تم الحفظ في الاستوديو — الفيديوهات'
          : '✅ تم الحفظ في الاستوديو — الموسيقى');
    } catch (e) {
      if (!mounted) return;
      _showSnack('خطأ في الحفظ: $e');
    }
  }

  /// حفظ الملف على iOS مع طلب صلاحية المكتبة بشكل صحيح
Future<void> _saveToGalleryIOS(LocalMediaItem item, File sourceFile) async {
  // طلب الإذن مع التعامل الصحيح مع كل الحالات
  final permissionState = await PhotoManager.requestPermissionExtend();

  if (!mounted) return;

  // مقبول كلياً أو جزئياً — كلاهما يسمح بالإضافة
  if (permissionState == PermissionState.authorized ||
      permissionState == PermissionState.limited) {
    try {
      AssetEntity? result;

      if (item.isVideo) {
        result = await PhotoManager.editor.saveVideo(
          sourceFile,
          title: item.title.replaceAll(RegExp(r'\.\w+$'), ''),
        );
} else {
  // الصوت: انسخه لمجلد Documents وأبلغ المستخدم
  final docsDir = await getApplicationDocumentsDirectory();
  final destPath = '${docsDir.path}/${item.title}';
  await sourceFile.copy(destPath);
  if (!mounted) return;
  _showSnack('✅ تم الحفظ في ملفات التطبيق');
  return;
}

      if (!mounted) return;

      if (result != null) {
        _showSnack(item.isVideo
            ? '✅ تم الحفظ في مكتبة الصور'
            : '✅ تم الحفظ في الملفات');
      } else {
        _showSnack('فشل الحفظ، حاول مجدداً');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('خطأ في الحفظ: $e');
    }
    return;
  }

  // مرفوض نهائياً — اذهب للإعدادات
  await showCupertinoDialog(
    context: context,
    builder: (_) => CupertinoAlertDialog(
      title: const Text('صلاحية مطلوبة'),
      content: const Text(
          'يحتاج دندن إذن "مكتبة الصور" للحفظ. افتح الإعدادات وفعّل الوصول.'),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            Navigator.pop(context);
            PhotoManager.openSetting();
          },
          child: const Text('الإعدادات'),
        ),
      ],
    ),
  );
}
  /// قراءة إصدار Android SDK
  Future<int> _getAndroidSdkVersion() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(result.stdout.toString().trim()) ?? 30;
    } catch (_) {
      return 30; // افتراضي: Android 11
    }
  }

  Future<void> _scanFile(String path) async {
    try {
      final OnAudioQuery audioQuery = OnAudioQuery();
      await audioQuery.scanMedia(path);
    } catch (_) {
      try {
        await Process.run('am', [
          'broadcast',
          '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
          '-d', 'file://$path',
        ]);
      } catch (_) {}
    }
  }

  OverlayEntry? _toastOverlay;

  void _showGlassToast(
    String message, {
    _ToastType type = _ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    _toastOverlay?.remove();
    _toastOverlay = null;

    final entry = OverlayEntry(
      builder: (ctx) => _GlassToast(message: message, type: type),
    );
    _toastOverlay = entry;
    Overlay.of(context).insert(entry);

    Future.delayed(duration, () {
      if (_toastOverlay == entry) {
        _toastOverlay?.remove();
        _toastOverlay = null;
      }
    });
  }

  void _showSnack(String message) {
    _ToastType type = _ToastType.info;
    String cleaned = message
        .replaceAll('✅', '')
        .replaceAll('🗑️', '')
        .replaceAll('❌', '')
        .trim();

    if (message.contains('✅') || message.contains('تم')) {
      type = _ToastType.success;
    } else if (message.contains('خطأ') || message.contains('فشل')) {
      type = _ToastType.error;
    } else if (message.contains('لم يتم') || message.contains('غير موجود')) {
      type = _ToastType.warning;
    } else if (message.contains('حذف') || message.contains('🗑️')) {
      type = _ToastType.delete;
    } else if (message.contains('نقل') || message.contains('إضافة') || message.contains('مجلد')) {
      type = _ToastType.move;
    }

    _showGlassToast(cleaned, type: type);
  }

  void _playAll(int startIndex) {
    final unfoldered = _unfolderiedItems;
audioService.playList(unfoldered, startIndex.clamp(0, unfoldered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildHeader(),
              if (_folders.isNotEmpty) _buildFoldersSection(),
              _buildSongsSectionHeader(),
              _buildFileList(),
              const SliverToBoxAdapter(child: SizedBox(height: 200)),
            ],
          ),
          // ── شريط الإجراءات عند التحديد ──
          _buildSelectionActionBar(),
        ],
      ),
    );
  }

  // ── شريط الإجراءات العائم عند التحديد (زجاجي مدمج) ──
  Widget _buildSelectionActionBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // ارتفاع الـ navbar الثابت
    const navbarHeight = 65.0;
    // المشغل الصغير: 72 عندما يكون نشطاً، 0 عندما لا يوجد
    // نستخدم ValueListenableBuilder لمراقبة حالة المشغل بشكل انسيابي
    return ValueListenableBuilder<int>(
      valueListenable: audioService.currentIndex,
      builder: (context, currentIdx, _) {
        final hasMiniPlayer = currentIdx >= 0 && audioService.currentItem != null;
        const miniPlayerHeight = 72.0;
        final targetBottom = bottomInset +
            navbarHeight +
            (hasMiniPlayer ? miniPlayerHeight : 0) +
            22;

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          bottom: targetBottom,
          left: 20,
          right: 20,
          child: AnimatedBuilder(
            animation: _selectionBarAnim,
            builder: (_, __) {
              final t = _selectionBarAnim.value.clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(0, 80 * (1 - t)),
                child: Opacity(
                  opacity: t,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          // طبقة زجاجية متدرجة
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [
                                    const Color(0xFF1E1E2E).withValues(alpha: 0.82),
                                    const Color(0xFF16213E).withValues(alpha: 0.88),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: 0.78),
                                    Colors.white.withValues(alpha: 0.92),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.white.withValues(alpha: 0.70),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.50 : 0.14),
                              blurRadius: 32,
                              spreadRadius: -2,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: AppColors.primary
                                  .withValues(alpha: isDark ? 0.12 : 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // ── عداد المحدد ──
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withValues(alpha: 0.22),
                                    AppColors.primary.withValues(alpha: 0.12),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.30),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.checkmark_circle_fill,
                                    size: 13,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${_selectedPaths.length}',
                                    style: TextStyle(
                                      fontFamily: 'Tajawal',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),

                            // ── زر النقل ──
                            Expanded(
                              child: GestureDetector(
                                onTap: _selectedPaths.isNotEmpty
                                    ? _moveSelectedToFolder
                                    : null,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    gradient: _selectedPaths.isNotEmpty
                                        ? LinearGradient(
                                            colors: [
                                              AppColors.primary
                                                  .withValues(alpha: 0.20),
                                              AppColors.primary
                                                  .withValues(alpha: 0.10),
                                            ],
                                          )
                                        : null,
                                    color: _selectedPaths.isEmpty
                                        ? (isDark
                                            ? Colors.white.withValues(alpha: 0.05)
                                            : Colors.black
                                                .withValues(alpha: 0.04))
                                        : null,
                                    borderRadius: BorderRadius.circular(13),
                                    border: _selectedPaths.isNotEmpty
                                        ? Border.all(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.35),
                                            width: 0.8)
                                        : Border.all(
                                            color: isDark
                                                ? Colors.white
                                                    .withValues(alpha: 0.07)
                                                : Colors.black
                                                    .withValues(alpha: 0.07),
                                            width: 0.6),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.folder_fill,
                                        size: 15,
                                        color: _selectedPaths.isNotEmpty
                                            ? AppColors.primary
                                            : context.appTextSec,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'نقل',
                                        style: TextStyle(
                                          fontFamily: 'Tajawal',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: _selectedPaths.isNotEmpty
                                              ? AppColors.primary
                                              : context.appTextSec,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // ── زر الحذف ──
                            Expanded(
                              child: GestureDetector(
                                onTap: _selectedPaths.isNotEmpty
                                    ? _deleteSelected
                                    : null,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    gradient: _selectedPaths.isNotEmpty
                                        ? const LinearGradient(
                                            colors: [
                                              Color(0x33EF5350),
                                              Color(0x1AEF5350),
                                            ],
                                          )
                                        : null,
                                    color: _selectedPaths.isEmpty
                                        ? (isDark
                                            ? Colors.white.withValues(alpha: 0.05)
                                            : Colors.black
                                                .withValues(alpha: 0.04))
                                        : null,
                                    borderRadius: BorderRadius.circular(13),
                                    border: _selectedPaths.isNotEmpty
                                        ? Border.all(
                                            color: const Color(0xFFEF5350)
                                                .withValues(alpha: 0.35),
                                            width: 0.8)
                                        : Border.all(
                                            color: isDark
                                                ? Colors.white
                                                    .withValues(alpha: 0.07)
                                                : Colors.black
                                                    .withValues(alpha: 0.07),
                                            width: 0.6),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.trash_fill,
                                        size: 15,
                                        color: _selectedPaths.isNotEmpty
                                            ? const Color(0xFFEF5350)
                                            : context.appTextSec,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'حذف',
                                        style: TextStyle(
                                          fontFamily: 'Tajawal',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: _selectedPaths.isNotEmpty
                                              ? const Color(0xFFEF5350)
                                              : context.appTextSec,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // ── زر إلغاء ──
                            GestureDetector(
                              onTap: _toggleSelectionMode,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 9),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.10)
                                        : Colors.black.withValues(alpha: 0.08),
                                    width: 0.6,
                                  ),
                                ),
                                child: Icon(
                                  CupertinoIcons.xmark,
                                  size: 15,
                                  color: isDark
                                      ? AppColors.darkTextSec
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SliverToBoxAdapter(
      child: Column(
        children: [
          // ── شريط العنوان ──
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20,
              right: 20,
              bottom: 8,
            ),
            child: Row(
              children: [
                // Logo
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(CupertinoIcons.music_note,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'دندن',
                  style: TextStyle(
                    fontSize: 28,
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    color: context.appText,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),

                // ── زر البحث ──
                if (_localItems.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() => _searchActive = !_searchActive);
                      if (_searchActive) {
                        Future.delayed(const Duration(milliseconds: 200), () {
                          _searchFocus.requestFocus();
                        });
                      } else {
                        _searchFocus.unfocus();
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _searchActive
                            ? AppColors.primary
                            : context.appSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _searchActive
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.darkDivider
                                  : AppColors.divider),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _searchActive
                                ? CupertinoIcons.xmark
                                : CupertinoIcons.search,
                            color: _searchActive
                                ? Colors.white
                                : context.appTextSec,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _searchActive ? 'إغلاق' : 'بحث',
                            style: TextStyle(
                              color: _searchActive
                                  ? Colors.white
                                  : context.appTextSec,
                              fontSize: 12,
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(width: 8),

                // ── زر إنشاء مجلد (بديل زر الملفات القديم) ──
                GestureDetector(
                  onTap: _createFolder,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.appSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(CupertinoIcons.folder_badge_plus,
                        size: 18, color: context.appTextSec),
                  ),
                ),

                const SizedBox(width: 8),

                // ── زر التحديد ──
                GestureDetector(
                  onTap: _toggleSelectionMode,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _selectionMode
                          ? AppColors.primary
                          : context.appSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _selectionMode
                          ? CupertinoIcons.xmark
                          : CupertinoIcons.checkmark_circle,
                      size: 18,
                      color:
                          _selectionMode ? Colors.white : context.appTextSec,
                    ),
                  ),
                ),

                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _loadFiles,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.appSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(CupertinoIcons.refresh,
                        size: 18, color: context.appTextSec),
                  ),
                ),
              ],
            ),
          ),

          // ── شريط البحث المنسدل ──
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: _searchActive
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Icon(
                            CupertinoIcons.search,
                            color: AppColors.primary.withValues(alpha: 0.7),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              textDirection: TextDirection.rtl,
                              onChanged: (val) =>
                                  setState(() => _searchQuery = val),
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 15,
                                color: context.appText,
                              ),
                              decoration: InputDecoration(
                                hintText: 'ابحث في مكتبتك…',
                                hintStyle: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontSize: 14,
                                  color: context.appTextSec
                                      .withValues(alpha: 0.6),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14),
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                                _searchFocus.requestFocus();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkSurfaceAlt
                                        : AppColors.surfaceAlt,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    CupertinoIcons.xmark,
                                    size: 11,
                                    color: context.appTextSec,
                                  ),
                                ),
                              
                              ),
                            )
                          else
                            const SizedBox(width: 14),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // ── عداد النتائج عند البحث ──
          if (_searchActive && _searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_filteredItems.length} نتيجة',
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── قسم المجلدات ───
  Widget _buildFoldersSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── عنوان القسم مع فاصل جميل ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.4)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'المجلدات',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.appText,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_folders.length}',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── شبكة المجلدات ──
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.55,
            ),
            itemCount: _folders.length,
            itemBuilder: (_, i) => _buildFolderCard(_folders[i]),
          ),

          // ── فاصل بصري بين المجلدات والأغاني ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          isDark
                              ? AppColors.darkDivider
                              : AppColors.divider,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceAlt
                          : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkDivider
                            : AppColors.divider,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.music_note_2,
                            size: 12,
                            color: isDark
                                ? AppColors.darkTextSec
                                : AppColors.textSecondary),
                        const SizedBox(width: 5),
                        Text(
                          'استماعي',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextSec
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          isDark
                              ? AppColors.darkDivider
                              : AppColors.divider,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderCard(MusicFolder folder) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = folder.songPaths
        .where((p) => _localItems.any((i) => i.path == p))
        .length;

    return GestureDetector(
      onTap: () => _openFolder(folder),
      onLongPress: () => _changeFolderColor(folder),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.95, end: 1.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutBack,
        builder: (_, val, child) =>
            Transform.scale(scale: val, child: child),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                folder.color,
                folder.color.withValues(alpha: 0.75),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: folder.color.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // ── خلفية زخرفية ──
              Positioned(
                right: -12,
                top: -12,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                left: -8,
                bottom: -8,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // ── المحتوى ──
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            CupertinoIcons.folder_fill,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          CupertinoIcons.ellipsis,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 16,
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$count ${count == 1 ? 'ملف' : 'ملفات'}',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFolder(MusicFolder folder) {
    final items = _localItems
        .where((i) => folder.songPaths.contains(i.path))
        .toList();
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => FolderDetailPage(
          folder: folder,
          items: items,
          allItems: _localItems,
          onUpdate: () {
            _loadFiles();
            _saveFolders();
          },
        ),
      ),
    );
  }

  // ── عنوان قسم الأغاني ──
  Widget _buildSongsSectionHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_localItems.isEmpty) return const SliverToBoxAdapter(child: SizedBox());

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.4)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _folders.isEmpty ? 'مكتبتك' : 'جميع الأغاني',
              style: TextStyle(
                fontFamily: 'Tajawal',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.appText,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_localItems.length}',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            const Spacer(),

if (!_selectionMode) ...[
              // ── زر الريلز ──
              GestureDetector(
                onTap: () {
                  final newVal = !_reelsMode;
                  setState(() => _reelsMode = newVal);
                  ReelsModeNotifier.instance.set(newVal);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: _reelsMode
                        ? const LinearGradient(
                            colors: [Color(0xFFE040FB), Color(0xFFFF4081)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: _reelsMode
                        ? null
                        : (isDark ? AppColors.darkSurface : AppColors.surface),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _reelsMode
                          ? Colors.transparent
                          : (isDark ? AppColors.darkDivider : AppColors.divider),
                      width: 0.8,
                    ),
                    boxShadow: _reelsMode
                        ? [
                            BoxShadow(
                              color: const Color(0xFFE040FB).withValues(alpha: 0.40),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.play_rectangle_fill,
                        size: 14,
                        color: _reelsMode ? Colors.white : context.appTextSec,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ريلز',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _reelsMode ? Colors.white : context.appTextSec,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // ── زر طريقة العرض ──
              GestureDetector(
                onTap: () {
  final newVal = !_gridView;
  setState(() => _gridView = newVal);
  _saveViewMode(newVal);
},
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: _gridView
                        ? LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withValues(alpha: 0.75),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: _gridView
                        ? null
                        : (isDark
                            ? AppColors.darkSurface
                            : AppColors.surface),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _gridView
                          ? Colors.transparent
                          : (isDark
                              ? AppColors.darkDivider
                              : AppColors.divider),
                      width: 0.8,
                    ),
                    boxShadow: _gridView
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: child,
                    ),
                    child: Icon(
                      _gridView
                          ? CupertinoIcons.square_grid_2x2_fill
                          : CupertinoIcons.square_grid_2x2,
                      key: ValueKey(_gridView),
                      size: 17,
                      color: _gridView
    ? (isDark ? Colors.white : const Color(0xFF83494F))
    : context.appTextSec,
                    ),
                  ),
                ),
              ),
            ], // نهاية !_selectionMode
            if (_selectionMode) ...[
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_selectedPaths.length == _filteredItems.length) {
                      _selectedPaths.clear();
                    } else {
                      _selectedPaths
                          .addAll(_filteredItems.map((i) => i.path));
                    }
                  });
                },
                child: Text(
                  _selectedPaths.length == _filteredItems.length
                      ? 'إلغاء الكل'
                      : 'تحديد الكل',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileList() {
    if (_localItems.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: context.appRedLight,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(CupertinoIcons.music_note_2,
                    size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              Text(
                'لا توجد ملفات بعد',
                style: TextStyle(
                    fontSize: 18,
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w600,
                    color: context.appText),
              ),
              const SizedBox(height: 8),
              Text(
                'حمّل مقاطع من تبويب تصفح',
                style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Tajawal',
                    color: context.appTextSec),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                      builder: (_) => const FileBrowserPage()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.appSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: context.appDivider, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.plus_circle_fill,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'استيراد من الجهاز',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.appText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── إظهار الأغاني غير المنقولة لأي مجلد فقط ──
    final allFoldered = _folders.expand((f) => f.songPaths).toSet();
    final unfoldered = _filteredItems.where((i) => !allFoldered.contains(i.path)).toList();
    final displayed = unfoldered;

    if (displayed.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(CupertinoIcons.search,
                    size: 34,
                    color: AppColors.primary.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 16),
              Text(
                'لا توجد نتائج',
                style: TextStyle(
                    fontSize: 17,
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w600,
                    color: context.appText),
              ),
              const SizedBox(height: 6),
              Text(
                'جرّب كلمة بحث مختلفة',
                style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Tajawal',
                    color: context.appTextSec),
              ),
            ],
          ),
        ),
      );
    }

    if (_gridView && !_selectionMode) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = displayed[index];

              return _ModernMusicCard(
                item: item,
                folders: _folders,
                onTap: () {
                  // ✦ وضع الريلز — يفتح مشغل الريلز للفيديوهات فقط
                  if (ReelsModeNotifier.instance.value && item.isVideo) {
                    final videoItems =
                        _localItems.where((e) => e.isVideo).toList();
                    final videoIndex = videoItems.indexOf(item);
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => ReelsVideoPlayer(
                          items: videoItems,
                          initialIndex: videoIndex < 0 ? 0 : videoIndex,
                          folders: _folders,
                          onFoldersChanged: _saveFolders,
                        ),
                        transitionsBuilder: (_, anim, __, child) {
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 1),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                  parent: anim, curve: Curves.easeOutCubic)),
                              child: child,
                            ),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 450),
                      ),
                    );
                    return;
                  }

                  // المشغل الأصلي (صوت أو وضع الريلز معطّل)
                  final playQueue = _unfolderiedItems;
audioService.playList(
  List<LocalMediaItem>.unmodifiable(playQueue),
  playQueue.indexOf(item),
);
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const FullScreenPlayer(),
                      transitionsBuilder: (_, animation, __, child) {
                        return SlideTransition(
                          position: Tween<Offset>(
                                  begin: const Offset(0, 1), end: Offset.zero)
                              .animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic)),
                          child: child,
                        );
                      },
                    ),
                  );
                },
                onDelete: () => _deleteItem(item),
                onSave: () => _saveToGallery(item),
                onMove: (folder) async {
                  if (!folder.songPaths.contains(item.path)) {
                    folder.songPaths.add(item.path);
                    await _saveFolders();
                    setState(() {});
                    if (mounted) {
                      _showGlassToast(
                        'تمت الإضافة إلى ${folder.name}',
                        type: _ToastType.move,
                      );
                    }
                  }
                },
              );
            },
            childCount: displayed.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.70,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = displayed[index];
            final isSelected = _selectedPaths.contains(item.path);

            if (_selectionMode) {
              return _SelectableMediaTile(
                key: ValueKey('sel_${item.path}'),
                item: item,
                isSelected: isSelected,
                onToggle: () {
                  setState(() {
                    if (isSelected) {
                      _selectedPaths.remove(item.path);
                    } else {
                      _selectedPaths.add(item.path);
                    }
                  });
                },
              );
            }

final unfoldered = _unfolderiedItems;
            return _SwipeableMediaTile(
              key: ValueKey(item.path),
              item: item,
              index: unfoldered.indexOf(item),
              allItems: unfoldered,
              onDelete: () => _deleteItem(item),
              onSave: () => _saveToGallery(item),
            );
          },
          childCount: displayed.length,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SELECTABLE TILE — وضع التحديد
// ═══════════════════════════════════════════════════════════
class _SelectableMediaTile extends StatefulWidget {
  final LocalMediaItem item;
  final bool isSelected;
  final VoidCallback onToggle;

  const _SelectableMediaTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  State<_SelectableMediaTile> createState() => _SelectableMediaTileState();
}

class _SelectableMediaTileState extends State<_SelectableMediaTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _checkCtrl;
  late Animation<double> _checkAnim;
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _checkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _checkAnim =
        CurvedAnimation(parent: _checkCtrl, curve: Curves.easeOutBack);
    if (widget.isSelected) _checkCtrl.value = 1.0;
    _loadThumb();
  }

  @override
  void didUpdateWidget(_SelectableMediaTile old) {
    super.didUpdateWidget(old);
    if (widget.isSelected != old.isSelected) {
      widget.isSelected ? _checkCtrl.forward() : _checkCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _checkCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadThumb() async {
    final path = await ThumbnailManager.getLocalThumbnail(widget.item.path);
    if (path != null && mounted) setState(() => _thumbPath = path);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: widget.onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.08)
              : (isDark ? AppColors.darkSurface : AppColors.surface),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isSelected
                ? AppColors.primary.withValues(alpha: 0.55)
                : (isDark ? AppColors.darkDivider : AppColors.divider),
            width: widget.isSelected ? 1.4 : 0.6,
          ),
        ),
        child: Row(
          children: [
            // ── الصورة المصغرة ──
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _thumbPath != null
                  ? Image.file(File(_thumbPath!),
                      width: 48, height: 48, fit: BoxFit.cover)
                  : Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: widget.item.isVideo
                              ? [
                                  const Color(0xFF1A1A2E),
                                  const Color(0xFF16213E)
                                ]
                              : [AppColors.redLight, const Color(0xFFFFD6D6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        widget.item.isVideo
                            ? CupertinoIcons.play_rectangle_fill
                            : CupertinoIcons.music_note,
                        color: widget.item.isVideo
                            ? Colors.white70
                            : AppColors.primary,
                        size: 22,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.title.replaceAll(RegExp(r'\.\w+$'), ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: widget.isSelected
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkText
                              : AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.item.isVideo ? 'فيديو' : 'صوت',
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
            ),
            // ── مربع التحديد ──
            ScaleTransition(
              scale: _checkAnim,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: widget.isSelected ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.isSelected
                        ? AppColors.primary
                        : (isDark
                            ? AppColors.darkDivider
                            : AppColors.divider),
                    width: 2,
                  ),
                  boxShadow: widget.isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: widget.isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 15)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  FOLDER DETAIL PAGE — صفحة تفاصيل المجلد
// ═══════════════════════════════════════════════════════════
class FolderDetailPage extends StatefulWidget {
  final MusicFolder folder;
  final List<LocalMediaItem> items;
  final List<LocalMediaItem> allItems;
  final VoidCallback onUpdate;

  const FolderDetailPage({
    super.key,
    required this.folder,
    required this.items,
    required this.allItems,
    required this.onUpdate,
  });

  @override
  State<FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage>
    with TickerProviderStateMixin {
  late List<LocalMediaItem> _items;

  // ── وضع العرض (قائمة / مكتبي) ──
bool _gridView = false;
  bool _reelsMode = false; // وضع الريلز

  // ── وضع التحديد ──
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};
  late AnimationController _selectionBarCtrl;
  late Animation<double> _selectionBarAnim;

  @override
void initState() {
    super.initState();
    _items = List.from(widget.items);
    audioService.currentIndex.addListener(_onIndexChange);
    _selectionBarCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _selectionBarAnim = CurvedAnimation(
        parent: _selectionBarCtrl, curve: Curves.easeOutBack);
    _loadViewMode();
  }

  void _onIndexChange() {
    if (mounted) setState(() {});
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedPaths.clear();
    });
    if (_selectionMode) {
      _selectionBarCtrl.forward();
    } else {
      _selectionBarCtrl.reverse();
    }
  }

  Future<void> _deleteSelected() async {
    
    if (_selectedPaths.isEmpty) return;
    final count = _selectedPaths.length;
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('حذف الملفات'),
        content: Text('هل تريد حذف $count ملف/ملفات؟'),
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
    for (final path in _selectedPaths) {
      try {
        await File(path).delete();
        ThumbnailManager.clearCache(path);
        widget.folder.songPaths.remove(path);
      } catch (_) {}
    }
    setState(() {
      _items = _items.where((i) => !_selectedPaths.contains(i.path)).toList();
      _selectedPaths.clear();
      _selectionMode = false;
    });
    _selectionBarCtrl.reverse();
    widget.onUpdate();
  }
Future<void> _loadViewMode() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('listen_grid_view') ?? false;
  final reels = prefs.getBool('reelsMode') ?? false;
  if (mounted) setState(() {
    _gridView = saved;
    _reelsMode = reels;
  });
}

Future<void> _saveViewMode(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('listen_grid_view', value);
}
  @override
  void dispose() {
    audioService.currentIndex.removeListener(_onIndexChange);
    _selectionBarCtrl.dispose();
    super.dispose();
  }

  void _removeFromFolder(LocalMediaItem item) {
    setState(() {
      widget.folder.songPaths.remove(item.path);
      _items = _items.where((i) => i.path != item.path).toList();
    });
    widget.onUpdate();
  }

  Future<void> _deleteItem(LocalMediaItem item) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('حذف الملف'),
        content: Text(
            'هل تريد حذف "${item.title.replaceAll(RegExp(r'\.\w+$'), '')}"؟'),
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
      await File(item.path).delete();
      ThumbnailManager.clearCache(item.path);
      widget.folder.songPaths.remove(item.path);
      setState(() {
        _items = _items.where((i) => i.path != item.path).toList();
      });
    } catch (_) {}
    widget.onUpdate();
  }

  Future<void> _saveToGallery(LocalMediaItem item) async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      status = item.isVideo
          ? await Permission.videos.request()
          : await Permission.audio.request();
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
    } else {
      status = await Permission.photosAddOnly.request();
    }

    if (!mounted) return;
    if (!status.isGranted) {
      _showSnack('لم يتم منح الإذن. حاول مجدداً.');
      return;
    }

    final sourceFile = File(item.path);
    if (!await sourceFile.exists()) {
      _showSnack('الملف غير موجود!');
      return;
    }

    try {
      if (Platform.isAndroid) {
        final destDir = item.isVideo
            ? Directory('/storage/emulated/0/Movies/دندن')
            : Directory('/storage/emulated/0/Music/دندن');
        if (!await destDir.exists()) await destDir.create(recursive: true);
        final destPath = '${destDir.path}/${item.title}';
        await sourceFile.copy(destPath);
        _showSnack(item.isVideo
            ? '✅ تم الحفظ في الاستوديو — الفيديوهات'
            : '✅ تم الحفظ في الاستوديو — الموسيقى');
      } else {
        _showSnack('✅ تم الحفظ');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('خطأ: $e');
    }
  }

  OverlayEntry? _toastOverlay;

  void _showGlassToast(
    String message, {
    _ToastType type = _ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    _toastOverlay?.remove();
    _toastOverlay = null;
    final entry = OverlayEntry(
      builder: (ctx) => _GlassToast(message: message, type: type),
    );
    _toastOverlay = entry;
    Overlay.of(context).insert(entry);
    Future.delayed(duration, () {
      if (_toastOverlay == entry) {
        _toastOverlay?.remove();
        _toastOverlay = null;
      }
    });
  }

  void _showSnack(String message) {
    _ToastType type = _ToastType.info;
    String cleaned = message
        .replaceAll('✅', '')
        .replaceAll('🗑️', '')
        .replaceAll('❌', '')
        .trim();
    if (message.contains('✅') || message.contains('تم')) {
      type = _ToastType.success;
    } else if (message.contains('خطأ') || message.contains('فشل')) {
      type = _ToastType.error;
    } else if (message.contains('لم يتم') || message.contains('غير موجود')) {
      type = _ToastType.warning;
    } else if (message.contains('حذف') || message.contains('🗑️')) {
      type = _ToastType.delete;
    } else if (message.contains('نقل') || message.contains('إضافة') || message.contains('مجلد')) {
      type = _ToastType.move;
    }
    _showGlassToast(cleaned, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: context.appBg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 12,
                    bottom: 24,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.folder.color,
                        widget.folder.color.withValues(alpha: 0.6),
                        context.appBg,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.6, 1],
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(CupertinoIcons.chevron_back,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                            const Spacer(),
// ── زر الريلز ──
                            GestureDetector(
                              onTap: () {
                                final newVal = !_reelsMode;
                                setState(() => _reelsMode = newVal);
                                ReelsModeNotifier.instance.set(newVal);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  gradient: _reelsMode
                                      ? const LinearGradient(
                                          colors: [Color(0xFFE040FB), Color(0xFFFF4081)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: _reelsMode
                                      ? null
                                      : Colors.white.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _reelsMode
                                        ? Colors.transparent
                                        : Colors.white.withOpacity(0.25),
                                    width: 1,
                                  ),
                                  boxShadow: _reelsMode
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFFE040FB)
                                                .withValues(alpha: 0.45),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          )
                                        ]
                                      : null,
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(scale: anim, child: child),
                                  child: Icon(
                                    CupertinoIcons.play_rectangle_fill,
                                    key: ValueKey(_reelsMode),
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // ── زر تبديل العرض ──
                            GestureDetector(
                              onTap: () {
  final newVal = !_gridView;
  setState(() => _gridView = newVal);
  _saveViewMode(newVal);
},
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  gradient: _gridView
                                      ? LinearGradient(
                                          colors: [
                                            Colors.white.withOpacity(0.35),
                                            Colors.white.withOpacity(0.20),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: _gridView
                                      ? null
                                      : Colors.white.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.25),
                                    width: 1,
                                  ),
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(scale: anim, child: child),
                                  child: Icon(
                                    _gridView
                                        ? CupertinoIcons.square_grid_2x2_fill
                                        : CupertinoIcons.list_bullet,
                                    key: ValueKey(_gridView),
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // ── زر التحديد ──
                            GestureDetector(
                              onTap: _toggleSelectionMode,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  gradient: _selectionMode
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFFFFFFFF),
                                            Color(0xCCFFFFFF),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: _selectionMode
                                      ? null
                                      : Colors.white.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  _selectionMode
                                      ? CupertinoIcons.xmark
                                      : CupertinoIcons.checkmark_circle,
                                  color: _selectionMode
                                      ? widget.folder.color
                                      : Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(CupertinoIcons.folder_fill,
                            color: Colors.white, size: 34),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.folder.name,
                        style: const TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_items.length} أغنية',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── شريط إجراءات التحديد ──
              if (_selectionMode)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: AnimatedBuilder(
                      animation: _selectionBarAnim,
                      builder: (_, __) {
                        final t = _selectionBarAnim.value.clamp(0.0, 1.0);
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - t)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: widget.folder.color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: widget.folder.color.withOpacity(0.25),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: widget.folder.color.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          CupertinoIcons.checkmark_circle_fill,
                                          size: 13,
                                          color: widget.folder.color,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          '${_selectedPaths.length}',
                                          style: TextStyle(
                                            fontFamily: 'Tajawal',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: widget.folder.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (_selectedPaths.length == _items.length) {
                                          _selectedPaths.clear();
                                        } else {
                                          _selectedPaths.addAll(_items.map((i) => i.path));
                                        }
                                      });
                                    },
                                    child: Text(
                                      _selectedPaths.length == _items.length
                                          ? 'إلغاء الكل'
                                          : 'تحديد الكل',
                                      style: TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: widget.folder.color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: _selectedPaths.isNotEmpty
                                        ? _deleteSelected
                                        : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        gradient: _selectedPaths.isNotEmpty
                                            ? const LinearGradient(
                                                colors: [
                                                  Color(0xFFFF3B30),
                                                  Color(0xFFFF6B6B),
                                                ],
                                              )
                                            : null,
                                        color: _selectedPaths.isEmpty
                                            ? Colors.grey.withOpacity(0.2)
                                            : null,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: _selectedPaths.isNotEmpty
                                            ? [
                                                BoxShadow(
                                                  color: const Color(0xFFFF3B30)
                                                      .withOpacity(0.35),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                )
                                              ]
                                            : null,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            CupertinoIcons.trash_fill,
                                            size: 13,
                                            color: _selectedPaths.isNotEmpty
                                                ? Colors.white
                                                : Colors.grey,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'حذف',
                                            style: TextStyle(
                                              fontFamily: 'Tajawal',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: _selectedPaths.isNotEmpty
                                                  ? Colors.white
                                                  : Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (_items.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.music_note,
                            size: 48,
                            color: widget.folder.color.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'المجلد فارغ',
                          style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 16,
                            color: context.appTextSec,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_gridView && !_selectionMode)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final item = _items[i];
                        return _FolderGridCard(
                          key: ValueKey(item.path),
                          item: item,
                          folderColor: widget.folder.color,
                          allItems: _items,
                          onTap: () {
                            audioService.playList(
                              List<LocalMediaItem>.unmodifiable(_items),
                              i,
                            );
                          },
                          onDelete: () => _deleteItem(item),
                          onSave: () => _saveToGallery(item),
                          onRemoveFromFolder: () => _removeFromFolder(item),
                        );
                      },
                      childCount: _items.length,
                    ),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.72,
                    ),
                  ),
                )
              else if (_selectionMode)
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final item = _items[i];
                        final isSelected = _selectedPaths.contains(item.path);
                        return _SelectableMediaTile(
                          key: ValueKey('sel_${item.path}'),
                          item: item,
                          isSelected: isSelected,
                          onToggle: () {
                            setState(() {
                              if (isSelected) {
                                _selectedPaths.remove(item.path);
                              } else {
                                _selectedPaths.add(item.path);
                              }
                            });
                          },
                        );
                      },
                      childCount: _items.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final item = _items[i];
                        return _FolderItemTile(
                          key: ValueKey(item.path),
                          item: item,
                          index: i,
                          allItems: _items,
                          folderColor: widget.folder.color,
                          onRemoveFromFolder: () => _removeFromFolder(item),
                          onDelete: () => _deleteItem(item),
                          onSave: () => _saveToGallery(item),
                        );
                      },
                      childCount: _items.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 200)),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  FOLDER ITEM TILE — كارت الأغنية داخل المجلد
// ═══════════════════════════════════════════════════════════
class _FolderItemTile extends StatefulWidget {
  final LocalMediaItem item;
  final int index;
  final List<LocalMediaItem> allItems;
  final Color folderColor;
  final VoidCallback onRemoveFromFolder;
  final VoidCallback onDelete;
  final VoidCallback onSave;

  const _FolderItemTile({
    super.key,
    required this.item,
    required this.index,
    required this.allItems,
    required this.folderColor,
    required this.onRemoveFromFolder,
    required this.onDelete,
    required this.onSave,
  });

  @override
  State<_FolderItemTile> createState() => _FolderItemTileState();
}

class _FolderItemTileState extends State<_FolderItemTile>
    with TickerProviderStateMixin {
  late AnimationController _swipeCtrl;
  late AnimationController _savePressCtrl;
  late AnimationController _deletePressCtrl;
  late AnimationController _removePressCtrl;
  late AnimationController _springCtrl;
  late Animation<double> _saveScaleAnim;
  late Animation<double> _deleteScaleAnim;
  late Animation<double> _removeScaleAnim;
  late Animation<double> _springAnim;

  double _dragOffset = 0;
  bool _revealed = false;
  String? _thumbPath;

  static const double _revealWidth = 230.0;

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));

    _savePressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _saveScaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
        CurvedAnimation(parent: _savePressCtrl, curve: Curves.easeInOut));

    _deletePressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _deleteScaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
        CurvedAnimation(parent: _deletePressCtrl, curve: Curves.easeInOut));

    _removePressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _removeScaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
        CurvedAnimation(parent: _removePressCtrl, curve: Curves.easeInOut));

    _springCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _springAnim = Tween<double>(begin: 0.0, end: 0.0).animate(
        CurvedAnimation(parent: _springCtrl, curve: Curves.elasticOut));

    _loadThumb();
    audioService.currentIndex.addListener(_onIndexChange);
  }

  void _onIndexChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    audioService.currentIndex.removeListener(_onIndexChange);
    _swipeCtrl.dispose();
    _savePressCtrl.dispose();
    _deletePressCtrl.dispose();
    _removePressCtrl.dispose();
    _springCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadThumb() async {
    final path = await ThumbnailManager.getLocalThumbnail(widget.item.path);
    if (path != null && mounted) {
      setState(() => _thumbPath = path);
    }
  }

  void _onHorizontalDrag(DragUpdateDetails details) {
    setState(() {
      _dragOffset =
          (_dragOffset - details.delta.dx).clamp(0.0, _revealWidth * 1.1);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > _revealWidth * 0.40 || velocity < -400) {
      _animateToReveal();
    } else {
      _animateToClose();
    }
  }

  void _animateToReveal() {
    final start = _dragOffset;
    _springAnim = Tween<double>(begin: start, end: _revealWidth).animate(
        CurvedAnimation(parent: _springCtrl, curve: Curves.elasticOut));
    _springCtrl.forward(from: 0).then((_) {
      if (mounted)
        setState(() {
          _dragOffset = _revealWidth;
          _revealed = true;
        });
    });
    _springCtrl.addListener(() {
      if (mounted)
        setState(() =>
            _dragOffset = _springAnim.value.clamp(0.0, _revealWidth * 1.06));
    });
  }

  void _animateToClose() {
    final start = _dragOffset;
    _springAnim = Tween<double>(begin: start, end: 0.0).animate(
        CurvedAnimation(parent: _springCtrl, curve: Curves.easeOutBack));
    _springCtrl.forward(from: 0).then((_) {
      if (mounted)
        setState(() {
          _dragOffset = 0;
          _revealed = false;
        });
    });
    _springCtrl.addListener(() {
      if (mounted)
        setState(
            () => _dragOffset = _springAnim.value.clamp(0.0, _revealWidth));
    });
  }

  void _closeSwipe() => _animateToClose();

  @override
  Widget build(BuildContext context) {
    final currentPath = audioService.currentItem?.path;
    final isActive = currentPath == widget.item.path;
    final revealFraction = (_dragOffset / _revealWidth).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ClipRect(
        child: Stack(
          children: [
            // ── أزرار الخلفية ──
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: _revealWidth,
              child: Opacity(
                opacity: revealFraction,
                child: Transform.translate(
                  offset: Offset((1 - revealFraction) * 30, 0),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        // ── زر الإرجاع (رجوع للاستماع) ──
                        Expanded(
                          child: ScaleTransition(
                            scale: _removeScaleAnim,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) => _removePressCtrl.forward(),
                              onTapUp: (_) async {
                                await _removePressCtrl.reverse();
                                _closeSwipe();
                                widget.onRemoveFromFolder();
                              },
                              onTapCancel: () => _removePressCtrl.reverse(),
                              child: Container(
                                margin: const EdgeInsets.only(
                                    right: 3, left: 3, top: 2, bottom: 2),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      widget.folderColor,
                                      widget.folderColor
                                          .withValues(alpha: 0.75)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: widget.folderColor
                                          .withValues(alpha: 0.4),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.22),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.arrow_uturn_left,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'إرجاع',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontFamily: 'Tajawal',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // ── زر الحفظ ──
                        Expanded(
                          child: ScaleTransition(
                            scale: _saveScaleAnim,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) => _savePressCtrl.forward(),
                              onTapUp: (_) async {
                                await _savePressCtrl.reverse();
                                _closeSwipe();
                                widget.onSave();
                              },
                              onTapCancel: () => _savePressCtrl.reverse(),
                              child: Container(
                                margin: const EdgeInsets.only(
                                    right: 3, left: 3, top: 2, bottom: 2),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF1565C0),
                                      Color(0xFF42A5F5)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF1976D2)
                                          .withValues(alpha: 0.45),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.22),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.arrow_down_to_line_alt,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'حفظ',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontFamily: 'Tajawal',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // ── زر الحذف ──
                        Expanded(
                          child: ScaleTransition(
                            scale: _deleteScaleAnim,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) => _deletePressCtrl.forward(),
                              onTapUp: (_) async {
                                await _deletePressCtrl.reverse();
                                _closeSwipe();
                                widget.onDelete();
                              },
                              onTapCancel: () => _deletePressCtrl.reverse(),
                              child: Container(
                                margin: const EdgeInsets.only(
                                    right: 3, left: 3, top: 2, bottom: 2),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFB71C1C),
                                      Color(0xFFEF5350)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFD32F2F)
                                          .withValues(alpha: 0.45),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.22),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.trash_fill,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'حذف',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontFamily: 'Tajawal',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── الكارت الرئيسي ──
            Transform.translate(
              offset: Offset(-_dragOffset, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: _onHorizontalDrag,
                onHorizontalDragEnd: _onDragEnd,
                onTap: () {
                  if (_revealed) {
                    _closeSwipe();
                    return;
                  }

                  // ✦ وضع الريلز — يفتح مشغل الريلز للفيديوهات فقط
                  if (ReelsModeNotifier.instance.value && widget.item.isVideo) {
                    final videoItems = widget.allItems.where((e) => e.isVideo).toList();
                    final videoIndex = videoItems.indexOf(widget.item);
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => ReelsVideoPlayer(
                          items: videoItems,
                          initialIndex: videoIndex < 0 ? 0 : videoIndex,
                          folders: const [],
                          onFoldersChanged: () async {},
                        ),
                        transitionsBuilder: (_, anim, __, child) {
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 1),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                  parent: anim, curve: Curves.easeOutCubic)),
                              child: child,
                            ),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 450),
                      ),
                    );
                    return;
                  }

                  // المشغل الأصلي (صوت أو وضع الريلز معطّل)
                  audioService.playList(
                    List<LocalMediaItem>.unmodifiable(widget.allItems),
                    widget.index,
                  );
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const FullScreenPlayer(),
                      transitionsBuilder: (_, animation, __, child) {
                        return SlideTransition(
                          position: Tween<Offset>(
                                  begin: const Offset(0, 1), end: Offset.zero)
                              .animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic)),
                          child: child,
                        );
                      },
                    ),
                  );
                },
                child: _buildTile(isActive),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(bool active) {
    const size = 52.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor = active
        ? (isDark
            ? Color.lerp(AppColors.darkSurface, AppColors.primary, 0.18)!
            : Color.lerp(Colors.white, AppColors.primary, 0.10)!)
        : (isDark ? AppColors.darkSurface : AppColors.surface);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.primary.withValues(alpha: 0.55)
              : (isDark ? AppColors.darkDivider : AppColors.divider),
          width: active ? 1.4 : 0.6,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // ── الصورة المصغرة ──
            _buildThumb(active, size, isDark),
            const SizedBox(width: 12),
            // ── معلومات الأغنية ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.title.replaceAll(RegExp(r'\.\w+$'), ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w600,
                      color: active
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkText
                              : AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        widget.item.isVideo
                            ? CupertinoIcons.play_rectangle
                            : CupertinoIcons.music_note,
                        size: 11,
                        color: active
                            ? AppColors.primary.withValues(alpha: 0.7)
                            : (isDark
                                ? AppColors.darkTextSec
                                : AppColors.textSecondary),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.item.isVideo ? 'فيديو' : 'صوت',
                        style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 12,
                            color: active
                                ? AppColors.primary.withValues(alpha: 0.7)
                                : (isDark
                                    ? AppColors.darkTextSec
                                    : AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ── زر التشغيل/إيقاف ──
            if (active)
              StreamBuilder<bool>(
                stream: audioService.player.playingStream,
                builder: (_, snap) {
                  final playing = snap.data ?? false;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (playing) {
                        audioService.pauseByUser();
                      } else {
                        audioService.playByUser();
                      }
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        playing
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  );
                },
              )
            else
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceAlt : AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.play_fill,
                  color: isDark ? AppColors.darkTextSec : AppColors.textSecondary,
                  size: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumb(bool isActive, double size, bool isDark) {
    if (_thumbPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(_thumbPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultThumb(isActive, size),
        ),
      );
    }
    return _defaultThumb(isActive, size);
  }

  Widget _defaultThumb(bool isActive, double size) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [AppColors.primary, AppColors.primaryDark]
              : widget.item.isVideo
                  ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                  : [AppColors.redLight, const Color(0xFFFFD6D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        widget.item.isVideo
            ? CupertinoIcons.play_rectangle_fill
            : CupertinoIcons.music_note,
        color: isActive
            ? Colors.white
            : widget.item.isVideo
                ? Colors.white70
                : AppColors.primary,
        size: 24,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  FOLDER GRID CARD — كارت مكتبي داخل المجلد
// ═══════════════════════════════════════════════════════════
class _FolderGridCard extends StatefulWidget {
  final LocalMediaItem item;
  final Color folderColor;
  final List<LocalMediaItem> allItems;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onSave;
  final VoidCallback onRemoveFromFolder;

  const _FolderGridCard({
    super.key,
    required this.item,
    required this.folderColor,
    required this.allItems,
    required this.onTap,
    required this.onDelete,
    required this.onSave,
    required this.onRemoveFromFolder,
  });

  @override
  State<_FolderGridCard> createState() => _FolderGridCardState();
}

class _FolderGridCardState extends State<_FolderGridCard>
    with SingleTickerProviderStateMixin {
  String? _thumbPath;
  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;
  bool _isFlipped = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutBack),
    );
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadThumb() async {
    final thumb = await ThumbnailManager.getLocalThumbnail(widget.item.path);
    if (mounted) setState(() => _thumbPath = thumb);
  }

  void _toggleFlip() {
    if (_isFlipped) {
      _flipCtrl.reverse();
    } else {
      _flipCtrl.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item.title.replaceAll(RegExp(r'\.\w+$'), '');

    return AnimatedBuilder(
      animation: _flipAnim,
      builder: (context, child) {
        final angle = _flipAnim.value * 3.14159;
        final isFront = angle < 1.5708;

        return GestureDetector(
          onLongPress: _toggleFlip,
          onTap: isFront ? widget.onTap : null,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: isFront
                ? _buildFront(title)
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(3.14159),
                    child: _buildBack(title),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildFront(String title) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: context.isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.03),
                ],
              )
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.folderColor.withOpacity(0.85),
                  widget.folderColor.withOpacity(0.65),
                ],
              ),
        border: Border.all(
          color: context.isDark
              ? Colors.white.withOpacity(0.06)
              : widget.folderColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.folderColor.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _thumbPath != null
                        ? Image.file(File(_thumbPath!), fit: BoxFit.cover)
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  widget.folderColor,
                                  widget.folderColor.withOpacity(0.6),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                widget.item.isVideo
                                    ? CupertinoIcons.play_rectangle_fill
                                    : CupertinoIcons.music_note,
                                color: Colors.white.withOpacity(0.7),
                                size: 36,
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.item.isVideo
                            ? CupertinoIcons.play_rectangle
                            : CupertinoIcons.music_note,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.55),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.item.isVideo
                              ? CupertinoIcons.play_rectangle
                              : CupertinoIcons.music_note,
                          color: Colors.white70,
                          size: 11,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.item.isVideo ? 'فيديو' : 'صوت',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBack(String title) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: context.isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.09),
                  Colors.white.withOpacity(0.04),
                ],
              )
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.folderColor.withOpacity(0.85),
                  widget.folderColor.withOpacity(0.65),
                ],
              ),
        border: Border.all(
          color: context.isDark
              ? Colors.white.withOpacity(0.07)
              : widget.folderColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.folderColor.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned(
              top: -20,
              left: -20,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -15,
              right: -15,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(CupertinoIcons.music_note,
                            color: Colors.white, size: 13),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleFlip,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(CupertinoIcons.xmark,
                              color: Colors.white70, size: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.20),
                      Colors.transparent,
                    ]),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildFolderActionButton(
                          icon: CupertinoIcons.trash_fill,
                          label: 'حذف',
                          color: const Color(0xFFFF3B30),
                          onTap: () {
                            _toggleFlip();
                            Future.delayed(
                                const Duration(milliseconds: 300), widget.onDelete);
                          },
                        ),
                        _buildFolderActionButton(
                          icon: CupertinoIcons.arrow_uturn_left,
                          label: 'إزالة من المجلد',
                          color: const Color(0xFFFF9F0A),
                          onTap: () {
                            _toggleFlip();
                            Future.delayed(const Duration(milliseconds: 300),
                                widget.onRemoveFromFolder);
                          },
                        ),
                        _buildFolderActionButton(
                          icon: CupertinoIcons.arrow_down_to_line_alt,
                          label: 'حفظ في المعرض',
                          color: const Color(0xFF34C759),
                          onTap: () {
                            _toggleFlip();
                            Future.delayed(
                                const Duration(milliseconds: 300), widget.onSave);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.25), color.withOpacity(0.10)],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withOpacity(0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 13),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Tajawal',
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SWIPEABLE MEDIA TILE — سحب يمين للحذف
// ─────────────────────────────────────────────
class _SwipeableMediaTile extends StatefulWidget {
  final LocalMediaItem item;
  final int index;
  final List<LocalMediaItem> allItems;
  final VoidCallback onDelete;
  final VoidCallback onSave;

  const _SwipeableMediaTile({
    super.key,
    required this.item,
    required this.index,
    required this.allItems,
    required this.onDelete,
    required this.onSave,
  });

  @override
  State<_SwipeableMediaTile> createState() => _SwipeableMediaTileState();
}

class _SwipeableMediaTileState extends State<_SwipeableMediaTile>
    with TickerProviderStateMixin {
  late AnimationController _swipeCtrl;
  late AnimationController _savePressCtrl;
  late AnimationController _deletePressCtrl;
  late AnimationController _springCtrl;
  late Animation<double> _saveScaleAnim;
  late Animation<double> _deleteScaleAnim;
  late Animation<double> _springAnim;

  double _dragOffset = 0;
  bool _revealed = false;
  String? _thumbPath;

  static const double _revealWidth = 156.0;

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));

    _savePressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _saveScaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
        CurvedAnimation(parent: _savePressCtrl, curve: Curves.easeInOut));

    _deletePressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _deleteScaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
        CurvedAnimation(parent: _deletePressCtrl, curve: Curves.easeInOut));

    _springCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _springAnim = Tween<double>(begin: 0.0, end: 0.0).animate(
        CurvedAnimation(parent: _springCtrl, curve: Curves.elasticOut));

    _loadThumb();
    audioService.currentIndex.addListener(_onIndexChange);
  }

  void _onIndexChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    audioService.currentIndex.removeListener(_onIndexChange);
    _swipeCtrl.dispose();
    _savePressCtrl.dispose();
    _deletePressCtrl.dispose();
    _springCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadThumb() async {
    final path = await ThumbnailManager.getLocalThumbnail(widget.item.path);
    if (path != null && mounted) {
      setState(() => _thumbPath = path);
      return;
    }
    if (widget.item.isVideo && widget.item.thumbnailUrl == null) {
      _tryGenerateLocalVideoThumb();
    }
    if (mounted) setState(() => _thumbPath = null);
  }

  Future<void> _tryGenerateLocalVideoThumb() async {
    try {
      final thumbPath = ThumbnailManager.getThumbPathDirect(widget.item.path);
      if (thumbPath != null && mounted) {
        setState(() => _thumbPath = thumbPath);
        return;
      }
    } catch (_) {}
  }

  void _onHorizontalDrag(DragUpdateDetails details) {
    setState(() {
      _dragOffset =
          (_dragOffset - details.delta.dx).clamp(0.0, _revealWidth * 1.1);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > _revealWidth * 0.40 || velocity < -400) {
      _animateToReveal();
    } else {
      _animateToClose();
    }
  }

  void _animateToReveal() {
    final start = _dragOffset;
    _springAnim = Tween<double>(begin: start, end: _revealWidth).animate(
        CurvedAnimation(parent: _springCtrl, curve: Curves.elasticOut));
    _springCtrl.forward(from: 0).then((_) {
      if (mounted)
        setState(() {
          _dragOffset = _revealWidth;
          _revealed = true;
        });
    });
    _springCtrl.addListener(() {
      if (mounted)
        setState(() =>
            _dragOffset = _springAnim.value.clamp(0.0, _revealWidth * 1.06));
    });
  }

  void _animateToClose() {
    final start = _dragOffset;
    _springAnim = Tween<double>(begin: start, end: 0.0).animate(
        CurvedAnimation(parent: _springCtrl, curve: Curves.easeOutBack));
    _springCtrl.forward(from: 0).then((_) {
      if (mounted)
        setState(() {
          _dragOffset = 0;
          _revealed = false;
        });
    });
    _springCtrl.addListener(() {
      if (mounted)
        setState(
            () => _dragOffset = _springAnim.value.clamp(0.0, _revealWidth));
    });
  }

  void _closeSwipe() {
    _animateToClose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = audioService.currentItem?.path;
    final isActive = currentPath == widget.item.path;

    final revealFraction = (_dragOffset / _revealWidth).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: _revealWidth,
              child: Opacity(
                opacity: revealFraction,
                child: Transform.translate(
                  offset: Offset((1 - revealFraction) * 30, 0),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        // ── زر الحفظ (أزرق) ──
                        Expanded(
                          child: ScaleTransition(
                            scale: _saveScaleAnim,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) => _savePressCtrl.forward(),
                              onTapUp: (_) async {
                                await _savePressCtrl.reverse();
                                _closeSwipe();
                                widget.onSave();
                              },
                              onTapCancel: () => _savePressCtrl.reverse(),
                              child: Container(
                                margin: const EdgeInsets.only(
                                    right: 4, left: 3, top: 2, bottom: 2),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF1565C0),
                                      Color(0xFF42A5F5)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF1976D2)
                                          .withValues(alpha: 0.45),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.22),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.arrow_down_to_line_alt,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'حفظ',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontFamily: 'Tajawal',
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // ── زر الحذف (أحمر) ──
                        Expanded(
                          child: ScaleTransition(
                            scale: _deleteScaleAnim,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) => _deletePressCtrl.forward(),
                              onTapUp: (_) async {
                                await _deletePressCtrl.reverse();
                                _closeSwipe();
                                widget.onDelete();
                              },
                              onTapCancel: () => _deletePressCtrl.reverse(),
                              child: Container(
                                margin: const EdgeInsets.only(
                                    right: 3, left: 4, top: 2, bottom: 2),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFB71C1C),
                                      Color(0xFFEF5350)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFD32F2F)
                                          .withValues(alpha: 0.45),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.22),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.trash_fill,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'حذف',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontFamily: 'Tajawal',
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── الكرت يتحرك لليسار عند السحب ──
            Transform.translate(
              offset: Offset(-_dragOffset, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: _onHorizontalDrag,
                onHorizontalDragEnd: _onDragEnd,
                onTap: () {
                  if (_revealed) {
                    _closeSwipe();
                    return;
                  }

                  // ✦ وضع الريلز — يفتح مشغل الريلز للفيديوهات فقط
                  if (ReelsModeNotifier.instance.value && widget.item.isVideo) {
                    final videoItems = widget.allItems.where((e) => e.isVideo).toList();
                    final videoIndex = videoItems.indexOf(widget.item);
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => ReelsVideoPlayer(
                          items: videoItems,
                          initialIndex: videoIndex < 0 ? 0 : videoIndex,
                          folders: const [],
                          onFoldersChanged: () async {},
                        ),
                        transitionsBuilder: (_, anim, __, child) {
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 1),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                  parent: anim, curve: Curves.easeOutCubic)),
                              child: child,
                            ),
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 450),
                      ),
                    );
                    return;
                  }

                  // المشغل الأصلي (صوت أو وضع الريلز معطّل)
                  audioService.playList(
                    List<LocalMediaItem>.unmodifiable(widget.allItems),
                    widget.index,
                  );
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const FullScreenPlayer(),
                      transitionsBuilder: (_, animation, __, child) {
                        return SlideTransition(
                          position: Tween<Offset>(
                                  begin: const Offset(0, 1), end: Offset.zero)
                              .animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic)),
                          child: child,
                        );
                      },
                    ),
                  );
                },
                child: _buildTile(isActive),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(bool active) {
    const size = 52.0;
    if (_thumbPath != null) {
      return _buildTileWithThumb(active, size);
    }
    return _buildTileWithoutThumb(active, size);
  }

  Widget _buildTileWithThumb(bool active, double size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor = active
        ? (isDark
            ? Color.lerp(AppColors.darkSurface, AppColors.primary, 0.18)!
            : Color.lerp(Colors.white, AppColors.primary, 0.10)!)
        : (isDark ? AppColors.darkSurface : AppColors.surface);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.primary.withValues(alpha: 0.55)
              : (isDark ? AppColors.darkDivider : AppColors.divider),
          width: active ? 1.4 : 0.6,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_thumbPath!),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultThumb(active, size),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.title.replaceAll(RegExp(r'\.\w+$'), ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w600,
                      color: active
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkText
                              : AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        widget.item.isVideo
                            ? CupertinoIcons.play_rectangle
                            : CupertinoIcons.music_note,
                        size: 11,
                        color: active
                            ? AppColors.primary.withValues(alpha: 0.7)
                            : (isDark
                                ? AppColors.darkTextSec
                                : AppColors.textSecondary),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.item.isVideo ? 'فيديو' : 'صوت',
                        style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 12,
                            color: active
                                ? AppColors.primary.withValues(alpha: 0.7)
                                : (isDark
                                    ? AppColors.darkTextSec
                                    : AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (active)
              StreamBuilder<bool>(
                stream: audioService.player.playingStream,
                builder: (_, snap) {
                  final playing = snap.data ?? false;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (playing) {
                        audioService.pauseByUser();
                      } else {
                        audioService.playByUser();
                      }
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        playing
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  );
                },
              )
            else
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceAlt
                      : AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.play_fill,
                  color: isDark
                      ? AppColors.darkTextSec
                      : AppColors.textSecondary,
                  size: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTileWithoutThumb(bool active, double size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor = active
        ? (isDark
            ? Color.lerp(AppColors.darkSurface, AppColors.primary, 0.18)!
            : Color.lerp(Colors.white, AppColors.primary, 0.10)!)
        : (isDark ? AppColors.darkSurface : AppColors.surface);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.primary.withValues(alpha: 0.55)
              : (isDark ? AppColors.darkDivider : AppColors.divider),
          width: active ? 1.4 : 0.6,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _defaultThumb(active, size),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.title.replaceAll(RegExp(r'\.\w+$'), ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w600,
                      color: active
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkText
                              : AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        widget.item.isVideo
                            ? CupertinoIcons.play_rectangle
                            : CupertinoIcons.music_note,
                        size: 11,
                        color: active
                            ? AppColors.primary.withValues(alpha: 0.7)
                            : (isDark
                                ? AppColors.darkTextSec
                                : AppColors.textSecondary),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.item.isVideo ? 'فيديو' : 'صوت',
                        style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 12,
                            color: active
                                ? AppColors.primary.withValues(alpha: 0.7)
                                : (isDark
                                    ? AppColors.darkTextSec
                                    : AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (active)
              StreamBuilder<bool>(
                stream: audioService.player.playingStream,
                builder: (_, snap) {
                  final playing = snap.data ?? false;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (playing) {
                        audioService.pauseByUser();
                      } else {
                        audioService.playByUser();
                      }
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        playing
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  );
                },
              )
            else
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceAlt
                      : AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.play_fill,
                  color: isDark
                      ? AppColors.darkTextSec
                      : AppColors.textSecondary,
                  size: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _defaultThumb(bool isActive, double size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [AppColors.primary, AppColors.primaryDark]
              : widget.item.isVideo
                  ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                  : [AppColors.redLight, const Color(0xFFFFD6D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        widget.item.isVideo
            ? CupertinoIcons.play_rectangle_fill
            : CupertinoIcons.music_note,
        color: isActive
            ? Colors.white
            : widget.item.isVideo
                ? Colors.white70
                : AppColors.primary,
        size: 24,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  MODERN MUSIC GRID CARD
// ═══════════════════════════════════════════════════════════
class _ModernMusicCard extends StatefulWidget {
  final LocalMediaItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onSave;
  final List<MusicFolder> folders;
  final Future<void> Function(MusicFolder) onMove;

  const _ModernMusicCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
    required this.onSave,
    required this.folders,
    required this.onMove,
  });

  @override
  State<_ModernMusicCard> createState() => _ModernMusicCardState();
}

class _ModernMusicCardState extends State<_ModernMusicCard>
    with SingleTickerProviderStateMixin {
  String? _thumbPath;
  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;
  bool _isFlipped = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutBack),
    );
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadThumb() async {
    final thumb =
        await ThumbnailManager.getLocalThumbnail(widget.item.path);

    if (mounted) {
      setState(() {
        _thumbPath = thumb;
      });
    }
  }

  void _toggleFlip() {
    if (_isFlipped) {
      _flipCtrl.reverse();
    } else {
      _flipCtrl.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  void _showFolderPicker() {
    if (widget.folders.isEmpty) {
      _showGlassToastStatic(
        context,
        'لا توجد مجلدات. أنشئ مجلداً أولاً.',
        type: _ToastType.warning,
      );
      return;
    }
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 14, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'اختر المجلد',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Tajawal',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...widget.folders.map((folder) => GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      await widget.onMove(folder);
                      if (mounted) setState(() => _isFlipped = false);
                      _flipCtrl.reverse();
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: folder.color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(CupertinoIcons.folder_fill,
                                color: folder.color, size: 16),
                          ),
                          const SizedBox(width: 12),
                          Text(folder.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Tajawal',
                                  fontSize: 14)),
                          const Spacer(),
                          Text('${folder.songPaths.length} عنصر',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontFamily: 'Tajawal',
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  )),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item.title.replaceAll(RegExp(r'\.\w+$'), '');

    return AnimatedBuilder(
      animation: _flipAnim,
      builder: (context, child) {
        final angle = _flipAnim.value * 3.14159;
        final isFront = angle < 1.5708; // π/2

        return GestureDetector(
          onLongPress: _toggleFlip,
          onTap: isFront ? widget.onTap : null,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: isFront
                ? _buildFront(title)
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(3.14159),
                    child: _buildBack(title),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildFront(String title) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: context.isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.03),
                ],
              )
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromARGB(255, 236, 236, 236).withOpacity(0.7),
                  Color.fromARGB(255, 236, 236, 236).withOpacity(0.7),
                ],
              ),
        border: Border.all(
          color: context.isDark
              ? Colors.white.withOpacity(0.06)
              : Color(0xFF69383D).withOpacity(0.1),
          width: 1,
        ),
boxShadow: context.isDark
    ? [
        // الوضع الداكن
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          blurRadius: 22,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.10),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ]
    : [
        // الوضع الفاتح
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.50),
          blurRadius: 12,
          offset: const Offset(0, -2),
        ),
      ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _thumbPath != null
                        ? Image.file(
                            File(_thumbPath!),
                            fit: BoxFit.cover,
                          )
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFFE8272A),
                                  Color(0xFF470707),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                widget.item.isVideo
                                    ? CupertinoIcons.play_rectangle_fill
                                    : CupertinoIcons.music_note_2,
                                color: Colors.white.withValues(alpha: 0.8),
                                size: 56,
                              ),
                            ),
                          ),
                  ),

                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.75),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.play_fill,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),

                  // مؤشر "اضغط مطولاً للخيارات"
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'اضغط مطولاً للخيارات',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 9,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Tajawal',
                    ),
                  ),

                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.item.isVideo
                              ? CupertinoIcons.play_rectangle
                              : CupertinoIcons.music_note,
                          color: Colors.white70,
                          size: 13,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.item.isVideo ? 'فيديو' : 'صوت',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBack(String title) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1A2E),
            Color(0xFF16213E),
            Color(0xFF0F3460),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: AppColors.primary.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            // ── توهج علوي أيمن ──
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // ── توهج سفلي أيسر ──
            Positioned(
              bottom: -25,
              left: -25,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF5E5CE6).withOpacity(0.20),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // ── خط توهج علوي ──
            Positioned(
              top: 0,
              left: 20,
              right: 20,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── المحتوى ──
            Column(
              children: [
                // ── رأس الكارت ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primaryDark,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.50),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(CupertinoIcons.music_note,
                            color: Colors.white, size: 15),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleFlip,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.10),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.15),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            CupertinoIcons.xmark,
                            color: Colors.white.withOpacity(0.65),
                            size: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── فاصل ──
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),

                // ── الأزرار الثلاثة عمودياً ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            icon: CupertinoIcons.trash_fill,
                            label: 'حذف',
                            sublabel: 'إزالة من المكتبة',
                            color: const Color(0xFFFF3B30),
                            onTap: () => widget.onDelete(),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Expanded(
                          child: _buildActionButton(
                            icon: CupertinoIcons.folder_badge_plus,
                            label: 'نقل',
                            sublabel: 'إضافة إلى مجلد',
                            color: const Color(0xFF5E5CE6),
                            onTap: _showFolderPicker,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Expanded(
                          child: _buildActionButton(
                            icon: CupertinoIcons.arrow_down_to_line_alt,
                            label: 'حفظ',
                            sublabel: 'تصدير إلى المعرض',
                            color: const Color(0xFF30D158),
                            onTap: () {
                              _toggleFlip();
                              Future.delayed(
                                  const Duration(milliseconds: 300),
                                  widget.onSave);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [
              color.withOpacity(0.18),
              color.withOpacity(0.07),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.28),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withOpacity(0.40),
                    color.withOpacity(0.22),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontFamily: 'Tajawal',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.38),
                      fontFamily: 'Tajawal',
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_left,
              color: color.withOpacity(0.50),
              size: 13,
            ),
          ],
        ),
      ),
    );
  }
}
// ═══════════════════════════════════════════════════════════
//  GLASS TOAST — نظام الإشعارات الزجاجي
// ═══════════════════════════════════════════════════════════

enum _ToastType { success, error, warning, info, delete, move }

void _showGlassToastStatic(
  BuildContext context,
  String message, {
  _ToastType type = _ToastType.info,
  Duration duration = const Duration(seconds: 3),
}) {
  OverlayEntry? entry;
  entry = OverlayEntry(
    builder: (ctx) => _GlassToast(message: message, type: type),
  );
  Overlay.of(context).insert(entry);
  Future.delayed(duration, () => entry?.remove());
}

class _GlassToast extends StatefulWidget {
  final String message;
  final _ToastType type;

  const _GlassToast({required this.message, required this.type});

  @override
  State<_GlassToast> createState() => _GlassToastState();
}

class _GlassToastState extends State<_GlassToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _slide = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  _ToastConfig get _config {
    switch (widget.type) {
      case _ToastType.success:
        return _ToastConfig(
          icon: Icons.check_circle_rounded,
          accentColor: const Color(0xFF30D158),
          label: 'تم بنجاح',
        );
      case _ToastType.error:
        return _ToastConfig(
          icon: Icons.cancel_rounded,
          accentColor: const Color(0xFFFF3B30),
          label: 'خطأ',
        );
      case _ToastType.warning:
        return _ToastConfig(
          icon: Icons.warning_rounded,
          accentColor: const Color(0xFFFF9F0A),
          label: 'تنبيه',
        );
      case _ToastType.delete:
        return _ToastConfig(
          icon: Icons.delete_rounded,
          accentColor: const Color(0xFFFF3B30),
          label: 'تم الحذف',
        );
      case _ToastType.move:
        return _ToastConfig(
          icon: Icons.folder_open_rounded,
          accentColor: const Color(0xFF5E5CE6),
          label: 'تم النقل',
        );
      case _ToastType.info:
        return _ToastConfig(
          icon: Icons.info_rounded,
          accentColor: const Color(0xFF0A84FF),
          label: 'معلومة',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config;
    final topPad = MediaQuery.of(context).padding.top;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) => Positioned(
        top: topPad + 12 + (_slide.value * 100),
        left: 20,
        right: 20,
        child: Opacity(
          opacity: _fade.value.clamp(0.0, 1.0),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cfg.accentColor.withOpacity(0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: cfg.accentColor.withOpacity(0.18),
                        blurRadius: 24,
                        spreadRadius: 0,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.28),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      // ── خط جانبي ملوّن ──
                      Container(
                        width: 3,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              cfg.accentColor,
                              cfg.accentColor.withOpacity(0.3),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // ── أيقونة النوع ──
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cfg.accentColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: cfg.accentColor.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            cfg.icon,
                            color: cfg.accentColor,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // ── النص ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              cfg.label,
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cfg.accentColor,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.message,
                              textDirection: TextDirection.rtl,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withOpacity(0.92),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastConfig {
  final IconData icon;
  final Color accentColor;
  final String label;
  const _ToastConfig({
    required this.icon,
    required this.accentColor,
    required this.label,
  });
}