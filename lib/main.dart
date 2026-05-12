import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ─────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.mustami3.audio',
    androidNotificationChannelName: 'مستمع',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light,
  ));

  runApp(const Mustami3App());
}

// ─────────────────────────────────────────────
//  THEME & CONSTANTS
// ─────────────────────────────────────────────
class AppColors {
  static const Color primary = Color(0xFFE8272A);
  static const Color primaryDark = Color(0xFFB71C1C);
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7F7F7);
  static const Color surfaceAlt = Color(0xFFF0F0F0);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color divider = Color(0xFFE0E0E0);
  static const Color redLight = Color(0xFFFFEBEB);
}

// ─────────────────────────────────────────────
//  GLOBAL AUDIO PLAYER SERVICE
// ─────────────────────────────────────────────
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer player = AudioPlayer();
  final ValueNotifier<List<MediaItem>> playlist = ValueNotifier([]);
  final ValueNotifier<int> currentIndex = ValueNotifier(0);

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  Future<void> playFile(String path, {String? title, String? artist}) async {
    try {
      final tag = MediaItem(
        id: path,
        title: title ?? path.split('/').last,
        artist: artist ?? 'مستمع',
      );
      await player.setAudioSource(AudioSource.file(path, tag: tag));
      await player.play();
    } catch (e) {
      debugPrint('Error playing file: $e');
    }
  }

  Future<void> playList(List<MediaItem> items, int index) async {
    try {
      playlist.value = items;
      currentIndex.value = index;
      final sources =
          items.map((item) => AudioSource.file(item.id, tag: item)).toList();
      await player.setAudioSource(ConcatenatingAudioSource(children: sources));
      await player.seek(Duration.zero, index: index);
      await player.play();
    } catch (e) {
      debugPrint('Error playing list: $e');
    }
  }

  void dispose() {
    player.dispose();
  }
}

final audioService = AudioPlayerService();

// ─────────────────────────────────────────────
//  APP ROOT
// ─────────────────────────────────────────────
class Mustami3App extends StatelessWidget {
  const Mustami3App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مستمع',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'SF Pro Display',
        useMaterial3: true,
      ),
      home: const MainShell(),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  MAIN SHELL — Bottom Nav
