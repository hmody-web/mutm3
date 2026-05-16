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
import 'app_icon_service.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'listen_page.dart';
import 'browse_page.dart';
import 'settings_page.dart';

// ═══════════════════════════════════════════════════════════
//  PAGE 1 — استمع (Listen) — with swipe-to-delete
// ═══════════════════════════════════════════════════════════
class ListenPage extends StatefulWidget {
  const ListenPage({super.key});

  @override
  State<ListenPage> createState() => _ListenPageState();
}

class _ListenPageState extends State<ListenPage> {
  List<LocalMediaItem> _localItems = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
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
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${dir.path}/dndn');
    if (!await musicDir.exists()) await musicDir.create(recursive: true);

    final entities = musicDir.listSync()
        .where((e) => e is File && !e.path.split('/').last.startsWith('.'))
        .toList();

    final withStat = entities.map((e) => MapEntry(e, e.statSync())).toList()
      ..sort((a, b) => b.value.modified.compareTo(a.value.modified));

    final items = <LocalMediaItem>[];
    for (final entry in withStat) {
      final path = entry.key.path;
      final name = path.split('/').last.toLowerCase();
      final isVideo = name.endsWith('.mp4') || name.endsWith('.webm') ||
          name.endsWith('.mkv') || name.endsWith('.mov');
      final isAudio = name.endsWith('.mp3') || name.endsWith('.m4a') ||
          name.endsWith('.aac') || name.endsWith('.opus') ||
          name.endsWith('.flac') || name.endsWith('.wav');
      if (isVideo || isAudio) {
        items.add(LocalMediaItem(
            path: path,
            title: path.split('/').last,
            isVideo: isVideo));
      }
    }

    if (mounted) {
      setState(() {
        _localItems = items;
      });
    }

