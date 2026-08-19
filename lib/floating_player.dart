part of 'main.dart';

// ═══════════════════════════════════════════════════════════════
//  FLOATING PLAYER MODE — المشغل العائم
// ═══════════════════════════════════════════════════════════════
class FloatingPlayerModeNotifier extends ValueNotifier<bool> {
  FloatingPlayerModeNotifier._() : super(false);
  static final FloatingPlayerModeNotifier instance = FloatingPlayerModeNotifier._();

  static const String prefKey = 'floatingPlayerMode';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getBool(prefKey) ?? false;
    if (value) {
      await prefs.setBool('reelsMode', false);
      ReelsModeNotifier.instance.value = false;
      audioService.isReelsMode = false;
    }
  }

  Future<void> set(bool v) async {
    value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, v);
    if (v) {
      await prefs.setBool('reelsMode', false);
      ReelsModeNotifier.instance.value = false;
      audioService.isReelsMode = false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  FLOATING PLAYER OVERLAY — يظهر فوق التطبيق كله
// ═══════════════════════════════════════════════════════════════
class FloatingPlayerOverlay extends StatelessWidget {
  const FloatingPlayerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FloatingPlayerModeNotifier.instance,
      builder: (_, enabled, __) {
        if (!enabled) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: audioService.isVisible,
          builder: (_, visible, __) {
            if (!visible) return const SizedBox.shrink();
            return ValueListenableBuilder<int>(
              valueListenable: audioService.currentIndex,
              builder: (_, __, ___) {
                final item = audioService.currentItem;
                if (item == null || !item.isVideo) return const SizedBox.shrink();
                return const _FloatingPlayerBody();
              },
            );
          },
        );
      },
    );
  }
}

class _FloatingPlayerBody extends StatefulWidget {
  const _FloatingPlayerBody();

  @override
  State<_FloatingPlayerBody> createState() => _FloatingPlayerBodyState();
}

class _FloatingPlayerBodyState extends State<_FloatingPlayerBody>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoCtrl;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _playingSub;
  String? _loadedPath;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    audioService.currentIndex.addListener(_reloadForCurrentItem);
    audioService.videoLoopSignal.addListener(_handleLoopSignal);
    _reloadForCurrentItem();
  }

  @override
  void dispose() {
    audioService.currentIndex.removeListener(_reloadForCurrentItem);
    audioService.videoLoopSignal.removeListener(_handleLoopSignal);
    _posSub?.cancel();
    _playingSub?.cancel();
    _videoCtrl?.dispose();
    super.dispose();
  }

  void _handleLoopSignal() {
    final ctrl = _videoCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    ctrl.seekTo(Duration.zero);
    if (audioService.player.playing) ctrl.play();
  }

  Future<void> _reloadForCurrentItem() async {
    final item = audioService.currentItem;
    if (item == null || !item.isVideo || item.path == _loadedPath) return;
    _loadedPath = item.path;
    await _posSub?.cancel();
    await _playingSub?.cancel();
    final old = _videoCtrl;
    _videoCtrl = null;
    if (mounted) setState(() {});
    await old?.dispose();

    final ctrl = VideoPlayerController.file(File(item.path));
    _videoCtrl = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.setLooping(false);
      await ctrl.setVolume(0.0);
      await ctrl.seekTo(audioService.player.position);
      if (audioService.player.playing) await ctrl.play();
      _bindSync(ctrl);
      if (mounted) setState(() {});
    } catch (_) {
      await ctrl.dispose();
      if (_videoCtrl == ctrl) _videoCtrl = null;
      if (mounted) setState(() {});
    }
  }

  void _bindSync(VideoPlayerController ctrl) {
    _posSub = audioService.player.positionStream.listen((pos) async {
      if (_syncing || !mounted || !ctrl.value.isInitialized) return;
      final diff = (ctrl.value.position - pos).inMilliseconds.abs();
      if (diff > 650) {
        _syncing = true;
        try { await ctrl.seekTo(pos); } catch (_) {}
        _syncing = false;
      }
    });

    _playingSub = audioService.player.playingStream.listen((playing) async {
      if (!mounted || !ctrl.value.isInitialized) return;
      try {
        if (playing) {
          await ctrl.play();
        } else {
          await ctrl.pause();
        }
      } catch (_) {}
    });
  }

  String _cleanTitle(String title) => title.replaceAll(RegExp(r'\.\w+$'), '');

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = context.isDark;
    final videoWidth = (size.width * 0.42).clamp(150.0, 260.0);
    final videoHeight = videoWidth * 1.58;
    final panelWidth = (size.width * 0.47).clamp(170.0, 310.0);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: RepaintBoundary(
          child: Stack(
            children: [
            Positioned(
              left: -videoWidth * 0.10,
              top: (size.height - videoHeight) / 2 - 20,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(0.28)
                  ..rotateZ(-0.035),
                child: _FloatingVideoCard(
                  width: videoWidth,
                  height: videoHeight,
                  controller: _videoCtrl,
                  title: _cleanTitle(audioService.currentItem?.title ?? ''),
                  isDark: isDark,
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: MediaQuery.of(context).padding.top + 18,
              bottom: 96,
              width: panelWidth,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(-0.18),
                child: _FloatingPlaylistPanel(isDark: isDark),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingVideoCard extends StatelessWidget {
  final double width;
  final double height;
  final VideoPlayerController? controller;
  final String title;
  final bool isDark;

  const _FloatingVideoCard({
    required this.width,
    required this.height,
    required this.controller,
    required this.title,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.28),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ctrl != null && ctrl.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: ctrl.value.size.width,
                  height: ctrl.value.size.height,
                  child: VideoPlayer(ctrl),
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: CupertinoActivityIndicator(color: Colors.white),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.62),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  _floatingRoundBtn(
                    icon: CupertinoIcons.xmark,
                    onTap: () async => audioService.stopAndClear(),
                  ),
                  const Spacer(),
                  _floatingRoundBtn(
                    icon: CupertinoIcons.arrow_down_right_arrow_up_left,
                    onTap: () => openFullScreenPlayer(context),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Tajawal',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      StreamBuilder<bool>(
                        stream: audioService.player.playingStream,
                        builder: (_, snap) {
                          final playing = snap.data ?? audioService.player.playing;
                          return _floatingRoundBtn(
                            icon: playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                            size: 19,
                            onTap: () => playing
                                ? audioService.pauseByUser()
                                : audioService.playByUser(),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StreamBuilder<Duration?>(
                          stream: audioService.player.durationStream,
                          builder: (_, durSnap) {
                            return StreamBuilder<Duration>(
                              stream: audioService.player.positionStream,
                              builder: (_, posSnap) {
                                final dur = durSnap.data?.inMilliseconds ?? 1;
                                final pos = posSnap.data?.inMilliseconds ?? 0;
                                final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 4,
                                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                );
                              },
                            );
                          },
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
    );
  }

  Widget _floatingRoundBtn({required IconData icon, required VoidCallback onTap, double size = 18}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.26),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: Colors.white, size: size),
          ),
        ),
      ),
    );
  }
}

