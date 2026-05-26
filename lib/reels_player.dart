import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'listen_page.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// ═══════════════════════════════════════════════════════
//  REELS VIDEO PLAYER — مشغل ريلز دندن
// ═══════════════════════════════════════════════════════

class ReelsVideoPlayer extends StatefulWidget {
  final List<LocalMediaItem> items;
  final int initialIndex;
  final List<MusicFolder> folders;
  final Future<void> Function() onFoldersChanged;

  const ReelsVideoPlayer({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.folders,
    required this.onFoldersChanged,
  });

  @override
  State<ReelsVideoPlayer> createState() => _ReelsVideoPlayerState();
}

class _ReelsVideoPlayerState extends State<ReelsVideoPlayer>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, bool> _initialized = {};

  bool _isLooping = true;
  bool _autoScroll = false;
  bool _showControls = true;
  bool _isTitleExpanded = false;
  bool _fillScreen = false;          // وضع ملء الشاشة الكامل
  bool _isTransitioning = false;     // هل نحن في مرحلة انتقال؟
  double _swipeProgress = 0.0;      // تقدم السحب (0.0 - 1.0) للريل التالي

  Timer? _autoScrollTimer;
  Timer? _controlsTimer;
  Timer? _progressTimer;

  // أنيميشن
  late AnimationController _overlayAnimCtrl;
  late Animation<double> _overlayAnim;
  late AnimationController _heartAnimCtrl;
  late Animation<double> _heartAnim;
  late AnimationController _pageTransitionCtrl;

  bool _showHeart = false;
  double _dragPosition = 0;

  // ── سحب الصفحة الكاملة (TikTok/Instagram style) ──
  double _dragOffset = 0.0;       // الإزاحة العمودية الحالية أثناء السحب
  bool _isDraggingPage = false;   // هل المستخدم يسحب الصفحة الآن؟

  // ── جيسجر الخروج الأفقي ──
  double _exitDragOffset = 0.0;   // الإزاحة الأفقية أثناء السحب للخروج
  bool _isDraggingExit = false;   // هل المستخدم يسحب للخروج الآن؟

  // ── شريط التمرير السلس ──
  bool _isSeeking = false;        // هل المستخدم يسحب الآن؟
  double _seekProgress = 0.0;    // الموضع المؤقت أثناء السحب (0.0 - 1.0)
  bool _wasPlayingBeforeSeek = false; // هل كان يعزف قبل السحب؟

  // ── نظام الإعجاب ──
  final Map<String, bool> _likedItems = {};  // حالة الإعجاب لكل فيديو
  bool _showLikeAnimation = false;           // هل يظهر أنيميشن الإعجاب؟
  late AnimationController _likeAnimCtrl;
  late Animation<double> _likeScaleAnim;
  late Animation<double> _likeOpacityAnim;
  late AnimationController _likeBurstCtrl;
  late Animation<double> _likeBurstAnim;

  // ── تشغيل في الخلفية (إشعار الميديا) ──
  // مشغل صوتي خفيف يُشغّل نفس الملف بصمت لإبقاء الإشعار حياً
  final AudioPlayer _bgAudioPlayer = AudioPlayer();
  StreamSubscription<int?>? _bgIndexSub;
  bool _syncingFromNotification = false;

  // ── حالة الخلفية ──
  // ── صور مصغرة للفيديوهات ──
  final Map<int, Uint8List?> _thumbnails = {};
  bool _isInBackground = false;     // هل التطبيق في الخلفية الآن؟
  bool _wasPlayingBeforeBackground = false; // هل كان يعزف قبل الذهاب للخلفية؟

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    _overlayAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _overlayAnim =
        CurvedAnimation(parent: _overlayAnimCtrl, curve: Curves.easeOut);
    _overlayAnimCtrl.forward();

    _heartAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _heartAnim = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.2)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 60),
      TweenSequenceItem(
          tween: Tween(begin: 1.2, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 40),
    ]).animate(_heartAnimCtrl);

    _pageTransitionCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));

    // أنيميشن زر الإعجاب
    _likeAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _likeScaleAnim = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.35)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 1.35, end: 0.92)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 30),
      TweenSequenceItem(
          tween: Tween(begin: 0.92, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 30),
    ]).animate(_likeAnimCtrl);
    _likeOpacityAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _likeAnimCtrl, curve: Curves.easeOut));

    _likeBurstCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _likeBurstAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _likeBurstCtrl, curve: Curves.easeOut));

    _initController(_currentIndex);
    if (_currentIndex > 0) _initController(_currentIndex - 1);
    if (_currentIndex < widget.items.length - 1)
      _initController(_currentIndex + 1);

    // تحميل حالة الإعجاب المحفوظة
    _loadLikedItems();

    // تسجيل مراقب دورة حياة التطبيق (خلفية / أمام)
    WidgetsBinding.instance.addObserver(this);

    // تشغيل في الخلفية عبر audioService مع إشعار الميديا
    _setupBackgroundPlayback();

    // الاستماع لتغييرات الأغنية من الإشعار
    _setupNotificationSync();

    // لا نخفي شريط النظام (الوقت والبطارية والشبكة)
  }

  /// يُعدّ قائمة الريلز في audioService لإظهار إشعار الميديا وإتاحة التحكم من الخلفية
  Future<void> _setupBackgroundPlayback() async {
    // نُعيد تشغيل القائمة كاملة عبر audioService ليتولى إدارة الخلفية والإشعار
    await audioService.playList(
      List<LocalMediaItem>.unmodifiable(widget.items),
      _currentIndex,
    );
  }

  /// يستمع لتغييرات currentIndex الصادرة من just_audio_background (الإشعار)
  void _setupNotificationSync() {
    audioService.currentIndex.addListener(_onNotificationIndexChanged);
  }

  void _onNotificationIndexChanged() {
    if (!mounted) return;
    final newIdx = audioService.currentIndex.value;
    if (newIdx < 0 || newIdx >= widget.items.length) return;
    if (newIdx == _currentIndex) return;
    // التنقل إلى الريل المطلوب من الإشعار
    _syncingFromNotification = true;
    _pageController.animateToPage(
      newIdx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  // ══════════════════════════════════════════════════════════
  //  إدارة دورة حياة التطبيق — تشغيل في الخلفية وشاشة القفل
  // ══════════════════════════════════════════════════════════
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final videoCtrl = _controllers[_currentIndex];

    switch (state) {
      // ── التطبيق ذهب للخلفية أو شاشة القفل ──
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _isInBackground = true;
        // احفظ حالة التشغيل الحالية
        _wasPlayingBeforeBackground = videoCtrl?.value.isPlaying ?? false;
        // أوقف الفيديو (الصورة فقط) لتوفير الموارد
        // لكن اجعل audioService يستمر في التشغيل لإبقاء الإشعار حياً
        if (_wasPlayingBeforeBackground) {
          videoCtrl?.pause();
          // أبلغ audioService بالاستمرار في التشغيل (صوت الخلفية)
          audioService.playAtIndex(_currentIndex);
        }
        break;

      // ── التطبيق عاد للواجهة ──
      case AppLifecycleState.resumed:
        _isInBackground = false;
        // استأنف الفيديو إذا كان يعزف قبل الذهاب للخلفية
        if (_wasPlayingBeforeBackground) {
          // تزامن موضع الفيديو مع موضع الصوت في audioService
          _syncVideoPositionFromAudio().then((_) {
            videoCtrl?.play();
          });
        }
        _wasPlayingBeforeBackground = false;
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// يزامن موضع الفيديو مع موضع صوت audioService بعد العودة من الخلفية
  Future<void> _syncVideoPositionFromAudio() async {
    final videoCtrl = _controllers[_currentIndex];
    if (videoCtrl == null) return;
    try {
      // محاولة المزامنة مع موضع الصوت إن أمكن
      // نستخدم try/catch لأن audioService قد يختلف تبعاً لتنفيذ main.dart
      final dynamic svc = audioService;
      final dynamic audioPos = svc?.player?.position;
      if (audioPos is Duration) {
        final videoDuration = videoCtrl.value.duration;
        if (videoDuration.inMilliseconds > 0 &&
            audioPos.inMilliseconds <= videoDuration.inMilliseconds) {
          await videoCtrl.seekTo(audioPos);
        }
      }
    } catch (_) {
      // تجاهل أخطاء المزامنة بصمت — الفيديو سيستأنف من آخر موضعه
    }
  }
Future<void> animateDragOffset({
  required double from,
  required double to,
}) async {
  const duration = Duration(milliseconds: 260);

  final start = DateTime.now();

  while (true) {
    final elapsed =
        DateTime.now().difference(start);

    double t =
        elapsed.inMilliseconds /
        duration.inMilliseconds;

    if (t >= 1) break;

    t = Curves.easeOutCubic.transform(t);

    setState(() {
      _dragOffset =
          from + (to - from) * t;
    });

    await Future.delayed(
      const Duration(milliseconds: 16),
    );
  }

  if (!mounted) return;

  setState(() {
    _dragOffset = to;
  });
}
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    audioService.currentIndex.removeListener(_onNotificationIndexChanged);
    _bgIndexSub?.cancel();
    _bgAudioPlayer.dispose();
    _detachAutoScrollListener();
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    _pageController.dispose();
    _overlayAnimCtrl.dispose();
    _heartAnimCtrl.dispose();
    _pageTransitionCtrl.dispose();
    _likeAnimCtrl.dispose();
    _likeBurstCtrl.dispose();
    _autoScrollTimer?.cancel();
    _controlsTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }
Future<void> _loadThumbnail(int index) async {
    if (_thumbnails.containsKey(index)) return;
    final item = widget.items[index];
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: item.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 120,
        quality: 75,
      );
      if (mounted) setState(() => _thumbnails[index] = bytes);
    } catch (_) {
      if (mounted) setState(() => _thumbnails[index] = null);
    }
  }
  Future<void> _initController(int index) async {
    if (index < 0 || index >= widget.items.length) return;
    if (_controllers.containsKey(index)) return;

    final item = widget.items[index];
    final ctrl = VideoPlayerController.file(File(item.path));
    _controllers[index] = ctrl;

    try {
      await ctrl.initialize();
      ctrl.setLooping(_isLooping);
      if (mounted) setState(() => _initialized[index] = true);
      _loadThumbnail(index);
      if (index == _currentIndex) {
        ctrl.play();
        _startProgressTimer();
        // إذا كان التصفح التلقائي مفعّلاً، أضف المراقب
        if (_autoScroll) _attachAutoScrollListener();
      }
    } catch (_) {
      if (mounted) setState(() => _initialized[index] = false);
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer =
        Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onSingleTap() {
    final ctrl = _controllers[_currentIndex];
    if (ctrl == null) return;
    setState(() {
      if (ctrl.value.isPlaying) {
        ctrl.pause();
      } else {
        ctrl.play();
      }
      // إظهار الـ overlay مؤقتاً عند النقر
      _showControls = true;
    });
    
  }

  void _toggleControls() {
    // النقر على الشاشة يُظهر العناصر فقط (الإخفاء عبر زر العين)
    if (!_showControls) {
      setState(() => _showControls = true);
    }
  }

  void _onPageChanged(int index) {
    final prevCtrl = _controllers[_currentIndex];
    prevCtrl?.pause();

    // أزل مراقب التصفح من الريل السابق
    _detachAutoScrollListener();

    _currentIndex = index;
    _isTitleExpanded = false;

    final curr = _controllers[index];
    if (curr != null && (_initialized[index] ?? false)) {
      curr.setLooping(_isLooping);
      curr.play();
      _startProgressTimer();
      // أعد تعليق المراقب على الريل الجديد
      if (_autoScroll) _attachAutoScrollListener();
    } else {
      _initController(index);
    }

    // pre-load neighbours
    if (index + 1 < widget.items.length) _initController(index + 1);
    if (index - 1 >= 0) _initController(index - 1);

    // dispose distant controllers
    final toRemove = _controllers.keys
        .where((k) => (k - index).abs() > 2)
        .toList();
    for (final k in toRemove) {
      _controllers[k]?.dispose();
      _controllers.remove(k);
      _initialized.remove(k);
    }

    // مزامنة audioService مع الريل الحالي (يُحدّث الإشعار تلقائياً)
    if (!_syncingFromNotification) {
      audioService.playAtIndex(index);
    }
    _syncingFromNotification = false;

    setState(() {});
  }

  // ── مراقب انتهاء الفيديو للتصفح التلقائي ──
  VoidCallback? _videoEndListener;

  void _attachAutoScrollListener() {
    final ctrl = _controllers[_currentIndex];
    if (ctrl == null) return;

    // أزل المراقب القديم إن وُجد
    _detachAutoScrollListener();

    void listener() {
      if (!_autoScroll) return;
      if (!mounted) return;
      final val = ctrl.value;
      // الفيديو وصل للنهاية (position == duration وليس يعزف)
      if (val.duration.inMilliseconds > 0 &&
          val.position.inMilliseconds >= val.duration.inMilliseconds - 100 &&
          !val.isPlaying) {
        _goToNextReel();
      }
    }

    _videoEndListener = listener;
    ctrl.addListener(listener);
  }

  void _detachAutoScrollListener() {
    if (_videoEndListener == null) return;
    // أزل المراقب من جميع الكنترولرز
    for (final c in _controllers.values) {
      try {
        c.removeListener(_videoEndListener!);
      } catch (_) {}
    }
    _videoEndListener = null;
  }

  void _goToNextReel() {
    _autoScrollTimer?.cancel();
    final next = _currentIndex + 1;
    if (!mounted) return;
    if (next < widget.items.length) {
      // أنيميشن سحب طبيعي للأعلى مثل الريلز
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _scheduleAutoScroll() {
    _autoScrollTimer?.cancel();
    // الاستماع المباشر للكنترولر أدق من Timer
    _attachAutoScrollListener();
  }

  void _onDoubleTap() {
    _onDoubleTapLike();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── نظام الإعجاب ──
  Future<void> _loadLikedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final liked = prefs.getStringList('liked_reels') ?? [];
    if (mounted) {
      setState(() {
        for (final path in liked) {
          _likedItems[path] = true;
        }
      });
    }
  }

  Future<void> _saveLikedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final liked = _likedItems.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    await prefs.setStringList('liked_reels', liked);
  }

  bool _isCurrentLiked() {
    final path = widget.items[_currentIndex].path;
    return _likedItems[path] ?? false;
  }

  void _toggleLike() {
    final path = widget.items[_currentIndex].path;
    final wasLiked = _likedItems[path] ?? false;
    setState(() {
      _likedItems[path] = !wasLiked;
      _showLikeAnimation = true;
    });
    _likeAnimCtrl.forward(from: 0);
    _likeBurstCtrl.forward(from: 0);
    _saveLikedItems();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showLikeAnimation = false);
    });
  }

  void _onDoubleTapLike() {
    // عند الدبل تاب: إعجاب + أنيميشن القلب
    final path = widget.items[_currentIndex].path;
    if (!(_likedItems[path] ?? false)) {
      _toggleLike();
    }
    setState(() => _showHeart = true);
    _heartAnimCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 900),
        () => mounted ? setState(() => _showHeart = false) : null);
  }

  void _showOptionsMenu(BuildContext context) {
    final isDark = context.isDark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _OptionsSheet(
        isLooping: _isLooping,
        autoScroll: _autoScroll,
        showControls: _showControls,
        folders: widget.folders,
        currentItem: widget.items[_currentIndex],
        onLoopChanged: (v) {
          setState(() {
            _isLooping = v;
            // تفعيل التكرار يُطفئ التصفح التلقائي
            if (v && _autoScroll) {
              _autoScroll = false;
              _detachAutoScrollListener();
            }
          });
          _controllers[_currentIndex]?.setLooping(v);
        },
        onAutoScrollChanged: (v) {
          setState(() {
            _autoScroll = v;
            // تفعيل التصفح التلقائي يُطفئ التكرار
            if (v) {
              _isLooping = false;
              _controllers[_currentIndex]?.setLooping(false);
              _attachAutoScrollListener();
            } else {
              _detachAutoScrollListener();
            }
          });
        },
        onToggleControls: () {
          Navigator.pop(context);
          setState(() => _showControls = !_showControls);
          _controlsTimer?.cancel();
        },
        onAddToFolder: _addToFolder,
      ),
    );
  }

  Future<void> _addToFolder(MusicFolder folder) async {
    final path = widget.items[_currentIndex].path;
    if (!folder.songPaths.contains(path)) {
      folder.songPaths.add(path);
      await widget.onFoldersChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت الإضافة إلى ${folder.name}',
                style: const TextStyle(fontFamily: 'Tajawal')),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

return Scaffold(
  backgroundColor: Colors.black,
  extendBody: true,
  extendBodyBehindAppBar: true,
  body: GestureDetector(
        // ── اكتشاف اتجاه السحب العمودي (تصفح الريلز) ──
        onVerticalDragStart: (details) {
          _dragOffset = 0.0;
          _isDraggingPage = true;
          _swipeProgress = 0.0;
        },
onVerticalDragUpdate: (details) {
  if (!_isDraggingPage) return;

  setState(() {
    _dragOffset += details.delta.dy;
  });
},
        onVerticalDragEnd: (details) async {
          if (!_isDraggingPage) return;
          _isDraggingPage = false;

          final velocity = details.primaryVelocity ?? 0;
          final screenH = MediaQuery.of(context).size.height;
          // الانتقال يحدث فقط عندما يصل المستخدم إلى الريل الثاني أو عند رفع الإصبع مع سرعة كافية
          final threshold = screenH * 0.45; // 45% من الشاشة = وصل للريل الثاني

          int targetPage = _currentIndex;

          if (_dragOffset < -threshold || velocity < -900) {
            if (_currentIndex < widget.items.length - 1) {
              targetPage = _currentIndex + 1;
            }
          } else if (_dragOffset > threshold || velocity > 900) {
            if (_currentIndex > 0) {
              targetPage = _currentIndex - 1;
            }
          }

          _dragOffset = 0.0;
          _swipeProgress = 0.0;
if (targetPage != _currentIndex) {
  final screenHeight = MediaQuery.of(context).size.height;

final shouldChangePage =
    _dragOffset.abs() > screenHeight * 0.5;

double endOffset = 0;

if (shouldChangePage) {
  endOffset =
      _dragOffset < 0
          ? -screenHeight
          : screenHeight;
}

await Future.delayed(Duration.zero);

if (!mounted) return;

await animateDragOffset(
  from: _dragOffset,
  to: endOffset,
);

if (shouldChangePage) {
  final nextPage =
      _dragOffset < 0
          ? _currentIndex + 1
          : _currentIndex - 1;

  if (nextPage >= 0 &&
      nextPage < widget.items.length) {
    _pageController.jumpToPage(nextPage);
  }
}

setState(() {
  _dragOffset = 0;
  _swipeProgress = 0;
});
}

        },
onVerticalDragCancel: () {
  if (!_isDraggingPage) return;

  _isDraggingPage = false;

  setState(() {
    _dragOffset = 0.0;
    _swipeProgress = 0.0;
  });
},
        // ── النقر والدبل تاب ──
        onTap: _onSingleTap,
        onDoubleTap: _onDoubleTap,
        child: _buildMainContent(size),
      ),
    );
  }

  Widget _buildMainContent(Size size) {
    // ── جيسجر الخروج الأفقي ──
return GestureDetector(
onHorizontalDragStart: (details) {
  final screenWidth = MediaQuery.of(context).size.width;
  final dx = details.globalPosition.dx;

  // السماح بالسحب فقط من 15% من الحواف
  final edgeSize = screenWidth * 0.15;

  final fromLeftEdge = dx <= edgeSize;
  final fromRightEdge = dx >= screenWidth - edgeSize;

  if (fromLeftEdge || fromRightEdge) {
    _isDraggingExit = true;
    _exitDragOffset = 0.0;
  } else {
    _isDraggingExit = false;
  }
},
  onHorizontalDragUpdate: (details) {
    if (!_isDraggingExit) return;
    setState(() {
      _exitDragOffset += details.delta.dx;
    });
  },
  onHorizontalDragEnd: (details) {
    if (!_isDraggingExit) return;
    _isDraggingExit = false;
    final velocity = details.primaryVelocity ?? 0;
    final threshold = size.width * 0.3;

    if (_exitDragOffset.abs() > threshold || velocity.abs() > 400) {
      Navigator.pop(context);
    } else {
      setState(() => _exitDragOffset = 0.0);
    }
  },
  onHorizontalDragCancel: () {
    _isDraggingExit = false;
    setState(() => _exitDragOffset = 0.0);
  },
  child: Transform.translate(
    offset: Offset(_exitDragOffset, 0),
        child: Stack(
          children: [
            // ── صفحات الفيديو ──
PageView.builder(
  controller: _pageController,
  scrollDirection: Axis.vertical,
  physics: const NeverScrollableScrollPhysics(),
  onPageChanged: _onPageChanged,
  itemCount: widget.items.length,
  itemBuilder: (_, index) {

    double offset = 0;

    // الريلز الحالي
    if (index == _currentIndex) {
      offset = _dragOffset;
    }

    // الريلز الجاي (السحب لفوك)
    else if (
      index == _currentIndex + 1 &&
      _dragOffset < 0
    ) {
      offset =
          MediaQuery.of(context).size.height +
          _dragOffset;
    }

    // الريلز السابق (السحب لجوه)
    else if (
      index == _currentIndex - 1 &&
      _dragOffset > 0
    ) {
      offset =
          -MediaQuery.of(context).size.height +
          _dragOffset;
    }

    return Transform.translate(
      offset: Offset(0, offset),
      child: _buildVideoPage(index, size),
    );
  },
),

            // ── طبقة القلب عند الدبل تاب ──
            if (_showHeart)
              Center(
                child: AnimatedBuilder(
                  animation: _heartAnim,
                  builder: (_, __) => Transform.scale(
                    scale: _heartAnim.value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        CupertinoIcons.heart_fill,
                        color: Colors.white,
                        size: 90,
                      ),
                    ),
                  ),
                ),
              ),

// ── الـ overlay (controls) ──
AnimatedOpacity(
  opacity: _showControls ? 1.0 : 0.0,
  duration: const Duration(milliseconds: 300),
  child: _buildOverlay(size),
),

// ── البار السفلي — يظهر دائماً ──
Positioned(
  bottom: 0,
  left: 0,
  right: 0,
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {},
    onVerticalDragStart: (_) {},
    onHorizontalDragStart: (_) {},
    child: _buildSongInfoBar(
      item: widget.items[_currentIndex],
      isPlaying: _controllers[_currentIndex]?.value.isPlaying ?? false,
    ),
  ),
),
          ],
        ),
      ),
    );
  }

