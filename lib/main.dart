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

// ─────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.mustami3.audio',
    androidNotificationChannelName: 'دندن',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  // تحميل الثيم المحفوظ أولاً
  await ThemeNotifier.instance.load();

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
  // Light
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7F7F7);
  static const Color surfaceAlt = Color(0xFFEEEEEE);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color divider = Color(0xFFE0E0E0);
  static const Color redLight = Color(0xFFFFEBEB);
  // Dark
  static const Color darkBg = Color(0xFF0D0D0D);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceAlt = Color(0xFF2C2C2E);
  static const Color darkText = Color(0xFFF2F2F7);
  static const Color darkTextSec = Color(0xFF8E8E93);
  static const Color darkDivider = Color(0xFF38383A);
  static const Color darkRedLight = Color(0xFF3A1212);
}

// ─────────────────────────────────────────────
//  THEME NOTIFIER — persistent dark mode
// ─────────────────────────────────────────────
class ThemeNotifier extends ValueNotifier<ThemeMode> {
  ThemeNotifier._() : super(ThemeMode.light);
  static final ThemeNotifier instance = ThemeNotifier._();

  bool get isDark => value == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = (prefs.getBool('darkMode') ?? false)
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  Future<void> toggle(bool dark) async {
    value = dark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', dark);
  }
}