    // توليد صور مصغرة للملفات التي ليس لها صورة بعد (فيديو + صوت)
    for (final item in items) {
      final existing = await ThumbnailManager.getLocalThumbnail(item.path);
      if (existing != null) continue;
      ThumbnailManager.generateLocalThumbnail(item.path).then((result) {
        if (result != null && mounted) setState(() {});
      });
    }
  }

  Future<void> _deleteItem(LocalMediaItem item) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('حذف الملف'),
        content: Text('هل تريد حذف "${item.title.replaceAll(RegExp(r'\.\w+$'), '')}"؟'),
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
    } catch (_) {}
    _loadFiles();
  }

  void _playAll(int startIndex) {
    audioService.playList(_localItems, startIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: CustomScrollView(
        slivers: [
          _buildHeader(),
          _buildFileList(),
          // bottom padding for mini player + nav bar
          const SliverToBoxAdapter(child: SizedBox(height: 160)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
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
                    child: const Icon(
                      CupertinoIcons.music_note,
                      color: Colors.white,
                      size: 24,
                    ),
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
            if (_localItems.isNotEmpty)
              GestureDetector(
                onTap: () => _playAll(0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.play_fill, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('تشغيل الكل',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => const FileBrowserPage()),
              ).then((_) => _loadFiles()),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(CupertinoIcons.folder_fill,
                    size: 18, color: context.appTextSec),
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
                style: TextStyle(fontSize: 14, fontFamily: 'Tajawal', color: context.appTextSec),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(builder: (_) => const FileBrowserPage()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.appSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.appDivider, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.folder_fill, size: 18, color: context.appText),
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

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = _localItems[index];
            return _SwipeableMediaTile(
              key: ValueKey(item.path),
              item: item,
              index: index,
              allItems: _localItems,
              onDelete: () => _deleteItem(item),
            );
          },
          childCount: _localItems.length,
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

  const _SwipeableMediaTile({
    super.key,
    required this.item,
    required this.index,
    required this.allItems,
    required this.onDelete,
  });

  @override
  State<_SwipeableMediaTile> createState() => _SwipeableMediaTileState();
}

class _SwipeableMediaTileState extends State<_SwipeableMediaTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _swipeCtrl;
  double _dragOffset = 0;
  bool _revealed = false;
  String? _thumbPath;

  static const double _revealWidth = 84.0;

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _loadThumb();
    // إعادة رسم الكرت عند تغيّر الأغنية الحالية
    audioService.currentIndex.addListener(_onIndexChange);
  }

  void _onIndexChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    audioService.currentIndex.removeListener(_onIndexChange);
    _swipeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadThumb() async {
    // أولاً: ابحث عن صورة محفوظة محلياً
    final path = await ThumbnailManager.getLocalThumbnail(widget.item.path);
    if (path != null && mounted) {
      setState(() => _thumbPath = path);
      return;
    }
    // ثانياً: إذا كان الملف فيديو محلياً، حاول تهيئة VideoPlayerController لجلب الفريم
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
      // الملف لا يوجد له صورة — نُظهر أيقونة تمييزية للفيديو
    } catch (_) {}
  }

  // السحب للجهة اليسرى (سالب) فقط في RTL
  void _onHorizontalDrag(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset - details.delta.dx).clamp(0.0, _revealWidth);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_dragOffset > _revealWidth * 0.45) {
      setState(() {
        _dragOffset = _revealWidth;
        _revealed = true;
      });
    } else {
      _closeSwipe();
    }
  }

  void _closeSwipe() {
    setState(() {
      _dragOffset = 0;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // نستخدم المقارنة بالمسار لأنها أكثر دقة من المقارنة بالـ index
    // (الـ index قد يتغير إذا حُذف عنصر من القائمة)
    final currentPath = audioService.currentItem?.path;
    final isActive = currentPath == widget.item.path;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── زر الحذف خلف الكرت (جهة اليسار) ──
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () {
                  _closeSwipe();
                  Future.microtask(() => widget.onDelete());
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _dragOffset.clamp(0.0, _revealWidth),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD32F2F), Color(0xFFFF3B30)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _dragOffset > _revealWidth * 0.6
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(CupertinoIcons.trash_fill,
                                color: Colors.white, size: 22),
                            SizedBox(height: 3),
                            Text('حذف',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),

          // ── الكرت الرئيسي ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onHorizontalDrag,
            onHorizontalDragEnd: _onDragEnd,
            onTap: () {
              if (_revealed) {
                _closeSwipe();
                return;
              }
              // نُمرر القائمة والـ index مباشرة — playList يضبط currentIndex قبل أي async
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
                              parent: animation, curve: Curves.easeOutCubic)),
                      child: child,
                    );
                  },
                ),
              );
            },
            child: Transform.translate(
              offset: Offset(-_dragOffset, 0),
              child: _buildTile(isActive),
            ),
          ),
        ],
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary.withValues(alpha: 0.07)
            : (isDark ? AppColors.darkSurface : AppColors.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.primary.withValues(alpha: 0.45)
              : (isDark ? AppColors.darkDivider : AppColors.divider),
          width: active ? 1.2 : 0.6,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
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
                          : (isDark ? AppColors.darkText : AppColors.textPrimary),
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
                            : (isDark ? AppColors.darkTextSec : AppColors.textSecondary),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.item.isVideo ? 'فيديو' : 'صوت',
                        style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 12,
                            color: active
                                ? AppColors.primary.withValues(alpha: 0.7)
                                : (isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
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

  Widget _buildTileWithoutThumb(bool active, double size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary.withValues(alpha: 0.07)
            : (isDark ? AppColors.darkSurface : AppColors.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.primary.withValues(alpha: 0.45)
              : (isDark ? AppColors.darkDivider : AppColors.divider),
          width: active ? 1.2 : 0.6,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
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
                          : (isDark ? AppColors.darkText : AppColors.textPrimary),
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
                            : (isDark ? AppColors.darkTextSec : AppColors.textSecondary),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.item.isVideo ? 'فيديو' : 'صوت',
                        style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 12,
                            color: active
                                ? AppColors.primary.withValues(alpha: 0.7)
                                : (isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
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