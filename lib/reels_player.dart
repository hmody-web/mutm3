import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'listen_page.dart';

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
    with TickerProviderStateMixin {
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
        vsync: this, duration: const Duration(milliseconds: 400));

    _initController(_currentIndex);
    if (_currentIndex > 0) _initController(_currentIndex - 1);
    if (_currentIndex < widget.items.length - 1)
      _initController(_currentIndex + 1);

    _scheduleControlsHide();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    _pageController.dispose();
    _overlayAnimCtrl.dispose();
    _heartAnimCtrl.dispose();
    _pageTransitionCtrl.dispose();
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
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleControlsHide();
  }

  void _onPageChanged(int index) {
    final prevCtrl = _controllers[_currentIndex];
    prevCtrl?.pause();

    _currentIndex = index;
    _isTitleExpanded = false;

    final curr = _controllers[index];
    if (curr != null && (_initialized[index] ?? false)) {
      curr.setLooping(_isLooping);
      curr.play();
      _startProgressTimer();
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

    _scheduleControlsHide();
    setState(() {});

    if (_autoScroll) _scheduleAutoScroll();
  }

  void _scheduleAutoScroll() {
    _autoScrollTimer?.cancel();
    final ctrl = _controllers[_currentIndex];
    if (ctrl == null) return;
    final dur = ctrl.value.duration;
    _autoScrollTimer = Timer(dur, () {
      if (!mounted) return;
      final next = _currentIndex + 1;
      if (next < widget.items.length) {
        _pageController.animateToPage(next,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut);
      }
    });
  }

  void _onDoubleTap() {
    setState(() => _showHeart = true);
    _heartAnimCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 800),
        () => mounted ? setState(() => _showHeart = false) : null);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
          setState(() => _isLooping = v);
          _controllers[_currentIndex]?.setLooping(v);
        },
        onAutoScrollChanged: (v) {
          setState(() => _autoScroll = v);
          if (v) {
            _scheduleAutoScroll();
          } else {
            _autoScrollTimer?.cancel();
          }
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
        onTap: _toggleControls,
        onDoubleTap: _onDoubleTap,
        child: Stack(
          children: [
            // ── صفحات الفيديو ──
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: widget.items.length,
              itemBuilder: (_, index) {
                return _buildVideoPage(index, size);
              },
            ),

            // ── طبقة القلب عند الدبل تاب ──
            if (_showHeart)
              Center(
                child: ScaleTransition(
                  scale: _heartAnim,
                  child: const Icon(CupertinoIcons.heart_fill,
                      color: Colors.white, size: 100),
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

    return Stack(
      fit: StackFit.expand,
      children: [
        // خلفية سوداء
        Container(color: Colors.black),

        // الفيديو بداخل حاوية مع الحفاظ على النسبة
        if (ctrl != null && isInit)
          Center(
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
                    color: Colors.white, radius: 16),
                const SizedBox(height: 12),
                Text(
                  'جارٍ التحميل...',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontFamily: 'Tajawal',
                      fontSize: 13),
                ),
              ],
            ),
          ),

        // تدرج سفلي للـ UI
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: size.height * 0.45,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.85),
                ],
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

    // عنوان مقتطع / كامل
    final title = item.title.replaceAll(RegExp(r'\.\w+$'), '');
    final shortTitle = title.length > 27 ? title.substring(0, 27) : title;

    return Stack(
      children: [
        // ─── الجانب الأيمن: لوجو + خيارات ───
        Positioned(
          right: 16,
          bottom: 140,
          child: Column(
            children: [
              // لوجو التطبيق دندن
              _buildSideButton(
                child: Image.asset('assets/images/jna7.png',
                    width: 28, height: 28, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text('♪',
                        style:
                            TextStyle(color: Colors.white, fontSize: 22))),
                label: '',
                onTap: () {},
                showLabel: false,
              ),
              const SizedBox(height: 20),

              // تشغيل/إيقاف
              _buildSideButton(
                child: Icon(
                  isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                  color: Colors.white,
                  size: 26,
                ),
                label: isPlaying ? 'إيقاف' : 'تشغيل',
                onTap: () {
                  setState(() {});
                  if (isPlaying) {
                    ctrl?.pause();
                  } else {
                    ctrl?.play();
                  }
                },
              ),
              const SizedBox(height: 20),

              // تكرار
              _buildSideButton(
                child: Icon(
                  CupertinoIcons.repeat,
                  color: _isLooping ? AppColors.primary : Colors.white,
                  size: 24,
                ),
                label: 'تكرار',
                onTap: () {
                  setState(() => _isLooping = !_isLooping);
                  _controllers[_currentIndex]?.setLooping(_isLooping);
                },
                isActive: _isLooping,
              ),
              const SizedBox(height: 20),

              // تصفح تلقائي
              _buildSideButton(
                child: Icon(
                  CupertinoIcons.infinite,
                  color: _autoScroll ? AppColors.primary : Colors.white,
                  size: 24,
                ),
                label: 'تلقائي',
                onTap: () {
                  setState(() => _autoScroll = !_autoScroll);
                  if (_autoScroll) {
                    _scheduleAutoScroll();
                  } else {
                    _autoScrollTimer?.cancel();
                  }
                },
                isActive: _autoScroll,
              ),
              const SizedBox(height: 20),

              // ثلاث نقاط - المزيد
              _buildSideButton(
                child: const Icon(CupertinoIcons.ellipsis_vertical,
                    color: Colors.white, size: 24),
                label: 'المزيد',
                onTap: () => _showOptionsMenu(context),
              ),
            ],
          ),
        ),

        // ─── أعلى: زر الرجوع ───
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(19),
                border:
                    Border.all(color: Colors.white.withOpacity(0.2), width: 1),
              ),
              child: const Icon(CupertinoIcons.xmark,
                  color: Colors.white, size: 18),
            ),
          ),
        ),

        // ─── مؤشر الفيديو الحالي ───
        Positioned(
          top: MediaQuery.of(context).padding.top + 14,
          left: 0,
          right: 60,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.white.withOpacity(0.15), width: 1),
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

        // ─── الأسفل: عنوان + شريط التمرير ───
        Positioned(
          bottom: 0,
          left: 0,
          right: 80,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // أيقونة الفيديو + العنوان
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(CupertinoIcons.play_rectangle_fill,
                          color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _isTitleExpanded = !_isTitleExpanded),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _isTitleExpanded ? title : shortTitle,
                            key: ValueKey(_isTitleExpanded),
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Tajawal',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(
                                    color: Colors.black54,
                                    offset: Offset(0, 1),
                                    blurRadius: 4),
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
                    if (title.length > 27)
                      Icon(
                        _isTitleExpanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        color: Colors.white.withOpacity(0.7),
                        size: 14,
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // وقت التشغيل
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(position),
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontFamily: 'Tajawal',
                          fontSize: 11),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontFamily: 'Tajawal',
                          fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // شريط التمرير
                GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    if (ctrl == null || !isInit) return;
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final width = box.size.width - 32;
                    final newProgress =
                        (progress + d.delta.dx / width).clamp(0.0, 1.0);
                    final newPos = duration * newProgress;
                    ctrl.seekTo(newPos);
                  },
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // خلفية
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // تقدم
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.primary.withOpacity(0.6),
                                  blurRadius: 4,
                                  spreadRadius: 1),
                            ],
                          ),
                        ),
                      ),
                      // دائرة التمرير
                      Positioned(
                        left: ((progress.clamp(0.0, 1.0)) *
                                (MediaQuery.of(context).size.width - 112)) -
                            6,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.primary.withOpacity(0.5),
                                  blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ─── مؤشرات التصفح (أسهم) ───
        if (_currentIndex > 0)
          Positioned(
            top: size.height * 0.5 - 40,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _showControls ? 0.6 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: const Icon(CupertinoIcons.chevron_up,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
      ],
    );
  }

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
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withOpacity(0.25)
                  : Colors.black.withOpacity(0.45),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? AppColors.primary.withOpacity(0.6)
                    : Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2),
                    ]
                  : [],
            ),
            child: Center(child: child),
          ),
          if (showLabel && label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.primary : Colors.white.withOpacity(0.8),
                fontFamily: 'Tajawal',
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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