import 'dart:io';
import 'dart:isolate';
import 'dart:async';
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

// ─────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.mustami3.audio',
    androidNotificationChannelName: 'مستمع',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light,
  ));

  _warmUpDioConnection();
  runApp(const Mustami3App());
}

void _warmUpDioConnection() {
  dio.head(
    'https://www.youtube.com',
    options: Options(
      receiveTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
      validateStatus: (_) => true,
    ),
  ).catchError((_) {});
}

// ─────────────────────────────────────────────
//  THEME & CONSTANTS
// ─────────────────────────────────────────────
class AppColors {
  static const Color primary = Color(0xFFE8272A);
  static const Color primaryDark = Color(0xFFB71C1C);
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7F7F7);
  static const Color surfaceAlt = Color(0xFFF0F0F0);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color divider = Color(0xFFE0E0E0);
  static const Color redLight = Color(0xFFFFEBEB);
}

// ─────────────────────────────────────────────
//  SINGLETONS
// ─────────────────────────────────────────────
final YoutubeExplode yt = YoutubeExplode();

final Dio dio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 10),
    sendTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
    },
  ),
);

// ─────────────────────────────────────────────
//  CACHED VIDEO MODEL
// ─────────────────────────────────────────────
class CachedVideo {
  final MuxedStreamInfo streamInfo;
  final String url;
  const CachedVideo({required this.streamInfo, required this.url});
}

// ─────────────────────────────────────────────
//  MANIFEST CACHE
// ─────────────────────────────────────────────
class _ManifestCache {
  static final Map<String, StreamManifest> _cache = {};
  static final Map<String, Future<StreamManifest>> _pending = {};
  static final Map<String, CachedVideo> _videoCache = {};

  static Future<StreamManifest> get(String videoId) {
    if (_cache.containsKey(videoId)) return Future.value(_cache[videoId]!);
    if (_pending.containsKey(videoId)) return _pending[videoId]!;
    final future = yt.videos.streamsClient
        .getManifest(videoId)
        .then((m) {
          _cache[videoId] = m;
          _pending.remove(videoId);
          _extractAndCacheVideo(videoId, m);
          return m;
        })
        .catchError((e) {
          _pending.remove(videoId);
          throw e;
        });
    _pending[videoId] = future;
    return future;
  }

  static void _extractAndCacheVideo(String videoId, StreamManifest manifest) {
    try {
      final muxed = manifest.muxed;
      if (muxed.isEmpty) return;
      final chosen = muxed.firstWhere(
        (s) => s.videoQuality.name.contains('360') || s.videoResolution.height == 360,
        orElse: () {
          final sorted = List<MuxedStreamInfo>.from(muxed)
            ..sort((a, b) =>
                (a.videoResolution.height - 360).abs()
                    .compareTo((b.videoResolution.height - 360).abs()));
          return sorted.first;
        },
      );
      _videoCache[videoId] = CachedVideo(streamInfo: chosen, url: chosen.url.toString());
    } catch (_) {}
  }

  static bool isCached(String videoId) => _cache.containsKey(videoId);
  static bool isVideoCached(String videoId) => _videoCache.containsKey(videoId);
  static StreamManifest? getCached(String videoId) => _cache[videoId];
  static CachedVideo? getCachedVideo(String videoId) => _videoCache[videoId];

  static Future<CachedVideo> getVideo(String videoId) async {
    if (_videoCache.containsKey(videoId)) return _videoCache[videoId]!;
    await get(videoId);
    if (_videoCache.containsKey(videoId)) return _videoCache[videoId]!;
    throw Exception('لا تتوفر صيغ muxed لهذا الفيديو');
  }

  static void prefetchAll(List<String> videoIds, {int limit = 5}) {
    for (final id in videoIds.take(limit)) {
      if (!isCached(id) && !_pending.containsKey(id)) {
        get(id).catchError((_) {});
      }
    }
  }
}

// ─────────────────────────────────────────────
//  MEDIA ITEM MODEL — يمثل ملف محلي واحد
// ─────────────────────────────────────────────
class LocalMediaItem {
  final String path;
  final String title;
  final bool isVideo;
  final String? thumbnailUrl; // YouTube thumbnail URL مخزّن مع الملف

  const LocalMediaItem({
    required this.path,
    required this.title,
    required this.isVideo,
    this.thumbnailUrl,
  });

  String get thumbnailCachePath {
    final dir = path.substring(0, path.lastIndexOf('/'));
    final name = path.split('/').last.replaceAll(RegExp(r'\.\w+$'), '');
    return '$dir/.thumb_$name.jpg';
  }
}

// ─────────────────────────────────────────────
//  THUMBNAIL CACHE MANAGER
// ─────────────────────────────────────────────
class ThumbnailManager {
  static final Map<String, String?> _memCache = {};

  /// يُرجع مسار صورة مخزّنة محلياً إن وُجدت
  static Future<String?> getLocalThumbnail(String mediaPath) async {
    if (_memCache.containsKey(mediaPath)) return _memCache[mediaPath];
    final name = mediaPath.split('/').last.replaceAll(RegExp(r'\.\w+$'), '');
    final dir = mediaPath.substring(0, mediaPath.lastIndexOf('/'));
    final thumbPath = '$dir/.thumb_$name.jpg';
    if (File(thumbPath).existsSync()) {
      _memCache[mediaPath] = thumbPath;
      return thumbPath;
    }
    _memCache[mediaPath] = null;
    return null;
  }

  /// يحفظ صورة من URL إلى ملف محلي بجانب الفيديو
  static Future<void> saveThumbnail(String mediaPath, String thumbnailUrl) async {
    try {
      final name = mediaPath.split('/').last.replaceAll(RegExp(r'\.\w+$'), '');
      final dir = mediaPath.substring(0, mediaPath.lastIndexOf('/'));
      final thumbPath = '$dir/.thumb_$name.jpg';
      if (File(thumbPath).existsSync()) return; // موجود مسبقاً
      final response = await dio.get<List<int>>(
        thumbnailUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.data != null) {
        await File(thumbPath).writeAsBytes(response.data!);
        _memCache[mediaPath] = thumbPath;
      }
    } catch (_) {}
  }