// ─────────────────────────────────────────────
//  CONTEXT HELPERS — pick color by theme
// ─────────────────────────────────────────────
extension AppTheme on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get appBg => isDark ? AppColors.darkBg : AppColors.background;
  Color get appSurface => isDark ? AppColors.darkSurface : AppColors.surface;
  Color get appSurfaceAlt => isDark ? AppColors.darkSurfaceAlt : AppColors.surfaceAlt;
  Color get appText => isDark ? AppColors.darkText : AppColors.textPrimary;
  Color get appTextSec => isDark ? AppColors.darkTextSec : AppColors.textSecondary;
  Color get appDivider => isDark ? AppColors.darkDivider : AppColors.divider;
  Color get appRedLight => isDark ? AppColors.darkRedLight : AppColors.redLight;
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

  static void invalidate(String mediaPath) {
    _memCache.remove(mediaPath);
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
//  AUDIO PLAYER SERVICE — Singleton (Rebuilt)
// ─────────────────────────────────────────────
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  // ── المشغل مع pipeline لتضخيم الصوت الحقيقي ──
  late final AudioPlayer player = AudioPlayer(
    audioPipeline: AudioPipeline(
      androidAudioEffects: [
        _loudnessEnhancer = AndroidLoudnessEnhancer(),
      ],
    ),
  );
  late final AndroidLoudnessEnhancer _loudnessEnhancer;

  final ValueNotifier<List<LocalMediaItem>> playlist = ValueNotifier([]);
  final ValueNotifier<int> currentIndex = ValueNotifier(-1);
  final ValueNotifier<bool> isVisible = ValueNotifier(false);

  ConcatenatingAudioSource? _concatenating;

  // ── مفتاح تجاهل تحديثات الـ stream أثناء العمليات اليدوية ──
  bool _ignoreStreamUpdates = false;
  Timer? _ignoreTimer;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // نتابع currentIndexStream فقط لتحديثات شاشة القفل / سماعات البلوتوث
    // ونتجاهل التحديثات أثناء عمليات seek/setAudioSource اليدوية
    player.currentIndexStream.listen((streamIndex) {
      if (_ignoreStreamUpdates) return;
      if (streamIndex == null) return;
      final list = playlist.value;
      if (streamIndex >= 0 && streamIndex < list.length) {
        if (streamIndex != currentIndex.value) {
          currentIndex.value = streamIndex;
          isVisible.value = true;
        }
      }
    });

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

  /// يمنع stream من التدخل لمدة [ms] ميلي ثانية
  void _lockStream([int ms = 800]) {
    _ignoreStreamUpdates = true;
    _ignoreTimer?.cancel();
    _ignoreTimer = Timer(Duration(milliseconds: ms), () {
      _ignoreStreamUpdates = false;
    });
  }

  /// يبني ConcatenatingAudioSource من قائمة الملفات المحلية
  ConcatenatingAudioSource _buildSource(List<LocalMediaItem> items) {
    return ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: items.map((item) {
        final localThumbPath = item.thumbnailCachePath;
        Uri? artUri;
        if (File(localThumbPath).existsSync()) {
          artUri = Uri.file(localThumbPath);
        } else if (item.thumbnailUrl != null) {
          artUri = Uri.parse(item.thumbnailUrl!);
        }
        return AudioSource.file(
          item.path,
          tag: MediaItem(
            id: item.path,
            title: item.title.replaceAll(RegExp(r'\.\w+$'), ''),
            artist: 'دندن',
            artUri: artUri,
          ),
        );
      }).toList(),
    );
  }

  /// تحديث MediaItem للعنصر الحالي بعد حفظ الصورة المحلية
  Future<void> updateCurrentArtwork() async {
    final idx = currentIndex.value;
    final list = playlist.value;
    if (idx < 0 || idx >= list.length || _concatenating == null) return;
    final item = list[idx];
    final localThumbPath = await ThumbnailManager.getLocalThumbnail(item.path);
    Uri? artUri;
    if (localThumbPath != null) {
      artUri = Uri.file(localThumbPath);
    } else if (item.thumbnailUrl != null) {
      artUri = Uri.parse(item.thumbnailUrl!);
    }
    try {
      final newTag = MediaItem(
        id: item.path,
        title: item.title.replaceAll(RegExp(r'\.\w+$'), ''),
        artist: 'دندن',
        artUri: artUri,
      );
      await _concatenating!.removeAt(idx);
      await _concatenating!.insert(idx, AudioSource.file(item.path, tag: newTag));
    } catch (_) {}
  }

  /// تشغيل قائمة كاملة ابتداءً من index معيّن — الدالة الأساسية
  Future<void> playList(List<LocalMediaItem> items, int startIndex) async {
    if (items.isEmpty) return;
    final targetIndex = startIndex.clamp(0, items.length - 1);

    // ① احجب الـ stream فوراً قبل أي عملية
    _lockStream(1200);

    // ② اضبط القيم المحلية بشكل نهائي
    playlist.value = List.unmodifiable(items);
    currentIndex.value = targetIndex;
    isVisible.value = true;

    // ③ ابنِ المصدر الجديد
    _concatenating = _buildSource(items);

    try {
      await player.setAudioSource(
        _concatenating!,
        initialIndex: targetIndex,
        initialPosition: Duration.zero,
        preload: false,
      );

      // ④ أعد الضبط بعد setAudioSource (قد يُعيد الـ stream تغييره)
      _lockStream(800);
      currentIndex.value = targetIndex;

      await player.play();
      updateCurrentArtwork();
    } catch (e) {
      debugPrint('AudioPlayerService.playList error: $e');
    }
  }

  /// الانتقال إلى index في القائمة الحالية (للنقر من داخل المشغل أو القائمة)
  Future<void> playAtIndex(int index) async {
    final list = playlist.value;
    if (index < 0 || index >= list.length) return;

    if (_concatenating != null && _concatenating!.length == list.length) {
      // ① احجب الـ stream
      _lockStream(1000);

      // ② اضبط currentIndex فوراً — هذا يُحدّث UI على الفور
      currentIndex.value = index;

      try {
        // ③ انتقل للمسار المطلوب
        await player.seek(Duration.zero, index: index);

        // ④ أعد التأكيد بعد seek
        _lockStream(600);
        currentIndex.value = index;

        await player.play();
        isVisible.value = true;
        updateCurrentArtwork();
        return;
      } catch (_) {}
    }

    // إعادة البناء الكامل إن لزم
    await playList(list, index);
  }

  Future<void> playNext() async {
    final idx = currentIndex.value;
    final list = playlist.value;
    if (idx < list.length - 1) {
      _lockStream(800);
      currentIndex.value = idx + 1;
      await player.seekToNext();
    }
  }

  Future<void> playPrevious() async {
    final pos = player.position;
    if (pos.inSeconds > 3) {
      await player.seek(Duration.zero);
    } else {
      final idx = currentIndex.value;
      if (idx > 0) {
        _lockStream(800);
        currentIndex.value = idx - 1;
      }
      await player.seekToPrevious();
    }
  }

  /// ضبط مستوى الصوت — يدعم 0% إلى 300% بتضخيم حقيقي
  /// 0-100% → setVolume(0.0-1.0) فقط
  /// 101-300% → setVolume(1.0) + LoudnessEnhancer
  void setVolumeBoost(double normalizedValue) {
    // normalizedValue: 0.0 إلى 3.0 (يمثل 0% إلى 300%)
    final v = normalizedValue.clamp(0.0, 3.0);
    if (v <= 1.0) {
      player.setVolume(v);
      try { _loudnessEnhancer.setTargetGain(0); } catch (_) {}
    } else {
      player.setVolume(1.0);
      // LoudnessEnhancer: targetGain بالـ mB (milli-Bels)
      // كل 100mB ≈ رفع ملحوظ في الصوت
      // v=2.0 → gain=800mB, v=3.0 → gain=1600mB
      final gainMB = ((v - 1.0) * 800.0);
      try { _loudnessEnhancer.setTargetGain(gainMB); } catch (_) {}
    }
  }

  LocalMediaItem? get currentItem {
    final idx = currentIndex.value;
    final list = playlist.value;
    if (idx < 0 || idx >= list.length) return null;
    return list[idx];
  }

  void dispose() {
    _ignoreTimer?.cancel();
    player.dispose();
  }
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

  static ThemeData _light() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Tajawal',
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
        dividerColor: AppColors.divider,
      );

  static ThemeData _dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Tajawal',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: AppColors.darkBg,
        cardColor: AppColors.darkSurface,
        dividerColor: AppColors.darkDivider,
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (_, mode, __) => MaterialApp(
        title: 'دندن',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: _light(),
        darkTheme: _dark(),
        home: const MainShell(),
        builder: (ctx, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      ),
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
  static const List<Widget> _pages = [
    ListenPage(),
    BrowsePage(),
    SettingsPage(),
  ];

  int _currentIndex = 0;

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

  void _onNavChange() {
    final next = _navIndexNotifier.value;
    if (next == _currentIndex) return;
    _currentIndex = next;
    setState(() {});
  }

  void _onSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final cur = _navIndexNotifier.value;
    if (v < -350 && cur > 0) {
      _navIndexNotifier.value = cur - 1;
    } else if (v > 350 && cur < 2) {
      _navIndexNotifier.value = cur + 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: GestureDetector(
        onHorizontalDragEnd: _onSwipe,
        child: Stack(children: [
          // ─ الصفحات بدون انيميشن ─
          IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          // ─ Mini Player + Bottom Nav ─
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _BottomArea(),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  BOTTOM AREA: Mini Player + Glass Nav Bar
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
        // Glass Nav Bar
        const _GlassNavBar(),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  GLASS NAV BAR — iOS Floating Glass Style
// ─────────────────────────────────────────────
class _GlassNavBar extends StatefulWidget {
  const _GlassNavBar();
  @override
  State<_GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<_GlassNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _indicatorCtrl;
  int _prevIndex = 0;

  static const List<_NavTabData> _tabs = [
    _NavTabData(icon: CupertinoIcons.music_note_2, label: 'استمع'),
    _NavTabData(icon: CupertinoIcons.search, label: 'تصفح'),
    _NavTabData(icon: CupertinoIcons.settings, label: 'الإعدادات'),
  ];

  @override
  void initState() {
    super.initState();
    _indicatorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _navIndexNotifier.addListener(_onNavChange);
  }

  @override
  void dispose() {
    _navIndexNotifier.removeListener(_onNavChange);
    _indicatorCtrl.dispose();
    super.dispose();
  }

  void _onNavChange() {
    if (_prevIndex != _navIndexNotifier.value) {
      _indicatorCtrl.forward(from: 0.0);
      _prevIndex = _navIndexNotifier.value;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final idx = _navIndexNotifier.value;

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: bottomPadding > 0 ? bottomPadding + 6 : 14,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              // زجاج شفاف حقيقي
              color: isDark
                  ? Colors.black.withOpacity(0.30)
                  : Colors.white.withOpacity(0.28),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.10)
                    : Colors.white.withOpacity(0.75),
                width: 1.2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withOpacity(0.08),
                        Colors.white.withOpacity(0.02),
                      ]
                    : [
                        Colors.white.withOpacity(0.60),
                        Colors.white.withOpacity(0.20),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(isDark ? 0.18 : 0.08),
                  blurRadius: 32,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(isDark ? 0.04 : 0.50),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: LayoutBuilder(builder: (ctx, constraints) {
              final tabWidth = constraints.maxWidth / _tabs.length;
              return Stack(alignment: Alignment.center, children: [
                // ── Animated Red Indicator Pill ──
                // RTL: tab 0 (استمع) في أقصى اليمين
                // right = idx * tabWidth يضع الـ indicator عند التبويب الصحيح
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  right: idx * tabWidth + tabWidth * 0.12,
                  top: 8,
                  bottom: 8,
                  width: tabWidth * 0.76,
                  child: AnimatedBuilder(
                    animation: _indicatorCtrl,
                    builder: (_, __) {
                      final s = Tween<double>(begin: 0.82, end: 1.0)
                          .animate(CurvedAnimation(
                              parent: _indicatorCtrl,
                              curve: Curves.easeOutBack))
                          .value;
                      return Transform.scale(
                        scale: s,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withOpacity(0.18),
                                AppColors.primaryDark.withOpacity(0.10),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.30),
                              width: 0.8,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── Tab Buttons ──
                Row(
                  children: List.generate(_tabs.length, (i) {
                    final tab = _tabs[i];
                    final isSelected = i == idx;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _navIndexNotifier.value = i,
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedScale(
                              scale: isSelected ? 1.2 : 1.0,
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutBack,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                child: i == 0
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.asset(
                                          'assets/images/logo.png',
                                          width: 22,
                                          height: 22,
                                          fit: BoxFit.cover,
                                          color: isSelected ? null : (isDark ? Colors.white38 : AppColors.textSecondary),
                                          colorBlendMode: isSelected ? null : BlendMode.srcIn,
                                          errorBuilder: (_, __, ___) => Icon(
                                            tab.icon,
                                            size: 22,
                                            color: isSelected
                                                ? AppColors.primary
                                                : (isDark ? Colors.white38 : AppColors.textSecondary),
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        tab.icon,
                                        size: 22,
                                        color: isSelected
                                            ? AppColors.primary
                                            : (isDark
                                                ? Colors.white38
                                                : AppColors.textSecondary),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: isSelected
                                    ? AppColors.primary
                                    : (isDark
                                        ? Colors.white38
                                        : AppColors.textSecondary),
                              ),
                              child: Text(tab.label),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class _NavTabData {
  final IconData icon;
  final String label;
  const _NavTabData({required this.icon, required this.label});
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
            color: context.isDark
                ? const Color(0xFF1C1C1E)
                : const Color(0xFF2C2C2E),
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
  VideoPlayerController? _videoCtrl;
  bool _videoInitialized = false;
  double _volume = 1.0;
  double _speed = 1.0;

  // عناصر تحكم الفيديو — تظهر عند النقر وتختفي بعد 5 ثوانٍ
  bool _showVideoControls = false;
  Timer? _hideControlsTimer;

  // For smooth slider dragging
  bool _dragging = false;
  double _dragValue = 0.0;

  // نتابع الـ streams حتى نُلغيها عند dispose
  StreamSubscription? _positionSub;
  StreamSubscription? _playingSub;

  @override
  void initState() {
    super.initState();
    _loadThumb();
    _initVideoIfNeeded();
    audioService.currentIndex.addListener(_onTrackChange);
  }

  @override
  void dispose() {
    audioService.currentIndex.removeListener(_onTrackChange);
    _hideControlsTimer?.cancel();
    _positionSub?.cancel();
    _playingSub?.cancel();
    // نوقف الفيديو المرئي فقط — الصوت يستمر عبر just_audio في الخلفية
    _videoCtrl?.pause();
    _videoCtrl?.dispose();
    super.dispose();
  }

  void _onTrackChange() {
    _loadThumb();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _videoCtrl?.pause();
    _videoCtrl?.dispose();
    _videoCtrl = null;
    if (mounted) setState(() { _videoInitialized = false; _showVideoControls = false; });
    _initVideoIfNeeded();
  }

  Future<void> _initVideoIfNeeded() async {
    final item = audioService.currentItem;
    if (item == null || !item.isVideo) return;

    // VideoPlayerController بدون صوت — الصوت يأتي من just_audio
    final ctrl = VideoPlayerController.file(File(item.path));
    try {
      await ctrl.initialize();
      // أوقف صوت video_player تماماً — الصوت يأتي من just_audio
      await ctrl.setVolume(0.0);
      // مزامنة الموضع مع just_audio
      final pos = audioService.player.position;
      await ctrl.seekTo(pos);
      final playing = audioService.player.playing;
      if (playing) await ctrl.play();
      if (mounted) {
        setState(() {
          _videoCtrl = ctrl;
          _videoInitialized = true;
        });
      }
      // مزامنة الموقف مستمرة
      _positionSub = audioService.player.positionStream.listen((pos) {
        if (_videoCtrl != null && _videoInitialized && !_dragging) {
          final diff = (ctrl.value.position - pos).abs();
          if (diff.inMilliseconds > 500) {
            ctrl.seekTo(pos);
          }
        }
      });
      // مزامنة التشغيل/الإيقاف
      _playingSub = audioService.player.playingStream.listen((playing) {
        if (_videoCtrl != null && _videoInitialized) {
          if (playing) {
            ctrl.play();
          } else {
            ctrl.pause();
          }
        }
      });
    } catch (_) {
      ctrl.dispose();
    }
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

  void _setVolume(double v) {
    final clamped = v.clamp(0.0, 3.0);
    setState(() => _volume = clamped);
    audioService.setVolumeBoost(clamped);
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    audioService.player.setSpeed(s);
    _videoCtrl?.setPlaybackSpeed(s);
  }

  // إظهار/إخفاء عناصر التحكم عند النقر على الفيديو
  void _toggleVideoControls() {
    setState(() => _showVideoControls = !_showVideoControls);
    _hideControlsTimer?.cancel();
    if (_showVideoControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showVideoControls = false);
      });
    }
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showVideoControls = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF2F2F7);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final controlBg = isDark ? Colors.white12 : Colors.black.withOpacity(0.07);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // سحب يمين لإغلاق المشغل
        if ((details.primaryVelocity ?? 0) > 400) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      backgroundColor: bgColor,
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
                        color: controlBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(CupertinoIcons.chevron_down,
                          color: textColor, size: 20),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'يُشغَّل الآن',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 36),
                ],
              ),
            ),

            // ── Video / Artwork ──
            Expanded(
              flex: 5,
              child: ValueListenableBuilder<int>(
                valueListenable: audioService.currentIndex,
                builder: (_, idx, __) {
                  final item = audioService.currentItem;
                  // إذا كان الملف فيديو وتم تهيئة المشغل
                  if (item != null && item.isVideo && _videoInitialized && _videoCtrl != null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: GestureDetector(
                          onTap: _toggleVideoControls,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // الفيديو
                              AspectRatio(
                                aspectRatio: _videoCtrl!.value.aspectRatio,
                                child: VideoPlayer(_videoCtrl!),
                              ),
                              // طبقة التحكم المتلاشية
                              AnimatedOpacity(
                                opacity: _showVideoControls ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 250),
                                child: IgnorePointer(
                                  ignoring: !_showVideoControls,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.3),
                                          Colors.black.withOpacity(0.7),
                                        ],
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        // أزرار السابق/تشغيل/التالي
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            GestureDetector(
                                              onTap: () { audioService.playNext(); _resetHideTimer(); },
                                              child: Container(
                                                width: 48, height: 48,
                                                decoration: BoxDecoration(
                                                  color: Colors.black45,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(CupertinoIcons.forward_end_fill, color: Colors.white, size: 22),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            StreamBuilder<bool>(
                                              stream: audioService.player.playingStream,
                                              builder: (_, snap) {
                                                final playing = snap.data ?? false;
                                                return GestureDetector(
                                                  onTap: () {
                                                    playing ? audioService.player.pause() : audioService.player.play();
                                                    _resetHideTimer();
                                                  },
                                                  child: Container(
                                                    width: 64, height: 64,
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary,
                                                      shape: BoxShape.circle,
                                                      boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 16)],
                                                    ),
                                                    child: Icon(
                                                      playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                                                      color: Colors.white, size: 28,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 16),
                                            GestureDetector(
                                              onTap: () { audioService.playPrevious(); _resetHideTimer(); },
                                              child: Container(
                                                width: 48, height: 48,
                                                decoration: BoxDecoration(
                                                  color: Colors.black45,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(CupertinoIcons.backward_end_fill, color: Colors.white, size: 22),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        // التحكم بالصوت والسرعة
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          child: Column(
                                            children: [
                                              // الصوت
                                              Row(
                                                children: [
                                                  Icon(
                                                    _volume == 0 ? CupertinoIcons.speaker_slash_fill :
                                                    _volume < 1.0 ? CupertinoIcons.speaker_1_fill :
                                                    CupertinoIcons.speaker_3_fill,
                                                    color: Colors.white70, size: 16,
                                                  ),
                                                  Expanded(
                                                    child: SliderTheme(
                                                      data: SliderThemeData(
                                                        trackHeight: 2,
                                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                                        activeTrackColor: AppColors.primary,
                                                        inactiveTrackColor: Colors.white24,
                                                        thumbColor: Colors.white,
                                                        overlayColor: Colors.white24,
                                                      ),
                                                      child: Slider(
                                                        value: _volume,
                                                        min: 0, max: 3.0,
                                                        onChanged: (v) { _setVolume(v); _resetHideTimer(); },
                                                      ),
                                                    ),
                                                  ),
                                                  Text('${(_volume * 100).toInt()}%',
                                                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Tajawal'),
                                                  ),
                                                ],
                                              ),
                                              // السرعة
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  const Icon(CupertinoIcons.speedometer, color: Colors.white54, size: 13),
                                                  const SizedBox(width: 6),
                                                  for (final s in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                                                    GestureDetector(
                                                      onTap: () { _setSpeed(s); _resetHideTimer(); },
                                                      child: Container(
                                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: _speed == s ? AppColors.primary : Colors.black45,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          s == 1.0 ? '1×' : '${s}×',
                                                          style: TextStyle(
                                                            color: _speed == s ? Colors.white : Colors.white70,
                                                            fontSize: 10, fontFamily: 'Tajawal', fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                            ],
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
                      ),
                    );
                  }
                  // صوت أو فيديو بدون تهيئة — اعرض الصورة المصغرة
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
                              style: TextStyle(
                                color: textColor,
                                fontSize: 20,
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'دندن',
                              style: TextStyle(
                                  color: subColor, fontSize: 14, fontFamily: 'Tajawal'),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // ── Progress Slider (smooth drag) ──
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
                            final displayProgress = _dragging ? _dragValue : progress;
                            return Column(
                              children: [
                                SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 5,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 10),
                                    overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 20),
                                    activeTrackColor: AppColors.primary,
                                    inactiveTrackColor: isDark ? Colors.white24 : Colors.black12,
                                    thumbColor: AppColors.primary,
                                    overlayColor: AppColors.primary.withOpacity(0.2),
                                  ),
                                  child: Slider(
                                    value: displayProgress.clamp(0.0, 1.0),
                                    onChangeStart: (val) {
                                      setState(() {
                                        _dragging = true;
                                        _dragValue = val;
                                      });
                                    },
                                    onChanged: (val) {
                                      setState(() => _dragValue = val);
                                    },
                                    onChangeEnd: (val) {
                                      setState(() => _dragging = false);
                                      final ms = (val * duration.inMilliseconds).toInt();
                                      audioService.player.seek(Duration(milliseconds: ms));
                                      _videoCtrl?.seekTo(Duration(milliseconds: ms));
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(_fmt(_dragging
                                          ? Duration(milliseconds: (_dragValue * duration.inMilliseconds).toInt())
                                          : position),
                                          style: TextStyle(color: subColor, fontSize: 12)),
                                      Text(_fmt(duration),
                                          style: TextStyle(color: subColor, fontSize: 12)),
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
                                  : controlBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.repeat,
                              color: _isRepeat
                                  ? AppColors.primary
                                  : subColor,
                              size: 20,
                            ),
                          ),
                        ),
                        // ── التالي → ──
                        GestureDetector(
                          onTap: () => audioService.playNext(),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: controlBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.forward_end_fill,
                              color: textColor,
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
                        // ── السابق ← ──
                        GestureDetector(
                          onTap: () => audioService.playPrevious(),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: controlBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.backward_end_fill,
                              color: textColor,
                              size: 26,
                            ),
                          ),
                        ),
                        // Shuffle
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: controlBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.shuffle,
                            color: subColor,
                            size: 20,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ── Volume & Speed Controls (للصوت فقط — الفيديو له تحكم داخلي) ──
                    if (!(_videoInitialized && _videoCtrl != null)) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Volume icon
                        Icon(
                          _volume == 0 ? CupertinoIcons.speaker_slash_fill :
                          _volume < 1.0 ? CupertinoIcons.speaker_1_fill :
                          CupertinoIcons.speaker_3_fill,
                          color: subColor, size: 18,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              activeTrackColor: AppColors.primary.withOpacity(0.8),
                              inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
                              thumbColor: AppColors.primary,
                              overlayColor: AppColors.primary.withOpacity(0.15),
                            ),
                            child: Slider(
                              value: _volume,
                              min: 0,
                              max: 3.0,
                              onChanged: _setVolume,
                            ),
                          ),
                        ),
                        Text(
                          '${(_volume * 100).toInt()}%',
                          style: TextStyle(color: subColor, fontSize: 11, fontFamily: 'Tajawal'),
                        ),
                      ],
                    ),

                    // Speed control row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.speedometer, color: subColor, size: 16),
                        const SizedBox(width: 8),
                        for (final s in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                          GestureDetector(
                            onTap: () => _setSpeed(s),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _speed == s
                                    ? AppColors.primary
                                    : controlBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                s == 1.0 ? '1×' : '${s}×',
                                style: TextStyle(
                                  color: _speed == s ? Colors.white : subColor,
                                  fontSize: 11,
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    ], // end if audio-only

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
                    child: Text(
                      'قائمة التشغيل',
                      style: TextStyle(
                        color: subColor,
                        fontSize: 13,
                        fontFamily: 'Tajawal',
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
                                              : subColor,
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
                                                  : textColor.withOpacity(0.7),
                                              fontSize: 13,
                                              fontFamily: 'Tajawal',
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
        _downloadDir = musicDir.path;
        _localItems = items;
      });
    }

    // توليد صور مصغرة للفيديوات التي ليس لها صورة بعد
    for (final item in items) {
      if (!item.isVideo) continue;
      final existing = await ThumbnailManager.getLocalThumbnail(item.path);
      if (existing != null) continue;
      _generateVideoThumbnail(item.path);
    }
  }

  Future<void> _generateVideoThumbnail(String videoPath) async {
    // video_player لا يوفر screenshot API مباشرة
    // للحصول على صور مصغرة حقيقية يُنصح بإضافة package:video_thumbnail
    // في الوقت الحالي نتأكد أن الملف موجود ونعيد التحقق من الصور المحفوظة مسبقاً
    final existing = await ThumbnailManager.getLocalThumbnail(videoPath);
    if (existing != null && mounted) {
      setState(() {}); // أعد البناء لعرض الصورة
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

  // السحب للجهة اليسرى (سالب) فقط في RTL
  void _onHorizontalDrag(DragUpdateDetails details) {
    setState(() {
      _dragOffset =
          (_dragOffset - details.delta.dx).clamp(0.0, _revealWidth);
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
              alignment: Alignment.centerLeft,
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
              // ① نحفظ القيم محلياً بشكل غير قابل للتغيير
              final int targetIndex = widget.index;
              final List<LocalMediaItem> targetList =
                  List<LocalMediaItem>.unmodifiable(widget.allItems);

              // ② نحدد currentIndex مباشرة قبل أي عملية async
              //    هذا يمنع الـ stream من تغييره
              audioService.currentIndex.value = targetIndex;

              // ③ نشغّل القائمة دائماً بـ playList لضمان الـ index الصحيح
              //    حتى لو القائمة نفسها، نُعيد بناء المصدر مع الـ index المحدد
              audioService.playList(targetList, targetIndex);

              // ④ نفتح المشغل — currentIndex محدد مسبقاً، لا يوجد تعارض
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary.withOpacity(0.07)
            : (isDark ? AppColors.darkSurface : AppColors.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.primary.withOpacity(0.45)
              : (isDark ? AppColors.darkDivider : AppColors.divider),
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
                  color: Colors.black.withOpacity(isDark ? 0.20 : 0.04),
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
                            ? AppColors.primary.withOpacity(0.7)
                            : (isDark ? AppColors.darkTextSec : AppColors.textSecondary),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.item.isVideo ? 'فيديو' : 'صوت',
                        style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 12,
                            color: active
                                ? AppColors.primary.withOpacity(0.7)
                                : (isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
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
      backgroundColor: context.appBg,
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
              child: Text(
                'تصفح',
                style: TextStyle(
                  fontSize: 28,
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w700,
                  color: context.appText,
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
                    color: context.appSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.appDivider, width: 0.8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.folder_fill,
                          color: context.appText, size: 26),
                      const SizedBox(width: 10),
                      Text(
                        'ملفات الجهاز',
                        style: TextStyle(
                          color: context.appText,
                          fontFamily: 'Tajawal',
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
//  FILE BROWSER PAGE — استيراد ملفات الصوت والفيديو من الجهاز
// ═══════════════════════════════════════════════════════════
class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({super.key});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  List<PlatformFile> _pickedFiles = [];
  bool _importing = false;

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'aac', 'opus', 'flac', 'wav', 'mp4', 'mkv', 'webm', 'mov'],
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() => _pickedFiles = result.files);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في فتح الملفات: $e', textDirection: TextDirection.rtl),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importSelected() async {
    if (_pickedFiles.isEmpty) return;
    setState(() => _importing = true);
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory('${dir.path}/dndn');
    if (!await destDir.exists()) await destDir.create(recursive: true);

    int copied = 0;
    for (final file in _pickedFiles) {
      if (file.path == null) continue;
      try {
        final src = File(file.path!);
        final name = file.name;
        final dest = File('${destDir.path}/$name');
        if (!await dest.exists()) {
          await src.copy(dest.path);
        }
        copied++;
        // توليد صورة مصغرة للفيديو عبر قراءة أول فريم
        final ext = name.split('.').last.toLowerCase();
        final isVideo = ['mp4', 'mkv', 'webm', 'mov'].contains(ext);
        if (isVideo) {
          _generateAndSaveVideoThumbnail(dest.path);
        }
      } catch (_) {}
    }

    _downloadCompleteNotifier.value = destDir.path;

    if (mounted) {
      setState(() => _importing = false);
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

  /// توليد وحفظ صورة مصغرة من الفيديو
  Future<void> _generateAndSaveVideoThumbnail(String videoPath) async {
    try {
      final ctrl = VideoPlayerController.file(File(videoPath));
      await ctrl.initialize();
      // انتقل للثانية الأولى للحصول على فريم واضح
      await ctrl.seekTo(const Duration(seconds: 1));
      await Future.delayed(const Duration(milliseconds: 300));
      await ctrl.dispose();
      // video_player لا يوفر screenshot مباشرة
      // نُنشئ ملف placeholder بحجم صفر كعلامة لإظهار الأيقونة الافتراضية
      // (الصورة الحقيقية تحتاج video_thumbnail package)
      // هنا نُعلّم ThumbnailManager أن هذا الملف لا يملك صورة حتى الآن
      ThumbnailManager.invalidate(videoPath);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.background;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkText : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final divider = isDark ? AppColors.darkDivider : AppColors.divider;
    final redLight = isDark ? AppColors.darkRedLight : AppColors.redLight;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bg,
                border: Border(bottom: BorderSide(color: divider, width: 0.5)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(CupertinoIcons.xmark, size: 18, color: textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ملفات الجهاز',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                        fontFamily: 'Tajawal',
                      ),
                    ),
                  ),
                  if (_pickedFiles.isNotEmpty)
                    GestureDetector(
                      onTap: _importing ? null : _importSelected,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _importing
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(
                                'إضافة (${_pickedFiles.length})',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Tajawal'),
                              ),
                      ),
                    ),
                ],
              ),
            ),
            // ── Body ──
            Expanded(
              child: _pickedFiles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: redLight,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(CupertinoIcons.folder_fill,
                                size: 38, color: AppColors.primary),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'اختر ملفات من الجهاز',
                            style: TextStyle(
                              fontSize: 18,
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'يدعم mp3 • m4a • mp4 • mkv وغيرها',
                            style: TextStyle(
                                fontSize: 13,
                                fontFamily: 'Tajawal',
                                color: textSecondary),
                          ),
                          const SizedBox(height: 32),
                          GestureDetector(
                            onTap: _pickFiles,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(CupertinoIcons.folder_open,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'تصفح الملفات',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Tajawal',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // زر تغيير الاختيار
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: GestureDetector(
                            onTap: _pickFiles,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: divider, width: 0.8),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(CupertinoIcons.folder_open,
                                      color: textSecondary, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'تغيير الاختيار',
                                    style: TextStyle(
                                        color: textSecondary,
                                        fontSize: 14,
                                        fontFamily: 'Tajawal',
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            itemCount: _pickedFiles.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final file = _pickedFiles[index];
                              final name = file.name;
                              final ext = name.split('.').last.toLowerCase();
                              final isVideo = ['mp4', 'mkv', 'webm', 'mov'].contains(ext);
                              return Container(
                                decoration: BoxDecoration(
                                  color: redLight,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.primary.withOpacity(0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  leading: Container(
                                    width: 42, height: 42,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isVideo
                                          ? CupertinoIcons.play_rectangle_fill
                                          : CupertinoIcons.music_note,
                                      color: Colors.white, size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    name.replaceAll(RegExp(r'\.\w+$'), ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontFamily: 'Tajawal',
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    ext.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 11, color: textSecondary),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
            // ── Bottom import bar ──
            if (_pickedFiles.isNotEmpty)
              Container(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                decoration: BoxDecoration(
                  color: bg,
                  border: Border(top: BorderSide(color: divider, width: 0.5)),
                ),
                child: GestureDetector(
                  onTap: _importing ? null : _importSelected,
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: _importing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'إضافة ${_pickedFiles.length} ملف إلى قسم استمع',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Tajawal',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.background;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkText : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final divider = isDark ? AppColors.darkDivider : AppColors.divider;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bg,
                border: Border(bottom: BorderSide(color: divider, width: 0.5)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(CupertinoIcons.xmark,
                          size: 18, color: textPrimary),
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
                                fontSize: 14,
                                fontFamily: 'Tajawal')),
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
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: divider, width: 0.5),
                      ),
                      child: TextField(
                        controller: _searchController,
                        textDirection: TextDirection.rtl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _search,
                        style: TextStyle(color: textPrimary, fontFamily: 'Tajawal'),
                        decoration: InputDecoration(
                          hintText: 'ابحث عن فيديو...',
                          hintStyle: TextStyle(
                              color: textSecondary, fontSize: 14, fontFamily: 'Tajawal'),
                          prefixIcon: Icon(CupertinoIcons.search,
                              color: textSecondary, size: 18),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                      ? _buildHomeCategories(isDark: isDark, bg: bg, textPrimary: textPrimary, textSecondary: textSecondary)
                      : _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeCategories({required bool isDark, required Color bg, required Color textPrimary, required Color textSecondary}) {
    final redLight = isDark ? AppColors.darkRedLight : AppColors.redLight;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('اكتشف',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Tajawal',
                  color: textPrimary)),
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
                    color: redLight,
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
                        fontFamily: 'Tajawal',
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
                Icon(CupertinoIcons.search, size: 48, color: isDark ? AppColors.darkDivider : AppColors.divider),
                const SizedBox(height: 12),
                Text('ابحث عن أي فيديو يوتيوب',
                    style: TextStyle(fontSize: 15, fontFamily: 'Tajawal', color: textSecondary)),
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
      final musicDir = Directory('${dir.path}/dndn');
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final surfaceAlt = isDark ? AppColors.darkSurfaceAlt : AppColors.surfaceAlt;
    final textPrimary = isDark ? AppColors.darkText : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final divider = isDark ? AppColors.darkDivider : AppColors.divider;
    final redLight = isDark ? AppColors.darkRedLight : AppColors.redLight;

    final thumb = video.thumbnails.mediumResUrl;
    final duration = video.duration;
    final durationStr = duration != null
        ? '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}'
        : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: divider, width: 0.5),
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
                          color: surfaceAlt,
                          child: Icon(CupertinoIcons.photo,
                              color: textSecondary),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 120,
                          height: 80,
                          color: surfaceAlt,
                          child: Icon(CupertinoIcons.play_rectangle_fill,
                              color: textSecondary),
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
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          video.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 11, color: textSecondary),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: redLight,
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
                                      fontFamily: 'Tajawal',
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
                  color: redLight,
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
                            fontFamily: 'Tajawal',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final surfaceAlt = isDark ? AppColors.darkSurfaceAlt : AppColors.surfaceAlt;
    final textPrimary = isDark ? AppColors.darkText : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final divider = isDark ? AppColors.darkDivider : AppColors.divider;

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
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: divider, width: 0.5),
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
                      color: surfaceAlt,
                      child: Icon(CupertinoIcons.play_rectangle_fill,
                          color: textSecondary),
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
                      style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      video.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 11, color: textSecondary),
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
      final musicDir = Directory('${dir.path}/dndn');
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.background;
    final textPrimary = isDark ? AppColors.darkText : AppColors.textPrimary;

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
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Icon(CupertinoIcons.xmark, color: textPrimary),
            ),
            title: Text(
              'مشاهدة الفيديو',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Tajawal',
                  color: textPrimary),
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
                  color: isDark ? AppColors.darkRedLight : AppColors.redLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _downloadStatus,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _downloadProgress > 0
                              ? _downloadProgress
                              : null,
                          backgroundColor: isDark ? Colors.white10 : Colors.white,
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Tajawal',
                          color: textPrimary,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkRedLight : AppColors.redLight,
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
                              style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'Tajawal',
                                  color: isDark ? AppColors.darkTextSec : AppColors.textSecondary,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      if (_relatedVideos.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'فيديوهات مشابهة',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Tajawal',
                            color: textPrimary,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : AppColors.background;
    final textPrimary = isDark ? AppColors.darkText : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final divider = isDark ? AppColors.darkDivider : AppColors.divider;
    final redLight = isDark ? AppColors.darkRedLight : AppColors.redLight;

    final isCached = _ManifestCache.isCached(videoId);
    final isVideoCached = _ManifestCache.isVideoCached(videoId);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: divider,
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
                color: redLight,
                child: const Icon(CupertinoIcons.cloud_download_fill,
                    color: AppColors.primary, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'تحميل الفيديو',
            style: TextStyle(
                fontSize: 18,
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w700,
                color: textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            videoTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: textSecondary),
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
                        fontFamily: 'Tajawal',
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
            isDark: isDark,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            divider: divider,
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
            isDark: isDark,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            divider: divider,
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
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color divider,
  }) {
    final surface = isDark ? AppColors.darkSurfaceAlt : AppColors.surface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: divider, width: 0.5),
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
                      style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textPrimary)),
                  Text(subtitle,
                      style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 11, color: textSecondary)),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_left,
                size: 14, color: textSecondary),
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
      _downloadPath = '${dir.path}/dndn';
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
                      Text(
                        'الإعدادات',
                        style: TextStyle(
                          fontSize: 28,
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700,
                          color: context.appText,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color.fromARGB(255, 53, 53, 53), Color.fromARGB(255, 102, 75, 75)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            // Logo in settings card
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(CupertinoIcons.music_note_2,
                                      color: Colors.white, size: 28),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('دندن',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Tajawal',
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700)),
                                Text('الإصدار 2.1.0',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontFamily: 'Tajawal',
                                        fontSize: 13)),
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
                        _actionTile(
                          'حذف جميع التنزيلات',
                          'مسح كل الملفات المحملة',
                          CupertinoIcons.trash_fill,
                          Colors.red,
                          _clearDownloads,
                        ),
                      ]),
                      const SizedBox(height: 160),
                    ],
                  ),
                ),
              ),
            ],
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
                        color: isDark ? AppColors.darkDivider : AppColors.divider,
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkRedLight : AppColors.redLight,
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
      subtitle: Text(subtitle,
          style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              color: isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
      trailing:
          CupertinoSwitch(value: value, onChanged: onChanged, activeColor: AppColors.primary),
    );
  }

  Widget _infoTile(String title, String value, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkRedLight : AppColors.redLight,
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
              color: isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
    );
  }

  Widget _qualityTile() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkRedLight : AppColors.redLight,
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
              child: Text('عالية', style: TextStyle(fontSize: 11, fontFamily: 'Tajawal'))),
          'medium': Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('متوسطة', style: TextStyle(fontSize: 11, fontFamily: 'Tajawal'))),
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
              fontFamily: 'Tajawal',
              fontSize: 14, fontWeight: FontWeight.w500, color: color)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 12,
              color: isDark ? AppColors.darkTextSec : AppColors.textSecondary)),
      onTap: onTap,
    );
  }
}