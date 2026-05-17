// lib/pages/download_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../main.dart';
import 'download_service.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _urlController = TextEditingController();
  final DownloadService _downloadService = DownloadService();

  bool _isLoading = false;
  bool _isProcessing = false;
  double _downloadProgress = 0;
  String? _errorMessage;
  VideoResult? _videoResult;

  // حالة WebView
  bool _showWebView = false;
  bool _webViewLoading = false;
  WebViewController? _webViewController;
  String _detectedVideoUrl = '';
  String _webViewUrl = '';

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // منطق الاستخراج التلقائي
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _processLink() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'الرجاء إدخال رابط صحيح');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _videoResult = null;
      _downloadProgress = 0;
    });

    try {
      final result = await _downloadService.extractVideoUrl(url);

      if (result != null) {
        setState(() {
          _videoResult = result;
          _isLoading = false;
        });
        _showDownloadSheet(result);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لم يُعثر على الفيديو تلقائياً.\n'
              'جرّب المتصفح الداخلي في التبويب الثاني للتسجيل ومشاهدة الفيديو مباشرةً.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ: ${e.toString()}';
      });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // WebView — كاشف الفيديو
  // ──────────────────────────────────────────────────────────────────────────

  void _initWebView(String startUrl) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
        'Mobile/15E148 Safari/604.1',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _webViewLoading = true),
        onPageFinished: (url) {
          setState(() {
            _webViewLoading = false;
            _webViewUrl = url;
          });
          // حقن JavaScript للكشف عن الفيديوهات في الصفحة
          _injectVideoDetector();
        },
      ))
      // التقاط أي طلب شبكة يحتوي على mp4 أو blob فيديو
      ..setOnConsoleMessage((msg) {
        final text = msg.message;
        if (_looksLikeVideoUrl(text)) {
          _onVideoDetected(text);
        }
      });

    // استخدام NavigationDelegate لاعتراض الطلبات
    controller.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) => setState(() => _webViewLoading = true),
      onPageFinished: (url) {
        setState(() {
          _webViewLoading = false;
          _webViewUrl = url;
        });
        _injectVideoDetector();
      },
      onNavigationRequest: (req) {
        final url = req.url;
        if (_looksLikeVideoUrl(url)) {
          _onVideoDetected(url);
          return NavigationDecision.prevent; // لا تفتح الرابط مباشرة
        }
        return NavigationDecision.navigate;
      },
    ));

    controller.loadRequest(Uri.parse(startUrl));
    setState(() {
      _webViewController = controller;
      _showWebView = true;
      _webViewLoading = true;
      _webViewUrl = startUrl;
    });
  }

  /// حقن JavaScript يكشف وسوم <video> وطلبات الشبكة
  Future<void> _injectVideoDetector() async {
    await _webViewController?.runJavaScript(r'''
      (function() {
        // 1. البحث في وسوم <video> الموجودة حالياً
        function checkVideos() {
          var videos = document.querySelectorAll('video');
          videos.forEach(function(v) {
            var src = v.src || v.currentSrc || '';
            if (src && src.length > 10) {
              console.log('__VIDEO_DETECTED__:' + src);
            }
            // مصادر <source> داخل <video>
            v.querySelectorAll('source').forEach(function(s) {
              if (s.src) console.log('__VIDEO_DETECTED__:' + s.src);
            });
          });
        }

        // 2. مراقبة أي تغيير في الـ DOM
        var observer = new MutationObserver(function() { checkVideos(); });
        observer.observe(document.body || document.documentElement, {
          childList: true, subtree: true, attributes: true
        });

        // 3. اعتراض fetch
        var origFetch = window.fetch;
        window.fetch = function(url, opts) {
          if (typeof url === 'string' && (url.indexOf('.mp4') > -1 || url.indexOf('video') > -1)) {
            console.log('__VIDEO_DETECTED__:' + url);
          }
          return origFetch.apply(this, arguments);
        };

        // 4. اعتراض XHR
        var origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          if (typeof url === 'string' && (url.indexOf('.mp4') > -1 || url.indexOf('video') > -1)) {
            console.log('__VIDEO_DETECTED__:' + url);
          }
          return origOpen.apply(this, arguments);
        };

        checkVideos();
        setTimeout(checkVideos, 2000);
        setTimeout(checkVideos, 5000);
      })();
    ''');
  }

  bool _looksLikeVideoUrl(String text) {
    // استخرج الجزء بعد البادئة
    final url = text.contains('__VIDEO_DETECTED__:')
        ? text.split('__VIDEO_DETECTED__:').last.trim()
        : text.trim();

    if (url.isEmpty || url.length < 15) return false;

    return (url.contains('.mp4') ||
            url.contains('video/mp4') ||
            url.contains('.m3u8') ||
            url.contains('/video/')) &&
        (url.startsWith('http://') || url.startsWith('https://'));
  }

  void _onVideoDetected(String rawText) {
    final url = rawText.contains('__VIDEO_DETECTED__:')
        ? rawText.split('__VIDEO_DETECTED__:').last.trim()
        : rawText.trim();

    if (url.isEmpty || url == _detectedVideoUrl) return;

    // تجنب تكرار النوافذ
    setState(() => _detectedVideoUrl = url);

    // عرض نافذة تأكيد فورية
    if (mounted) _showDetectedVideoDialog(url);
  }

  void _showDetectedVideoDialog(String url) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('🎬 تم اكتشاف فيديو!'),
        content: Column(
          children: [
            const SizedBox(height: 8),
            const Text(
              'تم رصد فيديو في الصفحة الحالية. هل تريد تحميله؟',
              style: TextStyle(fontFamily: 'Tajawal'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              url.length > 60 ? '${url.substring(0, 60)}…' : url,
              style: const TextStyle(
                fontSize: 11,
                color: CupertinoColors.systemGrey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              setState(() => _detectedVideoUrl = ''); // أعد الضبط
            },
            child: const Text('تجاهل'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(context);
              _tabController.animateTo(0); // ارجع لتبويب التحميل
              _downloadDetectedVideo(url);
            },
            child: const Text('تحميل الآن'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadDetectedVideo(String url) async {
    setState(() {
      _isProcessing = true;
      _downloadProgress = 0;
    });

    final file = await _downloadService.downloadVideo(
      url,
      'best',
      onProgress: (p) => setState(() => _downloadProgress = p),
    );

    setState(() => _isProcessing = false);

    if (!mounted) return;

    if (file != null) {
      _showSuccessSnack('تم التحميل بنجاح: ${file.path.split('/').last}');
    } else {
      _showErrorSnack('فشل التحميل — حاول مرة أخرى');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // sheet التحميل
  // ──────────────────────────────────────────────────────────────────────────

  void _showDownloadSheet(VideoResult result) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('تحميل الفيديو'),
        message: Text(
          'المصدر: ${result.source}   |   الجودة: ${result.quality}',
          style: const TextStyle(fontFamily: 'Tajawal'),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _startDownload(result.url);
            },
            child: const Text('تحميل الآن'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ),
    );
  }

  Future<void> _startDownload(String url) async {
    setState(() {
      _isProcessing = true;
      _downloadProgress = 0;
    });

    final file = await _downloadService.downloadVideo(
      url,
      'best',
      onProgress: (p) => setState(() => _downloadProgress = p),
    );

    setState(() => _isProcessing = false);

    if (!mounted) return;

    if (file != null) {
      _showSuccessSnack('✅ تم التحميل: ${file.path.split('/').last}');
    } else {
      _showErrorSnack('❌ فشل التحميل');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // مساعدات UI
  // ──────────────────────────────────────────────────────────────────────────

  void _showSuccessSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal')),
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showErrorSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal')),
      backgroundColor: Colors.red,
    ));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // بناء الواجهة
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      appBar: AppBar(
        title: const Text(
          'تحميل فيديو',
          style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontFamily: 'Tajawal', fontSize: 14),
          tabs: const [
            Tab(text: '🔗 رابط مباشر'),
            Tab(text: '🌐 متصفح داخلي'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLinkTab(),
          _buildBrowserTab(),
        ],
      ),
    );
  }

  // ── تبويب الرابط المباشر ──────────────────────────────────────────────────
  Widget _buildLinkTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // بطاقة الإدخال
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  CupertinoIcons.cloud_download,
                  size: 52,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 14),
                const Text(
                  'الصق رابط TikTok أو Instagram',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'يعمل مع المقاطع العامة — بدون تسجيل دخول',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _urlController,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: 'https://www.tiktok.com/…',
                    prefixIcon: const Icon(CupertinoIcons.link),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                ),
                const SizedBox(height: 20),

                // شريط التقدم
                if (_isProcessing) ...[
                  LinearProgressIndicator(
                    value: _downloadProgress > 0 ? _downloadProgress : null,
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 6,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _downloadProgress > 0
                        ? 'جاري التحميل… ${(_downloadProgress * 100).toStringAsFixed(0)}%'
                        : 'جاري المعالجة…',
                    style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                ],

                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: (_isLoading || _isProcessing) ? null : _processLink,
                    borderRadius: BorderRadius.circular(12),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'استخراج وتحميل',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // رسالة الخطأ
          if (_errorMessage != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: () {
                            _tabController.animateTo(1);
                            // افتح الرابط المُدخل في المتصفح الداخلي
                            final url = _urlController.text.trim();
                            if (url.isNotEmpty) {
                              final startUrl = _buildBrowserStartUrl(url);
                              _initWebView(startUrl);
                            }
                          },
                          child: const Text(
                            '← افتح في المتصفح الداخلي',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // نصيحة
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(CupertinoIcons.lightbulb, color: AppColors.primary, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'للفيديوهات الخاصة أو التي تتطلب تسجيل دخول، '
                    'استخدم تبويب المتصفح الداخلي وسجّل دخولك مباشرةً.',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── تبويب المتصفح الداخلي ────────────────────────────────────────────────
  Widget _buildBrowserTab() {
    if (!_showWebView) {
      return _buildBrowserLauncher();
    }
    return _buildActiveWebView();
  }

  Widget _buildBrowserLauncher() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(
                  CupertinoIcons.globe,
                  size: 56,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'متصفح داخلي مع كاشف فيديو',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'سجّل دخولك إلى Instagram أو TikTok، '
                  'وعند ظهور أي فيديو سيُعلمك التطبيق فوراً بخيار التحميل.',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // أزرار الإطلاق
          _launchButton(
            label: 'فتح Instagram',
            icon: CupertinoIcons.camera,
            url: 'https://www.instagram.com/',
          ),
          const SizedBox(height: 12),
          _launchButton(
            label: 'فتح TikTok',
            icon: CupertinoIcons.play_rectangle,
            url: 'https://www.tiktok.com/',
          ),
          const SizedBox(height: 20),

          // أو أدخل رابطاً
          const Row(children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('أو', style: TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Divider()),
          ]),
          const SizedBox(height: 16),

          TextField(
            controller: _urlController,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'الصق رابط الفيديو هنا…',
              prefixIcon: const Icon(CupertinoIcons.link),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: IconButton(
                icon: const Icon(CupertinoIcons.arrow_right_circle_fill,
                    color: AppColors.primary),
                onPressed: () {
                  final url = _urlController.text.trim();
                  if (url.isNotEmpty) {
                    _initWebView(_buildBrowserStartUrl(url));
                  }
                },
              ),
            ),
            onSubmitted: (val) {
              if (val.isNotEmpty) _initWebView(_buildBrowserStartUrl(val));
            },
          ),
        ],
      ),
    );
  }

  Widget _launchButton({
    required String label,
    required IconData icon,
    required String url,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _initWebView(url),
        icon: Icon(icon, color: AppColors.primary),
        label: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: AppColors.primary, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildActiveWebView() {
    return Column(
      children: [
        // شريط التحكم
        Container(
          color: context.isDark ? AppColors.darkSurface : AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.arrow_left, size: 20),
                onPressed: () => _webViewController?.goBack(),
                tooltip: 'رجوع',
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.arrow_right, size: 20),
                onPressed: () => _webViewController?.goForward(),
                tooltip: 'تقدم',
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.refresh, size: 20),
                onPressed: () => _webViewController?.reload(),
                tooltip: 'تحديث',
              ),
              Expanded(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: context.isDark ? Colors.black26 : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _webViewUrl.length > 45
                        ? '${_webViewUrl.substring(0, 45)}…'
                        : _webViewUrl,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.xmark, size: 18),
                onPressed: () => setState(() {
                  _showWebView = false;
                  _detectedVideoUrl = '';
                }),
                tooltip: 'إغلاق المتصفح',
              ),
            ],
          ),
        ),

        // شريط التحميل إذا كان يحمّل
        if (_webViewLoading)
          const LinearProgressIndicator(minHeight: 2),

        // بانر إذا جارٍ التحميل
        if (_isProcessing)
          Container(
            padding: const EdgeInsets.all(10),
            color: AppColors.primary.withValues(alpha: 0.1),
            child: Row(
              children: [
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  _downloadProgress > 0
                      ? 'جاري التحميل ${(_downloadProgress * 100).toStringAsFixed(0)}%'
                      : 'جاري التحميل…',
                  style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                ),
              ],
            ),
          ),

        // WebView نفسه
        Expanded(
          child: WebViewWidget(controller: _webViewController!),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────

  String _buildBrowserStartUrl(String url) {
    if (url.startsWith('http')) return url;
    if (url.contains('instagram.com') || url.contains('instagr.am')) {
      return url.startsWith('http') ? url : 'https://$url';
    }
    if (url.contains('tiktok.com') || url.contains('vm.tiktok.com')) {
      return url.startsWith('http') ? url : 'https://$url';
    }
    return 'https://$url';
  }
}