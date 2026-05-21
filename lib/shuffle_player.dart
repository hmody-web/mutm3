import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'main.dart'; // LocalMediaItem, ThumbnailManager, audioService, AppColors …

// ═══════════════════════════════════════════════════════════════
//  SHUFFLE PLAYER PAGE — الوضع العشوائي (3D Ring Carousel)
// ═══════════════════════════════════════════════════════════════

class ShufflePlayerPage extends StatefulWidget {
  final List<LocalMediaItem> items;

  const ShufflePlayerPage({super.key, required this.items});

  @override
  State<ShufflePlayerPage> createState() => _ShufflePlayerPageState();
}

class _ShufflePlayerPageState extends State<ShufflePlayerPage>
    with TickerProviderStateMixin {
  // ── أنيميشن الدوران الدائم (بطيء) ──
  late AnimationController _idleCtrl;

  // ── أنيميشن التسارع عند الضغط ──
  late AnimationController _spinCtrl;
  late CurvedAnimation _spinCurve;

  // ── أنيميشن السحب المغناطيسي للغلاف المختار ──
  late AnimationController _pickCtrl;
  late Animation<double> _pickScale;
  late Animation<double> _pickOpacity;

  // ── أنيميشن ظهور معلومات الأغنية ──
  late AnimationController _infoCtrl;
  late Animation<double> _infoAnim;

  // ── أنيميشن Particle / Light Trails ──
  late AnimationController _particleCtrl;

  // ── حالة المشغل ──
  _PlayerState _state = _PlayerState.idle;
  double _ringAngle = 0.0;        // الزاوية الحالية للحلقة
  double _spinVelocity = 0.0;     // سرعة الدوران (راديان/ثانية)
  LocalMediaItem? _chosenItem;
  String? _chosenThumbPath;
  int _chosenRingIndex = 0;

  // ── قائمة الأغاني في الحلقة (مختصرة إذا كثيرة) ──
  late List<LocalMediaItem> _ringItems;
  final int _maxRingItems = 10;

  // ── مؤقت الدوران المستمر ──
  Timer? _idleTimer;
  double _idleAngleDelta = 0.0;

  // ── جزيئات ضوئية ──
  final List<_Particle> _particles = [];
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();

    // اختصار قائمة الأغاني
    final shuffled = List<LocalMediaItem>.from(widget.items)..shuffle();
    _ringItems = shuffled.take(_maxRingItems).toList();

    // أنيميشن الدوران البطيء المستمر
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onIdleTick);

    // أنيميشن الضغط (تسارع ثم تباطؤ)
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _spinCurve = CurvedAnimation(parent: _spinCtrl, curve: Curves.easeInOut);

    // أنيميشن السحب المغناطيسي
    _pickCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pickScale = Tween<double>(begin: 1.0, end: 2.2).animate(
      CurvedAnimation(parent: _pickCtrl, curve: Curves.easeOutBack),
    );
    _pickOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pickCtrl, curve: Curves.easeOut),
    );

    // أنيميشن ظهور معلومات الأغنية
    _infoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _infoAnim = CurvedAnimation(parent: _infoCtrl, curve: Curves.easeOutCubic);

    // أنيميشن الجزيئات
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updateParticles);

    _startIdleRotation();
    _preloadThumbs();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _idleCtrl.dispose();
    _spinCtrl.dispose();
    _pickCtrl.dispose();
    _infoCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  // ─── تحميل الصور المصغرة مسبقاً ───
  Future<void> _preloadThumbs() async {
    for (final item in _ringItems) {
      await ThumbnailManager.getLocalThumbnail(item.path);
    }
    if (mounted) setState(() {});
  }

  // ─── الدوران البطيء في وضع الخمول ───
  void _startIdleRotation() {
    _idleCtrl.repeat();
  }

  void _onIdleTick() {
    if (_state == _PlayerState.idle || _state == _PlayerState.playing) {
      setState(() {
        _ringAngle += 0.003; // بطيء جداً
      });
    }
  }

  // ─── توليد جزيئات ضوئية ───
  void _spawnParticles() {
    _particles.clear();
    for (int i = 0; i < 30; i++) {
      _particles.add(_Particle(
        angle: _rand.nextDouble() * 2 * math.pi,
        radius: 80 + _rand.nextDouble() * 120,
        speed: 0.5 + _rand.nextDouble() * 2.0,
        size: 1.5 + _rand.nextDouble() * 3.0,
        opacity: 0.4 + _rand.nextDouble() * 0.6,
        color: _rand.nextBool() ? AppColors.primary : Colors.white,
      ));
    }
    _particleCtrl.repeat();
  }

  void _updateParticles() {
    if (_state != _PlayerState.spinning) return;
    setState(() {
      for (final p in _particles) {
        p.angle += p.speed * 0.05 * _spinVelocity;
        p.opacity = (p.opacity - 0.005).clamp(0.1, 1.0);
      }
    });
  }

  // ─── ضغط زر الدوران ───
  Future<void> _onSpinPressed() async {
    if (_state == _PlayerState.spinning || _state == _PlayerState.picking) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _state = _PlayerState.spinning;
      _spinVelocity = 0.0;
    });

    _spawnParticles();

    // مرحلة التسارع
    const totalDuration = Duration(milliseconds: 3500);
    const accelerateMs = 1200;
    const holdMs = 1500;
    const decelerateMs = 800;
    final stopwatch = Stopwatch()..start();

    late Timer spinTimer;
    spinTimer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      final elapsed = stopwatch.elapsedMilliseconds;

      if (elapsed < accelerateMs) {
        // تسارع
        final progress = elapsed / accelerateMs;
        _spinVelocity = Curves.easeIn.transform(progress) * 0.35;
        HapticFeedback.selectionClick();
      } else if (elapsed < accelerateMs + holdMs) {
        // ثبات
        _spinVelocity = 0.35;
      } else if (elapsed < totalDuration.inMilliseconds) {
        // تباطؤ
        final progress =
            (elapsed - accelerateMs - holdMs) / decelerateMs;
        _spinVelocity =
            0.35 * (1 - Curves.easeOut.transform(progress.clamp(0, 1)));
      } else {
        // انتهاء الدوران
        _spinVelocity = 0.0;
        spinTimer.cancel();
        _particleCtrl.stop();
        _onSpinEnd();
        return;
      }

      if (mounted) {
        setState(() {
          _ringAngle += _spinVelocity;
        });
      }
    });
  }

  // ─── اختيار الأغنية بعد انتهاء الدوران ───
  Future<void> _onSpinEnd() async {
    setState(() => _state = _PlayerState.picking);
    HapticFeedback.heavyImpact();

    // اختيار عشوائي
    final idx = _rand.nextInt(_ringItems.length);
    final chosen = _ringItems[idx];
    final thumbPath = await ThumbnailManager.getLocalThumbnail(chosen.path);

    setState(() {
      _chosenItem = chosen;
      _chosenThumbPath = thumbPath;
      _chosenRingIndex = idx;
    });

    // تأخير قصير ثم بدء أنيميشن السحب المغناطيسي
    await Future.delayed(const Duration(milliseconds: 300));
    await _pickCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 200));
    _infoCtrl.forward();

    setState(() => _state = _PlayerState.playing);

    // تشغيل الأغنية
    final startIdx = widget.items.indexOf(chosen);
    audioService.playList(
      widget.items,
      startIdx < 0 ? 0 : startIdx,
    );
  }

  // ─── إعادة الضبط ───
  void _reset() {
    _pickCtrl.reset();
    _infoCtrl.reset();
    _particleCtrl.reset();
    _particles.clear();
    setState(() {
      _state = _PlayerState.idle;
      _chosenItem = null;
      _chosenThumbPath = null;
      _spinVelocity = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
      body: Stack(
        children: [
          // ── خلفية متدرجة ديناميكية ──
          _BackgroundGlow(
            isDark: isDark,
            isActive: _state == _PlayerState.spinning,
            animValue: _spinCtrl.value,
          ),

          // ── المحتوى الرئيسي ──
          SafeArea(
            child: Column(
              children: [
                // ── شريط العنوان ──
                _buildTopBar(isDark),

                const Spacer(),

                // ── حلقة الكاروسيل ──
                SizedBox(
                  width: size.width,
                  height: size.width * 0.85,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // جزيئات ضوئية
                      if (_particles.isNotEmpty)
                        CustomPaint(
                          size: Size(size.width, size.width * 0.85),
                          painter: _ParticlePainter(_particles),
                        ),

                      // الحلقة ثلاثية الأبعاد
                      _Ring3DCarousel(
                        items: _ringItems,
                        angle: _ringAngle,
                        spinVelocity: _spinVelocity,
                        chosenIndex:
                            _state == _PlayerState.picking || _state == _PlayerState.playing
                                ? _chosenRingIndex
                                : null,
                        pickProgress: _pickCtrl.value,
                      ),

                      // الغلاف المختار في المنتصف (مرحلة الاختيار)
                      if (_chosenItem != null)
                        AnimatedBuilder(
                          animation: _pickCtrl,
                          builder: (_, __) => Opacity(
                            opacity: _pickOpacity.value,
                            child: Transform.scale(
                              scale: _pickScale.value,
                              child: _buildChosenCover(),
                            ),
                          ),
                        ),

                      // ── زر الدوران المركزي ──
                      if (_state != _PlayerState.picking)
                        _CenterSpinButton(
                          state: _state,
                          onPressed: _state == _PlayerState.playing
                              ? _reset
                              : _onSpinPressed,
                        ),
                    ],
                  ),
                ),

                const Spacer(),

                // ── معلومات الأغنية المختارة ──
                AnimatedBuilder(
                  animation: _infoAnim,
                  builder: (_, __) {
                    if (_chosenItem == null) {
                      return _buildIdleHint(isDark);
                    }
                    return Opacity(
                      opacity: _infoAnim.value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - _infoAnim.value)),
                        child: _buildSongInfo(isDark),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                CupertinoIcons.chevron_right,
                color: isDark ? Colors.white70 : Colors.black54,
                size: 18,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'الوضع العشوائي',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const Spacer(),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(CupertinoIcons.shuffle, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildChosenCover() {
    final size = 90.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.6),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _chosenThumbPath != null
            ? Image.file(File(_chosenThumbPath!), fit: BoxFit.cover)
            : Container(
                color: AppColors.primary.withOpacity(0.3),
                child: const Icon(CupertinoIcons.music_note,
                    color: Colors.white, size: 36),
              ),
      ),
    );
  }

  Widget _buildSongInfo(bool isDark) {
    final title = _chosenItem!.title
        .replaceAll(RegExp(r'\.\w{2,4}$'), '')
        .replaceAll('_', ' ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'يتم التشغيل الآن',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // زر "دوران جديد"
          GestureDetector(
            onTap: _reset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'دوران جديد',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleHint(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        _state == _PlayerState.spinning
            ? 'جارٍ الاختيار...'
            : 'اضغط الزر للدوران واختيار أغنية عشوائية',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 15,
          color: isDark ? Colors.white54 : Colors.black45,
          height: 1.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  3D RING CAROUSEL
// ═══════════════════════════════════════════════════════════════

class _Ring3DCarousel extends StatelessWidget {
  final List<LocalMediaItem> items;
  final double angle;
  final double spinVelocity;
  final int? chosenIndex;
  final double pickProgress;

  const _Ring3DCarousel({
    required this.items,
    required this.angle,
    required this.spinVelocity,
    this.chosenIndex,
    required this.pickProgress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = items.length;
    final ringRadius = 130.0;
    // ميل الحلقة لإعطاء Perspective
    const tiltX = 0.42; // راديان

    // نبني الأغاني مرتبة حسب عمقها (z) من الأبعد للأقرب
    final List<_RingItemData> renderList = [];
    for (int i = 0; i < count; i++) {
      final theta = angle + (2 * math.pi / count) * i;
      // موضع على الحلقة المائلة
      final x = ringRadius * math.sin(theta);
      final rawY = ringRadius * math.cos(theta);
      final y = rawY * math.sin(tiltX); // ضغط محور Y
      final z = rawY * math.cos(tiltX); // عمق

      // نسبة القرب (0=أبعد، 1=أقرب)
      final depthT = (z / ringRadius + 1) / 2;
      final scale = 0.45 + depthT * 0.65;
      final opacity = 0.35 + depthT * 0.65;
      final blur = (1 - depthT) * 3.0;

      renderList.add(_RingItemData(
        index: i,
        x: x,
        y: y,
        z: z,
        scale: scale,
        opacity: opacity,
        blur: blur,
        item: items[i],
      ));
    }

    // ترتيب حسب z (الأبعد أولاً حتى يُرسم تحت الأقرب)
    renderList.sort((a, b) => a.z.compareTo(b.z));

    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow حول الحلقة
        CustomPaint(
          size: const Size(300, 200),
          painter: _RingGlowPainter(
            isDark: isDark,
            spinVelocity: spinVelocity,
          ),
        ),

        // أغلفة الأغاني
        for (final data in renderList)
          _RingItemWidget(
            data: data,
            isChosen: chosenIndex == data.index,
            pickProgress: pickProgress,
            spinVelocity: spinVelocity,
          ),
      ],
    );
  }
}

class _RingItemData {
  final int index;
  final double x, y, z;
  final double scale, opacity, blur;
  final LocalMediaItem item;
  const _RingItemData({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.scale,
    required this.opacity,
    required this.blur,
    required this.item,
  });
}

class _RingItemWidget extends StatelessWidget {
  final _RingItemData data;
  final bool isChosen;
  final double pickProgress;
  final double spinVelocity;

  const _RingItemWidget({
    required this.data,
    required this.isChosen,
    required this.pickProgress,
    required this.spinVelocity,
  });

  @override
  Widget build(BuildContext context) {
    final baseSize = 72.0;
    final size = baseSize * data.scale;
    final thumbPath = ThumbnailManagerSync.memCacheLookup(data.item.path);

    // إذا كان المختار، يتحرك نحو المركز بسلاسة
    double dx = data.x;
    double dy = data.y;
    if (isChosen && pickProgress > 0) {
      dx = data.x * (1 - pickProgress);
      dy = data.y * (1 - pickProgress);
    }

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Opacity(
        opacity: isChosen ? 1.0 : (data.opacity * (isChosen ? 1 : (1 - pickProgress * 0.8))),
        child: Transform.scale(
          scale: isChosen ? (data.scale + pickProgress * 0.4) : data.scale,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: isChosen ? 0 : data.blur,
              sigmaY: isChosen ? 0 : data.blur,
            ),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14 * data.scale),
                boxShadow: [
                  BoxShadow(
                    color: isChosen
                        ? AppColors.primary.withOpacity(0.7)
                        : Colors.black.withOpacity(0.3 * data.scale),
                    blurRadius: isChosen ? 20 : 8,
                    spreadRadius: isChosen ? 3 : 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14 * data.scale),
                child: thumbPath != null
                    ? Image.file(File(thumbPath), fit: BoxFit.cover)
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withOpacity(0.7),
                              AppColors.primaryDark.withOpacity(0.9),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          CupertinoIcons.music_note,
                          color: Colors.white.withOpacity(0.8),
                          size: 24 * data.scale,
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

// ═══════════════════════════════════════════════════════════════
//  زر الدوران المركزي
// ═══════════════════════════════════════════════════════════════

class _CenterSpinButton extends StatefulWidget {
  final _PlayerState state;
  final VoidCallback onPressed;

  const _CenterSpinButton({
    required this.state,
    required this.onPressed,
  });

  @override
  State<_CenterSpinButton> createState() => _CenterSpinButtonState();
}

class _CenterSpinButtonState extends State<_CenterSpinButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSpinning = widget.state == _PlayerState.spinning;
    final isPlaying = widget.state == _PlayerState.playing;

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Transform.scale(
        scale: isSpinning ? 1.0 : _pulseAnim.value,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: isSpinning
                    ? [
                        AppColors.primary.withOpacity(0.9),
                        AppColors.primaryDark,
                      ]
                    : [
                        isDark ? const Color(0xFF2A2A2A) : Colors.white,
                        isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF0F0F0),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(isSpinning ? 0.6 : 0.3),
                  blurRadius: isSpinning ? 30 : 16,
                  spreadRadius: isSpinning ? 6 : 2,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: isSpinning
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? CupertinoIcons.arrow_counterclockwise
                          : CupertinoIcons.shuffle,
                      color: isPlaying
                          ? AppColors.primary
                          : (isDark ? Colors.white70 : AppColors.primary),
                      size: 30,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  الخلفية الديناميكية بالـ Glow
// ═══════════════════════════════════════════════════════════════

class _BackgroundGlow extends StatefulWidget {
  final bool isDark;
  final bool isActive;
  final double animValue;

  const _BackgroundGlow({
    required this.isDark,
    required this.isActive,
    required this.animValue,
  });

  @override
  State<_BackgroundGlow> createState() => _BackgroundGlowState();
}

class _BackgroundGlowState extends State<_BackgroundGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, 0.2),
            radius: 1.2,
            colors: widget.isDark
                ? [
                    AppColors.primary
                        .withOpacity(widget.isActive ? _glowAnim.value * 0.25 : 0.08),
                    Colors.transparent,
                    const Color(0xFF0A0A0A),
                  ]
                : [
                    AppColors.primary
                        .withOpacity(widget.isActive ? _glowAnim.value * 0.12 : 0.04),
                    Colors.transparent,
                    const Color(0xFFF5F5F5),
                  ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════

class _RingGlowPainter extends CustomPainter {
  final bool isDark;
  final double spinVelocity;

  _RingGlowPainter({required this.isDark, required this.spinVelocity});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = 130.0;
    final glowAlpha = (0.15 + spinVelocity * 0.5).clamp(0.0, 0.5);

    final paint = Paint()
      ..color = AppColors.primary.withOpacity(glowAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 + spinVelocity * 8
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + spinVelocity * 10);

    // حلقة مائلة (Ellipse)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: radius * 2,
        height: radius * 0.65,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingGlowPainter old) =>
      old.spinVelocity != spinVelocity;
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  _ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    for (final p in particles) {
      final x = cx + p.radius * math.cos(p.angle);
      final y = cy + p.radius * 0.4 * math.sin(p.angle);
      final paint = Paint()
        ..color = p.color.withOpacity(p.opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

// ═══════════════════════════════════════════════════════════════
//  DATA CLASSES
// ═══════════════════════════════════════════════════════════════

enum _PlayerState { idle, spinning, picking, playing }

class _Particle {
  double angle;
  final double radius;
  final double speed;
  final double size;
  double opacity;
  final Color color;

  _Particle({
    required this.angle,
    required this.radius,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.color,
  });
}

// ═══════════════════════════════════════════════════════════════
//  EXTENSION على ThumbnailManager لدعم الـ memCache sync
// ═══════════════════════════════════════════════════════════════
extension ThumbnailManagerSync on ThumbnailManager {
  static String? memCacheLookup(String path) {
    // نبحث في الـ memCache المحلي — يكفي لأن preloadThumbs يملؤه
    final thumbPath = path.substring(0, path.lastIndexOf('/')) +
        '/.thumb_' +
        path.split('/').last.replaceAll(RegExp(r'\.\w+$'), '') +
        '.jpg';
    final f = File(thumbPath);
    return f.existsSync() ? thumbPath : null;
  }
}