// ─────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    audioService.init();
    _pages = const [
      ListenPage(),
      BrowsePage(),
      SettingsPage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: const Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _navItem(0, CupertinoIcons.music_note_list, 'استمع'),
              _navItem(1, CupertinoIcons.compass, 'تصفح'),
              _navItem(2, CupertinoIcons.settings, 'إعدادات'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.redLight
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                size: 22,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PAGE 1 — استمع (Listen)
// ═══════════════════════════════════════════════════════════
class ListenPage extends StatefulWidget {
  const ListenPage({super.key});

  @override
  State<ListenPage> createState() => _ListenPageState();
}

class _ListenPageState extends State<ListenPage> {
  List<FileSystemEntity> _localFiles = [];
  String _downloadDir = '';

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${dir.path}/Mustami3');
    if (!await musicDir.exists()) await musicDir.create(recursive: true);
    setState(() {
      _downloadDir = musicDir.path;
      _localFiles = musicDir.listSync()
        ..sort((a, b) =>
            b.statSync().modified.compareTo(a.statSync().modified));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildHeader(),
          _buildNowPlaying(),
          _buildFileList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16,
          left: 20,
          right: 20,
          bottom: 8,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(CupertinoIcons.music_note,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'مستمع',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _loadFiles,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(CupertinoIcons.refresh,
                    size: 18, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNowPlaying() {
    return SliverToBoxAdapter(
      child: StreamBuilder<ProcessingState>(
        stream: audioService.player.processingStateStream,
        builder: (context, snapshot) {
          final isActive = audioService.player.playing ||
              (snapshot.data == ProcessingState.ready);
          if (!isActive) return const SizedBox.shrink();
          return _NowPlayingCard();
        },
      ),
    );
  }

  Widget _buildFileList() {
    if (_localFiles.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.redLight,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(CupertinoIcons.music_note_2,
                    size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              const Text(
                'لا توجد ملفات بعد',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'حمّل مقاطع من تبويب تصفح',
                style: TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final file = _localFiles[index];
            final name = file.path.split('/').last;
            final isVideo = name.endsWith('.mp4') ||
                name.endsWith('.webm') ||
                name.endsWith('.mkv');
            final isAudio = name.endsWith('.mp3') ||
                name.endsWith('.m4a') ||
                name.endsWith('.aac') ||
                name.endsWith('.opus');

            return _MediaTile(
              name: name,
              path: file.path,
              isVideo: isVideo,
              onTap: () {
                if (isAudio || isVideo) {
                  audioService.playFile(file.path, title: name);
                }
              },
              onDelete: () async {
                await File(file.path).delete();
                _loadFiles();
              },
            );
          },
          childCount: _localFiles.length,
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final String name;
  final String path;
  final bool isVideo;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MediaTile({
    required this.name,
    required this.path,
    required this.isVideo,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.redLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isVideo
                ? CupertinoIcons.play_rectangle_fill
                : CupertinoIcons.music_note,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          isVideo ? 'فيديو' : 'صوت',
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: GestureDetector(
          onTap: onDelete,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(CupertinoIcons.trash,
                size: 16, color: Colors.red),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _NowPlayingCard extends StatefulWidget {
  @override
  State<_NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<_NowPlayingCard> {
  @override
  Widget build(BuildContext context) {
    final player = audioService.player;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'يُشغَّل الآن',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          StreamBuilder(
            stream: player.sequenceStateStream,
            builder: (context, snapshot) {
              final tag =
                  snapshot.data?.currentSource?.tag as MediaItem?;
              return Text(
                tag?.title ?? 'غير معروف',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<Duration?>(
            stream: player.durationStream,
            builder: (context, durationSnap) {
              return StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, posSnap) {
                  final duration =
                      durationSnap.data ?? Duration.zero;
                  final position = posSnap.data ?? Duration.zero;
                  final progress =
                      duration.inMilliseconds > 0
                          ? position.inMilliseconds /
                              duration.inMilliseconds
                          : 0.0;
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: Colors.white24,
                          valueColor:
                              const AlwaysStoppedAnimation(Colors.white),
                          minHeight: 3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(position),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                          Text(_fmt(duration),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _controlBtn(CupertinoIcons.backward_fill,
                  () => player.seekToPrevious()),
              const SizedBox(width: 24),
              StreamBuilder<bool>(
                stream: player.playingStream,
                builder: (context, snap) {
                  final isPlaying = snap.data ?? false;
                  return GestureDetector(
                    onTap: () =>
                        isPlaying ? player.pause() : player.play(),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Icon(
                        isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        color: AppColors.primary,
                        size: 26,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 24),
              _controlBtn(CupertinoIcons.forward_fill,
                  () => player.seekToNext()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ═══════════════════════════════════════════════════════════
//  PAGE 2 — تصفح (Browse)
// ═══════════════════════════════════════════════════════════
class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
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
                'تصفح',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _BrowseCard(
                  icon: CupertinoIcons.play_rectangle_fill,
                  title: 'يوتيوب',
                  subtitle: 'ابحث وشاهد وحمّل الفيديوهات والأصوات',
                  color: AppColors.primary,
                  bgColor: AppColors.redLight,
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                          builder: (_) => const YouTubeSearchPage()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _BrowseCard(
                  icon: CupertinoIcons.folder_fill,
                  title: 'الملفات',
                  subtitle: 'استعرض الملفات المحلية على جهازك',
                  color: const Color(0xFF2563EB),
                  bgColor: const Color(0xFFEFF6FF),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                          builder: (_) => const LocalFilesPage()),
                    );
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _BrowseCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_left, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  YOUTUBE SEARCH PAGE  (الصفحة الرئيسية للبحث)
// ═══════════════════════════════════════════════════════════
class YouTubeSearchPage extends StatefulWidget {
  const YouTubeSearchPage({super.key});

  @override
  State<YouTubeSearchPage> createState() => _YouTubeSearchPageState();
}

class _YouTubeSearchPageState extends State<YouTubeSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final YoutubeExplode _yt = YoutubeExplode();
  List<Video> _results = [];
  bool _isSearching = false;
  String _query = '';

  // ── Popular categories for home screen ──
  final List<Map<String, String>> _categories = [
    {'label': 'موسيقى', 'query': 'أغاني عربية 2024'},
    {'label': 'بودكاست', 'query': 'بودكاست عربي'},
    {'label': 'قرآن كريم', 'query': 'قرآن كريم تلاوة'},
    {'label': 'رياضة', 'query': 'ملخصات كرة القدم'},
    {'label': 'تعليم', 'query': 'تعليم ودروس'},
    {'label': 'أخبار', 'query': 'أخبار اليوم'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _yt.close();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _query = query;
      _results = [];
    });
    try {
      final searchList = await _yt.search.search(query);
      setState(() {
        _results = searchList.whereType<Video>().take(20).toList();
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في البحث: $e',
                textDirection: TextDirection.rtl),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openVideo(Video video) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => YouTubePlayerPage(video: video),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar ──
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(
                  bottom: BorderSide(color: AppColors.divider, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(CupertinoIcons.xmark,
                          size: 18, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // YouTube logo area
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
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
                                fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Search Bar ──
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.divider, width: 0.5),
                      ),
                      child: TextField(
                        controller: _searchController,
                        textDirection: TextDirection.rtl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _search,
                        decoration: const InputDecoration(
                          hintText: 'ابحث عن فيديو...',
                          hintStyle: TextStyle(
                              color: AppColors.textSecondary, fontSize: 14),
                          prefixIcon: Icon(CupertinoIcons.search,
                              color: AppColors.textSecondary, size: 18),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => _search(_searchController.text),
                    child: Container(
                      height: 46,
                      width: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(CupertinoIcons.search,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ──
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    )
                  : _results.isEmpty
                      ? _buildHomeCategories()
                      : _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeCategories() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'اكتشف',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
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
                    color: AppColors.redLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.2),
                        width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    cat['label']!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Icon(CupertinoIcons.search,
                    size: 48, color: AppColors.divider),
                const SizedBox(height: 12),
                const Text(
                  'ابحث عن أي فيديو يوتيوب',
                  style: TextStyle(
                      fontSize: 15, color: AppColors.textSecondary),
                ),
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
        return _VideoResultCard(
          video: video,
          onTap: () => _openVideo(video),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  Video Result Card
// ─────────────────────────────────────────────
class _VideoResultCard extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;

  const _VideoResultCard({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbnails.mediumResUrl;
    final duration = video.duration;
    final durationStr = duration != null
        ? '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}'
        : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: Stack(
                children: [
                  Image.network(
                    thumb,
                    width: 120,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 120,
                      height: 80,
                      color: AppColors.surfaceAlt,
                      child: const Icon(CupertinoIcons.play_rectangle_fill,
                          color: AppColors.textSecondary),
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
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          durationStr,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info
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
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      video.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.redLight,
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  YOUTUBE PLAYER PAGE  (صفحة مشاهدة الفيديو + تحميل)
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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showDownloadOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DownloadSheet(
        videoId: widget.video.id.value,
        videoTitle: widget.video.title,
        onDownload: _download,
      ),
    );
  }

  Future<void> _download(
      String videoId, String quality, bool audioOnly) async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadStatus = 'جاري التحضير...';
    });

    try {
      final yt = YoutubeExplode();
      final dir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${dir.path}/Mustami3');
      if (!await musicDir.exists()) await musicDir.create(recursive: true);

      final manifest =
          await yt.videos.streamsClient.getManifest(videoId);
      final video = await yt.videos.get(videoId);
      final safeTitle =
          video.title.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF-]'), '').trim();

      setState(() => _downloadStatus = 'جاري التحميل...');

      Stream<List<int>> stream;
      String fileName;
      int totalBytes = 0;

      if (audioOnly) {
        final audio = manifest.audioOnly.withHighestBitrate();
        totalBytes = audio.size.totalBytes;
        stream = yt.videos.streamsClient.get(audio);
        fileName = '$safeTitle.m4a';
      } else {
        final muxed = manifest.muxed;
        final chosen = quality == 'high'
            ? muxed.withHighestBitrate()
            : muxed.firstWhere(
                (s) => s.videoQuality.name.contains('360'),
                orElse: () => muxed.last,
              );
        totalBytes = chosen.size.totalBytes;
        stream = yt.videos.streamsClient.get(chosen);
        fileName = '$safeTitle.mp4';
      }

      final file = File('${musicDir.path}/$fileName');
      final sink = file.openWrite();
      int downloaded = 0;

      await for (final chunk in stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (totalBytes > 0) {
          setState(() {
            _downloadProgress = downloaded / totalBytes;
            _downloadStatus =
                'جاري التحميل... ${(_downloadProgress * 100).toStringAsFixed(0)}%';
          });
        }
      }

      await sink.flush();
      await sink.close();
      yt.close();

      setState(() {
        _isDownloading = false;
        _downloadStatus = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم التحميل: $fileName',
                textDirection: TextDirection.rtl),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadStatus = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل التحميل: $e',
                textDirection: TextDirection.rtl),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(CupertinoIcons.xmark,
                  color: AppColors.textPrimary),
            ),
            title: const Text(
              'مشاهدة الفيديو',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            actions: [
              // Download Button
              GestureDetector(
                onTap: _isDownloading ? null : _showDownloadOptions,
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
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
                            Text(
                              'تحميل',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── YouTube Player ──
              player,

              // ── Download Progress Bar ──
              if (_isDownloading)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  color: AppColors.redLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _downloadStatus,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _downloadProgress > 0
                              ? _downloadProgress
                              : null,
                          backgroundColor: Colors.white,
                          valueColor: const AlwaysStoppedAnimation(
                              AppColors.primary),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Video Info ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.video.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.redLight,
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
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500),
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        ],
                      ),
                      if (widget.video.description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(color: AppColors.divider),
                        const SizedBox(height: 8),
                        const Text(
                          'الوصف',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.video.description,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.5),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                      const SizedBox(height: 80),
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
//  Download Bottom Sheet
// ─────────────────────────────────────────────
class _DownloadSheet extends StatefulWidget {
  final String videoId;
  final String videoTitle;
  final Function(String, String, bool) onDownload;

  const _DownloadSheet({
    required this.videoId,
    required this.videoTitle,
    required this.onDownload,
  });

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  StreamManifest? _manifest;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchManifest();
  }

  Future<void> _fetchManifest() async {
    try {
      final yt = YoutubeExplode();
      final manifest =
          await yt.videos.streamsClient.getManifest(widget.videoId);
      yt.close();
      if (mounted) {
        setState(() {
          _manifest = manifest;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Icon + title
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.redLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(CupertinoIcons.cloud_download_fill,
                color: AppColors.primary, size: 28),
          ),
          const SizedBox(height: 12),
          const Text(
            'خيارات التحميل',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            widget.videoTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            )
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'حدث خطأ أثناء جلب معلومات الفيديو.\nتأكد من الاتصال بالإنترنت وحاول مرة أخرى.',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            )
          else ...[
            _downloadBtn(
              icon: '🎵',
              label: 'صوت فقط (جودة عالية)',
              subtitle: 'تنزيل الصوت بصيغة m4a',
              onTap: () {
                Navigator.pop(context);
                widget.onDownload(widget.videoId, 'high', true);
              },
            ),
            const SizedBox(height: 10),
            _downloadBtn(
              icon: '📹',
              label: 'فيديو جودة عالية',
              subtitle: 'أعلى جودة متاحة',
              onTap: () {
                Navigator.pop(context);
                widget.onDownload(widget.videoId, 'high', false);
              },
            ),
            const SizedBox(height: 10),
            _downloadBtn(
              icon: '📱',
              label: 'فيديو 360p',
              subtitle: 'جودة متوسطة - حجم أصغر',
              onTap: () {
                Navigator.pop(context);
                widget.onDownload(widget.videoId, 'medium', false);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _downloadBtn({
    required String icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_left,
                size: 14, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Local Files Page
// ─────────────────────────────────────────────
class LocalFilesPage extends StatefulWidget {
  const LocalFilesPage({super.key});

  @override
  State<LocalFilesPage> createState() => _LocalFilesPageState();
}

class _LocalFilesPageState extends State<LocalFilesPage> {
  Future<void> _pickAndPlay() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;
      await audioService.playFile(path, title: name);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.xmark,
              color: AppColors.textPrimary),
        ),
        title: const Text(
          'الملفات',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(CupertinoIcons.folder_fill,
                    size: 52, color: Color(0xFF2563EB)),
              ),
              const SizedBox(height: 24),
              const Text(
                'اختر ملفاً للتشغيل',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'يمكنك تشغيل ملفات الصوت والفيديو من تخزين جهازك',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: _pickAndPlay,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
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
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PAGE 3 — إعدادات (Settings)
// ═══════════════════════════════════════════════════════════
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _backgroundPlay = true;
  bool _stopOnClose = false;
  String _downloadQuality = 'high';
  String _downloadPath = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationDocumentsDirectory();
    setState(() {
      _backgroundPlay = prefs.getBool('backgroundPlay') ?? true;
      _stopOnClose = prefs.getBool('stopOnClose') ?? false;
      _downloadQuality = prefs.getString('downloadQuality') ?? 'high';
      _downloadPath = '${dir.path}/Mustami3';
    });
  }

  Future<void> _savePref(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
  }

  Future<void> _clearDownloads() async {
    final dir = Directory(_downloadPath);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        await entity.delete();
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم حذف جميع التنزيلات',
              textDirection: TextDirection.rtl),
          backgroundColor: AppColors.textPrimary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
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
                'الإعدادات',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // App info card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.music_note_2,
                          color: Colors.white, size: 32),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('مستمع',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700)),
                          Text('الإصدار 2.0.0',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _settingsSection('التشغيل', [
                  _switchTile(
                    'التشغيل في الخلفية',
                    'يبقى يعمل عند إغلاق التطبيق',
                    CupertinoIcons.play_circle_fill,
                    _backgroundPlay,
                    (v) {
                      setState(() => _backgroundPlay = v);
                      _savePref('backgroundPlay', v);
                    },
                  ),
                  _switchTile(
                    'إيقاف عند الإغلاق',
                    'يتوقف عند إغلاق شاشة التطبيق',
                    CupertinoIcons.stop_circle_fill,
                    _stopOnClose,
                    (v) {
                      setState(() => _stopOnClose = v);
                      _savePref('stopOnClose', v);
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                _settingsSection('التحميل', [
                  _infoTile(
                      'مسار التحميل',
                      _downloadPath.split('/').last,
                      CupertinoIcons.folder_fill),
                  _qualityTile(),
                ]),
                const SizedBox(height: 16),
                _settingsSection('الإدارة', [
                  _actionTile(
                    'حذف جميع التنزيلات',
                    'مسح كل الملفات المحملة',
                    CupertinoIcons.trash_fill,
                    Colors.red,
                    _clearDownloads,
                  ),
                ]),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider, width: 0.5),
          ),
          child: Column(
            children: children.map((child) {
              final index = children.indexOf(child);
              return Column(
                children: [
                  child,
                  if (index < children.length - 1)
                    const Divider(
                        height: 1,
                        color: AppColors.divider,
                        indent: 16,
                        endIndent: 16),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _switchTile(String title, String subtitle, IconData icon,
      bool value, Function(bool) onChanged) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.redLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
      trailing: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }

  Widget _infoTile(String title, String value, IconData icon) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.redLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary)),
      trailing: Text(value,
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary)),
    );
  }

  Widget _qualityTile() {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.redLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(CupertinoIcons.dial_fill,
            color: AppColors.primary, size: 18),
      ),
      title: const Text('جودة التحميل',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary)),
      trailing: CupertinoSlidingSegmentedControl<String>(
        groupValue: _downloadQuality,
        thumbColor: AppColors.primary,
        children: const {
          'high': Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('عالية', style: TextStyle(fontSize: 11))),
          'medium': Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('متوسطة', style: TextStyle(fontSize: 11))),
        },
        onValueChanged: (v) {
          if (v != null) {
            setState(() => _downloadQuality = v);
            _savePref('downloadQuality', v);
          }
        },
      ),
    );
  }

  Widget _actionTile(String title, String subtitle, IconData icon,
      Color color, VoidCallback onTap) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
      onTap: onTap,
    );
  }
}