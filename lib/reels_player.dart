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
        vsync: this, duration: const Duration(milliseconds: 220));

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
      body: GestureDetector(
        // ── اكتشاف اتجاه السحب العمودي (تصفح الريلز) ──
        onVerticalDragStart: (details) {
          _dragOffset = 0.0;
          _isDraggingPage = true;
        },
        onVerticalDragUpdate: (details) {
          if (!_isDraggingPage) return;
          setState(() {
            _dragOffset += details.delta.dy;
          });
          // تحريك الـ PageView يدوياً بناءً على الإزاحة
          final currentPagePixels = _currentIndex * size.height;
          double effectiveOffset = _dragOffset;
          final isAtFirst = _currentIndex == 0 && _dragOffset > 0;
          final isAtLast = _currentIndex == widget.items.length - 1 && _dragOffset < 0;
          if (isAtFirst || isAtLast) {
            effectiveOffset = _dragOffset * 0.25; // مقاومة 75%
          }
          final newOffset = currentPagePixels - effectiveOffset;
          _pageController.jumpTo(newOffset.clamp(0.0, (widget.items.length - 1) * size.height));
        },
        onVerticalDragEnd: (details) {
          if (!_isDraggingPage) return;
          _isDraggingPage = false;

          final velocity = details.primaryVelocity ?? 0;
          final threshold = size.height * 0.22;

          int targetPage = _currentIndex;

          if (_dragOffset < -threshold || velocity < -700) {
            if (_currentIndex < widget.items.length - 1) {
              targetPage = _currentIndex + 1;
            }
          } else if (_dragOffset > threshold || velocity > 700) {
            if (_currentIndex > 0) {
              targetPage = _currentIndex - 1;
            }
          }

          _dragOffset = 0.0;
          _pageController.animateToPage(
            targetPage,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        },
        onVerticalDragCancel: () {
          if (!_isDraggingPage) return;
          _isDraggingPage = false;
          _dragOffset = 0.0;
          _pageController.animateToPage(
            _currentIndex,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        },
        // ── النقر والدبل تاب ──
        onTap: _toggleControls,
        onDoubleTap: _onDoubleTap,
        child: _buildMainContent(size),
      ),
    );
  }

  Widget _buildMainContent(Size size) {
    // ── جيسجر الخروج الأفقي ──
    return GestureDetector(
      onHorizontalDragStart: (details) {
        // نبدأ جيسجر الخروج فقط من حافة الشاشة (أول 30px)
        final isFromEdge = details.localPosition.dx < 30 ||
            details.localPosition.dx > size.width - 30;
        if (isFromEdge) {
          _isDraggingExit = true;
          _exitDragOffset = 0.0;
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
        final threshold = size.width * 0.35;

        if (_exitDragOffset.abs() > threshold || velocity.abs() > 600) {
          // خروج من المشغل
          setState(() => _exitDragOffset = 0.0);
          Navigator.pop(context);
        } else {
          // الرجوع لمكانه
          setState(() => _exitDragOffset = 0.0);
        }
      },
      onHorizontalDragCancel: () {
        if (!_isDraggingExit) return;
        _isDraggingExit = false;
        setState(() => _exitDragOffset = 0.0);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.translationValues(
          _isDraggingExit ? _exitDragOffset * 0.4 : 0.0,
          0,
          0,
        ),
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
                return _buildVideoPage(index, size);
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
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPage(int index, Size size) {
    final ctrl = _controllers[index];
    final isInit = _initialized[index] ?? false;

    // احسب ما إذا كان الفيديو عمودياً
    bool isPortrait = true;
    if (ctrl != null && isInit && ctrl.value.aspectRatio < 1.0) {
      isPortrait = true;
    } else if (ctrl != null && isInit && ctrl.value.aspectRatio >= 1.0) {
      isPortrait = false;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ══════════════════════════════════════════════
        //  طبقة الإضاءة السينمائية — نفس الفيديو مكبّر
        // ══════════════════════════════════════════════
        if (ctrl != null && isInit) ...[
          Positioned.fill(
            child: ClipRect(
              child: OverflowBox(
                maxWidth: size.width * 2.2,
                maxHeight: size.height * 2.2,
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
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                color: Colors.black.withOpacity(0.42),
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
        //  الفيديو الرئيسي — يملأ الشاشة للفيديوهات العمودية
        // ══════════════════════════════════════════════
        if (ctrl != null && isInit)
          isPortrait
              ? Positioned.fill(
                  // للفيديوهات العمودية: نملأ العرض كاملاً ونسمح بالقص العمودي
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: ctrl.value.size.width,
                      height: ctrl.value.size.height,
                      child: VideoPlayer(ctrl),
                    ),
                  ),
                )
              : Center(
                  child: AspectRatio(
                    aspectRatio: ctrl.value.aspectRatio,
                    child: VideoPlayer(ctrl),
                  ),
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

        // تدرج سفلي للـ UI — أعمق وأكثر احترافية
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
          right: 14,
          bottom: botPad + 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── لوجو التطبيق ──
              _buildSideButton(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 22, height: 22, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      CupertinoIcons.music_note_2,
                      color: Colors.white, size: 17,
                    ),
                  ),
                ),
                label: '',
                onTap: () {},
                showLabel: false,
              ),
              const SizedBox(height: 12),

              // ── زر الإعجاب ──
              _buildLikeButton(isLiked: _isCurrentLiked()),
              const SizedBox(height: 12),

              // ── تشغيل / إيقاف ──
              _buildSideButton(
                child: Icon(
                  isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                  color: Colors.white, size: 19,
                ),
                label: isPlaying ? 'إيقاف' : 'تشغيل',
                onTap: () {
                  setState(() {});
                  isPlaying ? ctrl?.pause() : ctrl?.play();
                },
              ),
              const SizedBox(height: 12),

              // ── المزيد ──
              _buildSideButton(
                child: const Icon(CupertinoIcons.ellipsis,
                    color: Colors.white, size: 19),
                label: 'المزيد',
                onTap: () => _showOptionsMenu(context),
              ),
              const SizedBox(height: 12),

              // ── زر إخفاء / إظهار العناصر ──
              _buildSideButton(
                child: Icon(
                  _showControls
                      ? CupertinoIcons.eye_slash_fill
                      : CupertinoIcons.eye_fill,
                  color: _showControls
                      ? Colors.white.withOpacity(0.8)
                      : AppColors.primary,
                  size: 19,
                ),
                label: _showControls ? 'إخفاء' : 'إظهار',
                onTap: () {
                  setState(() => _showControls = !_showControls);
                  _controlsTimer?.cancel();
                },
                isActive: !_showControls,
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
  }) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 0, 18, botPad + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── العنوان مع أيقونة ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // أيقونة التشغيل
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: const Icon(CupertinoIcons.play_rectangle_fill,
                        color: Colors.white, size: 12),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(
                          () => _isTitleExpanded = !_isTitleExpanded),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        child: Text(
                          _isTitleExpanded ? title : shortTitle,
                          key: ValueKey(_isTitleExpanded),
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Tajawal',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            shadows: [
                              Shadow(
                                  color: Colors.black87,
                                  offset: Offset(0, 1),
                                  blurRadius: 6),
                            ],
                          ),
                          maxLines: _isTitleExpanded ? 3 : 1,
                          overflow: _isTitleExpanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  if (title.length > 30) ...[
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _isTitleExpanded ? -0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        CupertinoIcons.chevron_down,
                        color: Colors.white.withOpacity(0.6),
                        size: 13,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),

              // ── شريط التمرير السلس بدون thumb ──
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final trackWidth = constraints.maxWidth;
                  final displayProgress =
                      _isSeeking ? _seekProgress : progress;

                  return Column(
                    children: [
                      // أوقات التشغيل
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(
                                _isSeeking ? duration * _seekProgress : position),
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontFamily: 'Tajawal',
                                fontSize: 11,
                                fontWeight: FontWeight.w500),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontFamily: 'Tajawal',
                                fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // شريط التمرير
                      GestureDetector(
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
                            _seekProgress =
                                (_seekProgress + delta).clamp(0.0, 1.0);
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
                          height: 36,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // مسار الخلفية
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                height: _isSeeking ? 5 : 3,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),

                              // شريط التقدم مع أنيميشن سلس
                              Align(
                                alignment: Alignment.centerLeft,
                                child: LayoutBuilder(
                                  builder: (_, bc) => AnimatedContainer(
                                    duration: _isSeeking
                                        ? Duration.zero
                                        : const Duration(milliseconds: 150),
                                    width: (displayProgress.clamp(0.0, 1.0) *
                                            trackWidth)
                                        .clamp(0.0, trackWidth),
                                    height: _isSeeking ? 5 : 3,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppColors.primary,
                                          AppColors.primary.withOpacity(0.85),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withOpacity(
                                              _isSeeking ? 0.7 : 0.4),
                                          blurRadius: _isSeeking ? 10 : 5,
                                          spreadRadius: _isSeeking ? 1 : 0,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // وقت السحب المؤقت يظهر فوق المسار
                              if (_isSeeking)
                                Positioned(
                                  left: (displayProgress.clamp(0.0, 1.0) *
                                          trackWidth -
                                      22)
                                      .clamp(0, trackWidth - 44),
                                  bottom: 22,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                          sigmaX: 8, sigmaY: 8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withOpacity(0.85),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _formatDuration(
                                              duration * displayProgress),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontFamily: 'Tajawal',
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
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
                              color: Colors.red.withOpacity(0.4),
                              blurRadius: 14,
                              spreadRadius: 1,
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
                        size: 19,
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
}

// ═══════════════════════════════════════════════════════
//  OPTIONS SHEET — ورقة خيارات المشغل
// ═══════════════════════════════════════════════════════

class _OptionsSheet extends StatefulWidget {
  final bool isLooping;
  final bool autoScroll;
  final List<MusicFolder> folders;
  final LocalMediaItem currentItem;
  final Function(bool) onLoopChanged;
  final Function(bool) onAutoScrollChanged;
  final Future<void> Function(MusicFolder) onAddToFolder;

  const _OptionsSheet({
    required this.isLooping,
    required this.autoScroll,
    required this.folders,
    required this.currentItem,
    required this.onLoopChanged,
    required this.onAutoScrollChanged,
    required this.onAddToFolder,
  });

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late bool _looping;
  late bool _autoScroll;

  @override
  void initState() {
    super.initState();
    _looping = widget.isLooping;
    _autoScroll = widget.autoScroll;
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