  static void clearCache(String mediaPath) {
    _memCache.remove(mediaPath);
    final name = mediaPath.split('/').last.replaceAll(RegExp(r'\.\w+$'), '');
    final dir = mediaPath.substring(0, mediaPath.lastIndexOf('/'));
    final thumbPath = '$dir/.thumb_$name.jpg';
    try { File(thumbPath).deleteSync(); } catch (_) {}
  }
}

// ─────────────────────────────────────────────
//  AUDIO PLAYER SERVICE — Singleton
// ─────────────────────────────────────────────
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer player = AudioPlayer();
  final ValueNotifier<List<LocalMediaItem>> playlist = ValueNotifier([]);
  final ValueNotifier<int> currentIndex = ValueNotifier(-1);
  final ValueNotifier<bool> isVisible = ValueNotifier(false);

  // القائمة المتسلسلة التي يفهمها iOS Control Center و lock screen
  ConcatenatingAudioSource? _concatenating;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // تحديث currentIndex عند تغيّر المسار الحالي (يشمل الضغط على next/prev من شاشة القفل)
    player.currentIndexStream.listen((index) {
      if (index != null && index != currentIndex.value) {
        currentIndex.value = index;
        isVisible.value = true;
      }
    });

    // إعادة تهيئة الجلسة عند انقطاع الصوت (مكالمة واردة مثلاً)
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        player.pause();
      } else {
        if (event.type == AudioInterruptionType.pause ||
            event.type == AudioInterruptionType.unknown) {
          player.play();
        }
      }
    });
  }

  /// يبني ConcatenatingAudioSource من قائمة الملفات المحلية
  ConcatenatingAudioSource _buildSource(List<LocalMediaItem> items) {
    return ConcatenatingAudioSource(
      useLazyPreparation: true, // يحمّل الملف فقط عند الحاجة — مهم للقوائم الطويلة
      children: items.map((item) {
        final thumb = item.thumbnailUrl;
        return AudioSource.file(
          item.path,
          tag: MediaItem(
            id: item.path,
            title: item.title.replaceAll(RegExp(r'\.\w+$'), ''),
            artist: 'مستمع',
            artUri: thumb != null ? Uri.parse(thumb) : null,
          ),
        );
      }).toList(),
    );
  }

  /// تشغيل قائمة كاملة ابتداءً من index معيّن
  Future<void> playList(List<LocalMediaItem> items, int startIndex) async {
    if (items.isEmpty) return;
    playlist.value = items;
    currentIndex.value = startIndex.clamp(0, items.length - 1);

    _concatenating = _buildSource(items);
    try {
      await player.setAudioSource(
        _concatenating!,
        initialIndex: currentIndex.value,
        initialPosition: Duration.zero,
      );
      await player.play();
      isVisible.value = true;
    } catch (e) {
      debugPrint('Error playList: $e');
    }
  }

  /// تشغيل عنصر واحد بالـ index بدون إعادة بناء القائمة (للنقر على عنصر في القائمة)
  Future<void> playAtIndex(int index) async {
    final list = playlist.value;
    if (index < 0 || index >= list.length) return;

    // إن كانت القائمة ذاتها لا زالت محمّلة، انتقل فقط
    if (_concatenating != null &&
        _concatenating!.length == list.length) {
      try {
        await player.seek(Duration.zero, index: index);
        await player.play();
        currentIndex.value = index;
        isVisible.value = true;
        return;
      } catch (_) {}
    }

    // وإلا أعد البناء
    await playList(list, index);
  }

  Future<void> playNext() async {
    final idx = currentIndex.value;
    final list = playlist.value;
    if (idx < list.length - 1) {
      await player.seekToNext();
    }
  }

  Future<void> playPrevious() async {
    // إذا مضى أكثر من 3 ثوانٍ، ارجع لبداية الأغنية الحالية
    final pos = player.position;
    if (pos.inSeconds > 3) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  LocalMediaItem? get currentItem {
    final idx = currentIndex.value;
    final list = playlist.value;
    if (idx < 0 || idx >= list.length) return null;
    return list[idx];
  }

  void dispose() => player.dispose();
}

final audioService = AudioPlayerService();
final ValueNotifier<String?> _downloadCompleteNotifier = ValueNotifier(null);

// ─────────────────────────────────────────────
//  DOWNLOAD SERVICE — Video Only (no MP3)
// ─────────────────────────────────────────────
class _DownloadArgs {
  final String videoId;
  final String safeTitle;
  final String dirPath;
  final String quality;
  final SendPort sendPort;
  final String? directUrl;

  const _DownloadArgs({
    required this.videoId,
    required this.safeTitle,
    required this.dirPath,
    required this.quality,
    required this.sendPort,
    this.directUrl,
  });
}

Future<void> _downloadWithDio({
  required String url,
  required String savePath,
  required SendPort sendPort,
}) async {
  final dioInstance = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive',
        'Range': 'bytes=0-',
      },
    ),
  );

  try {
    await dioInstance.download(
      url,
      savePath,
      deleteOnError: true,
      onReceiveProgress: (received, total) {
        if (total > 0) sendPort.send({'progress': received / total});
      },
    );
    sendPort.send({'done': savePath.split('/').last});
  } catch (e) {
    sendPort.send({'error': e.toString()});
  } finally {
    dioInstance.close();
  }
}

/// ★ Video-only isolate — no audioOnly support
Future<void> _downloadIsolate(_DownloadArgs args) async {
  if (args.directUrl != null) {
    final savePath = '${args.dirPath}/${args.safeTitle}.mp4';
    args.sendPort.send({'status': 'جاري التحميل...'});
    await _downloadWithDio(url: args.directUrl!, savePath: savePath, sendPort: args.sendPort);
    return;
  }

  final ytIsolate = YoutubeExplode();
  try {
    final manifest = await ytIsolate.videos.streamsClient.getManifest(args.videoId);
    final muxed = manifest.muxed;
    if (muxed.isEmpty) {
      args.sendPort.send({'error': 'لا تتوفر صيغ muxed لهذا الفيديو'});
      ytIsolate.close();
      return;
    }
    final chosen = args.quality == 'high'
        ? muxed.withHighestBitrate()
        : muxed.firstWhere(
            (s) => s.videoQuality.name.contains('360') || s.videoResolution.height == 360,
            orElse: () {
              final sorted = List<MuxedStreamInfo>.from(muxed)
                ..sort((a, b) =>
                    (a.videoResolution.height - 360).abs()
                        .compareTo((b.videoResolution.height - 360).abs()));
              return sorted.first;
            },
          );
    final url = chosen.url.toString();
    ytIsolate.close();
    final savePath = '${args.dirPath}/${args.safeTitle}.mp4';
    args.sendPort.send({'status': 'جاري التحميل...'});
    await _downloadWithDio(url: url, savePath: savePath, sendPort: args.sendPort);
  } catch (e) {
    ytIsolate.close();
    args.sendPort.send({'error': e.toString()});
  }
}

