// lib/services/download_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  // ─── استخراج رابط الفيديو ─────────────────────────────────────────────────

  /// نقطة الدخول الرئيسية — تجرب الطرق بالترتيب حتى تنجح إحداها
  Future<VideoResult?> extractVideoUrl(String url) async {
    final platform = _detectPlatform(url);
    if (platform == null) return null;

    // 1️⃣ cobalt.tools — مجاني تماماً، بدون مفتاح API، يدعم TikTok + Instagram
    final cobalt = await _tryCobalt(url);
    if (cobalt != null) return cobalt;

    // 2️⃣ SaveFrom (HTML scraping خفيف)
    final savefrom = await _trySaveFrom(url, platform);
    if (savefrom != null) return savefrom;

    // 3️⃣ SnapTik (TikTok فقط)
    if (platform == 'tiktok') {
      final snaptik = await _trySnapTik(url);
      if (snaptik != null) return snaptik;
    }

    return null;
  }

  // ── cobalt.tools API ────────────────────────────────────────────────────────
  Future<VideoResult?> _tryCobalt(String url) async {
    // cobalt هو مشروع مفتوح المصدر بدون مفاتيح — يدعم TikTok وInstagram ويوتيوب
    // الـ instance العام: https://co.wuk.sh  أو  https://cobalt.tools
    final endpoints = [
      'https://co.wuk.sh/api/json',
      'https://cobalt.tools/api/json', // نسخة احتياطية
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await http
            .post(
              Uri.parse(endpoint),
              headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'User-Agent':
                    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
                    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
                    'Mobile/15E148 Safari/604.1',
              },
              body: jsonEncode({
                'url': url,
                'vQuality': '720',      // جودة 720p
                'isNoTTWatermark': true, // TikTok بدون علامة مائية
                'isTTFullAudio': false,
              }),
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final status = data['status'] as String?;

          if (status == 'stream' || status == 'redirect') {
            final videoUrl = data['url'] as String?;
            if (videoUrl != null && videoUrl.isNotEmpty) {
              return VideoResult(url: videoUrl, quality: '720p', source: 'cobalt');
            }
          }

          // عدة روابط بجودات مختلفة
          if (status == 'picker') {
            final picker = data['picker'] as List?;
            if (picker != null && picker.isNotEmpty) {
              final first = picker.first as Map<String, dynamic>;
              final videoUrl = first['url'] as String?;
              if (videoUrl != null) {
                return VideoResult(url: videoUrl, quality: 'best', source: 'cobalt');
              }
            }
          }
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  // ── SaveFrom (scraping) ─────────────────────────────────────────────────────
  Future<VideoResult?> _trySaveFrom(String url, String platform) async {
    try {
      final encoded = Uri.encodeComponent(url);
      final apiUrl = 'https://worker.sf-tools.com/savefrom?url=$encoded';

      final response = await http
          .get(
            Uri.parse(apiUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': 'application/json',
              'Origin': 'https://en.savefrom.net',
              'Referer': 'https://en.savefrom.net/',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final links = data['url'] as List?;
        if (links != null && links.isNotEmpty) {
          // اختر أفضل جودة
          String? bestUrl;
          int bestHeight = 0;
          for (final link in links) {
            final map = link as Map<String, dynamic>;
            final linkUrl = map['url'] as String?;
            final height = (map['height'] as num?)?.toInt() ?? 0;
            if (linkUrl != null && height > bestHeight) {
              bestHeight = height;
              bestUrl = linkUrl;
            }
          }
          if (bestUrl != null) {
            return VideoResult(
              url: bestUrl,
              quality: bestHeight > 0 ? '${bestHeight}p' : 'best',
              source: 'savefrom',
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // ── SnapTik (TikTok فقط) ────────────────────────────────────────────────────
  Future<VideoResult?> _trySnapTik(String url) async {
    try {
      // الخطوة 1: الحصول على token
      final mainPage = await http
          .get(Uri.parse('https://snaptik.app/ar'))
          .timeout(const Duration(seconds: 10));

      String? token;
      final tokenMatch =
          RegExp(r'name="token"\s+value="([^"]+)"').firstMatch(mainPage.body);
      if (tokenMatch != null) token = tokenMatch.group(1);
      if (token == null) return null;

      // الخطوة 2: إرسال الرابط
      final response = await http
          .post(
            Uri.parse('https://snaptik.app/action_step2.php'),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Origin': 'https://snaptik.app',
              'Referer': 'https://snaptik.app/ar',
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
                  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
                  'Mobile/15E148 Safari/604.1',
            },
            body: {'url': url, 'token': token, 'lang': 'ar'},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        // استخراج روابط mp4 من HTML الناتج
        final mp4 = _extractBestMp4(response.body);
        if (mp4 != null) {
          return VideoResult(url: mp4, quality: 'HD', source: 'snaptik');
        }
      }
    } catch (_) {}
    return null;
  }

  // ── مساعدات ────────────────────────────────────────────────────────────────

  String? _detectPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('tiktok.com') || lower.contains('vm.tiktok.com')) {
      return 'tiktok';
    }
    if (lower.contains('instagram.com') || lower.contains('instagr.am')) {
      return 'instagram';
    }
    return null;
  }

  String? _extractBestMp4(String html) {
    // ابحث عن روابط mp4 مباشرة
    final regex = RegExp(
      r'https?://[^\s"<>]+\.mp4[^\s"<>]*',
      caseSensitive: false,
    );
    final matches = regex.allMatches(html).toList();
    if (matches.isEmpty) return null;

    // فضّل الروابط التي تحتوي على "no_watermark" أو "hd"
    for (final m in matches) {
      final u = m.group(0)!;
      if (u.contains('no_watermark') || u.contains('hd') || u.contains('HD')) {
        return u.replaceAll('\\u0026', '&').replaceAll('\\/', '/');
      }
    }
    return matches.first
        .group(0)!
        .replaceAll('\\u0026', '&')
        .replaceAll('\\/', '/');
  }

  // ─── تحميل الفيديو ────────────────────────────────────────────────────────

  /// تحميل الفيديو مع تقرير التقدم
  Future<File?> downloadVideo(
    String url,
    String quality, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/dndn');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final savePath = '${downloadDir.path}/$fileName';

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 15),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
              'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
              'Mobile/15E148 Safari/604.1',
          'Accept': '*/*',
          'Accept-Encoding': 'identity',
          'Connection': 'keep-alive',
        },
      ));

      await dio.download(
        url,
        savePath,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      final file = File(savePath);
      if (await file.exists() && await file.length() > 1000) {
        return file;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

// ─── نموذج النتيجة ────────────────────────────────────────────────────────────
class VideoResult {
  final String url;
  final String quality;
  final String source;

  const VideoResult({
    required this.url,
    required this.quality,
    required this.source,
  });
}