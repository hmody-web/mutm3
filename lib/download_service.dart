// lib/services/download_service.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  // قائمة APIs مجانية لتحميل من TikTok و Instagram
  final List<Map<String, String>> _apis = [
    {
      'url': 'https://tiksave.io/api/ajax',
      'method': 'POST',
      'platform': 'tiktok'
    },
    {
      'url': 'https://snaptik.app/api/ajax',
      'method': 'POST',
      'platform': 'tiktok'
    },
    {
      'url': 'https://tikdownloader.io/api/ajax',
      'method': 'POST',
      'platform': 'tiktok'
    },
    {
      'url': 'https://saveinsta.app/api/ajax',
      'method': 'POST',
      'platform': 'instagram'
    },
  ];

  /// استخراج رابط الفيديو من رابط TikTok أو Instagram
  Future<String?> extractVideoUrl(String url) async {
    // تحديد المنصة
    final platform = _detectPlatform(url);
    if (platform == null) return null;

    // المحاولة عبر APIs مختلفة
    for (final api in _apis) {
      if (api['platform'] != platform) continue;
      
      try {
        final result = await _tryApi(api, url);
        if (result != null) return result;
      } catch (e) {
        continue;
      }
    }

    // إذا فشل، جرب طريقة بديلة باستخدام WebView
    return null;
  }

  String? _detectPlatform(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('tiktok.com')) return 'tiktok';
    if (lowerUrl.contains('instagram.com') || lowerUrl.contains('instagr.am')) return 'instagram';
    return null;
  }

  Future<String?> _tryApi(Map<String, String> api, String url) async {
    try {
      final response = await http.post(
        Uri.parse(api['url']!),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {'url': url, 'ajax': '1'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // تحليل الرد حسب كل API
        final videoUrl = _parseApiResponse(response.body, api['url']!);
        if (videoUrl != null && videoUrl.isNotEmpty) {
          return videoUrl;
        }
      }
    } catch (e) {
      // فشل هذه المحاولة
    }
    return null;
  }

  String? _parseApiResponse(String body, String apiUrl) {
    // محاولة استخراج رابط الفيديو من الـ JSON
    try {
      // يمكنك تخصيص هذا حسب استجابة كل API
      if (body.contains('video_url')) {
        // مثال بسيط - في التطبيق الحقيقي استخدم jsonDecode
        final start = body.indexOf('"video_url":"');
        if (start != -1) {
          final end = body.indexOf('"', start + 13);
          if (end != -1) {
            return body.substring(start + 13, end).replaceAll('\\/', '/');
          }
        }
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// تحميل الفيديو وحفظه محلياً
  Future<File?> downloadVideo(String url, String quality) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/dndn');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final savePath = '${downloadDir.path}/$fileName';

      final dio = Dio();
      await dio.download(url, savePath, options: Options(
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ));

      return File(savePath);
    } catch (e) {
      return null;
    }
  }

  /// رابط مباشر لتحميل من TikTok عبر خدمة بديلة
  Future<String?> getDirectUrlFromTikTok(String url) async {
    // استخدام خدمة بديلة مجانية
    final fallbackUrls = [
      'https://tikcdn.io/ssstik?url=$url',
      'https://tikmate.online/download?url=$url',
    ];

    for (final fallback in fallbackUrls) {
      try {
        final response = await http.get(Uri.parse(fallback));
        if (response.statusCode == 200 && response.body.contains('.mp4')) {
          // استخراج الرابط من الصفحة (يمكن تحسينه)
          return _extractMp4FromHtml(response.body);
        }
      } catch (e) {
        continue;
      }
    }
    return null;
  }

  String? _extractMp4FromHtml(String html) {
    final regex = RegExp(r'https?://[^\s"' "'" r']+\.mp4[^\s"' "'" r']*');
    final match = regex.firstMatch(html);
    return match?.group(0);
  }
}