class _FloatingPlaylistPanel extends StatelessWidget {
  final bool isDark;
  const _FloatingPlaylistPanel({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withValues(alpha: isDark ? 0.34 : 0.48),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.42),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.12),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(CupertinoIcons.music_note_list, color: Colors.white, size: 17),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'القائمة الحالية',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<List<LocalMediaItem>>(
                  valueListenable: audioService.playlist,
                  builder: (_, list, __) {
                    return ValueListenableBuilder<int>(
                      valueListenable: audioService.currentIndex,
                      builder: (_, current, __) {
                        final videos = list.where((e) => e.isVideo).toList(growable: false);
                        final shown = videos.isNotEmpty ? videos : list;
                        if (shown.isEmpty) {
                          return Center(
                            child: Text(
                              'لا توجد عناصر',
                              style: TextStyle(
                                fontFamily: 'Tajawal',
                                color: isDark ? Colors.white70 : AppColors.textSecondary,
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final item = shown[i];
                            final originalIndex = list.indexWhere((e) => e.path == item.path);
                            final selected = originalIndex == current;
                            return _FloatingPlaylistTile(
                              item: item,
                              selected: selected,
                              isDark: isDark,
                              onTap: () { if (originalIndex >= 0) audioService.playAtIndex(originalIndex); },
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
      ),
    );
  }
}

class _FloatingPlaylistTile extends StatefulWidget {
  final LocalMediaItem item;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _FloatingPlaylistTile({
    required this.item,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_FloatingPlaylistTile> createState() => _FloatingPlaylistTileState();
}

class _FloatingPlaylistTileState extends State<_FloatingPlaylistTile> {
  String? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(covariant _FloatingPlaylistTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path) _loadThumb();
  }

  Future<void> _loadThumb() async {
    // لا تولّد صور مصغّرة لكل عناصر القائمة هنا.
    // توليد thumbnails داخل ListView يضغط الـ main thread ويسبب Skipped frames / ANR.
    // نعرض الصورة المخزنة فقط إن كانت موجودة، والباقي يظهر بأيقونة خفيفة.
    final path = await ThumbnailManager.getLocalThumbnail(widget.item.path);
    if (!mounted) return;
    if (path != _thumb) setState(() => _thumb = path);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item.title.replaceAll(RegExp(r'\.\w+$'), '');
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: widget.selected
              ? AppColors.primary.withValues(alpha: 0.90)
              : (widget.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.42)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.selected
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: widget.isDark ? 0.08 : 0.30),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _thumb != null
                  ? Image.file(File(_thumb!), width: 38, height: 38, fit: BoxFit.cover)
                  : Container(
                      width: 38,
                      height: 38,
                      color: AppColors.primary.withValues(alpha: 0.16),
                      child: Icon(
                        widget.item.isVideo ? CupertinoIcons.play_rectangle_fill : CupertinoIcons.music_note,
                        color: widget.selected ? Colors.white : AppColors.primary,
                        size: 17,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: widget.selected ? FontWeight.w800 : FontWeight.w600,
                  color: widget.selected
                      ? Colors.white
                      : (widget.isDark ? Colors.white : AppColors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
