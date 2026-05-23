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
import 'download_service.dart';
import 'download_page.dart';
// ═══════════════════════════════════════════════════════════
//  GLASS TOAST NOTIFICATION SYSTEM
// ═══════════════════════════════════════════════════════════

enum _ToastType { success, error, warning, info, delete, move }

class _ToastConfig {
  final IconData icon;
  final Color accentColor;
  final String label;
  const _ToastConfig({required this.icon, required this.accentColor, required this.label});
}

const _toastConfigs = {
  _ToastType.success: _ToastConfig(
    icon: Icons.check_circle_rounded,
    accentColor: Color(0xFF30D158),
    label: 'نجاح',
  ),
  _ToastType.error: _ToastConfig(
    icon: Icons.cancel_rounded,
    accentColor: Color(0xFFFF3B30),
    label: 'خطأ',
  ),
  _ToastType.warning: _ToastConfig(
    icon: Icons.warning_rounded,
    accentColor: Color(0xFFFF9F0A),
    label: 'تنبيه',
  ),
  _ToastType.info: _ToastConfig(
    icon: Icons.info_rounded,
    accentColor: Color(0xFF0A84FF),
    label: 'معلومة',
  ),
  _ToastType.delete: _ToastConfig(
    icon: Icons.delete_rounded,
    accentColor: Color(0xFFFF3B30),
    label: 'حذف',
  ),
  _ToastType.move: _ToastConfig(
    icon: Icons.folder_open_rounded,
    accentColor: Color(0xFF5E5CE6),
    label: 'نقل',
  ),
};

class _GlassToast extends StatefulWidget {
  final String message;
  final _ToastType type;
  final VoidCallback onDismiss;

  const _GlassToast({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_GlassToast> createState() => _GlassToastState();
}

class _GlassToastState extends State<_GlassToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slide = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6)),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _toastConfigs[widget.type]!;
    final topPad = MediaQuery.of(context).padding.top + 12;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Positioned(
          top: topPad,
          left: 16,
          right: 16,
          child: FractionalTranslation(
            translation: Offset(0, _slide.value),
            child: Opacity(
              opacity: _fade.value,
              child: child,
            ),
          ),
        );
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: config.accentColor.withOpacity(0.45),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: config.accentColor.withOpacity(0.22),
                    blurRadius: 24,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // خط جانبي ملوّن
                    Container(
                      width: 3,
                      margin: const EdgeInsets.only(left: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            config.accentColor,
                            config.accentColor.withOpacity(0.3),
                          ],
                        ),
                      ),
                    ),
                    // أيقونة
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: config.accentColor.withOpacity(0.15),
                      ),
                      child: Icon(
                        config.icon,
                        color: config.accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // النصوص
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            config.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w600,
                              color: config.accentColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.message,
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
    );
  }
}
// ═══════════════════════════════════════════════════════════
//  GLOBAL DOWNLOAD BAR SYSTEM — شريط تحميل عالمي سفلي
// ═══════════════════════════════════════════════════════════

class _DownloadTask {
  final String id;
  final String title;
  double progress;
  bool done;
  bool error;
  String? errorMsg;

  _DownloadTask({
    required this.id,
    required this.title,
    this.progress = 0,
    this.done = false,
    this.error = false,
    this.errorMsg,
  });
}

class _GlobalDownloadBarController {
  static final _GlobalDownloadBarController instance = _GlobalDownloadBarController._();
  _GlobalDownloadBarController._();

  OverlayEntry? _overlayEntry;
  final List<_DownloadTask> tasks = [];
  int _activeIndex = 0;
  bool _minimized = false;

  void _refresh() {
    _overlayEntry?.markNeedsBuild();
  }

  void addTask(_DownloadTask task) {
    tasks.add(task);
    _activeIndex = tasks.length - 1;
    _minimized = false;
    _refresh();
  }

  void updateProgress(String id, double progress) {
    final t = tasks.firstWhere((t) => t.id == id, orElse: () => _DownloadTask(id: '', title: ''));
    if (t.id.isEmpty) return;
    t.progress = progress;
    _refresh();
  }

  void completeTask(String id) {
    final t = tasks.firstWhere((t) => t.id == id, orElse: () => _DownloadTask(id: '', title: ''));
    if (t.id.isEmpty) return;
    t.done = true;
    t.progress = 1.0;
    _refresh();
    Future.delayed(const Duration(seconds: 3), () {
      tasks.removeWhere((t) => t.id == id);
      if (_activeIndex >= tasks.length && tasks.isNotEmpty) {
        _activeIndex = tasks.length - 1;
      }
      if (tasks.isEmpty) {
        _overlayEntry?.remove();
        _overlayEntry = null;
      }
      _refresh();
    });
  }

  void failTask(String id, String msg) {
    final t = tasks.firstWhere((t) => t.id == id, orElse: () => _DownloadTask(id: '', title: ''));
    if (t.id.isEmpty) return;
    t.error = true;
    t.errorMsg = msg;
    _refresh();
    Future.delayed(const Duration(seconds: 4), () {
      tasks.removeWhere((t) => t.id == id);
      if (_activeIndex >= tasks.length && tasks.isNotEmpty) {
        _activeIndex = tasks.length - 1;
      }
      if (tasks.isEmpty) {
        _overlayEntry?.remove();
        _overlayEntry = null;
      }
      _refresh();
    });
  }

  void show(BuildContext context) {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(builder: (_) => _GlobalDownloadBarWidget(controller: this));
    Overlay.of(context).insert(_overlayEntry!);
  }
}

class _GlobalDownloadBarWidget extends StatefulWidget {
  final _GlobalDownloadBarController controller;
  const _GlobalDownloadBarWidget({required this.controller});

  @override
  State<_GlobalDownloadBarWidget> createState() => _GlobalDownloadBarWidgetState();
}

class _GlobalDownloadBarWidgetState extends State<_GlobalDownloadBarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final tasks = ctrl.tasks;
    if (tasks.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom + 80;
    final activeIdx = ctrl._activeIndex.clamp(0, tasks.length - 1);
    final activeTask = tasks[activeIdx];

    return Positioned(
      bottom: bottomPad,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnim,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // تبويبات الخلفية (التحميلات الأخرى)
              for (int i = tasks.length - 1; i >= 0; i--)
                if (i != activeIdx)
                  Positioned(
                    top: -(tasks.length - 1 - i) * 6.0 - 6,
                    left: (tasks.length - 1 - i) * 3.0,
                    right: (tasks.length - 1 - i) * 3.0,
                    child: _buildCard(tasks[i], isDark, isBackground: true),
                  ),
              // البطاقة الرئيسية
              _buildCard(activeTask, isDark, isBackground: false, onHide: () {
                setState(() {
                  ctrl._minimized = !ctrl._minimized;
                });
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(_DownloadTask task, bool isDark, {bool isBackground = false, VoidCallback? onHide}) {
    final bg = isDark
        ? Colors.white.withOpacity(0.07)
        : Colors.white.withOpacity(0.92);
    final borderColor = task.done
        ? const Color(0xFF30D158).withOpacity(0.55)
        : task.error
            ? const Color(0xFFFF3B30).withOpacity(0.55)
            : AppColors.primary.withOpacity(0.45);
    final glowColor = task.done
        ? const Color(0xFF30D158)
        : task.error
            ? const Color(0xFFFF3B30)
            : AppColors.primary;

    final pct = (task.progress * 100).toStringAsFixed(0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(color: glowColor.withOpacity(0.18), blurRadius: 20, spreadRadius: 0),
              BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 14, offset: const Offset(0, 5)),
            ],
          ),
          child: isBackground
              ? SizedBox(height: 8, child: LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(glowColor.withOpacity(0.4)),
                  minHeight: 4,
                ))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 36,
                          margin: const EdgeInsets.only(left: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [glowColor, glowColor.withOpacity(0.3)],
                            ),
                          ),
                        ),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: glowColor.withOpacity(0.15),
                          ),
                          child: task.done
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFF30D158), size: 20)
                              : task.error
                                  ? const Icon(Icons.cancel_rounded, color: Color(0xFFFF3B30), size: 20)
                                  : SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        value: task.progress > 0 ? task.progress : null,
                                        strokeWidth: 2.2,
                                        valueColor: AlwaysStoppedAnimation(glowColor),
                                      ),
                                    ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.done ? 'تم التحميل' : task.error ? 'فشل التحميل' : 'جاري التحميل...',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w600,
                                  color: glowColor,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                task.error ? (task.errorMsg ?? '') : task.title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (!task.done && !task.error) ...[
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w700,
                              color: glowColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (onHide != null && !task.done && !task.error)
                          GestureDetector(
                            onTap: onHide,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: glowColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: glowColor.withOpacity(0.3), width: 0.8),
                              ),
                              child: Text(
                                'إخفاء',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w600,
                                  color: glowColor,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!task.done && !task.error) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: task.progress > 0 ? task.progress : null,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation(glowColor),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