Widget _buildVideoPage(int index, Size size) {
    final ctrl = _controllers[index];
    final isInit = _initialized[index] ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ══════════════════════════════════════════════
        //  خلفية ضبابية سينمائية
        // ══════════════════════════════════════════════
        if (ctrl != null && isInit) ...[
          Positioned.fill(
            child: ClipRect(
              child: OverflowBox(
                maxWidth: size.width * 3.5,
                maxHeight: size.height * 3.5,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: ctrl.value.aspectRatio,
                    child: VideoPlayer(ctrl),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                color: Colors.black.withOpacity(0.20),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.6),
                  ],
                ),
              ),
            ),
          ),
        ] else
          Container(color: Colors.black),

        // ══════════════════════════════════════════════
        //  الفيديو الرئيسي — دائماً بأبعاده الأصلية
        // ══════════════════════════════════════════════
if (ctrl != null && isInit)
  Builder(
    builder: (context) {
      final botPad = MediaQuery.of(context).padding.bottom;
      final isPortrait = ctrl.value.aspectRatio < 1.0;

      // وضع ملء الشاشة — يشتغل لأي فيديو
      if (_fillScreen) {
        return Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: ctrl.value.size.width,
              height: ctrl.value.size.height,
              child: VideoPlayer(ctrl),
            ),
          ),
        );
      }

      if (isPortrait) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: botPad + 80,
          child: Center(
            child: Transform.scale(
              scale: 1.07,
              child: AspectRatio(
                aspectRatio: ctrl.value.aspectRatio,
                child: VideoPlayer(ctrl),
              ),
            ),
          ),
        );
      } else {
        return Center(
          child: AspectRatio(
            aspectRatio: ctrl.value.aspectRatio,
            child: VideoPlayer(ctrl),
          ),
        );
      }
    },
  )
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CupertinoActivityIndicator(
                    color: Colors.white, radius: 18),
                const SizedBox(height: 14),
                Text(
                  'جارٍ التحميل...',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontFamily: 'Tajawal',
                      fontSize: 14),
                ),
              ],
            ),
          ),

        // تدرج سفلي
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: size.height * 0.55,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.15),
                  Colors.black.withOpacity(0.5),
                  Colors.black.withOpacity(0.88),
                ],
                stops: const [0.0, 0.4, 0.75, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverlay(Size size) {
    final item = widget.items[_currentIndex];
    final ctrl = _controllers[_currentIndex];
    final isInit = _initialized[_currentIndex] ?? false;

    final position = ctrl?.value.position ?? Duration.zero;
    final duration = ctrl?.value.duration ?? Duration.zero;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    final isPlaying = ctrl?.value.isPlaying ?? false;
    final title = item.title.replaceAll(RegExp(r'\.\w+$'), '');
    final shortTitle = title.length > 30 ? title.substring(0, 30) : title;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        // ═══════════════════════════════════════
        //  الجانب الأيمن — عمود الأزرار المحسّن
        // ═══════════════════════════════════════
        Positioned(
          right: 12,
          bottom: botPad + 85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── لوجو دندن الأحمر ──
              _buildDandanButton(),
              const SizedBox(height: 8),

              // ── زر الإعجاب ──
              _buildLikeButton(isLiked: _isCurrentLiked()),
              const SizedBox(height: 8),

              // ── زر ملء الشاشة ──
              _buildSideButton(
                child: Icon(
                  _fillScreen
                      ? CupertinoIcons.arrow_down_right_arrow_up_left
                      : CupertinoIcons.arrow_up_left_arrow_down_right,
                  color: _fillScreen ? AppColors.primary : Colors.white,
                  size: 20,
                ),
                label: _fillScreen ? 'ممتلئ' : 'ملء',
                onTap: () => setState(() => _fillScreen = !_fillScreen),
                isActive: _fillScreen,
              ),
              const SizedBox(height: 8),


              // ── المزيد ──
              _buildSideButton(
                child: const Icon(CupertinoIcons.ellipsis,
                    color: Colors.white, size: 20),
                label: 'المزيد',
                onTap: () => _showOptionsMenu(context),
              ),
            ],
          ),
        ),

        // ═══════════════════════════════════════
        //  الشريط العلوي — رجوع + عداد (Premium)
        // ═══════════════════════════════════════
        Positioned(
          top: topPad + 8,
          left: 14,
          right: 14,
          child: Row(
            children: [
              // زر الرجوع
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.2), width: 0.8),
                      ),
                      child: const Icon(CupertinoIcons.chevron_down,
                          color: Colors.white, size: 17),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // عداد الفيديو
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.18), width: 0.8),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.items.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ═══════════════════════════════════════
        //  الشريط السفلي — تصميم Premium محسّن
        // ═══════════════════════════════════════
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomBar(
            item: item,
            title: title,
            shortTitle: shortTitle,
            ctrl: ctrl,
            isInit: isInit,
            position: position,
            duration: duration,
            progress: progress,
            botPad: botPad,
            size: size,
            isPlaying: isPlaying,
          ),
        ),

        // ═══════════════════════════════════════
        //  شريط معلومات الأغنية — اسم + وصف + موجات
        // ═══════════════════════════════════════
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildSongInfoBar(
            item: widget.items[_currentIndex],
            isPlaying: _controllers[_currentIndex]?.value.isPlaying ?? false,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar({
    required LocalMediaItem item,
    required String title,
    required String shortTitle,
    required VideoPlayerController? ctrl,
    required bool isInit,
    required Duration position,
    required Duration duration,
    required double progress,
    required double botPad,
    required Size size,
    required bool isPlaying,
  }) {
    return Container(
  padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // شريط التقدم فقط بدون مؤقتين
          LayoutBuilder(
            builder: (ctx, constraints) {
              final trackWidth = constraints.maxWidth;
              final displayProgress = _isSeeking ? _seekProgress : progress;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (d) {
                  if (ctrl == null || !isInit) return;
                  _wasPlayingBeforeSeek = ctrl.value.isPlaying;
                  if (_wasPlayingBeforeSeek) ctrl.pause();
                  _progressTimer?.cancel();
                  setState(() {
                    _isSeeking = true;
                    _seekProgress = progress;
                  });
                },
                onHorizontalDragUpdate: (d) {
                  if (ctrl == null || !isInit || !_isSeeking) return;
                  final delta = d.delta.dx / trackWidth;
                  setState(() {
                    _seekProgress = (_seekProgress + delta).clamp(0.0, 1.0);
                  });
                },
                onHorizontalDragEnd: (_) async {
                  if (ctrl == null || !isInit) return;
                  await ctrl.seekTo(duration * _seekProgress);
                  if (_wasPlayingBeforeSeek) ctrl.play();
                  _startProgressTimer();
                  setState(() => _isSeeking = false);
                },
                onHorizontalDragCancel: () async {
                  if (ctrl == null || !isInit) return;
                  if (_wasPlayingBeforeSeek) ctrl.play();
                  _startProgressTimer();
                  setState(() => _isSeeking = false);
                },
                onTapDown: (d) async {
                  if (ctrl == null || !isInit) return;
                  final tapFraction =
                      (d.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                  await ctrl.seekTo(duration * tapFraction);
                  setState(() {});
                },
child: SizedBox(
  height: 28,
  child: Center(
    child: SizedBox(
      height: 3,
      child: Stack(
    alignment: Alignment.center,
    children: [
      Container(
        height: 3,
        decoration: const BoxDecoration(
          color: Color(0x40FFFFFF),
        ),
      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
  duration: const Duration(milliseconds: 150),
  width: (displayProgress.clamp(0.0, 1.0) * trackWidth)
      .clamp(0.0, trackWidth),
  height: 3,
  decoration: BoxDecoration(
    color: AppColors.primary,
    boxShadow: [
      BoxShadow(
        color: AppColors.primary.withOpacity(0.5),
        blurRadius: 6,
      ),
    ],
  ),
),
                      ),
                    ],
                  ),
                        ), 
    ), 
                ),
              );
            },
          ),

          SizedBox(height: botPad + 62),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  بطاقة المعلومات: عنوان + صورة مصغرة + موجات صوتية
  // ═══════════════════════════════════════════════════════
  Widget _buildInfoCard({
    required LocalMediaItem item,
    required String title,
    required bool isPlaying,
  }) {
    final shortTitle = title.length > 22 ? '${title.substring(0, 22)}...' : title;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 170,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.red.withOpacity(0.22),
                Colors.black.withOpacity(0.55),
                AppColors.primary.withOpacity(0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.red.withOpacity(0.45),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.18),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // صورة مصغرة مع تأثير
              Container(
                width: 34,
              height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.25),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withOpacity(0.7),
                                Colors.red.withOpacity(0.5),
                              ],
                            ),
                          ),
                          child: const Icon(
                            CupertinoIcons.music_note,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),

              // العنوان + موجات صوتية
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // العنوان
                    Text(
                      shortTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Tajawal',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // موجات صوتية متحركة
                    _buildSoundWaves(isPlaying: isPlaying),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // موجات صوتية متحركة
  Widget _buildSoundWaves({required bool isPlaying}) {
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(9, (i) {
          return _SoundWaveBar(
            index: i,
            isPlaying: isPlaying,
            color: i % 3 == 0
                ? Colors.red
                : i % 3 == 1
                    ? AppColors.primary
                    : Colors.white.withOpacity(0.8),
          );
        }),
      ),
    );
  }

  // زر جانبي Premium مع Glassmorphism
  Widget _buildSideButton({
    required Widget child,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    bool showLabel = true,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary.withOpacity(0.32)
                      : Colors.white.withOpacity(0.13),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive
                        ? AppColors.primary.withOpacity(0.7)
                        : Colors.white.withOpacity(0.22),
                    width: 1,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                              color: AppColors.primary.withOpacity(0.38),
                              blurRadius: 14,
                              spreadRadius: 1),
                        ]
                      : [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.22),
                              blurRadius: 8),
                        ],
                ),
                child: Center(child: child),
              ),
            ),
          ),
          if (showLabel && label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? AppColors.primary
                    : Colors.white.withOpacity(0.8),
                fontFamily: 'Tajawal',
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 6),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
Widget _buildDandanButton() {
  return GestureDetector(
    onTap: () {},
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.13),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.22),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.22),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                  color: Colors.white,
                  colorBlendMode: BlendMode.srcIn,
                  errorBuilder: (_, __, ___) => const Icon(
                    CupertinoIcons.music_note_2,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'دندن',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontFamily: 'Tajawal',
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(color: Colors.black87, blurRadius: 6),
            ],
          ),
        ),
      ],
    ),
  );
}
  // زر الإعجاب المتحرك
  Widget _buildLikeButton({required bool isLiked}) {
    return GestureDetector(
      onTap: _toggleLike,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _likeAnimCtrl,
            builder: (_, __) => ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isLiked
                        ? Colors.red.withOpacity(0.28)
                        : Colors.white.withOpacity(0.13),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isLiked
                          ? Colors.red.withOpacity(0.6)
                          : Colors.white.withOpacity(0.22),
                      width: 1,
                    ),
                    boxShadow: isLiked
                        ? [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.18),
                              blurRadius: 10,
                              spreadRadius: 0,
                            ),
                          ]
                        : [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.22),
                                blurRadius: 8),
                          ],
                  ),
                  child: Center(
                    child: Transform.scale(
                      scale: _likeAnimCtrl.isAnimating
                          ? _likeScaleAnim.value
                          : 1.0,
                      child: Icon(
                        isLiked
                            ? CupertinoIcons.heart_fill
                            : CupertinoIcons.heart,
                        color: isLiked ? Colors.red : Colors.white,
                        size: 25,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'إعجاب',
            style: TextStyle(
              color: isLiked ? Colors.red : Colors.white.withOpacity(0.8),
              fontFamily: 'Tajawal',
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              shadows: const [
                Shadow(color: Colors.black87, blurRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

// ═══════════════════════════════════════════════════════
  //  شريط معلومات الأغنية السفلي — بديل NavBar
  // ═══════════════════════════════════════════════════════
Widget _buildSongInfoBar({
    required LocalMediaItem item,
    required bool isPlaying,
  }) {
    final title = item.title.replaceAll(RegExp(r'\.\w+$'), '');
    final botPad = MediaQuery.of(context).padding.bottom;
    final thumbBytes = _thumbnails[_currentIndex];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 14, 20, botPad + 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.45),
                Colors.black.withOpacity(0.75),
              ],
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.08),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── الصورة المصغرة الحقيقية للفيديو ──
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10.5),
                  child: thumbBytes != null
                      ? Image.memory(
                          thumbBytes,
                          fit: BoxFit.cover,
                          width: 44,
                          height: 44,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withOpacity(0.8),
                                Colors.red.shade900.withOpacity(0.7),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: CupertinoActivityIndicator(
                              color: Colors.white,
                              radius: 8,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),

              // ── اسم الأغنية + الوصف ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Tajawal',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'DNDN • Offline Reel',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontFamily: 'Tajawal',
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // ── موجات صوتية متحركة ──
              SizedBox(
                height: 28,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(11, (i) {
                    return _SoundWaveBar(
                      index: i,
                      isPlaying: isPlaying,
                      color: i % 3 == 0
                          ? AppColors.primary
                          : i % 3 == 1
                              ? Colors.white.withOpacity(0.7)
                              : Colors.red.withOpacity(0.8),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════
//  SOUND WAVE BAR — شريط موجة صوتية متحرك
// ═══════════════════════════════════════════════════════

class _SoundWaveBar extends StatefulWidget {
  final int index;
  final bool isPlaying;
  final Color color;

  const _SoundWaveBar({
    required this.index,
    required this.isPlaying,
    required this.color,
  });

  @override
  State<_SoundWaveBar> createState() => _SoundWaveBarState();
}

class _SoundWaveBarState extends State<_SoundWaveBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400 + widget.index * 80),
    );
    _anim = Tween<double>(begin: 0.15, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.isPlaying) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _SoundWaveBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isPlaying && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 3,
        height: 20 * _anim.value,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(2),
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.5),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  OPTIONS SHEET — ورقة خيارات المشغل
// ═══════════════════════════════════════════════════════

class _OptionsSheet extends StatefulWidget {
  final bool isLooping;
  final bool autoScroll;
  final bool showControls;
  final List<MusicFolder> folders;
  final LocalMediaItem currentItem;
  final Function(bool) onLoopChanged;
  final Function(bool) onAutoScrollChanged;
  final VoidCallback onToggleControls;
  final Future<void> Function(MusicFolder) onAddToFolder;

  const _OptionsSheet({
    required this.isLooping,
    required this.autoScroll,
    required this.showControls,
    required this.folders,
    required this.currentItem,
    required this.onLoopChanged,
    required this.onAutoScrollChanged,
    required this.onToggleControls,
    required this.onAddToFolder,
  });

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late bool _looping;
  late bool _autoScroll;
  late bool _showControls;

  @override
  void initState() {
    super.initState();
    _looping = widget.isLooping;
    _autoScroll = widget.autoScroll;
    _showControls = widget.showControls;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // مقبض التمرير
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2)),
              ),

              // العنوان
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(CupertinoIcons.slider_horizontal_3,
                        color: AppColors.primary, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'خيارات المشغل',
                    style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Tajawal',
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // تكرار الفيديو
              _optionRow(
                icon: CupertinoIcons.repeat,
                title: 'تكرار الفيديو',
                subtitle: _looping ? 'مفعّل' : 'معطّل',
                trailing: CupertinoSwitch(
                  value: _looping,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _looping = v);
                    widget.onLoopChanged(v);
                  },
                ),
              ),
              const SizedBox(height: 12),

              // التصفح التلقائي
              _optionRow(
                icon: CupertinoIcons.infinite,
                title: 'التصفح التلقائي',
                subtitle: _autoScroll ? 'ينتقل للفيديو التالي تلقائياً' : 'معطّل',
                trailing: CupertinoSwitch(
                  value: _autoScroll,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _autoScroll = v);
                    widget.onAutoScrollChanged(v);
                  },
                ),
              ),
              const SizedBox(height: 12),

              // إضافة إلى مجلد
              GestureDetector(
                onTap: () => _showFolderPicker(context),
                child: _optionRow(
                  icon: CupertinoIcons.folder_badge_plus,
                  title: 'إضافة إلى مجلد',
                  subtitle: 'أضف هذا الفيديو لمجلد',
                  trailing: Icon(CupertinoIcons.chevron_left,
                      color: Colors.white.withOpacity(0.4), size: 16),
                ),
              ),

              const SizedBox(height: 12),

              // إخفاء / إظهار العناصر
              GestureDetector(
                onTap: widget.onToggleControls,
                child: _optionRow(
                  icon: _showControls
                      ? CupertinoIcons.eye_slash_fill
                      : CupertinoIcons.eye_fill,
                  title: _showControls ? 'إخفاء العناصر' : 'إظهار العناصر',
                  subtitle: _showControls
                      ? 'اخفِ أزرار التحكم للمشاهدة النظيفة'
                      : 'أظهر أزرار التحكم مرة أخرى',
                  trailing: Icon(
                    _showControls
                        ? CupertinoIcons.eye_slash_fill
                        : CupertinoIcons.eye_fill,
                    color: _showControls
                        ? Colors.white.withOpacity(0.4)
                        : AppColors.primary,
                    size: 16,
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: AppColors.primary, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Tajawal',
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontFamily: 'Tajawal',
                        fontSize: 12)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  void _showFolderPicker(BuildContext context) {
    if (widget.folders.isEmpty) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد مجلدات. أنشئ مجلداً أولاً.',
              style: TextStyle(fontFamily: 'Tajawal')),
          backgroundColor: Colors.grey,
        ),
      );
      return;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        color: const Color(0xFF1C1C1E),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.folder,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    const Text('اختر المجلد',
                        style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Tajawal',
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              ...widget.folders.map((folder) => GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      Navigator.pop(context);
                      await widget.onAddToFolder(folder);
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
                                borderRadius: BorderRadius.circular(8)),
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
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}