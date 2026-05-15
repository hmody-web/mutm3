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
//  يدعم: YouTube URLs + فيديو محلي + Album Art
// ─────────────────────────────────────────────
class ThumbnailManager {
  static final Map<String, String?> _memCache = {};

  // ── مسار ملف الصورة المخزّنة بجانب الملف الأصلي ──
  static String _thumbPath(String mediaPath) {
    final name = mediaPath.split('/').last.replaceAll(RegExp(r'\.\w+$'), '');
    final dir = mediaPath.substring(0, mediaPath.lastIndexOf('/'));
    return '$dir/.thumb_$name.jpg';
  }

  /// يُرجع مسار صورة مصغرة جاهزة (من الكاش أو من الملف) أو null
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
    return AdSlide(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['image'] ?? '',
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
  // true = أوقف المستخدم التشغيل يدوياً → لا نُعيد التشغيل تلقائياً بعد الانقطاع
  bool _userPaused = false;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // عند انتهاء الأغنية → شغّل التالية تلقائياً
    _completionSub = player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _autoNext();
      }
    });

    // ── الاستماع لتغييرات currentIndex من just_audio_background ──
    // عند الضغط على التالي/السابق في الإشعار أو شاشة القفل أو Bluetooth
    // يُغيّر just_audio_background currentIndex في ConcatenatingAudioSource
    _indexSub = player.currentIndexStream.distinct().listen((rawIdx) {
      if (rawIdx == null || _handlingIndexChange) return;
      final list = playlist.value;
      final cur = currentIndex.value;
      if (list.isEmpty || cur < 0) return;
      final hasPrev = cur > 0;

      // rawIdx 0 = السابق (إذا كان موجوداً), 1 أو 0 = الحالي, آخر = التالي
      final currentRawIdx = hasPrev ? 1 : 0;
      if (rawIdx < currentRawIdx) {
        // الضغط على السابق
        _playSingleFile(list, cur - 1);
      } else if (rawIdx > currentRawIdx) {
        // الضغط على التالي
        _playSingleFile(list, cur + 1);
      }
    });

    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        // انقطاع خارجي (مكالمة، تطبيق آخر...) → إيقاف مؤقت تلقائي
        // لكن لا نُغيّر _userPaused حتى لا يُعيد التشغيل بعد الانقطاع إذا كان المستخدم أوقفه
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

    // ── إعادة إظهار المشغل المصغر عند استكمال التشغيل من الإشعار أو شاشة القفل ──
    // عندما يضغط المستخدم على play في الإشعار بعد إخفاء المشغل بزر X،
    // نُعيد isVisible=true حتى يظهر المشغل المصغر مجدداً في التطبيق.
    // نتتبع أيضاً الـ pause القادم من شاشة القفل أو الإشعار (خارج pauseByUser)
    // حتى لا يُعيد interruptionEventStream التشغيل تلقائياً بعد انقطاع خارجي.
    _playingSub = player.playingStream.listen((playing) {
      if (playing) {
        // المستخدم استكمل التشغيل من الإشعار أو شاشة القفل → إلغاء علامة الإيقاف اليدوي
        _userPaused = false;
        if (!isVisible.value && currentIndex.value >= 0) {
          isVisible.value = true;
        }
      } else {
        // توقف التشغيل (من أي مصدر: شاشة القفل، إشعار، أو pauseByUser)
        // نعتبره إيقاف مؤقت مقصود من المستخدم لمنع الاستئناف التلقائي بعد الانقطاعات
        if (!_handlingIndexChange) {
          _userPaused = true;
        }
      }
    });
  }

  void _autoNext() {
    final idx = currentIndex.value;
    final list = playlist.value;
    _userPaused = false; // انتقال تلقائي → أعد التشغيل دائماً
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

  /// ─── الدالة المحورية: تشغيل ملف مع ConcatenatingAudioSource لدعم MediaSession ───
  Future<void> _playSingleFile(List<LocalMediaItem> list, int index) async {
    if (list.isEmpty || index < 0 || index >= list.length) return;
    final item = list[index];

    // ① حدّث القيم المرئية فوراً
    playlist.value = list;
    currentIndex.value = index;
    isVisible.value = true;
    _handlingIndexChange = true;

    // ① بناء tag للأغنية الحالية مع الصورة المصغرة قبل بدء التشغيل
    // لضمان ظهور الصورة في إشعار الخلفية وشاشة القفل فوراً
    final tag = await _buildTag(item);

    try {
      // ── pause() بدلاً من stop() ──
      // stop() يُلغي الـ AVAudioSession ويمسح MPNowPlayingInfoCenter مما يُطفئ
      // ضوابط شاشة القفل والخلفية. pause()+seek() يبقيان الـ session نشطاً
      // ويسمحان باستكمال التشغيل فور استدعاء setAudioSource الجديد.
      if (player.playing) await player.pause();

      // ② بناء ConcatenatingAudioSource بـ [prev?, current, next?]
      // هذا يُفعّل أزرار التالي والسابق في الإشعار وشاشة القفل وBluetooth
      final hasPrev = index > 0;
      final hasNext = index < list.length - 1;

      // دالة مساعدة محلية لبناء MediaItem مع الصورة للأغاني المجاورة
      Future<MediaItem> buildNeighborTag(LocalMediaItem neighbor) async {
        Uri? artUri;
        final localThumb = await ThumbnailManager.getLocalThumbnail(neighbor.path);
        if (localThumb != null) {
          artUri = Uri.file(localThumb);
        } else if (neighbor.thumbnailUrl != null) {
          artUri = Uri.parse(neighbor.thumbnailUrl!);
        }
        return MediaItem(
          id: neighbor.path,
          title: neighbor.title.replaceAll(RegExp(r'\.\w+$'), ''),
          artist: 'دندن',
          artUri: artUri,
        );
      }

      final sources = <AudioSource>[];
      if (hasPrev) {
        final prevTag = await buildNeighborTag(list[index - 1]);
        sources.add(AudioSource.file(list[index - 1].path, tag: prevTag));
      }
      sources.add(AudioSource.file(item.path, tag: tag));
      if (hasNext) {
        final nextTag = await buildNeighborTag(list[index + 1]);
        sources.add(AudioSource.file(list[index + 1].path, tag: nextTag));
      }

      final initialIdx = hasPrev ? 1 : 0;
      final concat = ConcatenatingAudioSource(children: sources);

      await player.setAudioSource(
        concat,
        initialIndex: initialIdx,
        initialPosition: Duration.zero,
        preload: false,
      );

      _handlingIndexChange = false;
      await player.play();

      // ③ تحديث artwork بشكل آمن — بدون إعادة setAudioSource
      // نُولّد الصورة في الخلفية فقط للتخزين المحلي (ThumbnailManager)
      // حتى تكون جاهزة للمرة القادمة. لا نُعيد تحميل الـ source أبداً
      // لأن ذلك كان يُسبب إطفاء الأغنية عند الإيقاف المؤقت من الخلفية.
      Future(() async {
        try {
          if (currentIndex.value != index) return;
          // توليد الصورة وتخزينها محلياً إن لم تكن موجودة
          await ThumbnailManager.generateLocalThumbnail(item.path);
          // توليد صور الأغاني المجاورة في الخلفية
          if (hasPrev) await ThumbnailManager.generateLocalThumbnail(list[index - 1].path);
          if (hasNext) await ThumbnailManager.generateLocalThumbnail(list[index + 1].path);
        } catch (_) {}
      });
    } catch (e) {
      _handlingIndexChange = false;
      debugPrint('AudioPlayerService._playSingleFile error: $e');
    }
  }

  Future<void> playList(List<LocalMediaItem> items, int startIndex) async {
    _userPaused = false; // تشغيل جديد → إلغاء حالة الإيقاف اليدوي
    final idx = startIndex.clamp(0, items.length - 1);
    await _playSingleFile(List.unmodifiable(items), idx);
  }

  Future<void> playAtIndex(int index) async {
    _userPaused = false;
    final list = playlist.value;
    if (list.isEmpty) return;
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
    final idx = currentIndex.value;
    final list = playlist.value;
    if (idx < list.length - 1) {
      await _playSingleFile(list, idx + 1);
    }
  }

  Future<void> playPrevious() async {
    _userPaused = false;
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
    with TickerProviderStateMixin {
  late AnimationController _indicatorCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
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
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _pulseAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.03)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.03, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(_pulseCtrl);
    _navIndexNotifier.addListener(_onNavChange);
  }

  @override
  void dispose() {
    _navIndexNotifier.removeListener(_onNavChange);
    _indicatorCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _triggerPulse() {
    _pulseCtrl.forward(from: 0.0);
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

    return GestureDetector(
      onTapDown: (_) => _triggerPulse(),
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) => Transform.scale(
          scale: _pulseAnim.value,
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
              // زجاج شفاف حقيقي
              color: isDark
                  ? Colors.black.withOpacity(0.30)
                  : Colors.white.withOpacity(0.28),
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
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.02),
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
                      color: AppColors.primary.withOpacity(isDark ? 0.12 : 0.08),
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
                                size: 22,
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
                            isDark: isDark,
                            onTap: () {
                              audioService.pauseByUser();
                              audioService.isVisible.value = false;
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
  final bool isDark;
  const _MiniBtn({required this.icon, required this.onTap, this.size = 20, this.isDark = true});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Icon(icon,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            size: size),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  VIDEO PLAYER WIDGET — مشغل فيديو متكامل مع ملء الشاشة
// ═══════════════════════════════════════════════════════════
class _VideoPlayerWidget extends StatefulWidget {
  final VideoPlayerController ctrl;
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
    required this.ctrl,
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

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    // دائماً أعد Portrait + System UI عند تدمير الـ widget
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
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
          ctrl: widget.ctrl,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // زر مستوى الصوت
          GestureDetector(
            onTap: () {
              setState(() {
                _showVolumeBar = !_showVolumeBar;
                _showSpeedOptions = false;
              });
              _resetTimer();
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _showVolumeBar ? AppColors.primary : Colors.black45,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                widget.volume == 0
                    ? CupertinoIcons.speaker_slash_fill
                    : widget.volume < 1.0
                        ? CupertinoIcons.speaker_1_fill
                        : CupertinoIcons.speaker_3_fill,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),

          // شريط الصوت المنسدل
          if (_showVolumeBar) ...[
            const SizedBox(width: 6),
            Expanded(
              child: SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 2,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                ),
                child: Slider(
                  value: widget.volume.clamp(0.0, 3.0),
                  min: 0,
                  max: 3.0,
                  onChanged: (v) {
                    widget.onVolumeChange(v);
                    _resetTimer();
                  },
                ),
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${(widget.volume * 100).toInt()}%',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 10, fontFamily: 'Tajawal'),
                textAlign: TextAlign.end,
              ),
            ),
          ] else
            const Spacer(),

          const SizedBox(width: 6),

          // زر السرعة
          GestureDetector(
            onTap: () {
              setState(() {
                _showSpeedOptions = !_showSpeedOptions;
                _showVolumeBar = false;
              });
              _resetTimer();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: _showSpeedOptions ? AppColors.primary : Colors.black45,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.speed == 1.0 ? '1×' : '${widget.speed}×',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // زر ملء الشاشة
          GestureDetector(
            onTap: () {
              _toggleFullScreen();
              _resetTimer();
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _isFullScreen
                    ? CupertinoIcons.fullscreen_exit
                    : CupertinoIcons.fullscreen,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
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
    final videoContent = SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── الفيديو يملأ كامل الحاوية ──
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: widget.ctrl.value.size.width > 0 ? widget.ctrl.value.size.width : 1920,
                height: widget.ctrl.value.size.height > 0 ? widget.ctrl.value.size.height : 1080,
                child: VideoPlayer(widget.ctrl),
              ),
            ),

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
                      // ── الشريط العلوي: صوت + سرعة + ملء ──
                      _buildTopBar(),

                      // ── لوحة خيارات السرعة ──
                      if (_showSpeedOptions) _buildSpeedPanel(),

                      const Spacer(),

                      // ── الوسط: ترجيع + تشغيل + تقديم ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // زر السابق 10 ثواني
                          GestureDetector(
                            onTap: () {
                              final pos = widget.audioPlayer.position;
                              final back = pos - const Duration(seconds: 10);
                              widget.onSeek(back < Duration.zero ? Duration.zero : back);
                              _resetTimer();
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(CupertinoIcons.gobackward_10,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // زر عشوائي
                          GestureDetector(
                            onTap: () {
                              setState(() => _isShuffle = !_isShuffle);
                              _resetTimer();
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _isShuffle
                                    ? AppColors.primary.withOpacity(0.7)
                                    : Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                CupertinoIcons.shuffle,
                                color: _isShuffle ? Colors.white : Colors.white70,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),

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
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withOpacity(0.55),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    playing
                                        ? CupertinoIcons.pause_fill
                                        : CupertinoIcons.play_fill,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 14),

                          // زر تكرار
                          GestureDetector(
                            onTap: () {
                              setState(() => _isRepeat = !_isRepeat);
                              widget.audioPlayer.setLoopMode(
                                  _isRepeat ? LoopMode.off : LoopMode.one);
                              _resetTimer();
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _isRepeat
                                    ? AppColors.primary.withOpacity(0.7)
                                    : Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                CupertinoIcons.repeat,
                                color: _isRepeat ? Colors.white : Colors.white70,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // زر التالي 10 ثواني
                          GestureDetector(
                            onTap: () {
                              final pos = widget.audioPlayer.position;
                              widget.onSeek(pos + const Duration(seconds: 10));
                              _resetTimer();
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(CupertinoIcons.goforward_10,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // ── شريط التقدم السفلي ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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
                                return Column(
                                  children: [
                                    SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 3,
                                        thumbShape: const RoundSliderThumbShape(
                                            enabledThumbRadius: 7),
                                        overlayShape: const RoundSliderOverlayShape(
                                            overlayRadius: 14),
                                        activeTrackColor: AppColors.primary,
                                        inactiveTrackColor: Colors.white30,
                                        thumbColor: Colors.white,
                                        overlayColor:
                                            AppColors.primary.withOpacity(0.3),
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
                                          final ms =
                                              (v * dur.inMilliseconds).toInt();
                                          widget.onSeek(
                                              Duration(milliseconds: ms));
                                          _startHideTimer();
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _fmt(_dragging
                                                ? Duration(
                                                    milliseconds: (_dragValue *
                                                            dur.inMilliseconds)
                                                        .toInt())
                                                : pos),
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11),
                                          ),
                                          Text(
                                            _fmt(dur),
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11),
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
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // ── وضع عادي: نسبة 16:9 بدون سواد ──
    return AspectRatio(
      aspectRatio: widget.ctrl.value.aspectRatio > 0
          ? widget.ctrl.value.aspectRatio
          : 16 / 9,
      child: Container(
        color: Colors.black,
        child: videoContent,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  IMMERSIVE FULLSCREEN PAGE — صفحة ملء الشاشة الحقيقية
//  مثل يوتيوب تماماً: لا StatusBar، لا NavigationBar، لا فراغات
// ═══════════════════════════════════════════════════════════
class _ImmersiveFullScreenPage extends StatefulWidget {
  final VideoPlayerController ctrl;
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
    required this.ctrl,
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
  bool _showVolumeBar = false;
  bool _showSpeedOptions = false;
  bool _isShuffle = false;
  bool _isRepeat = false;

  static const List<double> _fastSpeeds = [1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    // تأكيد إخفاء System UI عند بناء الصفحة
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
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

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
      child: Material(
        color: Colors.black,
        child: GestureDetector(
          onTap: _toggleControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── الفيديو يغطي الشاشة كاملة بدون فراغات ──
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: widget.ctrl.value.size.width > 0
                      ? widget.ctrl.value.size.width
                      : 1920,
                  height: widget.ctrl.value.size.height > 0
                      ? widget.ctrl.value.size.height
                      : 1080,
                  child: VideoPlayer(widget.ctrl),
                ),
              ),

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
                        // ── الشريط العلوي: رجوع + صوت + سرعة ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              // زر الرجوع (إغلاق fullscreen)
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.chevron_down,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // زر مستوى الصوت
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _showVolumeBar = !_showVolumeBar;
                                    _showSpeedOptions = false;
                                  });
                                  _resetTimer();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: _showVolumeBar ? AppColors.primary : Colors.black45,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    widget.volume == 0
                                        ? CupertinoIcons.speaker_slash_fill
                                        : widget.volume < 1.0
                                            ? CupertinoIcons.speaker_1_fill
                                            : CupertinoIcons.speaker_3_fill,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),

                              if (_showVolumeBar) ...[
                                const SizedBox(width: 6),
                                Expanded(
                                  child: SliderTheme(
                                    data: const SliderThemeData(
                                      trackHeight: 2,
                                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                                      overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor: Colors.white30,
                                      thumbColor: Colors.white,
                                      overlayColor: Colors.white24,
                                    ),
                                    child: Slider(
                                      value: widget.volume.clamp(0.0, 3.0),
                                      min: 0,
                                      max: 3.0,
                                      onChanged: (v) {
                                        widget.onVolumeChange(v);
                                        _resetTimer();
                                      },
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    '${(widget.volume * 100).toInt()}%',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 10, fontFamily: 'Tajawal'),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ] else
                                const Spacer(),

                              const SizedBox(width: 6),

                              // زر السرعة
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _showSpeedOptions = !_showSpeedOptions;
                                    _showVolumeBar = false;
                                  });
                                  _resetTimer();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: _showSpeedOptions ? AppColors.primary : Colors.black45,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    widget.speed == 1.0 ? '1×' : '${widget.speed}×',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontFamily: 'Tajawal',
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // لوحة السرعة
                        if (_showSpeedOptions)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final s in _fastSpeeds)
                                  GestureDetector(
                                    onTap: () {
                                      widget.onSpeedChange(s);
                                      setState(() => _showSpeedOptions = false);
                                      _resetTimer();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      decoration: BoxDecoration(
                                        color: widget.speed == s
                                            ? AppColors.primary
                                            : Colors.white10,
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

                        const Spacer(),

                        // ── الوسط: ترجيع + تشغيل + تقديم ──
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                final pos = widget.audioPlayer.position;
                                final back = pos - const Duration(seconds: 10);
                                widget.onSeek(back < Duration.zero ? Duration.zero : back);
                                _resetTimer();
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                                child: const Icon(CupertinoIcons.gobackward_10, color: Colors.white, size: 20),
                              ),
                            ),
                            const SizedBox(width: 12),

                            GestureDetector(
                              onTap: () {
                                setState(() => _isShuffle = !_isShuffle);
                                _resetTimer();
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _isShuffle ? AppColors.primary.withOpacity(0.7) : Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(CupertinoIcons.shuffle,
                                    color: _isShuffle ? Colors.white : Colors.white70, size: 18),
                              ),
                            ),
                            const SizedBox(width: 14),

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
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withOpacity(0.55),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 14),

                            GestureDetector(
                              onTap: () {
                                setState(() => _isRepeat = !_isRepeat);
                                widget.audioPlayer.setLoopMode(
                                    _isRepeat ? LoopMode.off : LoopMode.one);
                                _resetTimer();
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _isRepeat ? AppColors.primary.withOpacity(0.7) : Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(CupertinoIcons.repeat,
                                    color: _isRepeat ? Colors.white : Colors.white70, size: 18),
                              ),
                            ),
                            const SizedBox(width: 12),

                            GestureDetector(
                              onTap: () {
                                final pos = widget.audioPlayer.position;
                                widget.onSeek(pos + const Duration(seconds: 10));
                                _resetTimer();
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                                child: const Icon(CupertinoIcons.goforward_10, color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),

                        const Spacer(),

                        // ── شريط التقدم السفلي ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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
                                  return Column(
                                    children: [
                                      SliderTheme(
                                        data: SliderThemeData(
                                          trackHeight: 3,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                          activeTrackColor: AppColors.primary,
                                          inactiveTrackColor: Colors.white30,
                                          thumbColor: Colors.white,
                                          overlayColor: AppColors.primary.withOpacity(0.3),
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
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _fmt(_dragging
                                                  ? Duration(milliseconds: (_dragValue * dur.inMilliseconds).toInt())
                                                  : pos),
                                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                                            ),
                                            Text(
                                              _fmt(dur),
                                              style: const TextStyle(color: Colors.white70, fontSize: 11),
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
  // يمنع ظهور عناصر التحكم القديمة أثناء الانتقال بين الأغاني
  bool _isSwitching = false;

  // نتابع الـ streams حتى نُلغيها عند dispose
  StreamSubscription? _positionSub;
  StreamSubscription? _playingSub;

  @override
  void initState() {
    super.initState();
    // للأغاني فقط نُحمّل الـ thumbnail — للفيديوهات نبدأ بأسود مباشرة
    final item = audioService.currentItem;
    if (item != null && !item.isVideo) _loadThumb();
    _initVideoIfNeeded();
    audioService.currentIndex.addListener(_onTrackChange);
  }

  @override
  void dispose() {
    audioService.currentIndex.removeListener(_onTrackChange);
    _positionSub?.cancel();
    _playingSub?.cancel();
    // نوقف الفيديو المرئي فقط — الصوت يستمر عبر just_audio في الخلفية
    _videoCtrl?.pause();
    _videoCtrl?.dispose();
    super.dispose();
  }

  void _onTrackChange() {
    _positionSub?.cancel();
    _playingSub?.cancel();
    _videoCtrl?.pause();
    _videoCtrl?.dispose();
    _videoCtrl = null;
    // تعيين حالة الانتقال لمنع ظهور عناصر التحكم القديمة
    final item = audioService.currentItem;
    if (mounted) {
      setState(() {
        _isSwitching = true;
        _thumbPath = null;
        _videoInitialized = false;
      });
    }
    if (item == null) {
      // لا يوجد عنصر حالي — أوقف الانتقال فوراً
      if (mounted) setState(() => _isSwitching = false);
      return;
    }
    // لا نُحمّل الـ thumbnail للفيديوهات — نبقى على أسود 16:9 حتى يجهز الفيديو
    if (!item.isVideo) {
      _loadThumb(); // ستُوقف _isSwitching عند الانتهاء
    }
    _initVideoIfNeeded();
  }

  Future<void> _initVideoIfNeeded() async {
    final item = audioService.currentItem;
    // للأغاني الصوتية: _loadThumb هي التي تُوقف _isSwitching عند الانتهاء
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
          _isSwitching = false; // انتهت مرحلة الانتقال
        });
      }
      // مزامنة الموقف مستمرة
      _positionSub = audioService.player.positionStream.listen((pos) {
        if (_videoCtrl != null && _videoInitialized) {
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
      // في حالة الفشل: أوقف _isSwitching لتجنب تجميد الواجهة
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  Future<void> _loadThumb() async {
    final item = audioService.currentItem;
    if (item == null) return;
    final path = await ThumbnailManager.getLocalThumbnail(item.path);
    if (mounted) setState(() {
      _thumbPath = path;
      _isSwitching = false; // انتهت مرحلة الانتقال
    });
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
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF2F2F7);
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
            // الفيديو: دائماً 16:9 أسود أثناء التحميل → فيديو بعد الجهوزية
            // الصوت:  صورة مربعة مع thumbnail أو أيقونة
            ValueListenableBuilder<int>(
              valueListenable: audioService.currentIndex,
              builder: (_, idx, __) {
                final item = audioService.currentItem;
                final isVideo = item?.isVideo == true;

                if (isVideo) {
                  // ── وضع الفيديو: نسبة 16:9 ثابتة دائماً، لا thumbnail إطلاقاً ──
                  return AspectRatio(
                    aspectRatio: (_videoInitialized && _videoCtrl != null &&
                            _videoCtrl!.value.aspectRatio > 0)
                        ? _videoCtrl!.value.aspectRatio
                        : 16 / 9,
                    child: Container(
                      color: Colors.black,
                      child: _videoInitialized && _videoCtrl != null
                          ? _VideoPlayerWidget(
                              ctrl: _videoCtrl!,
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
                          // أثناء التحميل: مؤشر دوران فقط على خلفية سوداء 16:9
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
                  );
                }

                // ── وضع الصوت: صورة مربعة مع thumbnail أو أيقونة ──
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                  child: AspectRatio(
                    aspectRatio: 1,
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
                                CupertinoIcons.music_note_2,
                                color: Colors.white.withOpacity(0.5),
                                size: 80,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),

            // ── Track Info ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
              child: ValueListenableBuilder<int>(
                valueListenable: audioService.currentIndex,
                builder: (_, __, ___) {
                  final item = audioService.currentItem;
                  final title = item?.title.replaceAll(RegExp(r'\.\w+$'), '') ?? '';
                  return Row(
                    textDirection: TextDirection.rtl,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── User Logo (يمين التايتل في RTL) ──
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
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
                      const SizedBox(width: 14),
                      // ── Title + دندن ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _MarqueeTitle(
                              text: title,
                              textColor: textColor,
                              maxCharsBeforeScroll: 27,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'دندن',
                              style: TextStyle(
                                  color: subColor, fontSize: 14, fontFamily: 'Tajawal'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // ── أزرار التشغيل (للصوت فقط — الفيديو له تحكم داخلي) ──
            if (!_isSwitching && !(_videoInitialized && _videoCtrl != null)) ...[
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
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _isRepeat ? AppColors.primary.withOpacity(0.2) : controlBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(CupertinoIcons.repeat,
                          color: _isRepeat ? AppColors.primary : subColor, size: 20),
                    ),
                  ),
                  // السابق
                  GestureDetector(
                    onTap: () => audioService.playPrevious(),
                    child: Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(color: controlBg, shape: BoxShape.circle),
                      child: Icon(CupertinoIcons.backward_end_fill, color: textColor, size: 26),
                    ),
                  ),
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
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                              color: AppColors.primary.withOpacity(0.45),
                              blurRadius: 24, offset: const Offset(0, 8),
                            )],
                          ),
                          child: Icon(
                            playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                            color: Colors.white, size: 32,
                          ),
                        ),
                      );
                    },
                  ),
                  // التالي
                  GestureDetector(
                    onTap: () => audioService.playNext(),
                    child: Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(color: controlBg, shape: BoxShape.circle),
                      child: Icon(CupertinoIcons.forward_end_fill, color: textColor, size: 26),
                    ),
                  ),
                  // Shuffle placeholder
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: controlBg, shape: BoxShape.circle),
                    child: Icon(CupertinoIcons.shuffle, color: subColor, size: 20),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Volume
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  children: [
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
                          value: _volume, min: 0, max: 3.0,
                          onChanged: _setVolume,
                        ),
                      ),
                    ),
                    Text('${(_volume * 100).toInt()}%',
                        style: TextStyle(color: subColor, fontSize: 11, fontFamily: 'Tajawal')),
                  ],
                ),
              ),

              // Speed
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
                child: Row(
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
                            color: _speed == s ? AppColors.primary : controlBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            s == 1.0 ? '1×' : '${s}×',
                            style: TextStyle(
                              color: _speed == s ? Colors.white : subColor,
                              fontSize: 11, fontFamily: 'Tajawal', fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ], // end audio-only

            const SizedBox(height: 8),

            // ── فاصل أنيق بين المشغل وقائمة التشغيل ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 0.6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AppColors.primary.withOpacity(0.4),
                      AppColors.primary.withOpacity(0.4),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.25, 0.75, 1.0],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 4),

            // ── قائمة التشغيل ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
                    child: Text(
                      'قائمة التشغيل',
                      style: TextStyle(
                        color: subColor, fontSize: 13,
                        fontFamily: 'Tajawal', fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                                  onTap: () => audioService.playAtIndex(i),
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

// ─────────────────────────────────────────────
//  MARQUEE TITLE — عنوان متحرك للمشغل الكبير
// ─────────────────────────────────────────────
class _MarqueeTitle extends StatefulWidget {
  final String text;
  final Color textColor;
  final int maxCharsBeforeScroll;

  const _MarqueeTitle({
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

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    // نبدأ الأنيميشن بعد بناء الويدجت
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
  }

  @override
  void didUpdateWidget(_MarqueeTitle old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _timer?.cancel();
      _scrollCtrl.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
    }
  }

  void _startMarquee() {
    if (!mounted) return;
    final needsScroll = widget.text.length > widget.maxCharsBeforeScroll;
    setState(() => _needsScroll = needsScroll);
    if (!needsScroll) return;

    // انتظر ثانية ثم ابدأ التمرير ببطء
    _timer = Timer(const Duration(seconds: 1), () {
      _animateMarquee();
    });
  }

  void _animateMarquee() {
    if (!mounted || !_scrollCtrl.hasClients) return;
    final maxExtent = _scrollCtrl.position.maxScrollExtent;
    if (maxExtent <= 0) return;

    // مدة التمرير: 50ms لكل بكسل (بطيء وسلس)
    final duration = Duration(milliseconds: (maxExtent * 50).toInt());

    _scrollCtrl
        .animateTo(
          maxExtent,
          duration: duration,
          curve: Curves.linear,
        )
        .then((_) {
          if (!mounted) return;
          // توقف ثانيتين ثم ارجع للبداية
          _timer = Timer(const Duration(seconds: 2), () {
            if (!mounted || !_scrollCtrl.hasClients) return;
            _scrollCtrl.jumpTo(0);
            // انتظر ثانية ثم كرر
            _timer = Timer(const Duration(seconds: 1), () => _animateMarquee());
          });
        });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
                child: Padding(
                  padding: const EdgeInsets.only(right: 30),
                  child: Text(
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

    // توليد صور مصغرة للملفات التي ليس لها صورة بعد (فيديو + صوت)
    for (final item in items) {
      final existing = await ThumbnailManager.getLocalThumbnail(item.path);
      if (existing != null) continue;
      ThumbnailManager.generateLocalThumbnail(item.path).then((result) {
        if (result != null && mounted) setState(() {});
      });
    }
  }

  Future<void> _generateVideoThumbnail(String videoPath) async {
    final result = await ThumbnailManager.generateLocalThumbnail(videoPath);
    if (result != null && mounted) setState(() {});
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
          errorBuilder: (_, __, ___) => _defaultThumb(isActive, size),
        ),
      );
    }
    return _defaultThumb(isActive, size);
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
//  AD SLIDESHOW CARD — كارت إعلاني بنسبة 16:9 مع سلايدشو
// ═══════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════
//  AD SLIDESHOW CARD — Dynamic from Web DB
// ═══════════════════════════════════════════════════════════
class _AdSlideshowCard extends StatefulWidget {
  const _AdSlideshowCard();

  @override
  State<_AdSlideshowCard> createState() => _AdSlideshowCardState();
}

class _AdSlideshowCardState extends State<_AdSlideshowCard>
    with SingleTickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  Timer? _autoTimer;
  List<AdSlide> _slides = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAds();
  }

Future<void> _fetchAds() async {
  try {
    print('=== بدء جلب الإعلانات ===');
    final response = await dio.get(
      'https://scrptaty.com/dndn/index.php?json',
      options: Options(
        headers: {
          'Accept': 'application/json',
        },
      ),
    );
    
    print('Status code: ${response.statusCode}');
    print('Data type: ${response.runtimeType}');
    print('Data: ${response.data}');
    
    if (response.statusCode == 200) {
      // تأكد من أن response.data هي List
      if (response.data is List) {
        setState(() {
          _slides = (response.data as List)
              .map((item) => AdSlide.fromJson(item as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
        print('تم تحميل ${_slides.length} إعلان');
        _startAutoSlide();
      } else {
        print('البيانات ليست List: ${response.data.runtimeType}');
        throw Exception('تنسيق البيانات غير صحيح');
      }
    } else {
      throw Exception('HTTP ${response.statusCode}');
    }
  } catch (e) {
    print('❌ خطأ: $e');
    if (e is DioException) {
      print('Dio error type: ${e.type}');
      print('Dio message: ${e.message}');
      if (e.response != null) {
        print('Response: ${e.response?.data}');
      }
    }
    setState(() {
      _error = 'خطأ: $e';
      _isLoading = false;
    });
  }
}

  void _startAutoSlide() {
    if (_slides.length <= 1) return;
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _slides.isEmpty) return;
      final next = (_currentPage + 1) % _slides.length;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: context.appSurfaceAlt,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
      );
    }

    if (_error != null || _slides.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: context.appSurfaceAlt,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              _error != null ? 'حدث خطأ في تحميل الإعلانات' : 'لا توجد إعلانات',
              style: TextStyle(color: context.appTextSec),
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageCtrl,
              itemCount: _slides.length,
              onPageChanged: (i) {
                setState(() => _currentPage = i);
                _startAutoSlide();
              },
              itemBuilder: (context, index) {
                final slide = _slides[index];
                return GestureDetector(
                  onTap: () => _openLink(slide.link),
                  child: _buildSlide(slide),
                );
              },
            ),
            if (_slides.length > 1)
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slides.length, (i) {
                    final active = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(AdSlide slide) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: slide.imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          placeholder: (_, __) => Container(
            color: Colors.grey[900],
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Colors.white54),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.broken_image,
                color: Colors.white,
                size: 48,
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
                stops: const [0.4, 1.0],
                colors: [
                  const Color.fromARGB(22, 0, 0, 0),
                  Colors.black.withOpacity(0.75),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          right: 18,
          left: 18,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slide.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  slide.description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 12,
                    fontFamily: 'Tajawal',
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PAGE 2 — تصفح (Browse)
// ═══════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════
//  CUSTOM PAINTER FOR REPEATED ROTATED PATTERN
// ═══════════════════════════════════════════════════════════
class _RotatedRepeatedPattern extends StatelessWidget {
  final double opacity;
  final double angleDegrees;
  final double patternSize; // متغير جديد للتحكم بحجم النقش
  final String imagePath; // <--- أضف هذا المتغير الجديد لتحديد مسار الصورة

  const _RotatedRepeatedPattern({
    required this.opacity,
    required this.angleDegrees,
    this.patternSize = 40,
    required this.imagePath, // <--- اجعله مطلوباً
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FutureBuilder<ui.Image?>(
          future: _loadImage(constraints.maxWidth, constraints.maxHeight),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _PatternPainter(
                  image: snapshot.data!,
                  opacity: opacity,
                  angleRad: angleDegrees * 3.14159 / 180,
                  patternSize: patternSize, // تمرير الحجم
                ),
              );
            }
            return Container();
          },
        );
      },
    );
  }

  Future<ui.Image?> _loadImage(double width, double height) async {
    try {
      final completer = Completer<ui.Image>();
      // استخدم imagePath هنا بدلاً من المسار الثابت
      final assetImage = AssetImage(imagePath);
      final stream = assetImage.resolve(ImageConfiguration());

      stream.addListener(ImageStreamListener((info, _) {
        completer.complete(info.image);
      }, onError: (error, stackTrace) {
        completer.completeError(error);
      }));

      return await completer.future;
    } catch (e) {
      return null;
    }
  }
}

class _PatternPainter extends CustomPainter {
  final ui.Image image;
  final double opacity;
  final double angleRad;
  final double patternSize; // متغير جديد للتحكم بحجم النقش

  _PatternPainter({
    required this.image,
    required this.opacity,
    required this.angleRad,
    required this.patternSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(opacity)
      ..filterQuality = FilterQuality.medium;

    canvas.save();

    // تحريك الرسم إلى منتصف الحاوية للدوران حول المركز
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angleRad);
    canvas.translate(-size.width / 2, -size.height / 2);

    // استخدام الحجم المطلوب للنقش
    final imageWidth = patternSize;
    final imageHeight = patternSize;

    // حساب عدد التكرارات اللازمة
    final cols = (size.width / imageWidth).ceil() + 2;
    final rows = (size.height / imageHeight).ceil() + 2;

    // رسم الصور المتكررة
    for (int row = -1; row < rows; row++) {
      for (int col = -1; col < cols; col++) {
        final dx = col * imageWidth;
        final dy = row * imageHeight;

        // رسم الصورة بالحجم المطلوب
        final rect = Rect.fromLTWH(dx, dy, imageWidth, imageHeight);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          paint,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.opacity != opacity ||
        oldDelegate.angleRad != angleRad ||
        oldDelegate.patternSize != patternSize;
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
          // ── كرت الإعلانات (السلايد شو) ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const _AdSlideshowCard(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          // ── يوتيوب كرت ──
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
                  height: 45,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 228, 48, 51),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        const _RotatedRepeatedPattern(
                          opacity: 0.1,
                          angleDegrees: -32,
                          patternSize: 170,
                          imagePath: 'assets/images/yt-bg.png',
                        ),
                        const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(CupertinoIcons.play_rectangle_fill,
                                  color: Colors.white, size: 24),
                              SizedBox(width: 8),
                              Text(
                                'يوتيوب',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
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
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
          // ── كرت وسائط الجهاز (الجديد) ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () {
                  // TODO: أضف الرابط أو الوظيفة المطلوبة عند الضغط على الكرت
                  // يمكنك فتح صفحة لعرض الصور أو مقاطع الوسائط المختلفة
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('سيتم إضافة صفحة وسائط الجهاز قريباً', textDirection: TextDirection.rtl),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  height: 45,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 43, 160, 140), // لون أخضر
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color.fromARGB(255, 67, 160, 137).withOpacity(0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        const _RotatedRepeatedPattern(
                          opacity: 0.1,
                          angleDegrees: -32,
                          patternSize: 170,
                          imagePath: 'assets/images/img-bg.png', // الخلفية الجديدة
                        ),
                        const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(CupertinoIcons.photo_fill, // أيقونة الوسائط (صور/فيديو)
                                  color: Colors.white, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'وسائط الجهاز',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
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
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
          // ── ملفات الجهاز (الكرت الأزرق الأصلي) ──
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
                  height: 45,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 51, 124, 189),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E88E5).withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        const _RotatedRepeatedPattern(
                          opacity: 0.1,
                          angleDegrees: -32,
                          patternSize: 170,
                          imagePath: 'assets/images/files-bg.png',
                        ),
                        const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(CupertinoIcons.folder_fill,
                                  color: Colors.white, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'ملفات الجهاز',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
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
        // ★ توليد صورة مصغرة حقيقية مباشرة بعد النسخ (فيديو + صوت)
        ThumbnailManager.generateLocalThumbnail(dest.path).catchError((_) {});
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
                      const SizedBox(height: 16),

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
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.isDark
          ? AppColors.darkSurface
          : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: context.isDark
            ? AppColors.darkDivider
            : AppColors.divider,
        width: 0.5,
      ),
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0xFFE53935),
              BlendMode.srcIn,
            ),
            child: Image.asset(
              'assets/images/scrptaty.png',
              width: 58,
              height: 58,
              fit: BoxFit.cover,
            ),
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'المطور سكربتاتي',
                style: TextStyle(
                  color: context.appText,
                  fontFamily: 'Tajawal',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                'لتطوير وتصميم التطبيقات',
                style: TextStyle(
                  color: context.appTextSec,
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ),
),
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