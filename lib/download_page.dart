// lib/pages/download_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import 'download_service.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final TextEditingController _urlController = TextEditingController();
  final DownloadService _downloadService = DownloadService();
  
  bool _isLoading = false;
  String? _errorMessage;
  String? _videoUrl;
  bool _isProcessing = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _processLink() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'الرجاء إدخال رابط صحيح');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _videoUrl = null;
    });

    try {
      // محاولة استخراج الفيديو
      final extractedUrl = await _downloadService.extractVideoUrl(url);
      
      if (extractedUrl != null) {
        setState(() {
          _videoUrl = extractedUrl;
          _isLoading = false;
        });
        // عرض خيار التحميل
        _showDownloadOptions(extractedUrl);
      } else {
        // إذا فشل، نعرض خيارات بديلة
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر استخراج الفيديو تلقائياً. يرجى المحاولة باستخدام إحدى الطرق التالية:';
        });
        _showAlternativeOptions(url);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ: ${e.toString()}';
      });
    }
  }

  void _showDownloadOptions(String videoUrl) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('تحميل الفيديو'),
        message: const Text('اختر جودة التحميل'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _downloadVideo(videoUrl, 'high');
            },
            child: const Text('جودة عالية'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _downloadVideo(videoUrl, 'medium');
            },
            child: const Text('جودة متوسطة'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ),
    );
  }

  void _showAlternativeOptions(String originalUrl) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('طرق بديلة للتحميل'),
        message: const Text('اختر إحدى الطرق التالية'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _openInBrowser(originalUrl);
            },
            child: const Text('فتح الرابط في المتصفح'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showManualInstructions();
            },
            child: const Text('تعليمات التحميل اليدوي'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ),
    );
  }

  Future<void> _downloadVideo(String url, String quality) async {
    setState(() => _isProcessing = true);
    
    try {
      final file = await _downloadService.downloadVideo(url, quality);
      if (file != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم التحميل بنجاح إلى ${file.path.split('/').last}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('فشل التحميل');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التحميل: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _openInBrowser(String url) async {
    // استخدام url_launcher لفتح الرابط
    // (تأكد من إضافة url_launcher في pubspec.yaml)
    final uri = Uri.parse(url);
    // await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showManualInstructions() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تحميل يدوي', textAlign: TextAlign.right),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. افتح موقع snaptik.app في متصفحك'),
            const SizedBox(height: 8),
            const Text('2. الصق رابط الفيديو واضغط تحميل'),
            const SizedBox(height: 8),
            const Text('3. حمل الفيديو ثم أضفه للتطبيق عبر زر "إضافة محلي"'),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: _urlController.text),
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'الرابط',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      appBar: AppBar(
        title: const Text('تحميل فيديو'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Icon(
                    CupertinoIcons.cloud_download,
                    size: 50,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'الصق رابط الفيديو من TikTok أو Instagram',
                    style: TextStyle(fontFamily: 'Tajawal', fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: 'https://www.tiktok.com/...',
                      prefixIcon: const Icon(CupertinoIcons.link),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      onPressed: _isLoading || _isProcessing ? null : _processLink,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('استخراج الفيديو'),
                    ),
                  ),
                ],
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(fontFamily: 'Tajawal'),
                          ),
                        ),
                      ],
                    ),
                    if (_errorMessage!.contains('تعذر')) ...[
                      const SizedBox(height: 12),
                      CupertinoButton(
                        onPressed: () => _showAlternativeOptions(_urlController.text),
                        child: const Text('عرض الحلول البديلة'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}