// دالة static للاستخدام من Widgets بدون _toastOverlay
void _showGlassToastStatic(
  BuildContext context,
  String message, {
  _ToastType type = _ToastType.info,
  Duration duration = const Duration(seconds: 3),
}) {
  OverlayEntry? entry;
  entry = OverlayEntry(
    builder: (ctx) => _GlassToast(
      message: message,
      type: type,
      onDismiss: () => entry?.remove(),
    ),
  );
  Overlay.of(context).insert(entry);
  Future.delayed(duration, () {
    if (entry?.mounted == true) entry?.remove();
  });
}

// ═══════════════════════════════════════════════════════════
//  IMPORT PROGRESS DIALOG — نافذة تقدم الاستيراد
// ═══════════════════════════════════════════════════════════
class _ImportProgressDialog extends StatefulWidget {
  final int total;
  final Stream<_ImportEvent> events;

  const _ImportProgressDialog({required this.total, required this.events});

  @override
  State<_ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportEvent {
  final int done;
  final String currentName;
  final bool finished;
  const _ImportEvent({required this.done, required this.currentName, this.finished = false});
}

class _ImportProgressDialogState extends State<_ImportProgressDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  int _done = 0;
  String _currentName = '';
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    widget.events.listen((event) {
      if (mounted) {
        setState(() {
          _done = event.done;
          _currentName = event.currentName;
          _finished = event.finished;
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final textSecondary = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);
    final divider = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    const accent = AppColors.primary;

    final progress = widget.total == 0 ? 0.0 : (_done / widget.total).clamp(0.0, 1.0);
    final pct = (progress * 100).toStringAsFixed(0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.07)
                  : Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(28),
  border: Border.all(
  color: isDark
      ? accent.withOpacity(0.35)
      : accent.withOpacity(0.20),
  width: 1.2,
),
             boxShadow: [
  BoxShadow(
    color: isDark
        ? accent.withOpacity(0.18)
        : accent.withOpacity(0.08),
    blurRadius: 40,
    spreadRadius: 0,
  ),
  BoxShadow(
    color: Colors.black.withOpacity(isDark ? 0.55 : 0.08),
    blurRadius: 24,
    offset: const Offset(0, 8),
  ),
],
            ),
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── أيقونة متحركة ──
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) {
                      return Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          
gradient: RadialGradient(
  colors: [
    _finished
        ? const Color(0xFF30D158).withOpacity(0.18)
        : accent.withOpacity(isDark
            ? 0.20 * _pulse.value + 0.05
            : 0.12 * _pulse.value + 0.03),
    Colors.transparent,
  ],
),
border: Border.all(
  color: _finished
      ? const Color(0xFF30D158).withOpacity(0.75)
      : accent.withOpacity(isDark
          ? 0.35 + 0.45 * _pulse.value
          : 0.25 + 0.30 * _pulse.value),
  width: 1.5,
),
                        ),
                        child: Center(
                          child: _finished
                              ? const Icon(Icons.check_rounded, color: Color(0xFF30D158), size: 34)
                              : Icon(
                                  Icons.folder_open_rounded,
                                  color: accent.withOpacity(0.6 + 0.4 * _pulse.value),
                                  size: 34,
                                ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 22),

                  // ── العنوان ──
                  Text(
                    _finished ? 'اكتمل الاستيراد' : 'جاري الاستيراد...',
                    style: TextStyle(
                      fontSize: 19,
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _finished
                        ? 'تمت إضافة $_done من ${widget.total} فيديو'
                        : '$_done من ${widget.total} فيديو',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'Tajawal',
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── شريط التقدم المخصص ──
                  Stack(
                    children: [
                      // الخلفية
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.08) : divider,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      // التقدم مع أنيميشن
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: 8,
                        width: double.infinity,
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          alignment: Alignment.centerRight,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
gradient: LinearGradient(
  colors: [
    AppColors.primary,
    isDark
        ? AppColors.primary.withOpacity(0.65)
        : AppColors.primaryDark,
  ],
  begin: Alignment.centerRight,
  end: Alignment.centerLeft,
),
                              boxShadow: [
BoxShadow(
  color: accent.withOpacity(isDark ? 0.50 : 0.30),
  blurRadius: isDark ? 10 : 6,
  offset: const Offset(0, 2),
),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── النسبة المئوية واسم الملف ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _currentName.isNotEmpty ? _currentName : '...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Tajawal',
                            color: textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(_finished ? 0.15 : 0.08 + 0.08 * _pulse.value),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _finished ? '100%' : '$pct%',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Tajawal',
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  if (_finished) ...[
                    const SizedBox(height: 24),
                    // خط فاصل خفيف
                    Container(height: 0.5, color: divider),
                    const SizedBox(height: 20),
                    // زر الإغلاق
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
gradient: LinearGradient(
  colors: [
    AppColors.primaryDark,
    AppColors.primary,
  ],
  begin: Alignment.centerRight,
  end: Alignment.centerLeft,
),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                           BoxShadow(
  color: accent.withOpacity(isDark ? 0.45 : 0.25),
  blurRadius: isDark ? 18 : 12,
  offset: const Offset(0, 5),
),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'رائع!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ManifestCache {
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

class DownloadArgs {
  final String videoId;
  final String safeTitle;
  final String dirPath;
  final String quality;
  final SendPort sendPort;
  final String? directUrl;

  const DownloadArgs({
    required this.videoId,
    required this.safeTitle,
    required this.dirPath,
    required this.quality,
    required this.sendPort,
    this.directUrl,
  });
}

Future<void> downloadIsolate(DownloadArgs args) async {
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
// ═══════════════════════════════════════════════════════════
//  AD SLIDESHOW CARD — كارت إعلاني بنسبة 16:9 مع سلايدشو
// ═══════════════════════════════════════════════════════════
class _AdSlideshowCard extends StatefulWidget {
  const _AdSlideshowCard();

  @override
  State<_AdSlideshowCard> createState() => _AdSlideshowCardState();
}

class _AdSlideshowCardState extends State<_AdSlideshowCard>
    with SingleTickerProviderStateMixin {
  PageController _pageCtrl = PageController();
  int _currentPage = 0;
  Timer? _autoTimer;
  List<AdSlide> _slides = [];
  bool _isLoading = true;
  String? _error;

  static const _kAdsCache = 'ads_slides_cache_json';
  static const _kAdsPage  = 'ads_slides_current_page';
  static const _kAdsFetch = 'ads_slides_last_fetch_ms';
  // مدة صلاحية الكاش: 30 دقيقة
  static const _kCacheTtlMs = 30 * 60 * 1000;

  @override
  void initState() {
    super.initState();
    _loadFromCacheThenFetch();
  }

  /// 1) يعرض الكاش المحلي فوراً إن وُجد، ثم يحدّث من الشبكة في الخلفية
  Future<void> _loadFromCacheThenFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedJson  = prefs.getString(_kAdsCache);
    final cachedPage  = prefs.getInt(_kAdsPage) ?? 0;
    final lastFetchMs = prefs.getInt(_kAdsFetch) ?? 0;

    if (cachedJson != null) {
      try {
        final List<dynamic> data = jsonDecode(cachedJson);
        final slides = data.map((item) => AdSlide.fromJson(item)).toList();
        if (slides.isNotEmpty && mounted) {
          // ← تحديد الصفحة الأخيرة المحفوظة
          final startPage = cachedPage.clamp(0, slides.length - 1);
          _pageCtrl = PageController(initialPage: startPage);
          setState(() {
            _slides      = slides;
            _currentPage = startPage;
            _isLoading   = false;
          });
          _startAutoSlide();
        }
      } catch (_) {}
    }

    // تحديث من الشبكة إذا انتهت مدة الكاش أو لا يوجد كاش
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cachedJson == null || (now - lastFetchMs) > _kCacheTtlMs) {
      await _fetchAdsFromNetwork(prefs);
    }
  }

Future<void> _fetchAdsFromNetwork(SharedPreferences prefs) async {
  try {
    final uri = Uri.parse('https://scrptaty.com/dndn/index.php?json');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);

      await prefs.setString(_kAdsCache, response.body);
      await prefs.setInt(_kAdsFetch, DateTime.now().millisecondsSinceEpoch);

      if (!mounted) return;

      final newSlides =
          data.map((item) => AdSlide.fromJson(item)).toList();

      setState(() {
        _slides = newSlides;
        _isLoading = false;
        _error = null;
      });

      if (_autoTimer == null) _startAutoSlide();

    } else {
      // ← هذا الجزء كان ناقص
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = 'Server Error: ${response.statusCode}';
      });
    }

  } catch (e) {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _error = 'خطأ: $e';
    });
  }
}

  /// يُحفظ رقم الصفحة الحالية عند كل تغيير
  Future<void> _saveCurrentPage(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAdsPage, page);
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
                _saveCurrentPage(i);
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

    // التعتيم السفلي
    Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.4, 1.0],
            colors: [
              const Color.fromARGB(22, 0, 0, 0),
              Colors.black.withValues(alpha: 0.75),
            ],
          ),
        ),
      ),
    ),

    // ✨ تأثير اللمعة المتحركة
    Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: -1.5, end: 2.0),
          duration: const Duration(seconds: 4),
          curve: Curves.easeInOut,
          onEnd: () {
            if (mounted) {
              setState(() {});
            }
          },
          builder: (context, value, child) {
            return Transform.rotate(
              angle: -0.55,
              child: Transform.translate(
                offset: Offset(value * MediaQuery.of(context).size.width, 0),
                child: Container(
                  width: 70,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 10),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              slide.description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 12,
                fontFamily: 'Tajawal',
                shadows: [
                  Shadow(color: Colors.black54, blurRadius: 8),
                ],
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
//  CUSTOM PAINTER FOR REPEATED ROTATED PATTERN
// ═══════════════════════════════════════════════════════════
class _RotatedRepeatedPattern extends StatelessWidget {
  final double opacity;
  final double angleDegrees;
  final double patternSize;
  final String imagePath;

  const _RotatedRepeatedPattern({
    required this.opacity,
    required this.angleDegrees,
    this.patternSize = 40,
    required this.imagePath,
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
                  patternSize: patternSize,
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
  final double patternSize;

  _PatternPainter({
    required this.image,
    required this.opacity,
    required this.angleRad,
    required this.patternSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..filterQuality = FilterQuality.medium;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angleRad);
    canvas.translate(-size.width / 2, -size.height / 2);

    final imageWidth = patternSize;
    final imageHeight = patternSize;

    final cols = (size.width / imageWidth).ceil() + 2;
    final rows = (size.height / imageHeight).ceil() + 2;

    for (int row = -1; row < rows; row++) {
      for (int col = -1; col < cols; col++) {
        final dx = col * imageWidth;
        final dy = row * imageHeight;
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
//  BACKGROUND WITH REPEATED PATTERN
// ═══════════════════════════════════════════════════════════
class RepeatingPatternBackground extends StatelessWidget {
  final double opacity;
  final double rotationDegrees;
  final double patternWidth;
  final double patternHeight;
  final bool isDark;

  const RepeatingPatternBackground({
    super.key,
    required this.opacity,
    required this.rotationDegrees,
    this.patternWidth = 100,
    this.patternHeight = 100,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FutureBuilder<ui.Image?>(
          future: _loadImage(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _RepeatingPatternPainter(
                  image: snapshot.data!,
                  opacity: opacity,
                  rotationRad: rotationDegrees * -30.4 / 180,
                  patternWidth: patternWidth,
                  patternHeight: patternHeight,
                  isDark: isDark,
                ),
              );
            }
            return Container(color: Colors.transparent);
          },
        );
      },
    );
  }

  Future<ui.Image?> _loadImage() async {
    try {
      final completer = Completer<ui.Image>();
      final assetImage = AssetImage('assets/images/bg.png');
      final stream = assetImage.resolve(ImageConfiguration());

      stream.addListener(
        ImageStreamListener((info, _) {
          completer.complete(info.image);
        }, onError: (error, stackTrace) {
          completer.completeError(error);
        }),
      );

      return await completer.future;
    } catch (e) {
      debugPrint('خطأ في تحميل صورة الخلفية: $e');
      return null;
    }
  }
}

class _RepeatingPatternPainter extends CustomPainter {
  final ui.Image image;
  final double opacity;
  final double rotationRad;
  final double patternWidth;
  final double patternHeight;
  final bool isDark;

  _RepeatingPatternPainter({
    required this.image,
    required this.opacity,
    required this.rotationRad,
    required this.patternWidth,
    required this.patternHeight,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 20, size.height / 4);
    canvas.rotate(rotationRad);
    canvas.translate(-size.width / 1, -size.height / 2);

    final cols = (size.width / patternWidth).ceil() + 9;
    final rows = (size.height / patternHeight).ceil() + 9;

    final paint = Paint()
      ..filterQuality = FilterQuality.medium;
    
    if (isDark) {
      paint.color = Colors.white.withValues(alpha: 0.15);
    } else {
      paint.color = Colors.white.withValues(alpha: 0.04);
    }

    for (int row = 0; row <= rows; row++) {
      for (int col = 0; col <= cols; col++) {
        final dx = col * patternWidth;
        final dy = row * patternHeight;
        final rect = Rect.fromLTWH(dx, dy, patternWidth, patternHeight);
        
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
  bool shouldRepaint(covariant _RepeatingPatternPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.opacity != opacity ||
        oldDelegate.rotationRad != rotationRad ||
        oldDelegate.patternWidth != patternWidth ||
        oldDelegate.patternHeight != patternHeight ||
        oldDelegate.isDark != isDark;
  }
}

// ═══════════════════════════════════════════════════════════
//  PAGE 2 — تصفح (Browse)
// ═══════════════════════════════════════════════════════════
class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.background;
    
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          RepeatingPatternBackground(
            opacity: isDark ? 0.03 : 0.03,
            rotationDegrees: 300,
            patternWidth: 120,
            patternHeight: 120,
            isDark: isDark,
          ),
          CustomScrollView(
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
                    '',
                    style: TextStyle(fontSize: 0),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const _AdSlideshowCard(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _UrlDownloadBox(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
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
  color: context.isDark
      ? const Color.fromARGB(195, 199, 5, 5)
      : const Color.fromARGB(255, 204, 13, 13),

  borderRadius: BorderRadius.circular(18),

  border: Border.all(
    color: context.isDark
        ? const Color.fromARGB(249, 228, 21, 21)
        : const Color.fromARGB(255, 255, 0, 0),
    width: 1.2,
  ),

  boxShadow: [
    BoxShadow(
      color: context.isDark
          ? const Color.fromARGB(255, 109, 11, 11)
              .withValues(alpha: 0.2)
          : const Color.fromARGB(255, 190, 10, 10)
              .withValues(alpha: 0.2),
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GestureDetector(
onTap: () {
  Navigator.push(
    context,
    CupertinoPageRoute(builder: (_) => const MediaVideoBrowserPage()),
  );
},
                    child: Container(
                      height: 45,
decoration: BoxDecoration(
  color: context.isDark
      ? const Color.fromARGB(123, 105, 18, 155)
      : const Color.fromARGB(202, 68, 5, 119),

  borderRadius: BorderRadius.circular(18),

  border: Border.all(
    color: context.isDark
        ? const Color.fromARGB(251, 119, 37, 187)
        : const Color.fromARGB(206, 216, 99, 196),
    width: 1.2,
  ),

  boxShadow: [
    BoxShadow(
      color: context.isDark
          ? const Color.fromARGB(255, 106, 11, 109)
              .withValues(alpha: 0.2)
          : const Color.fromARGB(255, 79, 10, 190)
              .withValues(alpha: 0.2),
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
                              imagePath: 'assets/images/img-bg.png',
                            ),
                            const Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.photo_fill,
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
  color: context.isDark
      ? const Color.fromARGB(195, 3, 31, 187)
      : const Color.fromARGB(212, 13, 58, 204),

  borderRadius: BorderRadius.circular(18),

  border: Border.all(
    color: context.isDark
        ? const Color.fromARGB(248, 21, 111, 228)
        : const Color.fromARGB(255, 0, 81, 255),
    width: 1.2,
  ),

  boxShadow: [
    BoxShadow(
      color: context.isDark
          ? const Color.fromARGB(255, 11, 37, 109)
              .withValues(alpha: 0.2)
          : const Color.fromARGB(255, 11, 96, 255)
              .withValues(alpha: 0.2),
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
        ],
      ),
    );
  }
}



// ═══════════════════════════════════════════════════════════
//  URL DOWNLOAD BOX — بوكس إدخال الرابط مع لصق وبحث
// ═══════════════════════════════════════════════════════════
class _UrlDownloadBox extends StatefulWidget {
  const _UrlDownloadBox();

  @override
  State<_UrlDownloadBox> createState() => _UrlDownloadBoxState();
}

class _UrlDownloadBoxState extends State<_UrlDownloadBox> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _isArabic(String text) {
    if (text.isEmpty) return false;
    for (final ch in text.characters) {
      final code = ch.codeUnitAt(0);
      if (code >= 0x0600 && code <= 0x06FF) return true;
      if (ch == ' ') continue;
      return false;
    }
    return false;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() => _ctrl.text = data!.text!.trim());
    }
  }

  void _search() {
    final url = _ctrl.text.trim();
    if (url.isEmpty) return;
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => UrlDownloadPage(url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkText : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.darkTextSec : AppColors.textSecondary;
    final divider = isDark ? AppColors.darkDivider : AppColors.divider;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divider, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [
                const Icon(CupertinoIcons.link, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'تحميل بالرابط',
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkBg : AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: divider, width: 0.8),
                    ),
child: TextField(
  controller: _ctrl,
  // إذا كان الحقل فارغاً، سيتحاذى النص لليمين (لأجل التلميح)، وإذا كتب المستخدم سيتحقق من اللغة
  textDirection: _ctrl.text.isEmpty 
      ? TextDirection.rtl 
      : (_isArabic(_ctrl.text) ? TextDirection.rtl : TextDirection.ltr),
  textAlign: _ctrl.text.isEmpty 
      ? TextAlign.right 
      : (_isArabic(_ctrl.text) ? TextAlign.right : TextAlign.left),
  textAlignVertical: TextAlignVertical.center,
  onChanged: (_) => setState(() {}),
  style: TextStyle(
    fontSize: 13,
    color: textPrimary,
    fontFamily: 'Tajawal',
  ),
  decoration: InputDecoration(
    hintText: 'الصق رابط الفيديو هنا...',
    hintTextDirection: TextDirection.rtl, 
    hintStyle: TextStyle(
      fontSize: 13,
      color: textSecondary,
      fontFamily: 'Tajawal',
    ),
    border: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    isDense: true,
  ),
  onSubmitted: (_) => _search(),
),
                  ),
                ),
                const SizedBox(width: 8),
                // زر لصق
                GestureDetector(
                  onTap: _paste,
                  child: Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkBg : AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: divider, width: 0.8),
                    ),
                    child: Icon(CupertinoIcons.doc_on_clipboard, color: textSecondary, size: 19),
                  ),
                ),
                const SizedBox(width: 8),
                // زر بحث/تحميل
                GestureDetector(
                  onTap: _search,
                  child: Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(CupertinoIcons.arrow_down_circle_fill, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              'يدعم يوتيوب • TikTok • Instagram • روابط MP4/MP3 المباشرة',
              style: TextStyle(
                fontSize: 11,
                color: textSecondary,
                fontFamily: 'Tajawal',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  URL DOWNLOAD PAGE — صفحة تحميل الفيديو من الرابط
// ═══════════════════════════════════════════════════════════
class UrlDownloadPage extends StatefulWidget {
  final String url;
  const UrlDownloadPage({super.key, required this.url});

  @override
  State<UrlDownloadPage> createState() => _UrlDownloadPageState();
}

class _UrlDownloadPageState extends State<UrlDownloadPage> {
  // حالة الصفحة
  bool _loading = true;
  bool _downloading = false;
  bool _done = false;
  String? _error;
  double _progress = 0;

  // معلومات الفيديو
  String? _title;
  String? _author;
  String? _thumbnailUrl;
  Duration? _duration;
  String? _downloadUrl;
  String? _savedFileName;

  // نوع الرابط
  bool _isYoutube = false;
  bool _isDirectVideo = false;
  bool _isDirectAudio = false;
  String? _videoId;

  @override
  void initState() {
    super.initState();
    _analyzeAndFetch();
  }

  String? _extractYoutubeId(String url) {
    return YoutubePlayer.convertUrlToId(url);
  }

 bool _isDirectVideoUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('instagram.com') ||
         lower.contains('tiktok.com') ||
         lower.contains('facebook.com') ||
         lower.contains('fb.watch') ||
         lower.contains('twitter.com') ||
         lower.contains('x.com') ||
         lower.endsWith('.mp4') || 
         lower.endsWith('.mkv') || 
         lower.endsWith('.webm') || 
         lower.endsWith('.mov') || 
         lower.contains('.mp4?') || 
         lower.contains('.webm?');
}
Future<String?> _extractVideoFromHtml(String url) async {
  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      },
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      final htmlContent = response.body;

      // الفحص عن وسوم الميتا og:video المعتمدة في انستغرام وفيسبوك
      final ogVideoRegex = RegExp(r'<meta[^>]*property="og:video"[^>]*content="([^"]+)"');
      final ogMatch = ogVideoRegex.firstMatch(htmlContent);
      if (ogMatch != null && ogMatch.groupCount >= 1) {
        return ogMatch.group(1)!.replaceAll('&amp;', '&');
      }

      // فحص وسم og:video:url البديل
      final ogVideoUrlRegex = RegExp(r'<meta[^>]*property="og:video:url"[^>]*content="([^"]+)"');
      final ogUrlMatch = ogVideoUrlRegex.firstMatch(htmlContent);
      if (ogUrlMatch != null && ogUrlMatch.groupCount >= 1) {
        return ogUrlMatch.group(1)!.replaceAll('&amp;', '&');
      }

      // البحث عن أي رابط mp4 صريح مدمج داخل كود الجافا سكريبت بالصفحة
      final mp4Regex = RegExp(r'(https?://[^\s"<>]+?\.mp4[^\s"<>]*?)');
      final mp4Match = mp4Regex.firstMatch(htmlContent);
      if (mp4Match != null && mp4Match.groupCount >= 1) {
        return mp4Match.group(1)!.replaceAll('\\/', '/');
      }

      // البحث عن وسوم الفيديو src العادية للمواقع الأخرى
      final videoSrcRegex = RegExp(r'<video[^>]*src="([^"]+)"');
      final srcMatch = videoSrcRegex.firstMatch(htmlContent);
      if (srcMatch != null && srcMatch.groupCount >= 1) {
        return srcMatch.group(1);
      }
    }
  } catch (e) {
    debugPrint('خطأ في الفحص الذكي: $e');
  }
  return null;
}
  bool _isDirectAudioUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp3') || lower.endsWith('.m4a') ||
           lower.endsWith('.aac') || lower.endsWith('.opus') ||
           lower.endsWith('.flac') || lower.endsWith('.wav');
  }

Future<void> _analyzeAndFetch() async {
  setState(() {
    _loading = true;
    _error = null;
  });

  try {
    final url = widget.url.trim();
    _videoId = _extractYoutubeId(url);
    _isYoutube = _videoId != null;

    // ── يوتيوب: المسار القديم يعمل بشكل مثالي ──
    if (_isYoutube) {
      await _fetchYoutubeInfo(_videoId!);
      return;
    }

    // ── TikTok و Instagram: نستخدم DownloadService أولاً ──
    final isSocialMedia = url.contains('tiktok.com') ||
        url.contains('instagram.com') ||
        url.contains('instagr.am');

    if (isSocialMedia) {
      if (mounted) {
        setState(() { _title = 'جاري استخراج الفيديو...'; });
      }

      // المحاولة الأولى: DownloadService (APIs خارجية)
      final downloadService = DownloadService();
      final videoResult = await downloadService.extractVideoUrl(url);
      String? extracted = videoResult?.url; // استخرج الـ URL من VideoResult

      // المحاولة الثانية: سحب ذكي من HTML إن فشلت الـ APIs
      if (extracted == null || extracted.isEmpty) {
        extracted = await _extractVideoFromHtml(url);
      }

      if (extracted != null && extracted.isNotEmpty) {
        _isDirectVideo = true;
        // نحدد عنوان المنصة
        final platform = url.contains('tiktok.com') ? 'TikTok' : 'Instagram';
        if (mounted) {
          setState(() {
            _title = 'فيديو من $platform';
            _author = platform;
            _downloadUrl = extracted;
            _loading = false;
          });
        }
      } else {
        throw Exception(
          'تعذر استخراج الفيديو تلقائياً.\n'
          'قد يكون الحساب خاصاً أو يتطلب تسجيل دخول.',
        );
      }
      return;
    }

    // ── فيسبوك / تويتر / X ──
    final isFacebook = url.contains('facebook.com') || url.contains('fb.watch');
    final isTwitter  = url.contains('twitter.com') || url.contains('x.com');

    if (isFacebook || isTwitter) {
      if (mounted) setState(() { _title = 'جاري استخراج الفيديو...'; });
      final extracted = await _extractVideoFromHtml(url);
      if (extracted != null && extracted.isNotEmpty) {
        _isDirectVideo = true;
        final platform = isFacebook ? 'Facebook' : 'X (Twitter)';
        if (mounted) {
          setState(() {
            _title = 'فيديو من $platform';
            _author = platform;
            _downloadUrl = extracted;
            _loading = false;
          });
        }
      } else {
        throw Exception('تعذر استخراج الفيديو من هذه المنصة.');
      }
      return;
    }

    // ── روابط مباشرة (mp4 / mp3 / mkv …) ──
    _isDirectVideo = _isDirectVideoUrl(url);
    _isDirectAudio = !_isDirectVideo && _isDirectAudioUrl(url);

    if (_isDirectVideo || _isDirectAudio) {
      await _fetchDirectInfo(url);
      return;
    }

    // ── محاولة أخيرة: فحص HTML لأي رابط غير معروف ──
    final fallbackUrl = await _extractVideoFromHtml(url);
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      _isDirectVideo = true;
      await _fetchDirectInfo(fallbackUrl);
    } else {
      throw Exception('الرابط غير مدعوم أو لم يُعثر على فيديو بداخله.');
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }
}

  Future<void> _fetchYoutubeInfo(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(videoId);
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final muxed = manifest.muxed;
      if (muxed.isEmpty) throw Exception('لا تتوفر صيغ مدعومة لهذا الفيديو');

      // اختر أفضل جودة مناسبة (360p أو أقرب)
      final chosen = muxed.firstWhere(
        (s) => s.videoResolution.height == 360,
        orElse: () {
          final sorted = List<MuxedStreamInfo>.from(muxed)
            ..sort((a, b) => (a.videoResolution.height - 360).abs()
                .compareTo((b.videoResolution.height - 360).abs()));
          return sorted.first;
        },
      );

      if (mounted) {
        setState(() {
          _title = video.title;
          _author = video.author;
          _thumbnailUrl = video.thumbnails.highResUrl;
          _duration = video.duration;
          _downloadUrl = chosen.url.toString();
          _loading = false;
        });
      }
    } finally {
      yt.close();
    }
  }

  Future<void> _fetchDirectInfo(String url) async {
    // استخرج اسم الملف من الرابط
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'ملف';
    if (mounted) {
      setState(() {
        _title = fileName.isNotEmpty ? fileName : 'ملف مباشر';
        _author = uri.host;
        _downloadUrl = url;
        _loading = false;
      });
    }
  }

  Future<void> _startDownload() async {
    if (_downloadUrl == null) return;
    setState(() { _downloading = true; _progress = 0; _error = null; });
    try {
      // إنشاء مجلد الحفظ
      final dir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${dir.path}/dndn');
      if (!await destDir.exists()) await destDir.create(recursive: true);

      // اسم الملف
      String safeTitle = (_title ?? 'video')
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll(RegExp(r'\s+'), '_');
      if (safeTitle.length > 60) safeTitle = safeTitle.substring(0, 60);
      final ext = (_isDirectAudio) ? '.mp3' : '.mp4';
      final savePath = '${destDir.path}/$safeTitle$ext';
      _savedFileName = '$safeTitle$ext';

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 20),
        headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
              'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
          'Accept-Encoding': 'identity',
          'Connection': 'keep-alive',
          'Range': 'bytes=0-',
        },
      ));

      await dio.download(
        _downloadUrl!,
        savePath,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      dio.close();

      // توليد thumbnail وإشعار قسم استمع
      ThumbnailManager.generateLocalThumbnail(savePath).catchError((_) {});
      downloadCompleteNotifier.value = destDir.path;

      if (mounted) setState(() { _downloading = false; _done = true; });
    } catch (e) {
      if (mounted) setState(() {
        _downloading = false;
        _error = 'فشل التحميل: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
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
            // شريط العنوان
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
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        'تحميل الفيديو',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? _buildLoading(textSecondary)
                  : _error != null && !_downloading && !_done
                      ? _buildError(textPrimary, textSecondary)
                      : _buildContent(surface, textPrimary, textSecondary, divider, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(Color textSecondary) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'جاري جلب معلومات الفيديو...',
            style: TextStyle(fontSize: 14, color: textSecondary, fontFamily: 'Tajawal'),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Color textPrimary, Color textSecondary) {
    final url = widget.url.trim();
    final isSocial = url.contains('tiktok.com') ||
        url.contains('instagram.com') ||
        url.contains('instagr.am');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.exclamationmark_circle,
                color: AppColors.primary, size: 52),
            const SizedBox(height: 16),
            Text(
              _error ?? 'خطأ غير معروف',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: textPrimary, fontFamily: 'Tajawal'),
            ),
            const SizedBox(height: 24),
            // زر إعادة المحاولة
            GestureDetector(
              onTap: _analyzeAndFetch,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
            // زر المتصفح الداخلي — يظهر فقط لروابط التواصل الاجتماعي
            if (isSocial) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => DownloadPage(initialUrl: url),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 1.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.globe,
                          color: AppColors.primary, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'فتح في المتصفح الداخلي',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 15,
                            fontFamily: 'Tajawal',
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'سجّل دخولك وسيكتشف التطبيق الفيديو تلقائياً',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: textSecondary, fontFamily: 'Tajawal'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Color surface, Color textPrimary, Color textSecondary, Color divider, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الصورة المصغرة
            if (_thumbnailUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: _thumbnailUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: surface,
                      child: const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: surface,
                      child: const Icon(CupertinoIcons.video_camera_solid,
                          color: AppColors.primary, size: 48),
                    ),
                  ),
                ),
              ),
            if (_thumbnailUrl == null)
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Icon(
                    _isDirectAudio ? CupertinoIcons.music_note : CupertinoIcons.video_camera_solid,
                    color: AppColors.primary,
                    size: 52,
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // العنوان والمعلومات
            Text(
              _title ?? 'بدون عنوان',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: textPrimary,
                fontFamily: 'Tajawal',
              ),
            ),
            if (_author != null) ...[
              const SizedBox(height: 4),
              Text(
                _author!,
                style: TextStyle(fontSize: 13, color: textSecondary, fontFamily: 'Tajawal'),
              ),
            ],
            if (_duration != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(CupertinoIcons.time, size: 13, color: textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(_duration),
                    style: TextStyle(fontSize: 13, color: textSecondary, fontFamily: 'Tajawal'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),

            // الرابط
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: divider, width: 0.8),
              ),
              child: Row(
                children: [
                  Icon(CupertinoIcons.link, size: 13, color: textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 11, color: textSecondary, fontFamily: 'Tajawal'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // شريط التقدم أو رسالة الإتمام
            if (_downloading) ...[
              Text(
                'جاري التحميل... ${(_progress * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 14, color: textPrimary, fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: divider,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}% مكتمل',
                style: TextStyle(fontSize: 12, color: textSecondary, fontFamily: 'Tajawal'),
              ),
            ],

            if (_done) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3), width: 1),
                ),
                child: Column(
                  children: [
                    const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.green, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      'تم التحميل بنجاح!',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.green,
                        fontFamily: 'Tajawal',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تمت إضافة "${_savedFileName ?? _title ?? ''}" إلى قسم استمع',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: textSecondary, fontFamily: 'Tajawal'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: divider, width: 0.8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'العودة',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                ),
              ),
            ],

            if (_error != null && (_downloading || _done)) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'Tajawal'),
                ),
              ),
            ],

            // زر التحميل (يظهر فقط عندما لا يكون تحميل جارٍ ولم يكتمل)
// زر التحميل — يظهر الزر الفعلي فقط بعد اكتمال جلب الرابط
if (!_downloading && !_done) ...[
  if (_downloadUrl == null)
    // مؤشر انتظار مع نص "يرجى الانتظار" أثناء جلب معلومات الفيديو
    Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(width: 12),
          Text(
            'يرجى الانتظار...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'Tajawal',
            ),
          ),
        ],
      ),
    )
  else
    // زر التحميل الفعلي — يظهر فقط بعد جاهزية الرابط
    GestureDetector(
      onTap: _startDownload,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.arrow_down_circle_fill, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(
              _isDirectAudio ? 'تحميل الصوت وإضافته لاستمع' : 'تحميل الفيديو وإضافته لاستمع',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'Tajawal',
              ),
            ),
          ],
        ),
      ),
    ),
],
          ],
        ),
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

  OverlayEntry? _toastOverlay;

  void _showGlassToast(String message,
      {_ToastType type = _ToastType.info,
      Duration duration = const Duration(seconds: 3)}) {
    _toastOverlay?.remove();
    _toastOverlay = null;
    final entry = OverlayEntry(
      builder: (ctx) => _GlassToast(
        message: message,
        type: type,
        onDismiss: () {
          _toastOverlay?.remove();
          _toastOverlay = null;
        },
      ),
    );
    _toastOverlay = entry;
    Overlay.of(context).insert(entry);
    Future.delayed(duration, () {
      if (_toastOverlay == entry) {
        _toastOverlay?.remove();
        _toastOverlay = null;
      }
    });
  }

  void _showSnack(String message) {
    String clean = message
        .replaceAll('✅', '').replaceAll('❌', '').replaceAll('⏳', '')
        .replaceAll('🗑️', '').trim();
    _ToastType type;
    if (message.contains('تم') || message.contains('✅') || message.contains('تمت إضافة')) {
      type = _ToastType.move;
    } else if (message.contains('خطأ') || message.contains('فشل') || message.contains('❌')) {
      type = _ToastType.error;
    } else {
      type = _ToastType.info;
    }
    _showGlassToast(clean, type: type);
  }

  @override
  void dispose() {
    _toastOverlay?.remove();
    super.dispose();
  }

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
        _showGlassToast('خطأ في فتح الملفات: $e', type: _ToastType.error);
      }
    }
  }

  Future<void> _importSelected() async {
    if (_pickedFiles.isEmpty) return;
    setState(() => _importing = true);

    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory('${dir.path}/dndn');
    if (!await destDir.exists()) await destDir.create(recursive: true);

    final total = _pickedFiles.length;
    final controller = StreamController<_ImportEvent>.broadcast();

    // فتح نافذة التقدم (لا ننتظر إغلاقها)
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.55),
        builder: (_) => _ImportProgressDialog(
          total: total,
          events: controller.stream,
        ),
      );
    }

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
        controller.add(_ImportEvent(done: copied, currentName: name));
        ThumbnailManager.generateLocalThumbnail(dest.path).catchError((_) {});
      } catch (_) {}
    }

    // إرسال حدث الإتمام ثم الإغلاق التلقائي
    controller.add(_ImportEvent(done: copied, currentName: '', finished: true));
    await Future.delayed(const Duration(milliseconds: 300));
    await controller.close();

    downloadCompleteNotifier.value = destDir.path;

    if (mounted) {
      setState(() => _importing = false);
      // إغلاق Dialog وصفحة الاستيراد بعد لحظة
      await Future.delayed(const Duration(milliseconds: 1800));
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // إغلاق الـ Dialog
      }
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // العودة للخلف
      }
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
                                    color: AppColors.primary.withValues(alpha: 0.35),
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
                                    color: AppColors.primary.withValues(alpha: 0.3),
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
  final FocusNode _searchFocusNode = FocusNode();
  List<Video> _results = [];
  bool _isSearching = false;
  List<String> _suggestions = [];
  bool _showSuggestions = false;
  bool _loadingSuggestions = false;
  Timer? _debounce;

  OverlayEntry? _toastOverlay;

  void _showGlassToast(String message,
      {_ToastType type = _ToastType.info,
      Duration duration = const Duration(seconds: 3)}) {
    _toastOverlay?.remove();
    _toastOverlay = null;
    final entry = OverlayEntry(
      builder: (ctx) => _GlassToast(
        message: message,
        type: type,
        onDismiss: () {
          _toastOverlay?.remove();
          _toastOverlay = null;
        },
      ),
    );
    _toastOverlay = entry;
    Overlay.of(context).insert(entry);
    Future.delayed(duration, () {
      if (_toastOverlay == entry) {
        _toastOverlay?.remove();
        _toastOverlay = null;
      }
    });
  }

  void _showSnack(String message) {
    String clean = message
        .replaceAll('✅', '').replaceAll('❌', '').replaceAll('⏳', '')
        .replaceAll('🗑️', '').trim();
    _ToastType type;
    if (message.contains('تم') || message.contains('✅')) {
      type = _ToastType.success;
    } else if (message.contains('خطأ') || message.contains('فشل') || message.contains('❌')) {
      type = _ToastType.error;
    } else if (message.contains('لم يتم') || message.contains('غير موجود')) {
      type = _ToastType.warning;
    } else if (message.contains('حذف') || message.contains('🗑️')) {
      type = _ToastType.delete;
    } else if (message.contains('نقل') || message.contains('إضافة') || message.contains('مجلد')) {
      type = _ToastType.move;
    } else {
      type = _ToastType.info;
    }
    _showGlassToast(clean, type: type);
  }

  final List<Map<String, String>> _categories = const [
    {'label': 'اغاني عراقية', 'query': 'اغاني عراقية'},
    {'label': 'اغاني عربية', 'query': 'اغاني عربية'},
    {'label': 'اجنبي', 'query': 'اغاني اجنبية'},
    {'label': 'شيرين', 'query': ' اغاني شيرين'},
    {'label': 'كرة قدم', 'query': '  ملخص مباريات اليوم'},
    {'label': ' ديني', 'query': 'القران الكريم '},
    {'label': 'هادئ', 'query': 'موسيقى هادئة'},
    {'label': 'كاظم الساهر', 'query': 'اغاني كاظم الساهر'},
    {'label': 'ام كلثوم', 'query': 'اغاني ام كلثوم'},
  ];