// ─────────────────────────────────────────────
//  APP ROOT
// ─────────────────────────────────────────────
class Mustami3App extends StatelessWidget {
  const Mustami3App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مستمع',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'SF Pro Display',
        useMaterial3: true,
      ),
      home: const MainShell(),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
    );
  }
}

// Global nav index notifier
final ValueNotifier<int> _navIndexNotifier = ValueNotifier(0);

// ─────────────────────────────────────────────
//  MAIN SHELL — Bottom Nav + Mini Player
// ─────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final List<Widget> _pages = const [ListenPage(), BrowsePage(), SettingsPage()];

  @override
  void initState() {
    super.initState();
    audioService.init();
    _navIndexNotifier.addListener(_onNavChange);
  }

  @override
  void dispose() {
    _navIndexNotifier.removeListener(_onNavChange);
    super.dispose();
  }

  void _onNavChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final navIndex = _navIndexNotifier.value;
    return Scaffold(
      body: Stack(
        children: [
          // ★ IndexedStack يحافظ على state كل صفحة
          IndexedStack(index: navIndex, children: _pages),
          // ★ Mini Player + Bottom Nav فوق كل شيء
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomArea(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  BOTTOM AREA: Mini Player + Nav Bar
// ─────────────────────────────────────────────
class _BottomArea extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mini Player
        ValueListenableBuilder<bool>(
          valueListenable: audioService.isVisible,
          builder: (_, visible, __) {
            if (!visible) return const SizedBox.shrink();
            return _MiniPlayer();
          },
        ),
        // Bottom Nav
        Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: ValueListenableBuilder<int>(
              valueListenable: _navIndexNotifier,
              builder: (_, idx, __) {
                return Row(
                  children: [
                    _NavItem(index: 0, icon: CupertinoIcons.music_note_2, label: 'استمع', current: idx),
                    _NavItem(index: 1, icon: CupertinoIcons.search, label: 'تصفح', current: idx),
                    _NavItem(index: 2, icon: CupertinoIcons.settings, label: 'الإعدادات', current: idx),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final int current;

  const _NavItem({
    required this.index,
    required this.icon,
    required this.label,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = index == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => _navIndexNotifier.value = index,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 22,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  MINI PLAYER WIDGET
// ─────────────────────────────────────────────
class _MiniPlayer extends StatefulWidget {
  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _openFullPlayer() {
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
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position:
          Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(_slideAnim),
      child: GestureDetector(
        onTap: _openFullPlayer,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ValueListenableBuilder<int>(
              valueListenable: audioService.currentIndex,
              builder: (context, idx, _) {
                final item = audioService.currentItem;
                if (item == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      // ── الصورة المصغرة (تتحدث مع الأغنية) ──
                      _MiniThumbnail(key: ValueKey(item.path), item: item),
                      const SizedBox(width: 10),

                      // ── العنوان + شريط التقدم ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.title.replaceAll(RegExp(r'\.\w+$'), ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            StreamBuilder<Duration?>(
                              stream: audioService.player.durationStream,
                              builder: (_, durSnap) {
                                return StreamBuilder<Duration>(
                                  stream:
                                      audioService.player.positionStream,
                                  builder: (_, posSnap) {
                                    final dur =
                                        durSnap.data?.inMilliseconds ?? 1;
                                    final pos =
                                        posSnap.data?.inMilliseconds ?? 0;
                                    final progress = dur > 0
                                        ? (pos / dur).clamp(0.0, 1.0)
                                        : 0.0;
                                    return ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        backgroundColor: Colors.white12,
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                                AppColors.primary),
                                        minHeight: 3,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),

                      // ── السابق (يمين في RTL) ──
                      _MiniBtn(
                        icon: CupertinoIcons.forward_end_fill,
                        onTap: () => audioService.playNext(),
                      ),
                      const SizedBox(width: 2),

                      // ── تشغيل / إيقاف ──
                      StreamBuilder<bool>(
                        stream: audioService.player.playingStream,
                        builder: (_, snap) {
                          final playing = snap.data ?? false;
                          return _MiniBtn(
                            icon: playing
                                ? CupertinoIcons.pause_fill
                                : CupertinoIcons.play_fill,
                            size: 22,
                            onTap: () => playing
                                ? audioService.player.pause()
                                : audioService.player.play(),
                          );
                        },
                      ),
                      const SizedBox(width: 2),

                      // ── التالي (يسار في RTL) ──
                      _MiniBtn(
                        icon: CupertinoIcons.backward_end_fill,
                        onTap: () => audioService.playPrevious(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniThumbnail extends StatefulWidget {
  final LocalMediaItem item;
  const _MiniThumbnail({super.key, required this.item});

  @override
  State<_MiniThumbnail> createState() => _MiniThumbnailState();
}

class _MiniThumbnailState extends State<_MiniThumbnail> {
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // يُعاد استدعاؤه عند تغيير الـ key (أغنية جديدة)
  @override
  void didUpdateWidget(_MiniThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path) {
      _thumbPath = null;
      _load();
    }
  }

  Future<void> _load() async {
    final path = await ThumbnailManager.getLocalThumbnail(widget.item.path);
    if (mounted) setState(() => _thumbPath = path);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: _thumbPath != null
          ? Image.file(File(_thumbPath!),
              width: 46, height: 46, fit: BoxFit.cover)
          : Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primaryDark,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(
                widget.item.isVideo
                    ? CupertinoIcons.play_rectangle_fill
                    : CupertinoIcons.music_note,
                color: Colors.white,
                size: 20,
              ),
            ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const _MiniBtn({required this.icon, required this.onTap, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  FULL SCREEN PLAYER
// ─────────────────────────────────────────────
class FullScreenPlayer extends StatefulWidget {
  const FullScreenPlayer({super.key});

  @override
  State<FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends State<FullScreenPlayer> {
  bool _isRepeat = false;
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _loadThumb();
    audioService.currentIndex.addListener(_onTrackChange);
  }

  @override
  void dispose() {
    audioService.currentIndex.removeListener(_onTrackChange);
    super.dispose();
  }

  void _onTrackChange() {
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final item = audioService.currentItem;
    if (item == null) return;
    final path = await ThumbnailManager.getLocalThumbnail(item.path);
    if (mounted) setState(() => _thumbPath = path);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(CupertinoIcons.chevron_down,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'يُشغَّل الآن',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 36),
                ],
              ),
            ),

            // ── Artwork / Thumbnail ──
            Expanded(
              flex: 5,
              child: ValueListenableBuilder<int>(
                valueListenable: audioService.currentIndex,
                builder: (_, idx, __) {
                  final item = audioService.currentItem;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _thumbPath != null
                          ? Image.file(
                              File(_thumbPath!),
                              fit: BoxFit.cover,
                              width: double.infinity,
                            )
                          : Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withOpacity(0.8),
                                    AppColors.primaryDark,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Icon(
                                item?.isVideo == true
                                    ? CupertinoIcons.play_rectangle_fill
                                    : CupertinoIcons.music_note_2,
                                color: Colors.white.withOpacity(0.5),
                                size: 80,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),

            // ── Track Info ──
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    ValueListenableBuilder<int>(
                      valueListenable: audioService.currentIndex,
                      builder: (_, __, ___) {
                        final item = audioService.currentItem;
                        final title = item?.title.replaceAll(RegExp(r'\.\w+$'), '') ?? '';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'مستمع',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // ── Progress Slider ──
                    StreamBuilder<Duration?>(
                      stream: audioService.player.durationStream,
                      builder: (_, durSnap) {
                        return StreamBuilder<Duration>(
                          stream: audioService.player.positionStream,
                          builder: (_, posSnap) {
                            final duration = durSnap.data ?? Duration.zero;
                            final position = posSnap.data ?? Duration.zero;
                            final progress = duration.inMilliseconds > 0
                                ? position.inMilliseconds / duration.inMilliseconds
                                : 0.0;
                            return Column(
                              children: [
                                SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 4,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 8),
                                    overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 16),
                                    activeTrackColor: AppColors.primary,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                    overlayColor: AppColors.primary.withOpacity(0.2),
                                  ),
                                  child: Slider(
                                    value: progress.clamp(0.0, 1.0),
                                    onChanged: (val) {
                                      final ms =
                                          (val * duration.inMilliseconds).toInt();
                                      audioService.player
                                          .seek(Duration(milliseconds: ms));
                                    },
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_fmt(position),
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                      Text(_fmt(duration),
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // ── Controls ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Repeat
                        GestureDetector(
                          onTap: () {
                            setState(() => _isRepeat = !_isRepeat);
                            audioService.player.setLoopMode(
                                _isRepeat ? LoopMode.one : LoopMode.off);
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _isRepeat
                                  ? AppColors.primary.withOpacity(0.2)
                                  : Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.repeat,
                              color: _isRepeat
                                  ? AppColors.primary
                                  : Colors.white54,
                              size: 20,
                            ),
                          ),
                        ),
                        // ── التالي → (يمين في RTL = أغنية تالية) ──
                        GestureDetector(
                          onTap: () => audioService.playNext(),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              CupertinoIcons.forward_end_fill,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                        // ── تشغيل / إيقاف ──
                        StreamBuilder<bool>(
                          stream: audioService.player.playingStream,
                          builder: (_, snap) {
                            final playing = snap.data ?? false;
                            return GestureDetector(
                              onTap: () => playing
                                  ? audioService.player.pause()
                                  : audioService.player.play(),
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          AppColors.primary.withOpacity(0.45),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  playing
                                      ? CupertinoIcons.pause_fill
                                      : CupertinoIcons.play_fill,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            );
                          },
                        ),
                        // ── السابق ← (يسار في RTL = أغنية سابقة) ──
                        GestureDetector(
                          onTap: () => audioService.playPrevious(),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              CupertinoIcons.backward_end_fill,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                        // Shuffle placeholder
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.shuffle,
                            color: Colors.white54,
                            size: 20,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Playlist Queue ──
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28, vertical: 4),
                    child: Text(
                      'قائمة التشغيل',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<List<LocalMediaItem>>(
                      valueListenable: audioService.playlist,
                      builder: (_, items, __) {
                        return ValueListenableBuilder<int>(
                          valueListenable: audioService.currentIndex,
                          builder: (_, curIdx, __) {
                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final item = items[i];
                                final isActive = i == curIdx;
                                return GestureDetector(
                                  onTap: () => audioService.playAtIndex(i),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    margin: const EdgeInsets.only(bottom: 4),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AppColors.primary.withOpacity(0.2)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isActive
                                              ? CupertinoIcons.play_circle_fill
                                              : CupertinoIcons.music_note,
                                          color: isActive
                                              ? AppColors.primary
                                              : Colors.white38,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            item.title.replaceAll(
                                                RegExp(r'\.\w+$'), ''),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isActive
                                                  ? AppColors.primary
                                                  : Colors.white70,
                                              fontSize: 13,
                                              fontWeight: isActive
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
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
}

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
  String _downloadDir = '';

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _downloadCompleteNotifier.addListener(_onDownloadComplete);
  }

  void _onDownloadComplete() {
    if (_downloadCompleteNotifier.value != null) {
      _loadFiles();
      _downloadCompleteNotifier.value = null;
    }
  }

  @override
  void dispose() {
    _downloadCompleteNotifier.removeListener(_onDownloadComplete);
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${dir.path}/Mustami3');
    if (!await musicDir.exists()) await musicDir.create(recursive: true);

    final entities = musicDir.listSync()
        .where((e) => e is File && !e.path.split('/').last.startsWith('.'))
        .toList();

    final withStat = entities.map((e) => MapEntry(e, e.statSync())).toList()
      ..sort((a, b) => b.value.modified.compareTo(a.value.modified));

    final items = <LocalMediaItem>[];
    for (final entry in withStat) {
      final path = entry.key.path;
      final name = path.split('/').last;
      final isVideo = name.endsWith('.mp4') || name.endsWith('.webm') || name.endsWith('.mkv');
      final isAudio = name.endsWith('.mp3') || name.endsWith('.m4a') ||
          name.endsWith('.aac') || name.endsWith('.opus');
      if (isVideo || isAudio) {
        items.add(LocalMediaItem(path: path, title: name, isVideo: isVideo));
      }
    }

    if (mounted) {
      setState(() {
        _downloadDir = musicDir.path;
        _localItems = items;
      });
    }
  }

  Future<void> _deleteItem(LocalMediaItem item) async {
    // Confirm dialog
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
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildHeader(),
          _buildFileList(),
          // bottom padding for mini player + nav bar
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
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
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(CupertinoIcons.music_note, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'مستمع',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
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
              onTap: _loadFiles,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(CupertinoIcons.refresh,
                    size: 18, color: AppColors.textSecondary),
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
                  color: AppColors.redLight,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(CupertinoIcons.music_note_2,
                    size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              const Text(
                'لا توجد ملفات بعد',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'حمّل مقاطع من تبويب تصفح',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
              onTap: () => _playAll(index),
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
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SwipeableMediaTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_SwipeableMediaTile> createState() => _SwipeableMediaTileState();
}

class _SwipeableMediaTileState extends State<_SwipeableMediaTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _swipeCtrl;
  late Animation<double> _swipeAnim;
  double _dragOffset = 0;
  bool _revealed = false;
  String? _thumbPath;

  static const double _revealWidth = 84.0;

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _swipeAnim =
        CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutCubic);
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
    final path = await ThumbnailManager.getLocalThumbnail(widget.item.path);
    if (mounted) setState(() => _thumbPath = path);
  }

  // السحب للجهة اليمين (موجب) فقط
  void _onHorizontalDrag(DragUpdateDetails details) {
    setState(() {
      _dragOffset =
          (_dragOffset + details.delta.dx).clamp(0.0, _revealWidth);
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

  void _handleTap() {
    if (_revealed) {
      _closeSwipe();
      return;
    }
    // لا تعيد التشغيل إن كانت الأغنية ذاتها تعمل حالياً
    final isCurrentlyPlaying =
        audioService.currentItem?.path == widget.item.path;
    if (isCurrentlyPlaying) return;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = audioService.currentItem?.path == widget.item.path;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── زر الحذف خلف الكرت (جهة اليمين) ──
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () {
                  _closeSwipe();
                  widget.onDelete();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _dragOffset.clamp(0.0, _revealWidth),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF3B30), Color(0xFFD32F2F)],
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
            onHorizontalDragUpdate: _onHorizontalDrag,
            onHorizontalDragEnd: _onDragEnd,
            onTap: _handleTap,
            child: Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: _buildTile(isActive),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary.withOpacity(0.07)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.primary.withOpacity(0.45)
              : AppColors.divider,
          width: active ? 1.2 : 0.6,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // ── الصورة المصغرة ──
            _buildThumbnail(active),
            const SizedBox(width: 12),

            // ── العنوان والنوع ──
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
                      fontWeight: FontWeight.w600,
                      color: active
                          ? AppColors.primary
                          : AppColors.textPrimary,
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
                            ? AppColors.primary.withOpacity(0.7)
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.item.isVideo ? 'فيديو' : 'صوت',
                        style: TextStyle(
                            fontSize: 12,
                            color: active
                                ? AppColors.primary.withOpacity(0.7)
                                : AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── زر تشغيل/إيقاف (يعمل فقط للأغنية الحالية) ──
            if (active)
              StreamBuilder<bool>(
                stream: audioService.player.playingStream,
                builder: (_, snap) {
                  final playing = snap.data ?? false;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (playing) {
                        audioService.player.pause();
                      } else {
                        audioService.player.play();
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
                            color: AppColors.primary.withOpacity(0.35),
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
              // سهم صغير للإشارة بإمكانية التشغيل
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.play_fill,
                  color: AppColors.textSecondary,
                  size: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(bool isActive) {
    final size = 52.0;
    if (_thumbPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(_thumbPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [AppColors.primary, AppColors.primaryDark]
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
        color: isActive ? Colors.white : AppColors.primary,
        size: 24,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PAGE 2 — تصفح (Browse)
// ═══════════════════════════════════════════════════════════
class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 20,
                right: 20,
                bottom: 20,
              ),
              child: const Text(
                'تصفح',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          // ── يوتيوب ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const SearchPage()),
                  );
                },
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary, // أحمر يوتيوب
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.play_rectangle_fill,
                          color: Colors.white, size: 28),
                      SizedBox(width: 10),
                      Text(
                        'يوتيوب',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
          // ── ملفات الجهاز ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const FileBrowserPage()),
                  );
                },
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.divider, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.folder_fill,
                          color: AppColors.textPrimary, size: 26),
                      SizedBox(width: 10),
                      Text(
                        'ملفات الجهاز',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  FILE BROWSER PAGE — استيراد ملفات الصوت من الجهاز
// ═══════════════════════════════════════════════════════════
class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({super.key});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  List<FileSystemEntity> _files = [];
  bool _loading = true;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _scanFiles();
  }

  Future<void> _scanFiles() async {
    setState(() => _loading = true);
    try {
      // طلب إذن الوصول إلى الوسائط
      final status = await Permission.mediaLibrary.request();
      if (!status.isGranted) {
        // على iOS نحاول مباشرة من Documents وأي مجلد متاح
      }

      final found = <FileSystemEntity>[];
      final audioExts = {'.mp3', '.m4a', '.aac', '.opus', '.flac', '.wav'};

      // المجلدات المحتملة على iOS وAndroid
      final List<Directory?> roots = [
        await getApplicationDocumentsDirectory(),
        await getTemporaryDirectory(),
      ];

      // على Android نضيف التخزين الخارجي
      try {
        final external = await getExternalStorageDirectory();
        if (external != null) roots.add(external);
      } catch (_) {}

      for (final root in roots) {
        if (root == null) continue;
        try {
          await _scanDir(root, found, audioExts);
        } catch (_) {}
      }

      // إزالة الملفات المخفية والمكررة
      final seen = <String>{};
      final unique = found.where((f) {
        final name = f.path.split('/').last;
        if (name.startsWith('.')) return false;
        if (seen.contains(f.path)) return false;
        seen.add(f.path);
        return true;
      }).toList();

      // ترتيب أبجدي
      unique.sort((a, b) => a.path.split('/').last
          .toLowerCase()
          .compareTo(b.path.split('/').last.toLowerCase()));

      if (mounted) setState(() { _files = unique; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanDir(
      Directory dir, List<FileSystemEntity> found, Set<String> exts) async {
    try {
      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final e in entities) {
        if (e is File) {
          final lower = e.path.toLowerCase();
          if (exts.any((ext) => lower.endsWith(ext))) {
            found.add(e);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _importSelected() async {
    if (_selected.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory('${dir.path}/Mustami3');
    if (!await destDir.exists()) await destDir.create(recursive: true);

    int copied = 0;
    for (final path in _selected) {
      try {
        final file = File(path);
        final name = path.split('/').last;
        final dest = File('${destDir.path}/$name');
        if (!await dest.exists()) {
          await file.copy(dest.path);
        }
        copied++;
      } catch (_) {}
    }

    _downloadCompleteNotifier.value = destDir.path;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تمت إضافة $copied ملف إلى قسم استمع',
              textDirection: TextDirection.rtl),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(
                    bottom: BorderSide(color: AppColors.divider, width: 0.5)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(CupertinoIcons.xmark,
                          size: 18, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'ملفات الجهاز',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (_selected.isNotEmpty)
                    GestureDetector(
                      onTap: _importSelected,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'إضافة (${_selected.length})',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ── Body ──
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.primary)))
                  : _files.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(CupertinoIcons.music_note_2,
                                  size: 48, color: AppColors.divider),
                              const SizedBox(height: 12),
                              const Text(
                                'لم يُعثر على ملفات صوتية',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 15),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _scanFiles,
                                child: const Text('إعادة المسح'),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: _files.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final file = _files[index];
                            final name = file.path.split('/').last;
                            final isSelected =
                                _selected.contains(file.path);
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selected.remove(file.path);
                                  } else {
                                    _selected.add(file.path);
                                  }
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.redLight
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary.withOpacity(0.4)
                                        : AppColors.divider,
                                    width: 0.8,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.surfaceAlt,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isSelected
                                          ? CupertinoIcons.checkmark_alt
                                          : CupertinoIcons.music_note,
                                      color: isSelected
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    name.replaceAll(
                                        RegExp(r'\.\w+$'), ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    name.split('.').last.toUpperCase(),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            // ── Bottom import bar ──
            if (_selected.isNotEmpty)
              Container(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  border: Border(
                      top: BorderSide(color: AppColors.divider, width: 0.5)),
                ),
                child: GestureDetector(
                  onTap: _importSelected,
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'إضافة ${_selected.length} ملف إلى قسم استمع',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SEARCH PAGE
// ─────────────────────────────────────────────
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Video> _results = [];
  bool _isSearching = false;
  String _query = '';

  final List<Map<String, String>> _categories = const [
    {'label': '🎵 موسيقى', 'query': 'موسيقى عربية'},
    {'label': '🎸 روك', 'query': 'rock music'},
    {'label': '🎤 بوب', 'query': 'pop music 2024'},
    {'label': '🎹 كلاسيك', 'query': 'classical music'},
    {'label': '🎧 لوفي', 'query': 'lofi hip hop'},
    {'label': '🕌 ديني', 'query': 'أناشيد إسلامية'},
    {'label': '🎻 عود', 'query': 'موسيقى عود'},
    {'label': '🥁 جاز', 'query': 'jazz music'},
    {'label': '🌙 هادئ', 'query': 'relaxing music'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _query = query;
      _results = [];
    });
    try {
      final searchList = await yt.search.search(query);
      final videos = searchList.whereType<Video>().take(20).toList();
      setState(() {
        _results = videos;
        _isSearching = false;
      });
      _ManifestCache.prefetchAll(videos.map((v) => v.id.value).toList(), limit: 5);
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في البحث: $e', textDirection: TextDirection.rtl),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openVideo(Video video) {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => YouTubePlayerPage(video: video)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(CupertinoIcons.xmark,
                          size: 18, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(CupertinoIcons.play_rectangle_fill,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('يوتيوب',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider, width: 0.5),
                      ),
                      child: TextField(
                        controller: _searchController,
                        textDirection: TextDirection.rtl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _search,
                        decoration: const InputDecoration(
                          hintText: 'ابحث عن فيديو...',
                          hintStyle: TextStyle(
                              color: AppColors.textSecondary, fontSize: 14),
                          prefixIcon: Icon(CupertinoIcons.search,
                              color: AppColors.textSecondary, size: 18),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => _search(_searchController.text),
                    child: Container(
                      height: 46,
                      width: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(CupertinoIcons.search,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(AppColors.primary)))
                  : _results.isEmpty
                      ? _buildHomeCategories()
                      : _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeCategories() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('اكتشف',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.2,
            ),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              return GestureDetector(
                onTap: () {
                  _searchController.text = cat['query']!;
                  _search(cat['query']!);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.redLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.2), width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    cat['label']!,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Icon(CupertinoIcons.search, size: 48, color: AppColors.divider),
                const SizedBox(height: 12),
                const Text('ابحث عن أي فيديو يوتيوب',
                    style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final video = _results[index];
        return _VideoResultCard(video: video, onTap: () => _openVideo(video));
      },
    );
  }
}

// ─────────────────────────────────────────────
//  VIDEO RESULT CARD
// ─────────────────────────────────────────────
class _VideoResultCard extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;

  const _VideoResultCard({required this.video, required this.onTap});

  void _quickDownload(BuildContext context) {
    final videoId = video.id.value;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DownloadSheet(
        videoId: videoId,
        videoTitle: video.title,
        thumbnailUrl: video.thumbnails.mediumResUrl,
        onDownload: (id, quality) =>
            _startQuickDownload(context, id, quality),
      ),
    );
  }

  Future<void> _startQuickDownload(
    BuildContext context,
    String id,
    String quality,
  ) async {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('⏳ بدء التحميل...', textDirection: TextDirection.rtl),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${dir.path}/Mustami3');
      if (!await musicDir.exists()) await musicDir.create(recursive: true);

      final safeTitle =
          video.title.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF\-]'), '').trim();
      final receivePort = ReceivePort();

      String? directUrl;
      if (_ManifestCache.isVideoCached(id)) {
        directUrl = _ManifestCache.getCachedVideo(id)!.url;
      }

      unawaited(Isolate.spawn(
        _downloadIsolate,
        _DownloadArgs(
          videoId: id,
          safeTitle: safeTitle,
          dirPath: musicDir.path,
          quality: quality,
          sendPort: receivePort.sendPort,
          directUrl: directUrl,
        ),
      ));

      await for (final msg in receivePort) {
        if (msg is Map) {
          if (msg.containsKey('done')) {
            receivePort.close();
            final fileName = msg['done'] as String;
            final savedPath = '${musicDir.path}/$fileName';
            // Save thumbnail
            await ThumbnailManager.saveThumbnail(
                savedPath, video.thumbnails.mediumResUrl);
            _downloadCompleteNotifier.value = musicDir.path;
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ تم التحميل: $fileName',
                      textDirection: TextDirection.rtl),
                  backgroundColor: Colors.green.shade700,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            }
            break;
          } else if (msg.containsKey('error')) {
            receivePort.close();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ فشل التحميل: ${msg['error']}',
                      textDirection: TextDirection.rtl),
                  backgroundColor: Colors.red,
                ),
              );
            }
            break;
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل التحميل: $e',
                textDirection: TextDirection.rtl),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbnails.mediumResUrl;
    final duration = video.duration;
    final durationStr = duration != null
        ? '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}'
        : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: thumb,
                        width: 120,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 120,
                          height: 80,
                          color: AppColors.surfaceAlt,
                          child: const Icon(CupertinoIcons.photo,
                              color: AppColors.textSecondary),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 120,
                          height: 80,
                          color: AppColors.surfaceAlt,
                          child: const Icon(CupertinoIcons.play_rectangle_fill,
                              color: AppColors.textSecondary),
                        ),
                      ),
                      if (durationStr.isNotEmpty)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(durationStr,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11)),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          video.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.redLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.play_fill,
                                  size: 10, color: AppColors.primary),
                              SizedBox(width: 4),
                              Text('تشغيل',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () => _quickDownload(context),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.redLight,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.cloud_download_fill,
                        size: 14, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text('تحميل فيديو',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Related Video Card
// ─────────────────────────────────────────────
class _RelatedVideoCard extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;

  const _RelatedVideoCard({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbnails.mediumResUrl;
    final duration = video.duration;
    final durationStr = duration != null
        ? '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}'
        : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: thumb,
                    width: 110,
                    height: 72,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 110,
                      height: 72,
                      color: AppColors.surfaceAlt,
                      child: const Icon(CupertinoIcons.play_rectangle_fill,
                          color: AppColors.textSecondary),
                    ),
                  ),
                  if (durationStr.isNotEmpty)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(durationStr,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10)),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      video.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
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
}

// ═══════════════════════════════════════════════════════════
//  YOUTUBE PLAYER PAGE
// ═══════════════════════════════════════════════════════════
class YouTubePlayerPage extends StatefulWidget {
  final Video video;
  const YouTubePlayerPage({super.key, required this.video});

  @override
  State<YouTubePlayerPage> createState() => _YouTubePlayerPageState();
}

class _YouTubePlayerPageState extends State<YouTubePlayerPage> {
  late YoutubePlayerController _controller;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String _downloadStatus = '';
  List<Video> _relatedVideos = [];

  @override
  void initState() {
    super.initState();
    final videoId = widget.video.id.value;
    _controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: false,
        forceHD: false,
      ),
    );
    _ManifestCache.get(videoId).catchError((_) {});
    _loadRelated();
  }

  Future<void> _loadRelated() async {
    try {
      final results = await yt.search.search(widget.video.author);
      if (mounted) {
        setState(() {
          _relatedVideos = results
              .whereType<Video>()
              .where((v) => v.id.value != widget.video.id.value)
              .take(10)
              .toList();
        });
        _ManifestCache.prefetchAll(
          _relatedVideos.map((v) => v.id.value).toList(),
          limit: 3,
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showDownloadOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DownloadSheet(
        videoId: widget.video.id.value,
        videoTitle: widget.video.title,
        thumbnailUrl: widget.video.thumbnails.mediumResUrl,
        onDownload: _download,
      ),
    );
  }

  Future<void> _download(String videoId, String quality) async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadStatus = 'بدء التحميل...';
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${dir.path}/Mustami3');
      if (!await musicDir.exists()) await musicDir.create(recursive: true);

      final safeTitle = widget.video.title
          .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF\-]'), '')
          .trim();

      String? directUrl;
      if (_ManifestCache.isVideoCached(videoId)) {
        directUrl = _ManifestCache.getCachedVideo(videoId)!.url;
      }

      final receivePort = ReceivePort();
      unawaited(Isolate.spawn(
        _downloadIsolate,
        _DownloadArgs(
          videoId: videoId,
          safeTitle: safeTitle,
          dirPath: musicDir.path,
          quality: quality,
          sendPort: receivePort.sendPort,
          directUrl: directUrl,
        ),
      ));

      if (mounted) setState(() => _downloadStatus = 'جاري التحميل...');

      await for (final msg in receivePort) {
        if (msg is Map) {
          if (msg.containsKey('progress')) {
            final p = (msg['progress'] as double).clamp(0.0, 1.0);
            if (mounted) {
              setState(() {
                _downloadProgress = p;
                _downloadStatus =
                    'جاري التحميل... ${(p * 100).toStringAsFixed(0)}%';
              });
            }
          } else if (msg.containsKey('done')) {
            receivePort.close();
            final fileName = msg['done'] as String;
            final savedPath = '${musicDir.path}/$fileName';
            // Save thumbnail
            await ThumbnailManager.saveThumbnail(
                savedPath, widget.video.thumbnails.mediumResUrl);
            if (mounted) {
              setState(() {
                _isDownloading = false;
                _downloadStatus = '';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ تم التحميل: $fileName',
                      textDirection: TextDirection.rtl),
                  backgroundColor: Colors.green.shade700,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
              _downloadCompleteNotifier.value = musicDir.path;
            }
            break;
          } else if (msg.containsKey('error')) {
            receivePort.close();
            throw Exception(msg['error']);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل التحميل: $e',
                textDirection: TextDirection.rtl),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: AppColors.primary,
        progressColors: const ProgressBarColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primaryDark,
        ),
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(CupertinoIcons.xmark,
                  color: AppColors.textPrimary),
            ),
            title: const Text(
              'مشاهدة الفيديو',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            actions: [
              GestureDetector(
                onTap: _isDownloading ? null : _showDownloadOptions,
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _isDownloading
                        ? AppColors.surfaceAlt
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _isDownloading
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: _downloadProgress > 0
                                    ? _downloadProgress
                                    : null,
                                valueColor: const AlwaysStoppedAnimation(
                                    AppColors.primary),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.cloud_download_fill,
                                color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text('تحميل',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              player,
              if (_isDownloading)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  color: AppColors.redLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _downloadStatus,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _downloadProgress > 0
                              ? _downloadProgress
                              : null,
                          backgroundColor: Colors.white,
                          valueColor: const AlwaysStoppedAnimation(
                              AppColors.primary),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.video.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.redLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                                CupertinoIcons.person_circle_fill,
                                color: AppColors.primary,
                                size: 18),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.video.author,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      if (_relatedVideos.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'فيديوهات مشابهة',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._relatedVideos.map(
                          (v) => _RelatedVideoCard(
                            video: v,
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                CupertinoPageRoute(
                                  builder: (_) =>
                                      YouTubePlayerPage(video: v),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  ★ Download Bottom Sheet — Video Only
// ─────────────────────────────────────────────
class _DownloadSheet extends StatelessWidget {
  final String videoId;
  final String videoTitle;
  final String thumbnailUrl;
  final Function(String, String) onDownload; // (id, quality) — no audioOnly

  const _DownloadSheet({
    required this.videoId,
    required this.videoTitle,
    required this.thumbnailUrl,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isCached = _ManifestCache.isCached(videoId);
    final isVideoCached = _ManifestCache.isVideoCached(videoId);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Thumbnail preview
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: thumbnailUrl,
              width: 120,
              height: 80,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: 120,
                height: 80,
                color: AppColors.redLight,
                child: const Icon(CupertinoIcons.cloud_download_fill,
                    color: AppColors.primary, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'تحميل الفيديو',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            videoTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (isVideoCached || isCached)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isVideoCached ? Colors.green : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isVideoCached ? 'جاهز للتحميل الفوري ⚡' : 'جاهز للتحميل',
                    style: TextStyle(
                        fontSize: 11,
                        color: isVideoCached ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          _downloadBtn(
            context: context,
            icon: '📹',
            label: 'فيديو جودة عالية',
            subtitle: 'أعلى جودة متاحة',
            onTap: () {
              Navigator.pop(context);
              onDownload(videoId, 'high');
            },
          ),
          const SizedBox(height: 10),
          _downloadBtn(
            context: context,
            icon: '📱',
            label: 'فيديو 360p',
            subtitle: 'جودة متوسطة - حجم أصغر',
            onTap: () {
              Navigator.pop(context);
              onDownload(videoId, 'medium');
            },
          ),
        ],
      ),
    );
  }

  Widget _downloadBtn({
    required BuildContext context,
    required String icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_left,
                size: 14, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PAGE 3 — الإعدادات
// ═══════════════════════════════════════════════════════════
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
      _downloadPath = '${dir.path}/Mustami3';
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
      ThumbnailManager._memCache.clear();
      _downloadCompleteNotifier.value = _downloadPath;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                      const Text(
                        'الإعدادات',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(CupertinoIcons.music_note_2,
                                  color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 14),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('مستمع',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700)),
                                Text('الإصدار 2.1.0',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          ],
                        ),
                      ),
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
                      _settingsSection('التحميل', [
                        _infoTile(
                            'مسار التحميل',
                            _downloadPath.split('/').last,
                            CupertinoIcons.folder_fill),
                        _qualityTile(),
                      ]),
                      const SizedBox(height: 16),
                      _settingsSection('الإدارة', [
                        _actionTile(
                          'حذف جميع التنزيلات',
                          'مسح كل الملفات المحملة',
                          CupertinoIcons.trash_fill,
                          Colors.red,
                          _clearDownloads,
                        ),
                      ]),
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
  }

  Widget _settingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider, width: 0.5),
          ),
          child: Column(
            children: children.map((child) {
              final index = children.indexOf(child);
              return Column(
                children: [
                  child,
                  if (index < children.length - 1)
                    const Divider(
                        height: 1,
                        color: AppColors.divider,
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
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.redLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing:
          CupertinoSwitch(value: value, onChanged: onChanged, activeColor: AppColors.primary),
    );
  }

  Widget _infoTile(String title, String value, IconData icon) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.redLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary)),
      trailing: Text(value,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
    );
  }

  Widget _qualityTile() {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.redLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(CupertinoIcons.dial_fill,
            color: AppColors.primary, size: 18),
      ),
      title: const Text('جودة التحميل',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary)),
      trailing: CupertinoSlidingSegmentedControl<String>(
        groupValue: _downloadQuality,
        thumbColor: AppColors.primary,
        children: const {
          'high': Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('عالية', style: TextStyle(fontSize: 11))),
          'medium': Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('متوسطة', style: TextStyle(fontSize: 11))),
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
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
              fontSize: 14, fontWeight: FontWeight.w500, color: color)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      onTap: onTap,
    );
  }
}