import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'dart:math' as math;
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
import 'package:flutter_dynamic_icon/flutter_dynamic_icon.dart';
// ─────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.mustami3.audio',
    androidNotificationChannelName: 'دندن',
    // false = لا يوقف الـ foreground service عند pause()
    // مما يبقي الإشعار حياً ويسمح باستكمال التشغيل من شاشة القفل أو الخلفية
    androidNotificationOngoing: false,
    androidStopForegroundOnPause: false,
    androidNotificationClickStartsActivity: true,
  );

  // تحميل الثيم المحفوظ أولاً
  await ThemeNotifier.instance.load();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light,
  ));
await SystemChrome.setPreferredOrientations([
  DeviceOrientation.portraitUp,
]);
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
    final isDarkMode = prefs.getBool('darkMode') ?? false;
    value = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    // مزامنة الأيقونة مع الثيم المحفوظ عند بدء التطبيق
    await AppIconService.instance.updateIcon(isDark: isDarkMode);
  }

  Future<void> toggle(bool dark) async {
    value = dark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', dark);
    // تغيير أيقونة التطبيق حسب الثيم الجديد
    await AppIconService.instance.updateIcon(isDark: dark);
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


class LocalMediaItem {
  final String path;
  final String title;
  final bool isVideo;
  final String? thumbnailUrl;
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


class ThumbnailManager {
  static final Map<String, String?> _memCache = {};

  static String _thumbPath(String mediaPath) {
    final name = mediaPath.split('/').last.replaceAll(RegExp(r'\.\w+$'), '');
    final dir = mediaPath.substring(0, mediaPath.lastIndexOf('/'));
    return '$dir/.thumb_$name.jpg';
  }

  static Future<String?> getLocalThumbnail(String mediaPath) async {
    if (_memCache.containsKey(mediaPath)) return _memCache[mediaPath];
    final tp = _thumbPath(mediaPath);
    if (File(tp).existsSync()) {
      _memCache[mediaPath] = tp;
      return tp;
    }
    _memCache[mediaPath] = null;
    return null;
  }

  /// يحفظ صورة من URL (يوتيوب) إلى ملف محلي بجانب الملف
  static Future<void> saveThumbnail(String mediaPath, String thumbnailUrl) async {
    try {
      final tp = _thumbPath(mediaPath);
      if (File(tp).existsSync()) return;
      final response = await dio.get<List<int>>(
        thumbnailUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.data != null) {
        await File(tp).writeAsBytes(response.data!);
        _memCache[mediaPath] = tp;
      }
    } catch (_) {}
  }

  /// ★ استخراج Frame حقيقي من فيديو محلي باستخدام video_thumbnail
  static Future<String?> generateVideoThumbnail(String videoPath) async {
    try {
      final tp = _thumbPath(videoPath);
      if (File(tp).existsSync()) {
        _memCache[videoPath] = tp;
        return tp;
      }
      final result = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: tp,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        quality: 85,
        timeMs: 1000,
      );
      if (result != null && File(result).existsSync()) {
        _memCache[videoPath] = result;
        return result;
      }
    } catch (_) {}
    _memCache[videoPath] = null;
    return null;
  }

  /// ★ استخراج Album Art من ملف صوتي محلي باستخدام on_audio_query
  static Future<String?> generateAudioThumbnail(String audioPath) async {
    try {
      final tp = _thumbPath(audioPath);
      if (File(tp).existsSync()) {
        _memCache[audioPath] = tp;
        return tp;
      }
      final OnAudioQuery audioQuery = OnAudioQuery();
      final artworkData = await audioQuery.queryArtwork(
        audioPath.hashCode,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 400,
        quality: 85,
      );
      if (artworkData != null && artworkData.isNotEmpty) {
        await File(tp).writeAsBytes(artworkData);
        _memCache[audioPath] = tp;
        return tp;
      }
    } catch (_) {}
    _memCache[audioPath] = null;
    return null;
  }

  /// ★ الدالة الشاملة: تولّد thumbnail تلقائياً حسب نوع الملف
  static Future<String?> generateLocalThumbnail(String mediaPath) async {
    final cached = await getLocalThumbnail(mediaPath);
    if (cached != null) return cached;

    final ext = mediaPath.split('.').last.toLowerCase();
    final isVideo = ['mp4', 'mkv', 'webm', 'mov'].contains(ext);
    final isAudio = ['mp3', 'm4a', 'aac', 'opus', 'flac', 'wav'].contains(ext);

    if (isVideo) {
      return await generateVideoThumbnail(mediaPath);
    } else if (isAudio) {
      return await generateAudioThumbnail(mediaPath);
    }
    return null;
  }

  static void invalidate(String mediaPath) {
    _memCache.remove(mediaPath);
  }

  static String? getThumbPathDirect(String mediaPath) {
    final tp = _thumbPath(mediaPath);
    return File(tp).existsSync() ? tp : null;
  }

  static void clearCache(String mediaPath) {
    _memCache.remove(mediaPath);
    final tp = _thumbPath(mediaPath);
    try { File(tp).deleteSync(); } catch (_) {}
  }
}
// ═══════════════════════════════════════════════════════════
//  MODEL: AD SLIDE
// ═══════════════════════════════════════════════════════════
class AdSlide {
  final String title;
  final String description;
  final String imageUrl;
  final String link;

  AdSlide({
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.link,
  });

factory AdSlide.fromJson(Map<String, dynamic> json) {
  const baseUrl = 'https://scrptaty.com/dndn/';
  final rawImage = json['image'] ?? '';
  
  return AdSlide(
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    imageUrl: rawImage.startsWith('http') ? rawImage : '$baseUrl$rawImage',
    link: json['link'] ?? '',
  );
}
}
// ─────────────────────────────────────────────
//  AUDIO PLAYER SERVICE — Singleton (v4 — MediaSession next/prev support)
// ─────────────────────────────────────────────
//
//  يستخدم ConcatenatingAudioSource بـ 3 عناصر (prev, current, next)
//  حتى تظهر أزرار التالي والسابق في الإشعار وشاشة القفل وBluetooth.
//  عند الضغط على التالي/السابق، يُغيّر just_audio_background currentIndex
//  فنستمع لذلك ونُشغّل الملف الصحيح.
//
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

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

  StreamSubscription? _completionSub;
  StreamSubscription? _indexSub;
  StreamSubscription? _playingSub;
  bool _handlingIndexChange = false;
  bool _userPaused = false;
  bool _isSwitching = false;
  int _pendingIndex = -1;
  List<LocalMediaItem>? _pendingList;

  // مؤشر لتتبع ما إذا كان الـ pause ناتج عن انتقال تلقائي بين أغاني
  bool _isAutoTransitioning = false;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // ── عند انتهاء الأغنية → شغّل التالية تلقائياً ──
    _completionSub = player.processingStateStream
        .distinct()
        .listen((state) {
      if (state == ProcessingState.completed) {
        _isAutoTransitioning = true;
        _autoNext();
      }
    });

    // ── الاستماع لتغييرات currentIndex من just_audio_background ──
    // عند الضغط على التالي/السابق في الإشعار أو شاشة القفل أو Bluetooth
    _indexSub = player.currentIndexStream.distinct().listen((rawIdx) {
      if (rawIdx == null || _handlingIndexChange || _isSwitching) return;
      final list = playlist.value;
      final cur = currentIndex.value;
      if (list.isEmpty || cur < 0) return;
      final hasPrev = cur > 0;

      final currentRawIdx = hasPrev ? 1 : 0;
      if (rawIdx < currentRawIdx) {
        // ── الضغط على السابق من الإشعار/شاشة القفل ──
        // نُعطّل loopMode مؤقتاً عند الانتقال اليدوي حتى لا تُعاد نفس الأغنية
        _isAutoTransitioning = true;
        final wasLoop = player.loopMode == LoopMode.one;
        if (wasLoop) player.setLoopMode(LoopMode.off);
        Future.microtask(() async {
          await _playSingleFile(list, cur - 1);
          if (wasLoop) await player.setLoopMode(LoopMode.one);
        });
      } else if (rawIdx > currentRawIdx) {
        // ── الضغط على التالي من الإشعار/شاشة القفل ──
        _isAutoTransitioning = true;
        final wasLoop = player.loopMode == LoopMode.one;
        if (wasLoop) player.setLoopMode(LoopMode.off);
        Future.microtask(() async {
          await _playSingleFile(list, cur + 1);
          if (wasLoop) await player.setLoopMode(LoopMode.one);
        });
      }
    });

    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        // انقطاع خارجي (مكالمة، تطبيق آخر...) → إيقاف مؤقت
        if (player.playing) player.pause();
      } else {
        // انتهى الانقطاع → أعد التشغيل فقط إذا لم يوقفه المستخدم يدوياً
        if (!_userPaused &&
            (event.type == AudioInterruptionType.pause ||
                event.type == AudioInterruptionType.unknown)) {
          player.play();
        }
      }
    });

    // ── مراقبة حالة التشغيل/الإيقاف ──
    _playingSub = player.playingStream.listen((playing) {
      if (playing) {
        // بدأ التشغيل → ألغِ علامة الإيقاف اليدوي والانتقال التلقائي
        _userPaused = false;
        _isAutoTransitioning = false;
        if (!isVisible.value && currentIndex.value >= 0) {
          isVisible.value = true;
        }
      } else {
        // توقف التشغيل — لا يُعتبر userPaused إذا كان انتقالاً تلقائياً
        if (!_handlingIndexChange && !_isAutoTransitioning) {
          _userPaused = true;
        }
      }
    });
  }

  void _autoNext() {
    final idx = currentIndex.value;
    final list = playlist.value;
    _userPaused = false;
    _isSwitching = false;
    _pendingIndex = -1;
    _pendingList = null;
    if (player.loopMode == LoopMode.one) {
      player.seek(Duration.zero);
      player.play();
      return;
    }
    if (idx < list.length - 1) {
      _playSingleFile(list, idx + 1);
    }
  }

  Future<MediaItem> _buildTag(LocalMediaItem item) async {
    Uri? artUri;
    final localThumb = await ThumbnailManager.getLocalThumbnail(item.path);
    if (localThumb != null) {
      artUri = Uri.file(localThumb);
    } else if (item.thumbnailUrl != null) {
      artUri = Uri.parse(item.thumbnailUrl!);
    }
    return MediaItem(
      id: item.path,
      title: item.title.replaceAll(RegExp(r'\.\w+$'), ''),
      artist: 'دندن',
      artUri: artUri,
    );
  }

  Future<void> _playSingleFile(List<LocalMediaItem> list, int index) async {
    if (list.isEmpty || index < 0 || index >= list.length) return;

    if (_isSwitching) {
      _pendingIndex = index;
      _pendingList = list;
      return;
    }

    _isSwitching = true;
    _pendingIndex = -1;
    _pendingList = null;

    playlist.value = list;
    currentIndex.value = index;
    isVisible.value = true;
    _handlingIndexChange = true;

    int? pendingAfter;
    List<LocalMediaItem>? pendingListAfter;

    try {
      try { if (player.playing) await player.pause(); } catch (_) {}

      final item = list[index];
      final hasPrev = index > 0;
      final hasNext = index < list.length - 1;

      Future<MediaItem> buildTag(LocalMediaItem it) async {
        Uri? artUri;
        final localThumb = await ThumbnailManager.getLocalThumbnail(it.path);
        if (localThumb != null) {
          artUri = Uri.file(localThumb);
        } else if (it.thumbnailUrl != null) {
          artUri = Uri.parse(it.thumbnailUrl!);
        }
        return MediaItem(
          id: it.path,
          title: it.title.replaceAll(RegExp(r'\.\w+$'), ''),
          artist: 'دندن',
          artUri: artUri,
        );
      }

      final tagFutures = <Future<MediaItem>>[
        if (hasPrev) buildTag(list[index - 1]),
        buildTag(item),
        if (hasNext) buildTag(list[index + 1]),
      ];
      final tags = await Future.wait(tagFutures);

      int tagIdx = 0;
      final sources = <AudioSource>[];
      if (hasPrev) sources.add(AudioSource.file(list[index - 1].path, tag: tags[tagIdx++]));
      sources.add(AudioSource.file(item.path, tag: tags[tagIdx++]));
      if (hasNext) sources.add(AudioSource.file(list[index + 1].path, tag: tags[tagIdx]));

      final initialIdx = hasPrev ? 1 : 0;
      final concat = ConcatenatingAudioSource(children: sources);

      await player.setAudioSource(
        concat,
        initialIndex: initialIdx,
        initialPosition: Duration.zero,
        preload: false,
      );

      _handlingIndexChange = false;
      _isSwitching = false;

      // احفظ الـ pending قبل play()
      if (_pendingIndex >= 0) {
        pendingAfter = _pendingIndex;
        pendingListAfter = _pendingList ?? list;
        _pendingIndex = -1;
        _pendingList = null;
      }

      try { await player.play(); } catch (_) {}

      // تحميل thumbnails في الخلفية
      Future(() async {
        try {
          if (currentIndex.value != index) return;
          await ThumbnailManager.generateLocalThumbnail(item.path);
          if (hasPrev) await ThumbnailManager.generateLocalThumbnail(list[index - 1].path);
          if (hasNext) await ThumbnailManager.generateLocalThumbnail(list[index + 1].path);
        } catch (_) {}
      });

    } catch (e) {
      _handlingIndexChange = false;
      _isSwitching = false;
      debugPrint('_playSingleFile error: $e');

      if (_pendingIndex >= 0) {
        pendingAfter = _pendingIndex;
        pendingListAfter = _pendingList ?? list;
        _pendingIndex = -1;
        _pendingList = null;
      }
    }

    // تنفيذ الطلب المعلق بعد انتهاء كل شيء
    if (pendingAfter != null) {
      Future.microtask(() => _playSingleFile(pendingListAfter ?? list, pendingAfter!));
    }
  }

  Future<void> playList(List<LocalMediaItem> items, int startIndex) async {
    _userPaused = false;
    _isSwitching = false;
    _pendingIndex = -1;
    _pendingList = null;
    final idx = startIndex.clamp(0, items.length - 1);
    await _playSingleFile(List.unmodifiable(items), idx);
  }

  Future<void> playAtIndex(int index) async {
    _userPaused = false;
    final list = playlist.value;
    if (list.isEmpty) return;
    if (index == currentIndex.value && !_isSwitching && _pendingIndex < 0) return;
    await _playSingleFile(list, index);
  }

  /// إيقاف مؤقت بواسطة المستخدم — يحفظ النية حتى لا تُعيد الجلسة التشغيل تلقائياً
  Future<void> pauseByUser() async {
    _userPaused = true;
    await player.pause();
  }

  /// تشغيل بواسطة المستخدم — يمسح علامة الإيقاف اليدوي
  Future<void> playByUser() async {
    _userPaused = false;
    await player.play();
  }

  Future<void> playNext() async {
    _userPaused = false;
    _isSwitching = false;
    _pendingIndex = -1;
    _pendingList = null;
    final idx = currentIndex.value;
    final list = playlist.value;
    if (idx < list.length - 1) {
      await _playSingleFile(list, idx + 1);
    }
  }

  Future<void> playPrevious() async {
    _userPaused = false;
    _isSwitching = false;
    _pendingIndex = -1;
    _pendingList = null;
    final pos = player.position;
    if (pos.inSeconds > 3) {
      await player.seek(Duration.zero);
    } else {
      final idx = currentIndex.value;
      final list = playlist.value;
      if (idx > 0) {
        await _playSingleFile(list, idx - 1);
      } else {
        await player.seek(Duration.zero);
      }
    }
  }

  /// ضبط مستوى الصوت — يدعم 0% إلى 300% بتضخيم حقيقي
  void setVolumeBoost(double normalizedValue) {
    final v = normalizedValue.clamp(0.0, 3.0);
    if (v <= 1.0) {
      player.setVolume(v);
      try { _loudnessEnhancer.setTargetGain(0.0); } catch (_) {}
    } else {
      player.setVolume(1.0);
      final gainMB = (v - 1.0) * 800.0;
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
    _completionSub?.cancel();
    _indexSub?.cancel();
    _playingSub?.cancel();
    player.dispose();
  }
}