@override
  void dispose() {
    _toastOverlay?.remove();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

/// يكتشف لغة النص تلقائياً ويُرجع كود اللغة المناسب
  String _detectLanguage(String text) {
    // عربي
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return 'ar';
    // صيني
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(text)) return 'zh-CN';
    // ياباني
    if (RegExp(r'[\u3040-\u30FF]').hasMatch(text)) return 'ja';
    // كوري
    if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(text)) return 'ko';
    // روسي / سيريلي
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(text)) return 'ru';
    // افتراضي إنجليزي
    return 'en';
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().length < 2) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    setState(() { _loadingSuggestions = true; _showSuggestions = true; });
    try {
      final encoded = Uri.encodeComponent(query);
      final lang = _detectLanguage(query); // اكتشاف اللغة تلقائياً
      final url = Uri.parse(
        'https://suggestqueries.google.com/complete/search?client=youtube&ds=yt&q=$encoded&hl=$lang',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (response.statusCode == 200) {
        // فك ترميز UTF-8 بشكل صريح لدعم العربية وجميع اللغات
        final raw = utf8.decode(response.bodyBytes);
        final match = RegExp(r'\[\[(.+)\]\]').firstMatch(raw);
        if (match != null) {
          final innerJson = '[${match.group(0)}]';
          final List parsed = jsonDecode(innerJson);
          final List inner = parsed[0];
          final List<String> sug = inner
              .whereType<List>()
              .map((item) => item[0].toString())
              .take(8)
              .toList();
          setState(() { _suggestions = sug; _loadingSuggestions = false; });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() { _loadingSuggestions = false; });
  }
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() { _suggestions = []; _showSuggestions = false; _loadingSuggestions = false; });
      return;
    }