final audioService = AudioPlayerService();
final ValueNotifier<String?> downloadCompleteNotifier = ValueNotifier(null);

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
  resizeToAvoidBottomInset: false,
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
// ─────────────────────────────────────────────
//  GLASS NAV BAR — iOS Floating Glass Style (Fluid Drag & Blend)
// ─────────────────────────────────────────────
class _GlassNavBar extends StatefulWidget {
  const _GlassNavBar();
  @override
  State<_GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<_GlassNavBar>
    with TickerProviderStateMixin {
  late AnimationController _indicatorCtrl;
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;
  
  // متغيرات مخصصة لحساب تأثير المزج والتمدد أثناء السحب
  double _dragOffset = 0.0;
  bool _isDragging = false;
  int _prevIndex = 0;
  // القسم المستهدف عند الإفلات (لا يُطبَّق إلا عند رفع الإصبع)
  int _pendingNavIndex = 0;

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
      duration: const Duration(milliseconds: 350), // حركة أنعم للمؤشر
      value: 1.0,
    );

    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180), 
    );

    _scaleAnim = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutBack),
    );

    _navIndexNotifier.addListener(_onNavChange);
  }

  @override
  void dispose() {
    _navIndexNotifier.removeListener(_onNavChange);
    _indicatorCtrl.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _startScaling() {
    _scaleCtrl.forward();
  }

  void _stopScaling() {
    _scaleCtrl.reverse();
    setState(() {
      _isDragging = false;
    });
  }

  void _onNavChange() {
    if (_prevIndex != _navIndexNotifier.value) {
      _indicatorCtrl.forward(from: 0.0);
      _prevIndex = _navIndexNotifier.value;
    }
    if (mounted) setState(() {});
  }

  // تحديث موقع السحب الفعلي لإصبع المستخدم — المؤشر يتبع الإصبع فقط، التبويب يتغير عند الإفلات
  void _updateDragPosition(Offset localPosition, double totalWidth) {
    if (totalWidth <= 0) return;
    setState(() {
      _isDragging = true;
      _dragOffset = localPosition.dx.clamp(0.0, totalWidth);
    });

    // حساب التبويب المستهدف — لكن لا نُغيّره الآن، فقط نحتفظ به للإفلات
    final invertedX = totalWidth - localPosition.dx;
    final tabWidth = totalWidth / _tabs.length;
    _pendingNavIndex = (invertedX / tabWidth).floor().clamp(0, _tabs.length - 1);
  }

  // عند الإفلات: انتقل للقسم الذي توقف عنده الإصبع
  void _commitDrag() {
    _stopScaling();
    if (_navIndexNotifier.value != _pendingNavIndex) {
      _navIndexNotifier.value = _pendingNavIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final idx = _navIndexNotifier.value;

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth - 36;

        return GestureDetector(
          onTapDown: (details) {
            _startScaling();
            _updateDragPosition(details.localPosition, barWidth);
          },
          onHorizontalDragStart: (details) {
            _startScaling();
            _updateDragPosition(details.localPosition, barWidth);
          },
          onHorizontalDragUpdate: (details) {
            _updateDragPosition(details.localPosition, barWidth);
          },
          onTapUp: (_) => _commitDrag(),
          onHorizontalDragEnd: (_) => _commitDrag(),
          onHorizontalDragCancel: () => _stopScaling(),
          child: AnimatedBuilder(
            animation: _scaleAnim,
            builder: (_, child) => Transform.scale(
              scale: _scaleAnim.value,
              child: child,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                bottom: bottomPadding > 0 ? bottomPadding + 6 : 14,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    height: 66,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withOpacity(1)
                          : Colors.white.withOpacity(1),
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(
                        color: isDark
                            ? const Color.fromARGB(255, 114, 114, 114).withOpacity(0.1)
                            : const Color.fromARGB(255, 12, 0, 0).withOpacity(0.07),
                        width: 1.2,
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [Colors.black.withOpacity(0.3), Colors.black.withOpacity(0.3)]
                            : [Colors.white.withOpacity(0.5), Colors.white.withOpacity(0.5)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(255, 0, 0, 0).withOpacity(isDark ? 0.18 : 0.08),
                          blurRadius: 32,
                          spreadRadius: -4,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(builder: (ctx, innerConstraints) {
                      final totalBarWidth = innerConstraints.maxWidth;
                      final tabWidth = totalBarWidth / _tabs.length;

                      // ── الحسبة السحرية للمزج والتمدد (Fluid Blend Logic) ──
                      double indicatorWidth = tabWidth * 0.76;
                      double indicatorRightPosition = idx * tabWidth + tabWidth * 0.12;
                      double indicatorTop = 8;
                      double indicatorBottom = 8;

                      if (_isDragging) {
                        // المؤشر يتبع الإصبع مباشرة بدون أي طفرة
                        // تحويل إحداثيات السحب لـ RTL (اليمين = الصفر)
                        double rtlDragX = totalBarWidth - _dragOffset;

                        // موضع المؤشر يتمركز حول الإصبع مباشرة
                        double fingerCenter = rtlDragX;

                        // مقدار التمدد بناءً على المسافة من مركز القسم الحالي
                        double currentTabCenter = idx * tabWidth + tabWidth * 0.5;
                        double distance = (fingerCenter - currentTabCenter).abs();

                        // تمدد أفقي خفيف
                        indicatorWidth = (tabWidth * 0.76) + (distance * 0.08);
                        indicatorWidth = indicatorWidth.clamp(tabWidth * 0.76, tabWidth * 1.05);

                        // تمدد رأسي بنفس النسبة (عكسي — يصغر من الأعلى والأسفل)
                        final verticalStretch = (distance * 0.04).clamp(0.0, 3.0);
                        indicatorTop = 8 - verticalStretch;
                        indicatorBottom = 8 - verticalStretch;

                        // المؤشر يتمركز حول الإصبع
                        indicatorRightPosition = fingerCenter - (indicatorWidth / 2);
                        indicatorRightPosition = indicatorRightPosition.clamp(0.0, totalBarWidth - indicatorWidth);
                      }

                      return Stack(alignment: Alignment.center, children: [
                        // ── المؤشر الأحمر الذكي (تأثير مائع وممتزج) ──
                        AnimatedPositioned(
                          // عند السحب تكون الاستجابة فورية صفر مللي ثانية للمزج، وعند الإفلات يعود بسلاسة كالزنبرك
                          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          right: indicatorRightPosition,
                          width: indicatorWidth,
                          top: indicatorTop,
                          bottom: indicatorBottom,
                          child: AnimatedBuilder(
                            animation: _indicatorCtrl,
                            builder: (_, __) {
                              final s = Tween<double>(begin: 0.9, end: 1.0)
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
                                        AppColors.primary.withOpacity(0.22), // زيادة الوضوح أثناء التمدد
                                        AppColors.primaryDark.withOpacity(0.12),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(40),
                                    border: Border.all(
                                      color: AppColors.primary.withOpacity(0.1),
                                      width: 0.8,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        
                        // ── Tab Buttons (عناصر التبويبات) ──
                        Row(
                          children: List.generate(_tabs.length, (i) {
                            final tab = _tabs[i];
                            final isSelected = i == idx;
                            return Expanded(
                              child: IgnorePointer(
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
                                                    color: isSelected ? AppColors.primary : (isDark ? Colors.white38 : AppColors.textSecondary),
                                                  ),
                                                ),
                                              )
                                            : Icon(
                                                tab.icon,
                                                size: 22,
                                                color: isSelected ? AppColors.primary : (isDark ? Colors.white38 : AppColors.textSecondary),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 200),
                                      style: TextStyle(
                                        fontFamily: 'Tajawal',
                                        fontSize: 10,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                        color: isSelected ? AppColors.primary : (isDark ? Colors.white38 : AppColors.textSecondary),
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
            ),
          ),
        );
      },
    );
  }
}

class _NavTabData {
  final IconData icon;
  final String label;
  const _NavTabData({required this.icon, required this.label});
}
// ─────────────────────────────────────────────
//  MINI PLAYER WIDGET — Glass style matching bottom nav bar
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
    final isDark = context.isDark;
    return SlideTransition(
      position:
          Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(_slideAnim),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: GestureDetector(
          onTap: _openFullPlayer,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  // زجاج شفاف حقيقي بنفس تصميم البار السفلي
                  color: isDark
                      ? Colors.black.withOpacity(0.30)
                      : Colors.white.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark
                        ? const Color.fromARGB(255, 114, 114, 114).withOpacity(0.1)
                        : const Color.fromARGB(255, 12, 0, 0).withOpacity(0.07),
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
                      color: const Color.fromARGB(255, 0, 0, 0).withOpacity(isDark ? 0.18 : 0.08),
                      blurRadius: 32,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: const Color.fromARGB(0, 17, 1, 1).withOpacity(isDark ? 0.25 : 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(isDark ? 0.04 : 0.50),
                      blurRadius: 1,
                      offset: const Offset(0, 1),
                    ),
                    BoxShadow(
                      color: AppColors.primary.withOpacity(isDark ? 0.02 : 0.08),
                      blurRadius: 16,
                      spreadRadius: -2,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ValueListenableBuilder<int>(
                  valueListenable: audioService.currentIndex,
                  builder: (context, idx, _) {
                    final item = audioService.currentItem;
                    if (item == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          // ── الصورة المصغرة ──
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
                                  style: TextStyle(
                                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Tajawal',
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
                                            backgroundColor: isDark
                                                ? Colors.white24
                                                : Colors.black12,
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

                          // ── تشغيل / إيقاف ──
                          StreamBuilder<bool>(
                            stream: audioService.player.playingStream,
                            builder: (_, snap) {
                              final playing = snap.data ?? false;
                              return _MiniBtn(
                                icon: playing
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill,
                                size: 28,
                                btnSize: 44,
                                isDark: isDark,
                                onTap: () => playing
                                    ? audioService.pauseByUser()
                                    : audioService.playByUser(),
                              );
                            },
                          ),
                          const SizedBox(width: 2),

                          // ── زر الإغلاق ──
                          _MiniBtn(
                            icon: CupertinoIcons.xmark,
                            size: 22,
                            btnSize: 40,
                            isDark: isDark,
                            onTap: () async {
                              await audioService.player.stop();
                              audioService.isVisible.value = false;
                              audioService.currentIndex.value = -1;
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
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
  final double btnSize;
  final bool isDark;
  const _MiniBtn({
    required this.icon,
    required this.onTap,
    this.size = 22,
    this.btnSize = 40,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: btnSize,
        height: btnSize,
        child: Center(
          child: Icon(
            icon,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            size: size,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  VIDEO PLAYER WIDGET — مشغل فيديو متكامل مع ملء الشاشة
// ═══════════════════════════════════════════════════════════
class _VideoPlayerWidget extends StatefulWidget {
  final ValueNotifier<VideoPlayerController?> ctrlNotifier;
  final AudioPlayer audioPlayer;
  final void Function(Duration) onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final double speed;
  final double volume;
  final void Function(double) onSpeedChange;
  final void Function(double) onVolumeChange;

  const _VideoPlayerWidget({
    required this.ctrlNotifier,
    required this.audioPlayer,
    required this.onSeek,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
    required this.speed,
    required this.volume,
    required this.onSpeedChange,
    required this.onVolumeChange,
  });

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  bool _showControls = true;
  Timer? _hideTimer;
  bool _dragging = false;
  double _dragValue = 0.0;
  bool _isFullScreen = false;
  bool _showVolumeBar = false;
  bool _showSpeedOptions = false;
  bool _isShuffle = false;
  bool _isRepeat = false;
  String? _doubleTapHint;
  Timer? _doubleTapHintTimer;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _doubleTapHintTimer?.cancel();
    // لا نُغيّر الاتجاه هنا — فقط عند الخروج الفعلي من FullScreen
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showVolumeBar = false;
        _showSpeedOptions = false;
      }
    });
    if (_showControls) _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() {
        _showControls = false;
        _showVolumeBar = false;
        _showSpeedOptions = false;
      });
    });
  }

  void _resetTimer() {
    _hideTimer?.cancel();
    _startHideTimer();
  }

  void _toggleFullScreen() {
    if (!_isFullScreen) {
      setState(() => _isFullScreen = true);
      _enterFullScreen();
    } else {
      _exitFullScreen();
    }
  }

  Future<void> _enterFullScreen() async {
    // ① إخفاء System UI كامل — immersive حقيقي مثل يوتيوب
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    // ② دوران Landscape إجباري
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    if (!mounted) return;

    // ③ فتح صفحة fullscreen بدون أي Scaffold أو AppBar
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (ctx, _, __) => _ImmersiveFullScreenPage(
          ctrlNotifier: widget.ctrlNotifier,
          audioPlayer: widget.audioPlayer,
          onSeek: widget.onSeek,
          onPlayPause: widget.onPlayPause,
          onNext: widget.onNext,
          onPrev: widget.onPrev,
          speed: widget.speed,
          volume: widget.volume,
          onSpeedChange: widget.onSpeedChange,
          onVolumeChange: widget.onVolumeChange,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );

    // بعد العودة من fullscreen — أعد الإعدادات
    _exitFullScreen();
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (mounted) setState(() => _isFullScreen = false);
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  // سرعات بطيئة ومتوسطة وسريعة
  static const List<double> _slowSpeeds = [
    0.50, 0.51, 0.52, 0.53, 0.54, 0.55, 0.56, 0.57, 0.58, 0.59,
    0.60, 0.61, 0.62, 0.63, 0.64, 0.65, 0.66, 0.67, 0.68, 0.69,
    0.70, 0.71, 0.72, 0.73, 0.74, 0.75, 0.76, 0.77, 0.78, 0.79,
    0.80, 0.81, 0.82, 0.83, 0.84, 0.85, 0.86, 0.87, 0.88, 0.89,
    0.90, 0.91, 0.92, 0.93, 0.94, 0.95, 0.96, 0.97, 0.98, 0.99,
  ];
  static const List<double> _fastSpeeds = [1.25, 1.5, 1.75, 2.0];

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // زر الإعدادات — يسار العلوي
          GestureDetector(
            onTap: () {
              _showSettingsSheet(context);
              _resetTimer();
            },
            child: const Icon(CupertinoIcons.settings,
                color: Colors.white, size: 24),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSpeedPanel() {
    final slowValue = (widget.speed >= 0.50 && widget.speed < 1.0)
        ? widget.speed
        : 1.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── السرعات البطيئة: سلايدر من 0.50 إلى 1.00 بفارق 0.01 ──
          Row(
            children: [
              const Text('🐢', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Expanded(
                child: SliderTheme(
                  data: const SliderThemeData(
                    trackHeight: 2,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                  ),
                  child: Slider(
                    value: slowValue.clamp(0.50, 1.0),
                    min: 0.50,
                    max: 1.0,
                    divisions: 50,
                    onChanged: (v) {
                      // تقريب لأقرب 0.01
                      final rounded = (v * 100).round() / 100;
                      widget.onSpeedChange(rounded);
                      _resetTimer();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: (widget.speed >= 0.50 && widget.speed < 1.0)
                      ? AppColors.primary
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.speed >= 0.50 && widget.speed < 1.0
                      ? '${slowValue.toStringAsFixed(2)}×'
                      : '0.50×',
                  style: TextStyle(
                    color: (widget.speed >= 0.50 && widget.speed < 1.0)
                        ? Colors.white
                        : Colors.white70,
                    fontSize: 11,
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          // زر 1× العادي
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () { widget.onSpeedChange(1.0); _resetTimer(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: widget.speed == 1.0 ? AppColors.primary : Colors.white24,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '1× عادي',
                style: TextStyle(
                  color: widget.speed == 1.0 ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),

          // ── السرعات السريعة ──
          Row(
            children: [
              const Text('🚀', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final s in _fastSpeeds)
                      GestureDetector(
                        onTap: () { widget.onSpeedChange(s); _resetTimer(); },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.speed == s ? AppColors.primary : Colors.white24,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${s}×',
                            style: TextStyle(
                              color: widget.speed == s ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // محتوى الفيديو مع أدوات التحكم
    final videoContent = ValueListenableBuilder<VideoPlayerController?>(
      valueListenable: widget.ctrlNotifier,
      builder: (_, ctrl, __) {
        if (ctrl == null) {
          return const SizedBox.shrink();
        }
        return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── الفيديو يملأ كامل الحاوية ──
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: ctrl.value.size.width > 0 ? ctrl.value.size.width : 1920,
                height: ctrl.value.size.height > 0 ? ctrl.value.size.height : 1080,
                child: VideoPlayer(ctrl),
              ),
            ),

            // ── طبقة double-tap — تعمل دائماً بغض النظر عن حالة controls ──
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleControls,
                      onDoubleTap: () {
                        if (_showControls) setState(() => _showControls = false);
                        final pos = widget.audioPlayer.position;
                        final back = pos - const Duration(seconds: 10);
                        widget.onSeek(back < Duration.zero ? Duration.zero : back);
                        setState(() => _doubleTapHint = 'backward');
                        _doubleTapHintTimer?.cancel();
                        _doubleTapHintTimer = Timer(const Duration(milliseconds: 800), () {
                          if (mounted) setState(() => _doubleTapHint = null);
                        });
                        _hideTimer?.cancel();
                      },
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleControls,
                      onDoubleTap: () {
                        if (_showControls) setState(() => _showControls = false);
                        final pos = widget.audioPlayer.position;
                        widget.onSeek(pos + const Duration(seconds: 10));
                        setState(() => _doubleTapHint = 'forward');
                        _doubleTapHintTimer?.cancel();
                        _doubleTapHintTimer = Timer(const Duration(milliseconds: 800), () {
                          if (mounted) setState(() => _doubleTapHint = null);
                        });
                        _hideTimer?.cancel();
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── أنيميشن التقديم/التأخير ──
            if (_doubleTapHint != null)
              _SeekRippleAnimation(isForward: _doubleTapHint == 'forward'),

            // ── طبقة التحكم (controls overlay) ──
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x99000000),
                        Color(0x00000000),
                        Color(0x00000000),
                        Color(0x99000000),
                      ],
                      stops: [0.0, 0.3, 0.6, 1.0],
                    ),
                  ),
                  child: Column(
                    children: [
                      // ── الشريط العلوي: إعدادات فقط ──
                      _buildTopBar(),

                      const Spacer(),

                      // ── الوسط: السابق + تشغيل + التالي ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // زر السابق
                          GestureDetector(
                            onTap: () {
                              widget.onPrev();
                              _resetTimer();
                            },
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.25),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(CupertinoIcons.forward_end_fill,
                                  color: Colors.white, size: 22),
                            ),
                          ),
                          const SizedBox(width: 24),

                          // تشغيل / إيقاف
                          StreamBuilder<bool>(
                            stream: widget.audioPlayer.playingStream,
                            builder: (_, snap) {
                              final playing = snap.data ?? false;
                              return GestureDetector(
                                onTap: () {
                                  widget.onPlayPause();
                                  _resetTimer();
                                },
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.3),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    playing
                                        ? CupertinoIcons.pause_fill
                                        : CupertinoIcons.play_fill,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 24),

                          // زر التالي
                          GestureDetector(
                            onTap: () {
                              widget.onNext();
                              _resetTimer();
                            },
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.25),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(CupertinoIcons.backward_end_fill,
                                  color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // ── شريط التقدم السفلي + زر ملء الشاشة ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                        child: StreamBuilder<Duration?>(
                          stream: widget.audioPlayer.durationStream,
                          builder: (_, durSnap) {
                            return StreamBuilder<Duration>(
                              stream: widget.audioPlayer.positionStream,
                              builder: (_, posSnap) {
                                final dur = durSnap.data ?? Duration.zero;
                                final pos = posSnap.data ?? Duration.zero;
                                final progress = dur.inMilliseconds > 0
                                    ? pos.inMilliseconds / dur.inMilliseconds
                                    : 0.0;
                                final display = _dragging ? _dragValue : progress;
                                final displayPos = _dragging
                                    ? Duration(milliseconds: (_dragValue * dur.inMilliseconds).toInt())
                                    : pos;
                                return Column(
                                  children: [
                                    // ── صف الوقت وزر ملء الشاشة ──
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Row(
                                        children: [
                                          // وقت بصيغة pill داكنة
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '${_fmt(displayPos)} / ${_fmt(dur)}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          // زر ملء الشاشة — يمين
                                          GestureDetector(
                                            onTap: () {
                                              _toggleFullScreen();
                                              _resetTimer();
                                            },
                                            child: const Icon(
                                              CupertinoIcons.fullscreen,
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // ── شريط التقدم أبيض سميك مع مسافات جانبية ──
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          trackHeight: 5,
                                          thumbShape: RoundSliderThumbShape(
                                              enabledThumbRadius: _dragging ? 12 : 7),
                                          overlayShape: const RoundSliderOverlayShape(
                                              overlayRadius: 0),
                                          activeTrackColor: Colors.white,
                                          inactiveTrackColor: Colors.white30,
                                          thumbColor: Colors.white,
                                          overlayColor: Colors.transparent,
                                        ),
                                        child: Slider(
                                          value: display.clamp(0.0, 1.0),
                                          onChangeStart: (v) {
                                            setState(() {
                                              _dragging = true;
                                              _dragValue = v;
                                            });
                                            _hideTimer?.cancel();
                                          },
                                          onChanged: (v) =>
                                              setState(() => _dragValue = v),
                                          onChangeEnd: (v) {
                                            setState(() => _dragging = false);
                                            final ms = (v * dur.inMilliseconds).toInt();
                                            widget.onSeek(Duration(milliseconds: ms));
                                            _startHideTimer();
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
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
      }, // end ValueListenableBuilder builder
    ); // end ValueListenableBuilder

    // ── وضع عادي: نسبة 16:9 ثابتة دائماً بغض النظر عن نوع الفيديو ──
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: videoContent,
      ),
    );
  }

  void _showSettingsSheet(BuildContext ctx) {
    _hideTimer?.cancel();
    double localVolume = widget.volume;
    double localSpeed = widget.speed;
    bool localRepeat = _isRepeat;
    bool localShuffle = _isShuffle;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (_, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),


              // ── سرعة التشغيل ──
              Row(children: [
                const Icon(CupertinoIcons.speedometer, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                const Text('سرعة التشغيل',
                    style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: SliderTheme(
                    data: const SliderThemeData(
                      trackHeight: 3,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: localSpeed.clamp(0.5, 2.0),
                      min: 0.5, max: 2.0,
                      divisions: 30,
                      onChanged: (v) {
                        final r = (v * 20).round() / 20.0;
                        setSheet(() => localSpeed = r);
                        widget.onSpeedChange(r);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text('${localSpeed.toStringAsFixed(2)}×',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Tajawal'),
                      textAlign: TextAlign.end),
                ),
              ]),

              const Divider(color: Colors.white12, height: 20),

              // ── تكرار الفيديو ──
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(CupertinoIcons.repeat, color: Colors.white70, size: 20),
                title: const Text('تكرار الفيديو',
                    style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15)),
                trailing: CupertinoSwitch(
                  value: localRepeat,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setSheet(() => localRepeat = v);
                    setState(() => _isRepeat = v);
                    widget.audioPlayer.setLoopMode(v ? LoopMode.one : LoopMode.off);
                  },
                ),
              ),

              const Divider(color: Colors.white12, height: 1),

              // ── تشغيل عشوائي ──
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(CupertinoIcons.shuffle, color: Colors.white70, size: 20),
                title: const Text('تشغيل عشوائي',
                    style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15)),
                trailing: CupertinoSwitch(
                  value: localShuffle,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setSheet(() => localShuffle = v);
                    setState(() => _isShuffle = v);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _startHideTimer());
  }
}

// ═══════════════════════════════════════════════════════════
//  IMMERSIVE FULLSCREEN PAGE — صفحة ملء الشاشة الحقيقية
//  مثل يوتيوب تماماً: لا StatusBar، لا NavigationBar، لا فراغات
// ═══════════════════════════════════════════════════════════
class _ImmersiveFullScreenPage extends StatefulWidget {
  final ValueNotifier<VideoPlayerController?> ctrlNotifier;
  final AudioPlayer audioPlayer;
  final void Function(Duration) onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final double speed;
  final double volume;
  final void Function(double) onSpeedChange;
  final void Function(double) onVolumeChange;

  const _ImmersiveFullScreenPage({
    required this.ctrlNotifier,
    required this.audioPlayer,
    required this.onSeek,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
    required this.speed,
    required this.volume,
    required this.onSpeedChange,
    required this.onVolumeChange,
  });

  @override
  State<_ImmersiveFullScreenPage> createState() => _ImmersiveFullScreenPageState();
}

class _ImmersiveFullScreenPageState extends State<_ImmersiveFullScreenPage> {
  bool _showControls = true;
  Timer? _hideTimer;
  bool _dragging = false;
  double _dragValue = 0.0;
  bool _isShuffle = false;
  bool _isRepeat = false;

  // Pinch-to-zoom
  double _scale = 1.0;
  double _baseScale = 1.0;

  // double-tap feedback
  String? _doubleTapHint;
  Timer? _doubleTapHintTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _doubleTapHintTimer?.cancel();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _resetTimer() {
    _hideTimer?.cancel();
    _startHideTimer();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  void _showSettingsSheet(BuildContext ctx) {
    _hideTimer?.cancel();
    double localVolume = widget.volume;
    double localSpeed = widget.speed;
    bool localRepeat = _isRepeat;
    bool localShuffle = _isShuffle;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (_, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1C1C1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),


              // ── سرعة التشغيل ──
              Row(children: [
                const Icon(CupertinoIcons.speedometer, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                const Text('سرعة التشغيل',
                    style: TextStyle(color: Colors.white70, fontFamily: 'Tajawal', fontSize: 13)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: SliderTheme(
                    data: const SliderThemeData(
                      trackHeight: 3,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: localSpeed.clamp(0.5, 2.0),
                      min: 0.5, max: 2.0,
                      divisions: 30,
                      onChanged: (v) {
                        final r = (v * 20).round() / 20.0;
                        setSheet(() => localSpeed = r);
                        widget.onSpeedChange(r);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text('${localSpeed.toStringAsFixed(2)}×',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Tajawal'),
                      textAlign: TextAlign.end),
                ),
              ]),

              const Divider(color: Colors.white12, height: 20),

              // ── تكرار الفيديو ──
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(CupertinoIcons.repeat, color: Colors.white70, size: 20),
                title: const Text('تكرار الفيديو',
                    style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15)),
                trailing: CupertinoSwitch(
                  value: localRepeat,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setSheet(() => localRepeat = v);
                    setState(() => _isRepeat = v);
                    widget.audioPlayer.setLoopMode(v ? LoopMode.one : LoopMode.off);
                  },
                ),
              ),

              const Divider(color: Colors.white12, height: 1),

              // ── تشغيل عشوائي ──
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(CupertinoIcons.shuffle, color: Colors.white70, size: 20),
                title: const Text('تشغيل عشوائي',
                    style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15)),
                trailing: CupertinoSwitch(
                  value: localShuffle,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setSheet(() => localShuffle = v);
                    setState(() => _isShuffle = v);
                  },
                ),
              ),

              const Divider(color: Colors.white12, height: 1),

              // ── مشاركة الشاشة ──
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(CupertinoIcons.arrow_turn_up_right, color: Colors.white70, size: 20),
                title: const Text('مشاركة الشاشة',
                    style: TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 15)),
                onTap: () => Navigator.pop(_),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _startHideTimer());
  }

  @override
  Widget build(BuildContext context) {
    final item = audioService.currentItem;
    final title = item?.title.replaceAll(RegExp(r'\.\w+$'), '') ?? '';
    const artist = 'دندن';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── الفيديو بنسبته الأصلية مع pinch zoom ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (d) => _baseScale = _scale,
              onScaleUpdate: (d) {
                setState(() => _scale = (_baseScale * d.scale).clamp(1.0, 3.0));
              },
              child: Transform.scale(
                scale: _scale,
                child: ValueListenableBuilder<VideoPlayerController?>(
                  valueListenable: widget.ctrlNotifier,
                  builder: (_, ctrl, __) {
                    if (ctrl == null) return const SizedBox.expand();
                    return FittedBox(
                      fit: _scale > 1.0 ? BoxFit.cover : BoxFit.contain,
                      child: SizedBox(
                        width: ctrl.value.size.width > 0
                            ? ctrl.value.size.width : 1920,
                        height: ctrl.value.size.height > 0
                            ? ctrl.value.size.height : 1080,
                        child: VideoPlayer(ctrl),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── double tap: يسار=رجوع 10ث، يمين=تقديم 10ث — يعمل دائماً حتى لو الأزرار ظاهرة ──
            // ── ضغطة واحدة → إخفاء الأزرار إذا كانت ظاهرة ──
            Positioned.fill(
              child: Row(
                children: [
                  // نصف الشاشة اليسار → رجوع 10 ثواني
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // ضغطة واحدة: إذا الأزرار ظاهرة أخفها، وإلا أظهرها
                        _toggleControls();
                      },
                      onDoubleTap: () {
                        // إخفاء الأزرار فوراً عند الـ double tap
                        if (_showControls) setState(() => _showControls = false);
                        final pos = widget.audioPlayer.position;
                        final back = pos - const Duration(seconds: 10);
                        widget.onSeek(back < Duration.zero ? Duration.zero : back);
                        setState(() => _doubleTapHint = 'backward');
                        _doubleTapHintTimer?.cancel();
                        _doubleTapHintTimer = Timer(const Duration(milliseconds: 900), () {
                          if (mounted) setState(() => _doubleTapHint = null);
                        });
                        _hideTimer?.cancel();
                      },
                    ),
                  ),
                  // نصف الشاشة اليمين → تقديم 10 ثواني
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _toggleControls();
                      },
                      onDoubleTap: () {
                        // إخفاء الأزرار فوراً عند الـ double tap
                        if (_showControls) setState(() => _showControls = false);
                        final pos = widget.audioPlayer.position;
                        widget.onSeek(pos + const Duration(seconds: 10));
                        setState(() => _doubleTapHint = 'forward');
                        _doubleTapHintTimer?.cancel();
                        _doubleTapHintTimer = Timer(const Duration(milliseconds: 900), () {
                          if (mounted) setState(() => _doubleTapHint = null);
                        });
                        _hideTimer?.cancel();
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── أنيميشن التقديم/التأخير الرهيب ──
            if (_doubleTapHint != null)
              _SeekRippleAnimation(isForward: _doubleTapHint == 'forward'),

            // ── طبقة التحكم ──
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x99000000),
                        Color(0x00000000),
                        Color(0x00000000),
                        Color(0x99000000),
                      ],
                      stops: [0.0, 0.3, 0.6, 1.0],
                    ),
                  ),
                  child: Column(
                    children: [
                      // ── الشريط العلوي: عنوان يمين + إعدادات يسار ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // العنوان + الفنان — أقصى اليسار
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontFamily: 'Tajawal',
                                          fontWeight: FontWeight.w700)),
                                  Text(artist,
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontFamily: 'Tajawal')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            // زر الإعدادات — أقصى اليمين
                            GestureDetector(
                              onTap: () {
                                _showSettingsSheet(context);
                                _resetTimer();
                              },
                              child: const Icon(CupertinoIcons.settings,
                                  color: Colors.white, size: 30),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // ── الوسط: السابق + تشغيل + التالي ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () { widget.onPrev(); _resetTimer(); },
                            child: Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(CupertinoIcons.forward_end_fill,
                                  color: Colors.white, size: 26),
                            ),
                          ),
                          const SizedBox(width: 28),
                          StreamBuilder<bool>(
                            stream: widget.audioPlayer.playingStream,
                            builder: (_, snap) {
                              final playing = snap.data ?? false;
                              return GestureDetector(
                                onTap: () { widget.onPlayPause(); _resetTimer(); },
                                child: Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                                    color: Colors.white, size: 36,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 28),
                          GestureDetector(
                            onTap: () { widget.onNext(); _resetTimer(); },
                            child: Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(CupertinoIcons.backward_end_fill,
                                  color: Colors.white, size: 26),
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // ── شريط التقدم + الوقت يسار + زر خروج يمين (كلاهما فوق الشريط) ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                        child: StreamBuilder<Duration?>(
                          stream: widget.audioPlayer.durationStream,
                          builder: (_, durSnap) {
                            return StreamBuilder<Duration>(
                              stream: widget.audioPlayer.positionStream,
                              builder: (_, posSnap) {
                                final dur = durSnap.data ?? Duration.zero;
                                final pos = posSnap.data ?? Duration.zero;
                                final progress = dur.inMilliseconds > 0
                                    ? pos.inMilliseconds / dur.inMilliseconds
                                    : 0.0;
                                final display = _dragging ? _dragValue : progress;
                                final displayPos = _dragging
                                    ? Duration(milliseconds: (_dragValue * dur.inMilliseconds).toInt())
                                    : pos;
                                return Column(
                                  children: [
                                    // ── صف الوقت (يسار) + زر الخروج (يمين) فوق الشريط ──
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                                      child: Row(
                                        children: [
                                          // الوقت — يسار مع خلفية سوداء شفافة
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '${_fmt(displayPos)} / ${_fmt(dur)}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          // زر الخروج من ملء الشاشة — يمين
                                          GestureDetector(
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              _resetTimer();
                                            },
                                            child: const Icon(
                                              CupertinoIcons.fullscreen_exit,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            // ── شريط التقدم أبيض سميك مع مسافات جانبية ──
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                                      child: SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 6,
                                        thumbShape: RoundSliderThumbShape(
                                            enabledThumbRadius: _dragging ? 14 : 8),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                                        activeTrackColor: Colors.white,
                                        inactiveTrackColor: Colors.white30,
                                        thumbColor: Colors.white,
                                        overlayColor: Colors.transparent,
                                      ),
                                      child: Slider(
                                        value: display.clamp(0.0, 1.0),
                                        onChangeStart: (v) {
                                          setState(() {
                                            _dragging = true;
                                            _dragValue = v;
                                          });
                                          _hideTimer?.cancel();
                                        },
                                        onChanged: (v) => setState(() => _dragValue = v),
                                        onChangeEnd: (v) {
                                          setState(() => _dragging = false);
                                          final ms = (v * dur.inMilliseconds).toInt();
                                          widget.onSeek(Duration(milliseconds: ms));
                                          _startHideTimer();
                                        },
                                      ),
                                    ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
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
  final ValueNotifier<VideoPlayerController?> _videoCtrlNotifier = ValueNotifier(null);
  bool _videoInitialized = false;
  double _volume = 1.0;
  double _speed = 1.0;
  bool _isSwitching = false;
  bool _isSeeking = false;          // يمنع seekTo المتزامنة
  int _generation = 0;              // يُبطل أي Future قديمة عند تغيير الأغنية

  StreamSubscription? _positionSub;
  StreamSubscription? _playingSub;

  @override
  void initState() {
    super.initState();
    final item = audioService.currentItem;
    if (item != null && !item.isVideo) _loadThumb();
    _initVideoIfNeeded();
    audioService.currentIndex.addListener(_onTrackChange);
  }

  @override
  void dispose() {
    audioService.currentIndex.removeListener(_onTrackChange);
    _positionSub?.cancel();
    _positionSub = null;
    _playingSub?.cancel();
    _playingSub = null;
    _generation++;
    final ctrl = _videoCtrl;
    _videoCtrl = null;
    // امسح القيمة أولاً قبل dispose حتى لا يصل أي listener إلى controller محذوف
    _videoCtrlNotifier.value = null;
    // dispose في الخلفية لا يحجب الـ UI
    Future.microtask(() async {
      try { await ctrl?.pause(); } catch (_) {}
      try { ctrl?.dispose(); } catch (_) {}
    });
    _videoCtrlNotifier.dispose();
    super.dispose();
  }

  void _onTrackChange() {
    _generation++;                  // بطّل كل Futures قديمة
    _positionSub?.cancel();
    _positionSub = null;
    _playingSub?.cancel();
    _playingSub = null;
    _isSeeking = false;

    // تحرير controller القديم في الخلفية
    final oldCtrl = _videoCtrl;
    _videoCtrl = null;
    // إخفاء الـ notifier أولاً قبل dispose القديم
    _videoCtrlNotifier.value = null;
    Future.microtask(() async {
      try { await oldCtrl?.pause(); } catch (_) {}
      try { oldCtrl?.dispose(); } catch (_) {}
    });

    if (!mounted) return;

    // تأجيل setState إلى ما بعد الـ frame الحالي لتجنب إعادة البناء أثناء callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isSwitching = true;
        _thumbPath = null;
        _videoInitialized = false;
      });

      final item = audioService.currentItem;
      if (item == null) {
        if (mounted) setState(() => _isSwitching = false);
        return;
      }

      // مهلة أمان: إذا لم ينتهِ التحميل خلال 8 ثوانٍ أُوقف _isSwitching
      final gen = _generation;
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted && _isSwitching && _generation == gen) {
          setState(() => _isSwitching = false);
        }
      });

      if (!item.isVideo) {
        _loadThumb();
      } else {
        _initVideoIfNeeded();
      }
    });
  }

  Future<void> _initVideoIfNeeded() async {
    final item = audioService.currentItem;
    if (item == null || !item.isVideo) return;

    final gen = _generation;
    final ctrl = VideoPlayerController.file(File(item.path));
    try {
      await ctrl.initialize();

      // تُجاهَل هذه النتيجة إذا تغيّرت الأغنية أثناء التهيئة
      if (!mounted || _generation != gen) {
        try { ctrl.dispose(); } catch (_) {}
        return;
      }

      await ctrl.setVolume(0.0);
      await ctrl.seekTo(audioService.player.position);
      if (audioService.player.playing) await ctrl.play();

      if (!mounted || _generation != gen) {
        try { ctrl.dispose(); } catch (_) {}
        return;
      }

      setState(() {
        _videoCtrl = ctrl;
        _videoInitialized = true;
        _isSwitching = false;
      });
      _videoCtrlNotifier.value = ctrl;

      // مزامنة الموقف — مع حماية كاملة من الـ deadlock
      _positionSub = audioService.player.positionStream.listen((pos) {
        if (_generation != gen || _videoCtrl == null || !_videoInitialized) return;
        if (_isSeeking) return;
        final diff = (ctrl.value.position - pos).abs();
        if (diff.inMilliseconds > 800) {
          _isSeeking = true;
          ctrl.seekTo(pos).then((_) {
            if (_generation == gen) _isSeeking = false;
          }).catchError((_) {
            _isSeeking = false;
          });
        }
      });

      _playingSub = audioService.player.playingStream.listen((playing) {
        if (_generation != gen || _videoCtrl == null || !_videoInitialized) return;
        try {
          if (playing) { ctrl.play(); } else { ctrl.pause(); }
        } catch (_) {}
      });

    } catch (e) {
      try { ctrl.dispose(); } catch (_) {}
      if (mounted && _generation == gen) {
        setState(() => _isSwitching = false);
      }
    }
  }

  Future<void> _loadThumb() async {
    final item = audioService.currentItem;
    if (item == null) return;
    final gen = _generation;
    final path = await ThumbnailManager.getLocalThumbnail(item.path);
    if (mounted && _generation == gen) {
      setState(() {
        _thumbPath = path;
        _isSwitching = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final bgColor = isDark
        ? const Color(0xFF0A0A0F)
        : const Color(0xFFF0F0F5);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final controlBg = isDark ? Colors.white12 : Colors.black.withOpacity(0.07);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 400) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          SafeArea(
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
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: controlBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08),
                          width: 0.5,
                        ),
                      ),
                      child: Icon(CupertinoIcons.chevron_down,
                          color: textColor, size: 20),
                    ),
                  ),
                  const Spacer(),
                  Column(
                    children: [
                      Text(
                        'يُشغَّل الآن',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 24, height: 2.5,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(width: 38),
                ],
              ),
            ),

            // ── Video / Artwork ──
            ValueListenableBuilder<int>(
              valueListenable: audioService.currentIndex,
              builder: (_, idx, __) {
                final item = audioService.currentItem;
                final isVideo = item?.isVideo == true;

                if (isVideo) {
                  return Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.5 : 0.15),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          color: Colors.black,
                          child: _videoInitialized && _videoCtrl != null
                              ? _VideoPlayerWidget(
                                  ctrlNotifier: _videoCtrlNotifier,
                                  audioPlayer: audioService.player,
                                  onSeek: (pos) {
                                    audioService.player.seek(pos);
                                    _videoCtrl?.seekTo(pos);
                                  },
                                  onPlayPause: () {
                                    if (audioService.player.playing) {
                                      audioService.pauseByUser();
                                    } else {
                                      audioService.playByUser();
                                    }
                                  },
                                  onNext: () => audioService.playNext(),
                                  onPrev: () => audioService.playPrevious(),
                                  speed: _speed,
                                  volume: _volume,
                                  onSpeedChange: _setSpeed,
                                  onVolumeChange: _setVolume,
                                )
                              : const Center(
                                  child: SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation(Colors.white38),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                  );
                }

                // ── وضع الصوت: صورة مربعة مع ظل رائع ──
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 8),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.25),
                            blurRadius: 40,
                            spreadRadius: 5,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: _thumbPath != null
                            ? Image.file(
                                File(_thumbPath!),
                                fit: BoxFit.cover,
                                width: double.infinity,
                              )
                            : Container(
                                width: double.infinity,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFFE8272A),
                                      Color(0xFF8B1010),
                                      Color(0xFF3D0505),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // دوائر زخرفية خلف الأيقونة
                                    Positioned(
                                      top: -20, right: -20,
                                      child: Container(
                                        width: 120, height: 120,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white.withOpacity(0.05),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: -30, left: -30,
                                      child: Container(
                                        width: 160, height: 160,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white.withOpacity(0.04),
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      CupertinoIcons.music_note_2,
                                      color: Colors.white.withOpacity(0.6),
                                      size: 80,
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
            // ── Track Info ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: ValueListenableBuilder<int>(
                valueListenable: audioService.currentIndex,
                builder: (_, __, ___) {
                  final item = audioService.currentItem;
                  final title = item?.title.replaceAll(RegExp(r'\.\w+$'), '') ?? '';
                  return Row(
                    textDirection: TextDirection.rtl,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Logo / أيقونة ──
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 46, height: 46, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 46, height: 46,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppColors.primary, AppColors.primaryDark],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(CupertinoIcons.music_note_2,
                                  color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // ── Title + دندن ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.length > 27
                                  ? '${title.substring(0, 27)}...'
                                  : title,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 20,
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  width: 6, height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'دندن',
                                  style: TextStyle(
                                      color: subColor, fontSize: 13, fontFamily: 'Tajawal'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 10),

            // ── أزرار التشغيل (للصوت فقط — الفيديو له تحكم داخلي) ──
            if (!_isSwitching && !(_videoInitialized && _videoCtrl != null)) ...[
              // شريط تقدم الصوت
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: StreamBuilder<Duration?>(
                  stream: audioService.player.durationStream,
                  builder: (_, durSnap) {
                    return StreamBuilder<Duration>(
                      stream: audioService.player.positionStream,
                      builder: (_, posSnap) {
                        final dur = durSnap.data ?? Duration.zero;
                        final pos = posSnap.data ?? Duration.zero;
                        final progress = dur.inMilliseconds > 0
                            ? pos.inMilliseconds / dur.inMilliseconds
                            : 0.0;
                        return Column(
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                activeTrackColor: AppColors.primary,
                                inactiveTrackColor: isDark ? Colors.white.withOpacity(0.15) : Colors.black12,
                                thumbColor: Colors.white,
                                overlayColor: AppColors.primary.withOpacity(0.2),
                                trackShape: const RoundedRectSliderTrackShape(),
                              ),
                              child: Slider(
                                value: progress.clamp(0.0, 1.0),
                                onChanged: (v) {
                                  final ms = (v * dur.inMilliseconds).toInt();
                                  audioService.player.seek(Duration(milliseconds: ms));
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${pos.inMinutes.remainder(60).toString().padLeft(2,'0')}:${pos.inSeconds.remainder(60).toString().padLeft(2,'0')}',
                                    style: TextStyle(color: subColor, fontSize: 11, fontFamily: 'Tajawal'),
                                  ),
                                  Text(
                                    '${dur.inMinutes.remainder(60).toString().padLeft(2,'0')}:${dur.inSeconds.remainder(60).toString().padLeft(2,'0')}',
                                    style: TextStyle(color: subColor, fontSize: 11, fontFamily: 'Tajawal'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // أزرار السابق + تشغيل + التالي
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // السابق
                  GestureDetector(
                    onTap: () => audioService.playPrevious(),
                    child: Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: controlBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                      child: Icon(CupertinoIcons.backward_end_fill,
                          color: textColor, size: 24),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // تشغيل / إيقاف
                  StreamBuilder<bool>(
                    stream: audioService.player.playingStream,
                    builder: (_, snap) {
                      final playing = snap.data ?? false;
                      return GestureDetector(
                        onTap: () => playing
                            ? audioService.pauseByUser()
                            : audioService.playByUser(),
                        child: Container(
                          width: 76, height: 76,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.5),
                                blurRadius: 28,
                                spreadRadius: 2,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Icon(
                            playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                            color: Colors.white, size: 34,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 20),
                  // التالي
                  GestureDetector(
                    onTap: () => audioService.playNext(),
                    child: Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: controlBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                      child: Icon(CupertinoIcons.forward_end_fill,
                          color: textColor, size: 24),
                    ),
                  ),
                ],
              ),
            ], // end audio-only

            const SizedBox(height: 12),

            // ── فاصل أنيق ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(height: 0.5, width: 24,
                      color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08)),
                  Expanded(
                    child: Container(
                      height: 0.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppColors.primary.withOpacity(0.5),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(height: 0.5, width: 24,
                      color: isDark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08)),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // ── قائمة التشغيل ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.music_note_list,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'قائمة التشغيل',
                          style: TextStyle(
                            color: subColor, fontSize: 13,
                            fontFamily: 'Tajawal', fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
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
                                return _PlaylistTile(
                                  item: item,
                                  isActive: isActive,
                                  textColor: textColor,
                                  subColor: subColor,
                                  onTap: () => Future.microtask(() => audioService.playAtIndex(i)),
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
          // ── Idle Overlay فوق كل شيء ──
          const Positioned.fill(
            child: _IdleOverlay(),
          ),
        ],
      ),
    ),
    );
  }
}

// ─────────────────────────────────────────────
//  MARQUEE TITLE — عنوان متحرك للمشغل الكبير
// ─────────────────────────────────────────────
class _MarqueeTitle extends StatefulWidget {
  final String text;
  final Color textColor;
  final int maxCharsBeforeScroll;

  const _MarqueeTitle({
    super.key,
    required this.text,
    required this.textColor,
    this.maxCharsBeforeScroll = 27,
  });

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollCtrl;
  Timer? _timer;
  bool _needsScroll = false;
  // رقم جيل يُبطل أي حلقة قديمة فور تغيير النص أو dispose
  int _loopGen = 0;

  static const double _gap = 60.0;
  static const double _speed = 40.0; // بكسل في الثانية

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
  }

  @override
  void didUpdateWidget(_MarqueeTitle old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      // إلغاء الحلقة القديمة فوراً برفع رقم الجيل
      _loopGen++;
      _timer?.cancel();
      _timer = null;
      if (_scrollCtrl.hasClients) {
        try { _scrollCtrl.jumpTo(0); } catch (_) {}
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
    }
  }

  void _startMarquee() {
    if (!mounted) return;
    final needsScroll = widget.text.length > widget.maxCharsBeforeScroll;
    if (mounted) setState(() => _needsScroll = needsScroll);
    if (!needsScroll) return;

    final gen = _loopGen;
    _timer = Timer(const Duration(seconds: 1), () {
      if (mounted && _loopGen == gen) _loop(gen);
    });
  }

  void _loop(int gen) {
    // إذا تغيّر الجيل أو تم الـ dispose أو لا يوجد clients → توقف
    if (!mounted || _loopGen != gen || !_scrollCtrl.hasClients) return;

    double oneLoop;
    try {
      oneLoop = _scrollCtrl.position.maxScrollExtent / 2 + _gap / 2;
    } catch (_) { return; }
    if (oneLoop <= 0) return;

    final duration = Duration(milliseconds: (oneLoop / _speed * 1000).toInt());

    _scrollCtrl
        .animateTo(
          _scrollCtrl.offset + oneLoop,
          duration: duration,
          curve: Curves.linear,
        )
        .then((_) {
          if (!mounted || _loopGen != gen || !_scrollCtrl.hasClients) return;

          try {
            if (_scrollCtrl.offset >= oneLoop) {
              _scrollCtrl.jumpTo(_scrollCtrl.offset - oneLoop);
            }
          } catch (_) {
            return;
          }

          _loop(gen);
        })
        .catchError((_) {/* animation cancelled — توقف بهدوء */});
  }

  @override
  void dispose() {
    _loopGen++; // إبطال أي حلقة جارية
    _timer?.cancel();
    _timer = null;
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: _needsScroll
          ? ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: const [0.0, 0.05, 0.88, 1.0],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.text,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: widget.textColor,
                        fontSize: 20,
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: _gap),
                    Text(
                      widget.text,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: widget.textColor,
                        fontSize: 20,
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: _gap),
                  ],
                ),
              ),
            )
          : Text(
              widget.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: widget.textColor,
                fontSize: 20,
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  IDLE OVERLAY — يظهر بعد 10 ثواني من عدم التفاعل
// ═══════════════════════════════════════════════════════════
class _IdleOverlay extends StatefulWidget {
  const _IdleOverlay();

  @override
  State<_IdleOverlay> createState() => _IdleOverlayState();
}

class _IdleOverlayState extends State<_IdleOverlay>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  Timer? _idleTimer;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _resetTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _resetTimer() {
    _idleTimer?.cancel();
    // إذا كان الـ overlay ظاهراً → أخفه فوراً
    if (_visible) _hide();
    _idleTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) _show();
    });
  }

  void _show() {
    setState(() => _visible = true);
    _fadeCtrl.forward();
    // إخفاء شريط الحالة والتنقل → وضع ملء الشاشة
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _hide() {
    _fadeCtrl.reverse().then((_) {
      if (mounted) setState(() => _visible = false);
    });
    // استعادة شريط الحالة والتنقل
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  void _onTap() {
    _resetTimer();
  }

@override
Widget build(BuildContext context) {
return Listener(
  behavior: HitTestBehavior.translucent,

  onPointerDown: (_) {
    if (_visible) return;
    _onTap();
  },

  onPointerMove: (_) {
    if (_visible) return;
    _onTap();
  },

  child: Stack(
    children: [
      if (_visible)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,

            onTap: () {
              _hide();
              _resetTimer();
            },

            child: FadeTransition(
              opacity: _fadeAnim,
              child: _IdleOverlayContent(),
            ),
          ),
        ),
    ],
  ),
);
}
}

// ─────────────────────────────────────────────
//  محتوى الـ Idle Overlay
// ─────────────────────────────────────────────

/// بناء TextSpan مختلط: كلمات عربية → mzghrf، كلمات إنجليزية → zen
List<TextSpan> _buildMixedTitleSpans(String title) {
  // نقسم النص على المسافات مع الاحتفاظ بها
  final parts = title.split(RegExp(r'(?<=\s)|(?=\s)'));
  return parts.map((part) {
    final isEnglish = RegExp(r'^[A-Za-z0-9\s\p{P}]+$', unicode: true).hasMatch(part.trim()) && part.trim().isNotEmpty;
    return TextSpan(
      text: part,
      style: TextStyle(
        fontFamily: isEnglish ? 'zen' : 'mzghrf',
        fontSize: 28,
        fontWeight: FontWeight.w100,
        color: Colors.white,
        height: 1.3,
        leadingDistribution: TextLeadingDistribution.even,
        shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
      ),
    );
  }).toList();
}

class _IdleOverlayContent extends StatefulWidget {
  @override
  State<_IdleOverlayContent> createState() => _IdleOverlayContentState();
}

class _IdleOverlayContentState extends State<_IdleOverlayContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _titleScrollCtrl;
  late ScrollController _scrollCtrl;
  Timer? _scrollTimer;

  @override
  void initState() {
    super.initState();
    _titleScrollCtrl = AnimationController(vsync: this);
    _scrollCtrl = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startTitleScroll());
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _titleScrollCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _startTitleScroll() {
    if (!mounted) return;
    final item = audioService.currentItem;
    if (item == null) return;
    final title = item.title.replaceAll(RegExp(r'\.\w+$'), '');
    if (title.length <= 22) return;

    _scrollTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      _scrollLoop();
    });
  }

  void _scrollLoop() {
    if (!mounted || !_scrollCtrl.hasClients) return;
    final maxExtent = _scrollCtrl.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final duration = Duration(milliseconds: (maxExtent / 35 * 1000).toInt());
    _scrollCtrl
        .animateTo(maxExtent, duration: duration, curve: Curves.linear)
        .then((_) {
          if (!mounted || !_scrollCtrl.hasClients) return;
          _scrollCtrl.jumpTo(0);
          _scrollTimer = Timer(const Duration(milliseconds: 800), () {
            if (mounted) _scrollLoop();
          });
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final item = audioService.currentItem;
    final title = item?.title.replaceAll(RegExp(r'\.\w+$'), '') ?? '';

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final totalH = constraints.maxHeight;

        return Stack(
          children: [
            // ── نوتات موسيقية متصاعدة ──
            const _FloatingMusicNotes(),
            // ── الخلفية المتدرجة ──
// ── الخلفية المتدرجة + Blur ──
Positioned(
  bottom: 0,
  left: 0,
  right: 0,
  height: totalH -
    ((MediaQuery.of(context).size.width * (9 / 16)) +
    MediaQuery.of(context).padding.top +
    64),
  child: ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: 2.2,
        sigmaY: 2.2,
      ),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color(0xD0A30000),
              Color.fromARGB(155, 163, 0, 0),
              Color.fromARGB(131, 232, 39, 42),
              Color(0x40C0181B),
              Colors.transparent,
            ],
            stops: [0.0, 0.32, 0.58, 0.82, 1.0],
          ),
        ),
      ),
    ),
  ),
),
            // ── المحتوى في المنتصف-أسفل ──
            Positioned(
              bottom: totalH * 0.08,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── أمواج الصوت الحقيقية ──
                  const SizedBox(
                    height: 72,
                    width: 220,
                    child: _RealSoundWave(),
                  ),

                  const SizedBox(height: 16),

                  // ── عنوان الأغنية — يتحدث فور تغيير الأغنية ──
                  ValueListenableBuilder<int>(
                    valueListenable: audioService.currentIndex,
                    builder: (_, __, ___) {
                      final item = audioService.currentItem;
                      final title = item?.title.replaceAll(RegExp(r'\.\w+$'), '') ?? '';
                      // أعد تشغيل الـ scroll من البداية عند كل أغنية جديدة
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollCtrl.hasClients) {
                          _scrollCtrl.jumpTo(0);
                        }
                        _scrollTimer?.cancel();
                        _startTitleScroll();
                      });
                      return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
                    child: SizedBox(
                      height: 54,
                      child: title.length > 22
                          ? ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
                                stops: [0.0, 0.06, 0.88, 1.0],
                              ).createShader(bounds),
                              blendMode: BlendMode.dstIn,
                              child: SingleChildScrollView(
                                controller: _scrollCtrl,
                                scrollDirection: Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RichText(
                                      maxLines: 1,
                                      textDirection: TextDirection.rtl,
                                      text: TextSpan(children: _buildMixedTitleSpans(title)),
                                    ),
                                    const SizedBox(width: 60),
                                    RichText(
                                      maxLines: 1,
                                      textDirection: TextDirection.rtl,
                                      text: TextSpan(children: _buildMixedTitleSpans(title)),
                                    ),
                                    const SizedBox(width: 60),
                                    RichText(
                                      maxLines: 1,
                                      textDirection: TextDirection.rtl,
                                      text: TextSpan(children: _buildMixedTitleSpans(title)),
                                    ),
                                    const SizedBox(width: 60),
                                  ],
                                ),
                              ),
                            )
                          : RichText(
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              textDirection: TextDirection.rtl,
                              text: TextSpan(children: _buildMixedTitleSpans(title)),
                            ),
                    ),
                  ); // نهاية return Padding داخل ValueListenableBuilder
                    },
                  ), // نهاية ValueListenableBuilder

                  const SizedBox(height: 20),

                  // ── لوجو التطبيق + دندن (أبيض، بدون ظل) ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        color: Colors.white,
                        colorBlendMode: BlendMode.srcIn,
                        errorBuilder: (_, __, ___) => const Icon(
                          CupertinoIcons.music_note_2,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'دندن',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          // بدون shadows
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  _RealSoundWave — أمواج 60fps تتفاعل مع الصوت
// ─────────────────────────────────────────────
class _RealSoundWave extends StatefulWidget {
  const _RealSoundWave();

  @override
  State<_RealSoundWave> createState() => _RealSoundWaveState();
}

class _RealSoundWaveState extends State<_RealSoundWave>
    with SingleTickerProviderStateMixin {

  static const int _barCount = 18;

  // الأرتفاع الحالي لكل شريط (يتحرك بـ lerp ناعم)
  final List<double> _heights = List.filled(_barCount, 0.06);

  // الـ seed الثابت لكل شريط — يعطي كل شريط شخصيته الخاصة
  // أرقام أولية مختلفة لتردد مختلف لكل شريط
  static const List<double> _freq1 = [
    1.30, 1.85, 2.40, 1.60, 2.10, 1.45, 2.70, 1.90,
    2.25, 1.55, 2.80, 1.75, 2.15, 1.40, 2.60, 1.95, 2.35, 1.65,
  ];
  static const List<double> _freq2 = [
    3.10, 2.45, 3.70, 2.90, 3.30, 2.65, 3.85, 2.50,
    3.15, 2.80, 3.50, 2.35, 3.75, 2.95, 3.20, 2.55, 3.60, 2.70,
  ];
  static const List<double> _phase0 = [
    0.00, 0.70, 1.40, 2.10, 2.80, 0.35, 1.05, 1.75,
    2.45, 3.15, 0.50, 1.20, 1.90, 2.60, 0.15, 0.85, 1.55, 2.25,
  ];

  // تحكم التشغيل
  late AnimationController _ticker;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _posSub;

  bool _isPlaying = false;
  double _songTime = 0.0;       // الزمن الحقيقي للأغنية بالثانية
  double _animTime = 0.0;       // زمن الـ animation المتراكم (60fps)
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 999),
    )..addListener(_onFrame)..forward();

    // مزامنة حالة التشغيل
    _playingSub = audioService.player.playingStream.listen((playing) {
      if (!mounted) return;
      _isPlaying = playing;
    });

    // نأخذ الزمن الحقيقي من positionStream كـ seed للتنوع
    _posSub = audioService.player.positionStream.listen((pos) {
      if (!mounted) return;
      _songTime = pos.inMilliseconds / 1000.0;
      if (!_isPlaying) _isPlaying = audioService.player.playing;
    });

    // قراءة الحالة الابتدائية
    _isPlaying = audioService.player.playing;
    _songTime = audioService.player.position.inMilliseconds / 1000.0;
  }

  void _onFrame() {
    if (!mounted) return;

    // حساب delta time حقيقي (بالثانية) بين كل frame
    final now = DateTime.now();
    final dt = _lastTick == null
        ? 0.016
        : now.difference(_lastTick!).inMicroseconds / 1000000.0;
    _lastTick = now;

    // تراكم زمن الأنيميشن بسرعة مناسبة للحركة الجميلة
    if (_isPlaying) {
      _animTime += dt;
    }

    setState(() {
      for (int i = 0; i < _barCount; i++) {
        final double target;

        if (_isPlaying) {
          // ── وضع التشغيل: كل شريط له موجتان بترددات مختلفة ──
          // الموجة الأولى: سريعة وحيّة (تمثل الإيقاع)
          final w1 = math.sin(_animTime * _freq1[i] * math.pi + _phase0[i]);
          // الموجة الثانية: بطيئة وعميقة (تمثل الهارمونيكس)
          final w2 = math.sin(_animTime * _freq2[i] * 0.7 * math.pi + _phase0[i] + 1.3);
          // موجة ثالثة مبنية على زمن الأغنية الحقيقي للتنوع
          final w3 = math.sin(_songTime * 0.8 + i * 0.55 + _phase0[i] * 0.5);

          // دمج الموجات: الأولى تسيطر، الثانية تضيف عمق، الثالثة تضيف تنوع
          final combined = w1 * 0.55 + w2 * 0.30 + w3 * 0.15;

          // تحويل من [-1,1] إلى [minH, 1.0]
          // الأشرطة الوسطية لها سقف أعلى قليلاً
          final center = (i - (_barCount - 1) / 2).abs() / ((_barCount - 1) / 2);
          final maxH = 1.0 - center * 0.18;  // الوسط 100%، الأطراف 82%
          final minH = 0.12;

          target = minH + (combined * 0.5 + 0.5) * (maxH - minH);
        } else {
          // ── وضع الإيقاف: موجة هادئة جداً تنبض ببطء ──
          final idle = math.sin(_animTime * 1.2 * math.pi + _phase0[i]);
          target = 0.05 + (idle * 0.5 + 0.5) * 0.07;
        }

        // Lerp ناعم جداً — سرعة مختلفة حسب الاتجاه
        // عند الصعود أسرع (استجابة للإيقاع)، عند النزول أبطأ (ذيل ناعم)
        final diff = target - _heights[i];
        final lerpSpeed = diff > 0 ? 0.28 : 0.16;
        _heights[i] += diff * lerpSpeed;
      }
    });
  }

  @override
  void dispose() {
    _ticker.removeListener(_onFrame);
    _ticker.dispose();
    _playingSub?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveformPainter(
        heights: _heights,
        isPlaying: _isPlaying,
      ),
      size: const Size(double.infinity, 72),
    );
  }
}

// ─────────────────────────────────────────────
//  _WaveformPainter — رسم الأمواج بـ CustomPainter
// ─────────────────────────────────────────────
class _WaveformPainter extends CustomPainter {
  final List<double> heights;
  final bool isPlaying;

  const _WaveformPainter({
    required this.heights,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 18;
    final totalW = size.width;
    final totalH = size.height;
    final centerY = totalH / 2;

    // حساب عرض الشريط والمسافة بشكل متناسق
    // نريد مسافة صغيرة ومتناسقة بين الأشرطة
    const barW = 5.0;
    const gap = 4.5;
    final totalNeeded = barCount * barW + (barCount - 1) * gap;
    final startX = (totalW - totalNeeded) / 2 + barW / 2;

    for (int i = 0; i < barCount; i++) {
      final x = startX + i * (barW + gap);
      final rawH = heights[i].clamp(0.04, 1.0);
      final barH = (rawH * totalH * 0.90).clamp(3.0, totalH * 0.92);

      // شفافية: الوسط أكثر وضوحاً، الأطراف أخف قليلاً
      final center = (i - (barCount - 1) / 2).abs() / ((barCount - 1) / 2);
      final baseOpacity = isPlaying
          ? (1.0 - center * 0.28).clamp(0.72, 1.0)
          : (1.0 - center * 0.35).clamp(0.40, 0.65);

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, centerY), width: barW, height: barH),
        const Radius.circular(barW / 2),
      );

      // ── Glow خفيف حول الشريط (فقط عند التشغيل) ──
      if (isPlaying && rawH > 0.25) {
        final glowOpacity = (rawH - 0.25) * 0.22 * baseOpacity;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(x, centerY),
              width: barW + 5,
              height: barH + 4,
            ),
            const Radius.circular((barW + 5) / 2),
          ),
          Paint()
            ..color = Colors.white.withOpacity(glowOpacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
        );
      }

      // ── الشريط الرئيسي بـ gradient أبيض ناعم ──
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(baseOpacity),
              Colors.white.withOpacity(baseOpacity * 0.70),
            ],
          ).createShader(
            Rect.fromCenter(center: Offset(x, centerY), width: barW, height: barH),
          ),
      );

      // ── خط لامع رفيع في المنتصف (يعطي إحساس بعمق) ──
      if (barH > 10) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(x, centerY - barH * 0.12),
              width: barW * 0.35,
              height: barH * 0.30,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = Colors.white.withOpacity(baseOpacity * 0.45),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.isPlaying != isPlaying || old.heights != heights;
}

// ─────────────────────────────────────────────
//  _FallbackSoundWave — احتياطي (مستخدم ضمنياً)
// ─────────────────────────────────────────────
class _FallbackSoundWave extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 72,
      width: double.infinity,
      child: _RealSoundWave(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  _FloatingMusicNotes — نوتات موسيقية تتصاعد بهدوء وجمال
// ═══════════════════════════════════════════════════════════
class _FloatingMusicNotes extends StatefulWidget {
  const _FloatingMusicNotes();

  @override
  State<_FloatingMusicNotes> createState() => _FloatingMusicNotesState();
}

class _FloatingMusicNotesState extends State<_FloatingMusicNotes>
    with TickerProviderStateMixin {

  static const _noteSymbols = ['♩', '♪', '♫', '♬', '𝅘𝅥𝅮', '♩', '♪'];
  final _rand = math.Random();
  final List<_MusicNote> _notes = [];
  late AnimationController _ticker;
  DateTime? _lastTick;
  Timer? _spawnTimer;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(hours: 1))
      ..addListener(_onFrame)
      ..forward();

    // إضافة نوتة جديدة كل فترة بشكل عشوائي وهادئ
    _scheduleNextNote();
  }

  void _scheduleNextNote() {
    if (!mounted) return;
    // توليد نوتة كل 1.2 إلى 2.8 ثانية — هادئ وغير مزعج
    final delay = 1200 + _rand.nextInt(1600);
    _spawnTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      _spawnNote();
      _scheduleNextNote();
    });
  }

  void _spawnNote() {
    if (!mounted) return;
    final symbol = _noteSymbols[_rand.nextInt(_noteSymbols.length)];
    final x = 0.08 + _rand.nextDouble() * 0.84; // موضع أفقي عشوائي بين 8%-92%
    final size = 18.0 + _rand.nextDouble() * 16.0; // حجم بين 18-34
    final speed = 0.045 + _rand.nextDouble() * 0.03; // سرعة هادئة جداً
    final drift = (_rand.nextDouble() - 0.5) * 0.18; // انجراف أفقي طفيف
    final rotationSpeed = (_rand.nextDouble() - 0.5) * 0.8; // دوران بطيء
    final delay = _rand.nextDouble() * 0.3;

    setState(() {
      _notes.add(_MusicNote(
        symbol: symbol,
        x: x,
        y: 1.05, // تبدأ من تحت الشاشة
        size: size,
        speed: speed,
        drift: drift,
        rotationSpeed: rotationSpeed,
        opacity: 0.0,
        rotation: 0.0,
        birthTime: DateTime.now().millisecondsSinceEpoch / 1000.0 + delay,
      ));
    });
  }

  void _onFrame() {
    if (!mounted) return;
    final now = DateTime.now();
    final dt = _lastTick == null
        ? 0.016
        : now.difference(_lastTick!).inMicroseconds / 1000000.0;
    _lastTick = now;

    final currentTime = now.millisecondsSinceEpoch / 1000.0;

    setState(() {
      for (int i = _notes.length - 1; i >= 0; i--) {
        final note = _notes[i];
        // انتظر حتى يحين وقت ظهور النوتة
        if (currentTime < note.birthTime) continue;

        final age = currentTime - note.birthTime;

        // حساب الموضع الجديد
        final newY = note.y - note.speed * dt;
        final newX = note.x + note.drift * dt * 0.3;
        final newRotation = note.rotation + note.rotationSpeed * dt;

        // الشفافية: ظهور تدريجي في البداية، اختفاء تدريجي عند نصف الشاشة
        double newOpacity;
        if (age < 0.6) {
          // ظهور خلال 0.6 ثانية
          newOpacity = (age / 0.6).clamp(0.0, 1.0) * 0.75;
        } else if (newY <= 0.5) {
          // اختفاء تدريجي عند الوصول لنصف الشاشة
          final fadeProgress = ((0.5 - newY) / 0.22).clamp(0.0, 1.0);
          newOpacity = (1.0 - fadeProgress) * 0.75;
        } else {
          newOpacity = 0.75;
        }

        // إزالة النوتة عند اختفائها تماماً أو خروجها من الشاشة
        if (newOpacity <= 0.01 || newY < 0.25) {
          _notes.removeAt(i);
          continue;
        }

        _notes[i] = _MusicNote(
          symbol: note.symbol,
          x: newX.clamp(0.02, 0.98),
          y: newY,
          size: note.size,
          speed: note.speed,
          drift: note.drift,
          rotationSpeed: note.rotationSpeed,
          opacity: newOpacity,
          rotation: newRotation,
          birthTime: note.birthTime,
        );
      }
    });
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    _ticker.removeListener(_onFrame);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return Stack(
              children: _notes.map((note) {
                return Positioned(
                  left: note.x * w - note.size / 2,
                  top: note.y * h - note.size / 2,
                  child: Opacity(
                    opacity: note.opacity.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: note.rotation,
                      child: Text(
                        note.symbol,
                        style: TextStyle(
                          fontSize: note.size,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.white.withOpacity(0.4),
                              blurRadius: 8,
                            ),
                            Shadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _MusicNote {
  final String symbol;
  final double x;
  final double y;
  final double size;
  final double speed;
  final double drift;
  final double rotationSpeed;
  final double opacity;
  final double rotation;
  final double birthTime;

  const _MusicNote({
    required this.symbol,
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.drift,
    required this.rotationSpeed,
    required this.opacity,
    required this.rotation,
    required this.birthTime,
  });
}

// ═══════════════════════════════════════════════════════════
//  SEEK RIPPLE ANIMATION — أنيميشن التقديم والتأخير الرهيب
// ═══════════════════════════════════════════════════════════
class _SeekRippleAnimation extends StatefulWidget {
  final bool isForward;
  const _SeekRippleAnimation({required this.isForward});

  @override
  State<_SeekRippleAnimation> createState() => _SeekRippleAnimationState();
}

class _SeekRippleAnimationState extends State<_SeekRippleAnimation>
    with TickerProviderStateMixin {
  late AnimationController _rippleCtrl;
  late AnimationController _arrowCtrl;
  late Animation<double> _rippleAnim;
  late Animation<double> _arrowAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _arrowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _rippleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut),
    );
    _arrowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _arrowCtrl, curve: Curves.elasticOut),
    );
    _fadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _rippleCtrl,
        curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
      ),
    );

    _rippleCtrl.forward();
    _arrowCtrl.forward();
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    _arrowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isForward = widget.isForward;
    return Positioned.fill(
      child: IgnorePointer(
        child: Row(
          children: [
            if (!isForward) Expanded(child: _buildSide(isForward)) else const Expanded(child: SizedBox()),
            if (isForward) Expanded(child: _buildSide(isForward)) else const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
  }

  Widget _buildSide(bool isForward) {
    return AnimatedBuilder(
      animation: Listenable.merge([_rippleCtrl, _arrowCtrl]),
      builder: (_, __) {
        return FadeTransition(
          opacity: _fadeAnim,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: isForward ? Alignment.centerRight : Alignment.centerLeft,
                radius: 1.2,
                colors: [
                  Colors.white.withOpacity(0.18 * _rippleAnim.value),
                  Colors.white.withOpacity(0.06 * _rippleAnim.value),
                  Colors.transparent,
                ],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── السهام المتحركة ──
                  ScaleTransition(
                    scale: _arrowAnim,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        return AnimatedBuilder(
                          animation: _rippleCtrl,
                          builder: (_, __) {
                            final delay = i * 0.12;
                            final progress = (_rippleAnim.value - delay).clamp(0.0, 1.0);
                            return Opacity(
                              opacity: progress,
                              child: Icon(
                                isForward
                                    ? CupertinoIcons.chevron_left
                                    : CupertinoIcons.chevron_right,
                                color: Colors.white,
                                size: 22 + (i * 4.0),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── النص +10 ثواني ──
                  ScaleTransition(
                    scale: _arrowAnim,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: Text(
                        isForward ? '+10 ثواني' : '-10 ثواني',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  PLAYLIST TILE — عنصر قائمة التشغيل مع thumbnail حقيقي
// ─────────────────────────────────────────────
class _PlaylistTile extends StatefulWidget {
  final LocalMediaItem item;
  final bool isActive;
  final Color textColor;
  final Color subColor;
  final VoidCallback onTap;

  const _PlaylistTile({
    required this.item,
    required this.isActive,
    required this.textColor,
    required this.subColor,
    required this.onTap,
  });

  @override
  State<_PlaylistTile> createState() => _PlaylistTileState();
}

class _PlaylistTileState extends State<_PlaylistTile> {
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final path = await ThumbnailManager.getLocalThumbnail(widget.item.path);
    if (mounted && path != null) setState(() => _thumbPath = path);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isActive
              ? Border.all(color: AppColors.primary.withOpacity(0.4), width: 1)
              : null,
        ),
        child: Row(
          children: [
            // ── Thumbnail حقيقي ──
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _thumbPath != null
                  ? Image.file(
                      File(_thumbPath!),
                      width: 52, height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _defaultThumb(isActive),
                    )
                  : (widget.item.thumbnailUrl != null
                      ? CachedNetworkImage(
                          imageUrl: widget.item.thumbnailUrl!,
                          width: 52, height: 52,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _defaultThumb(isActive),
                        )
                      : _defaultThumb(isActive)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.title.replaceAll(RegExp(r'\.\w+$'), ''),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? AppColors.primary : widget.textColor,
                      fontSize: 14,
                      fontFamily: 'Tajawal',
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        widget.item.isVideo
                            ? CupertinoIcons.play_rectangle
                            : CupertinoIcons.music_note,
                        size: 11,
                        color: isActive
                            ? AppColors.primary.withOpacity(0.7)
                            : widget.subColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.item.isVideo ? 'فيديو' : 'صوت',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Tajawal',
                          color: isActive
                              ? AppColors.primary.withOpacity(0.7)
                              : widget.subColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isActive)
              StreamBuilder<bool>(
                stream: audioService.player.playingStream,
                builder: (_, snap) {
                  final playing = snap.data ?? false;
                  return Icon(
                    playing
                        ? CupertinoIcons.pause_circle_fill
                        : CupertinoIcons.play_circle_fill,
                    color: AppColors.primary,
                    size: 22,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _defaultThumb(bool isActive) {
    return Container(
      width: 52, height: 52,
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
      ),
      child: Icon(
        widget.item.isVideo
            ? CupertinoIcons.play_rectangle_fill
            : CupertinoIcons.music_note,
        color: isActive ? Colors.white : (widget.item.isVideo ? Colors.white70 : AppColors.primary),
        size: 22,
      ),
    );
  }
}