_debounce = Timer(const Duration(milliseconds: 100), () => _fetchSuggestions(value));  }

  void _selectSuggestion(String suggestion) {
    _searchController.text = suggestion;
    _searchFocusNode.unfocus();
    setState(() { _showSuggestions = false; _suggestions = []; });
    _search(suggestion);
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _results = [];
    });
    try {
      final searchList = await yt.search.search(query);
      final videos = searchList.whereType<Video>().take(20).toList();
      setState(() {
        _results = videos;
        _isSearching = false;
      });
      ManifestCache.prefetchAll(videos.map((v) => v.id.value).toList(), limit: 5);
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        _showGlassToast('خطأ في البحث: $e', type: _ToastType.error);
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
Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 46,
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.only(
                              topRight: const Radius.circular(14),
                              topLeft: const Radius.circular(14),
                              bottomRight: Radius.circular(_showSuggestions && _suggestions.isNotEmpty ? 0 : 14),
                              bottomLeft: Radius.circular(_showSuggestions && _suggestions.isNotEmpty ? 0 : 14),
                            ),
                            border: Border.all(
                              color: _showSuggestions && _suggestions.isNotEmpty
                                  ? AppColors.primary.withOpacity(0.4)
                                  : divider,
                              width: _showSuggestions && _suggestions.isNotEmpty ? 1.2 : 0.5,
                            ),
                            boxShadow: _showSuggestions && _suggestions.isNotEmpty
                                ? [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 2))]
                                : [],
                          ),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            textDirection: TextDirection.rtl,
                            textInputAction: TextInputAction.search,
                            onChanged: _onSearchChanged,
                            onSubmitted: (v) {
                              setState(() { _showSuggestions = false; });
                              _search(v);
                            },
                            onTap: () {
                              if (_searchController.text.trim().length >= 2) {
                                setState(() => _showSuggestions = _suggestions.isNotEmpty);
                              }
                            },
                            style: TextStyle(color: textPrimary, fontFamily: 'Tajawal'),
                            decoration: InputDecoration(
                              hintText: 'ابحث عن فيديو أو موسيقى...',
                              hintStyle: TextStyle(color: textSecondary, fontSize: 14, fontFamily: 'Tajawal'),
                              prefixIcon: _loadingSuggestions
                                  ? Padding(
                                      padding: const EdgeInsets.all(13),
                                      child: SizedBox(
                                        width: 18, height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(AppColors.primary),
                                        ),
                                      ),
                                    )
                                  : Icon(CupertinoIcons.search, color: _showSuggestions ? AppColors.primary : textSecondary, size: 18),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () {
                                        _searchController.clear();
                                        setState(() { _suggestions = []; _showSuggestions = false; _results = []; });
                                      },
                                      child: Icon(CupertinoIcons.xmark_circle_fill, color: textSecondary, size: 18),
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          setState(() => _showSuggestions = false);
                          _searchFocusNode.unfocus();
                          _search(_searchController.text);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 46,
                          width: 46,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(CupertinoIcons.search, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                  // ── قائمة المقترحات ──
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    _buildSuggestionsPanel(isDark, surface, textPrimary, textSecondary, divider),
                  const SizedBox(height: 12),
                ],
              ),
            ),
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

  Widget _buildSuggestionsPanel(bool isDark, Color surface, Color textPrimary, Color textSecondary, Color divider) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        border: Border(
          left: BorderSide(color: AppColors.primary.withOpacity(0.4), width: 1.2),
          right: BorderSide(color: AppColors.primary.withOpacity(0.4), width: 1.2),
          bottom: BorderSide(color: AppColors.primary.withOpacity(0.4), width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        child: Column(
          children: [
            Container(height: 0.5, color: AppColors.primary.withOpacity(0.15)),
            ...List.generate(_suggestions.length, (index) {
              final suggestion = _suggestions[index];
              final query = _searchController.text.trim().toLowerCase();
              final isLast = index == _suggestions.length - 1;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _selectSuggestion(suggestion),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 150 + index * 30),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      border: isLast ? null : Border(
                        bottom: BorderSide(color: divider.withOpacity(0.5), width: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(CupertinoIcons.search, size: 14, color: AppColors.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildHighlightedText(suggestion, query, textPrimary, textSecondary),
                        ),
                        Icon(
                          CupertinoIcons.arrow_up_right,
                          size: 13,
                          color: textSecondary.withOpacity(0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedText(String suggestion, String query, Color textPrimary, Color textSecondary) {
    if (query.isEmpty) {
      return Text(
        suggestion,
        style: TextStyle(fontSize: 14, fontFamily: 'Tajawal', color: textPrimary),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerSuggestion = suggestion.toLowerCase();
    final matchStart = lowerSuggestion.indexOf(query);

    if (matchStart == -1) {
      return Text(
        suggestion,
        style: TextStyle(fontSize: 14, fontFamily: 'Tajawal', color: textPrimary),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          if (matchStart > 0)
            TextSpan(
              text: suggestion.substring(0, matchStart),
              style: TextStyle(fontSize: 14, fontFamily: 'Tajawal', color: textSecondary),
            ),
          TextSpan(
            text: suggestion.substring(matchStart, matchStart + query.length),
            style: const TextStyle(
              fontSize: 14,
              fontFamily: 'Tajawal',
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (matchStart + query.length < suggestion.length)
            TextSpan(
              text: suggestion.substring(matchStart + query.length),
              style: TextStyle(fontSize: 14, fontFamily: 'Tajawal', color: textPrimary, fontWeight: FontWeight.w500),
            ),
        ],
      ),
      textDirection: TextDirection.rtl,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
                        color: AppColors.primary.withValues(alpha: 0.2), width: 0.5),
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
    final taskId = '${id}_${DateTime.now().millisecondsSinceEpoch}';
    final shortTitle = video.title.length > 35
        ? '${video.title.substring(0, 35)}...'
        : video.title;
    final task = _DownloadTask(id: taskId, title: shortTitle);
    final ctrl = _GlobalDownloadBarController.instance;

    if (context.mounted) {
      ctrl.show(context);
      ctrl.addTask(task);
      ctrl._refresh();
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${dir.path}/dndn');
      if (!await musicDir.exists()) await musicDir.create(recursive: true);

      final safeTitle =
          video.title.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF\-]'), '').trim();
      final receivePort = ReceivePort();

      String? directUrl;
      if (ManifestCache.isVideoCached(id)) {
        directUrl = ManifestCache.getCachedVideo(id)!.url;
      }

      unawaited(Isolate.spawn(
        downloadIsolate,
        DownloadArgs(
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
          if (msg.containsKey('progress')) {
            ctrl.updateProgress(taskId, (msg['progress'] as double).clamp(0.0, 1.0));
          } else if (msg.containsKey('done')) {
            receivePort.close();
            final fileName = msg['done'] as String;
            final savedPath = '${musicDir.path}/$fileName';
            await ThumbnailManager.saveThumbnail(
                savedPath, video.thumbnails.mediumResUrl);
            downloadCompleteNotifier.value = musicDir.path;
            ctrl.completeTask(taskId);
            break;
          } else if (msg.containsKey('error')) {
            receivePort.close();
            ctrl.failTask(taskId, msg['error'] as String);
            break;
          }
        }
      }
    } catch (e) {
      ctrl.failTask(taskId, e.toString());
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
                              color: Colors.black.withValues(alpha: 0.75),
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
                          color: Colors.black.withValues(alpha: 0.75),
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

  OverlayEntry? _toastOverlay;

  void _showGlassToast(String message,
      {_ToastType type = _ToastType.info,
      Duration duration = const Duration(seconds: 3)}) {
    _toastOverlay?.remove();
    _toastOverlay = null;
    final entry = OverlayEntry(
      builder: (ctx) => _GlassToast(
        message: message,
        type: type,
        onDismiss: () {
          _toastOverlay?.remove();
          _toastOverlay = null;
        },
      ),
    );
    _toastOverlay = entry;
    Overlay.of(context).insert(entry);
    Future.delayed(duration, () {
      if (_toastOverlay == entry) {
        _toastOverlay?.remove();
        _toastOverlay = null;
      }
    });
  }

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
    ManifestCache.get(videoId).catchError((_) {});
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
        ManifestCache.prefetchAll(
          _relatedVideos.map((v) => v.id.value).toList(),
          limit: 3,
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _toastOverlay?.remove();
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
      if (ManifestCache.isVideoCached(videoId)) {
        directUrl = ManifestCache.getCachedVideo(videoId)!.url;
      }

      final receivePort = ReceivePort();
      unawaited(Isolate.spawn(
        downloadIsolate,
        DownloadArgs(
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
            await ThumbnailManager.saveThumbnail(
                savedPath, widget.video.thumbnails.mediumResUrl);
            if (mounted) {
              setState(() {
                _isDownloading = false;
                _downloadStatus = '';
              });
              _showGlassToast('تم التحميل: $fileName', type: _ToastType.success);
              downloadCompleteNotifier.value = musicDir.path;
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
        _showGlassToast('فشل التحميل: $e', type: _ToastType.error);
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
                          backgroundColor: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white,
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
  final Function(String, String) onDownload;

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

    final isCached = ManifestCache.isCached(videoId);
    final isVideoCached = ManifestCache.isVideoCached(videoId);

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
//  MEDIA VIDEO BROWSER PAGE — استيراد مقاطع الفيديو فقط من وسائط الجهاز
// ═══════════════════════════════════════════════════════════
class MediaVideoBrowserPage extends StatefulWidget {
  const MediaVideoBrowserPage({super.key});

  @override
  State<MediaVideoBrowserPage> createState() => _MediaVideoBrowserPageState();
}

class _MediaVideoBrowserPageState extends State<MediaVideoBrowserPage> {
  List<PlatformFile> _pickedVideos = [];
  bool _importing = false;

  OverlayEntry? _toastOverlay;

  void _showGlassToast(String message,
      {_ToastType type = _ToastType.info,
      Duration duration = const Duration(seconds: 3)}) {
    _toastOverlay?.remove();
    _toastOverlay = null;
    final entry = OverlayEntry(
      builder: (ctx) => _GlassToast(
        message: message,
        type: type,
        onDismiss: () {
          _toastOverlay?.remove();
          _toastOverlay = null;
        },
      ),
    );
    _toastOverlay = entry;
    Overlay.of(context).insert(entry);
    Future.delayed(duration, () {
      if (_toastOverlay == entry) {
        _toastOverlay?.remove();
        _toastOverlay = null;
      }
    });
  }

  @override
  void dispose() {
    _toastOverlay?.remove();
    super.dispose();
  }

  // دالة اختيار مقاطع الفيديو فقط من وسائط الجهاز
  Future<void> _pickVideos() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.video, // تحديد اختيار مقاطع الفيديو فقط
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() => _pickedVideos = result.files);
      }
    } catch (e) {
      if (mounted) {
        _showGlassToast('خطأ في فتح وسائط الجهاز: $e', type: _ToastType.error);
      }
    }
  }

  // دالة استيراد وتخزين مقاطع الفيديو المحددة إلى مجلد dndn ليظهر في صفحة استمع
  Future<void> _importSelected() async {
    if (_pickedVideos.isEmpty) return;
    setState(() => _importing = true);

    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory('${dir.path}/dndn');
    if (!await destDir.exists()) await destDir.create(recursive: true);

    final total = _pickedVideos.length;
    final controller = StreamController<_ImportEvent>.broadcast();

    // فتح نافذة التقدم
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.55),
        builder: (_) => _ImportProgressDialog(
          total: total,
          events: controller.stream,
        ),
      );
    }

    int copied = 0;
    for (final file in _pickedVideos) {
      if (file.path == null) continue;
      try {
        final src = File(file.path!);
        final name = file.name;
        final dest = File('${destDir.path}/$name');
        if (!await dest.exists()) {
          await src.copy(dest.path);
        }
        copied++;
        controller.add(_ImportEvent(done: copied, currentName: name));
        // توليد صورة مصغرة للفيديو المحلي
        ThumbnailManager.generateLocalThumbnail(dest.path).catchError((_) {});
      } catch (_) {}
    }

    // إرسال حدث الإتمام
    controller.add(_ImportEvent(done: copied, currentName: '', finished: true));
    await Future.delayed(const Duration(milliseconds: 300));
    await controller.close();

    // تحديث المستمع (Notifier) لتظهر الملفات فوراً في صفحة استمع
    downloadCompleteNotifier.value = destDir.path;

    if (mounted) {
      setState(() => _importing = false);
      // إغلاق Dialog وصفحة الاستيراد بعد لحظة
      await Future.delayed(const Duration(milliseconds: 1800));
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // إغلاق الـ Dialog
      }
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // العودة للخلف
      }
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
            // شريط العنوان العلوي (Header)
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
                      'وسائط الجهاز (فيديو)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                        fontFamily: 'Tajawal',
                      ),
                    ),
                  ),
                  if (_pickedVideos.isNotEmpty)
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
                                'تم (${_pickedVideos.length})',
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
            // محتوى الصفحة (قائمة الفيديوهات أو زر الاختيار المبدئي)
            Expanded(
              child: _pickedVideos.isEmpty
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
                            child: const Icon(CupertinoIcons.video_camera_solid,
                                size: 38, color: AppColors.primary),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'اختر مقاطع فيديو من وسائط الجهاز',
                            style: TextStyle(
                              fontSize: 18,
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'سيتم عرض مقاطع الفيديو فقط لاستيرادها',
                            style: TextStyle(
                                fontSize: 13,
                                fontFamily: 'Tajawal',
                                color: textSecondary),
                          ),
                          const SizedBox(height: 32),
                          GestureDetector(
                            onTap: _pickVideos,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(CupertinoIcons.photo_on_rectangle,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'فتح معرض الفيديوهات',
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: GestureDetector(
                            onTap: _pickVideos,
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
                                  Icon(CupertinoIcons.refresh, color: textSecondary, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'تعديل الاختيار / إضافة مقاطع أخرى',
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            itemCount: _pickedVideos.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final file = _pickedVideos[index];
                              final name = file.name;
                              final ext = name.split('.').last.toLowerCase();
                              return Container(
                                decoration: BoxDecoration(
                                  color: redLight,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  leading: Container(
                                    width: 42, height: 42,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      CupertinoIcons.play_rectangle_fill,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    name.replaceAll(RegExp(r'\.\w+$'), ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontFamily: 'Tajawal',
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    ext.toUpperCase(),
                                    style: TextStyle(fontSize: 11, color: textSecondary),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
            // الزر السفلي العائم عند اختيار ملفات
            if (_pickedVideos.isNotEmpty)
              Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
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
                            'استيراد ${_pickedVideos.length} فيديو إلى صفحة استمع',
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