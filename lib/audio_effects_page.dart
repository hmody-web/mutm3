// ═══════════════════════════════════════════════════════════════
//  audio_effects_page.dart
//  شاشة مؤثرات الصوت — تصميم مطابق لتطبيق xDL
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_effects_channel.dart';

// ── نموذج إعداد مسبق ──
class _Preset {
  final String name;
  final List<double> bands; // 10 قيم
  const _Preset(this.name, this.bands);
}

class AudioEffectsPage extends StatefulWidget {
  const AudioEffectsPage({super.key});

  @override
  State<AudioEffectsPage> createState() => _AudioEffectsPageState();
}

class _AudioEffectsPageState extends State<AudioEffectsPage> {
  final _fx = AudioEffectsChannel.instance;

  // ── حالة التفعيل ──
  bool _enabled = false;

  // ── المعادل 10 نطاقات ──
  final List<double> _bands = List.filled(10, 0.0);
  final List<String> _bandLabels = ['16K','8K','4K','2K','1K','500','250','125','62','31'];

  // ── تعزيز الجهير ──
  double _bassGain = 0;
  double _bassFreq = 110;
  double _deepBass = 0;

  // ── تعزيز الصوت ──
  double _vocalGain = 0;
  double _vocalFreq = 3000;

  // ── الطبقة العالية ──
  double _trebleGain = 0;

  // ── مستوى الصوت ──
  double _volume = 0;

  // ── الإعدادات المسبقة ──
  final List<_Preset> _presets = const [
    _Preset('افتراضي',   [0,0,0,0,0,0,0,0,0,0]),
    _Preset('باس قوي',   [0,0,0,0,-2,-3,0,3,5,6]),
    _Preset('صوت واضح',  [-2,-1,0,1,3,4,3,1,0,-1]),
    _Preset('روك',       [4,3,2,0,-1,-1,0,2,3,4]),
    _Preset('جاز',       [3,2,1,2,0,-1,0,1,2,3]),
    _Preset('كلاسيك',    [4,3,2,1,0,0,-1,2,3,4]),
    _Preset('بوب',       [0,1,2,3,2,0,-1,-1,0,0]),
    _Preset('إلكتروني',  [5,4,2,0,-2,-3,-1,2,4,5]),
  ];
  int _selectedPreset = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ── تحميل الإعدادات المحفوظة ──
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enabled    = prefs.getBool('fx_enabled')    ?? false;
      _bassGain   = prefs.getDouble('fx_bassGain') ?? 0;
      _bassFreq   = prefs.getDouble('fx_bassFreq') ?? 110;
      _deepBass   = prefs.getDouble('fx_deepBass') ?? 0;
      _vocalGain  = prefs.getDouble('fx_vocalGain')  ?? 0;
      _vocalFreq  = prefs.getDouble('fx_vocalFreq')  ?? 3000;
      _trebleGain = prefs.getDouble('fx_trebleGain') ?? 0;
      _volume     = prefs.getDouble('fx_volume')     ?? 0;
      for (int i = 0; i < 10; i++) {
        _bands[i] = prefs.getDouble('fx_band_$i') ?? 0;
      }
    });
    if (_enabled) _fx.setEnabled(true);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fx_enabled', _enabled);
    await prefs.setDouble('fx_bassGain',   _bassGain);
    await prefs.setDouble('fx_bassFreq',   _bassFreq);
    await prefs.setDouble('fx_deepBass',   _deepBass);
    await prefs.setDouble('fx_vocalGain',  _vocalGain);
    await prefs.setDouble('fx_vocalFreq',  _vocalFreq);
    await prefs.setDouble('fx_trebleGain', _trebleGain);
    await prefs.setDouble('fx_volume',     _volume);
    for (int i = 0; i < 10; i++) {
      await prefs.setDouble('fx_band_$i', _bands[i]);
    }
  }

  void _applyPreset(_Preset preset) {
    setState(() {
      for (int i = 0; i < 10; i++) {
        _bands[i] = preset.bands[i];
      }
    });
    _fx.setAllBands(_bands);
    _saveSettings();
  }

  void _resetEQ() {
    setState(() {
      for (int i = 0; i < 10; i++) _bands[i] = 0;
      _selectedPreset = 0;
    });
    _fx.setAllBands(_bands);
    _saveSettings();
  }

  // ── ألوان حسب الثيم ──
  Color get _bg       => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF0D0D0D) : const Color(0xFFF2F2F7);
  Color get _card     => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1C1C1E) : Colors.white;
  Color get _text     => Theme.of(context).brightness == Brightness.dark
      ? Colors.white : const Color(0xFF1A1A1A);
  Color get _subText  => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF8E8E93) : const Color(0xFF6B6B6B);
  Color get _accent   => const Color(0xFFE8272A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  children: [
                    _buildPresetsRow(),
                    const SizedBox(height: 12),
                    _buildEQSection(),
                    const SizedBox(height: 12),
                    _buildBassSection(),
                    const SizedBox(height: 12),
                    _buildVocalSection(),
                    const SizedBox(height: 12),
                    _buildTrebleSection(),
                    const SizedBox(height: 12),
                    _buildVolumeSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  //  HEADER
  // ══════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          // زر الإغلاق
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _card,
                shape: BoxShape.circle,
              ),
              child: Icon(CupertinoIcons.xmark, size: 16, color: _subText),
            ),
          ),
          const Spacer(),
          // العنوان
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: _text, size: 22),
              const SizedBox(width: 8),
              Text('مؤثرات الصوت',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
              ),
            ],
          ),
          const Spacer(),
          // مفتاح التفعيل
          CupertinoSwitch(
            value: _enabled,
            activeColor: _accent,
            onChanged: (v) {
              setState(() => _enabled = v);
              _fx.setEnabled(v);
              _saveSettings();
            },
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  //  PRESETS ROW
  // ══════════════════════════════════════
  Widget _buildPresetsRow() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = _selectedPreset == i;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedPreset = i);
              _applyPreset(_presets[i]);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected ? _accent : _card,
                borderRadius: BorderRadius.circular(20),
                border: selected ? null : Border.all(
                  color: _subText.withOpacity(0.2), width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _presets[i].name,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : _subText,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════
  //  EQ SECTION
  // ══════════════════════════════════════
  Widget _buildEQSection() {
    return _buildCard(
      icon: Icons.graphic_eq_rounded,
      title: 'المعادل',
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // محاور Y
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['12+', '0', '12-'].map((l) => Text(l,
                      style: TextStyle(fontSize: 9, color: _subText, fontFamily: 'Tajawal'),
                    )).toList(),
                  ),
                ),
                // الأشرطة
                Expanded(
                  child: Row(
                    children: List.generate(10, (i) {
                      return Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 7),
                                    overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 14),
                                    activeTrackColor: _enabled
                                        ? _accent
                                        : _subText.withOpacity(0.5),
                                    inactiveTrackColor: _subText.withOpacity(0.2),
                                    thumbColor: _enabled ? Colors.white : _subText,
                                  ),
                                  child: Slider(
                                    value: _bands[i],
                                    min: -12, max: 12,
                                    onChanged: _enabled ? (v) {
                                      setState(() => _bands[i] = v);
                                      _fx.setBandLevel(i, v);
                                      _saveSettings();
                                    } : null,
                                  ),
                                ),
                              ),
                            ),
                            Text(_bandLabels[i],
                              style: TextStyle(
                                fontSize: 9,
                                fontFamily: 'Tajawal',
                                color: _subText,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _enabled ? _resetEQ : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _enabled
                    ? _subText.withOpacity(0.12)
                    : _subText.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text('إعادة تعيين المعادل',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _enabled ? _text : _subText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  //  BASS SECTION
  // ══════════════════════════════════════
  Widget _buildBassSection() {
    return _buildCard(
      icon: CupertinoIcons.speaker_3_fill,
      title: 'تعزيز الجهير',
      child: Column(
        children: [
          _buildSlider(
            label: 'الكسب',
            value: _bassGain,
            min: 0, max: 30,
            unit: 'dB',
            showPlus: true,
            onChanged: (v) {
              setState(() => _bassGain = v);
              _fx.setBassBoost(gain: v, freq: _bassFreq);
              _saveSettings();
            },
          ),
          _buildSlider(
            label: 'التردد',
            value: _bassFreq,
            min: 50, max: 300,
            unit: 'Hz',
            onChanged: (v) {
              setState(() => _bassFreq = v);
              _fx.setBassBoost(gain: _bassGain, freq: v);
              _saveSettings();
            },
          ),
          _buildSlider(
            label: 'جهير عميق',
            value: _deepBass,
            min: -12, max: 12,
            unit: 'dB',
            showPlus: true,
            onChanged: (v) {
              setState(() => _deepBass = v);
              _saveSettings();
            },
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  //  VOCAL SECTION
  // ══════════════════════════════════════
  Widget _buildVocalSection() {
    return _buildCard(
      icon: CupertinoIcons.mic_fill,
      title: 'تعزيز الصوت',
      child: Column(
        children: [
          _buildSlider(
            label: 'الكسب',
            value: _vocalGain,
            min: 0, max: 12,
            unit: 'dB',
            showPlus: true,
            onChanged: (v) {
              setState(() => _vocalGain = v);
              _fx.setVocalBoost(gain: v, freq: _vocalFreq);
              _saveSettings();
            },
          ),
          _buildSlider(
            label: 'تردد الصوت',
            value: _vocalFreq,
            min: 500, max: 8000,
            unit: 'Hz',
            onChanged: (v) {
              setState(() => _vocalFreq = v);
              _fx.setVocalBoost(gain: _vocalGain, freq: v);
              _saveSettings();
            },
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  //  TREBLE SECTION
  // ══════════════════════════════════════
  Widget _buildTrebleSection() {
    return _buildCard(
      icon: CupertinoIcons.music_note,
      title: 'الطبقة العالية',
      child: _buildSlider(
        label: 'الكسب',
        value: _trebleGain,
        min: -12, max: 12,
        unit: 'dB',
        showPlus: true,
        onChanged: (v) {
          setState(() => _trebleGain = v);
          _fx.setTreble(v);
          _saveSettings();
        },
      ),
    );
  }

  // ══════════════════════════════════════
  //  VOLUME SECTION
  // ══════════════════════════════════════
  Widget _buildVolumeSection() {
    return _buildCard(
      icon: CupertinoIcons.volume_up,
      title: 'مستوى الصوت والعلو',
      child: _buildSlider(
        label: 'مستوى الصوت',
        value: _volume,
        min: -12, max: 12,
        unit: 'dB',
        showPlus: true,
        onChanged: (v) {
          setState(() => _volume = v);
          _fx.setVolume(v);
          _saveSettings();
        },
      ),
    );
  }

  // ══════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════

  Widget _buildCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(icon, color: _text, size: 18),
              const SizedBox(width: 8),
              Text(title,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
    bool showPlus = false,
  }) {
    final displayVal = value.round();
    final valStr = showPlus && displayVal >= 0
        ? '$unit ${displayVal}+'
        : '$unit $displayVal';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Badge القيمة
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _enabled
                      ? _accent.withOpacity(0.12)
                      : _subText.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _enabled
                        ? _accent.withOpacity(0.3)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Text(valStr,
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _enabled ? _accent : _subText,
                  ),
                ),
              ),
              Text(label,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 14,
                  color: _subText,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: _enabled ? _accent : _subText.withOpacity(0.4),
              inactiveTrackColor: _subText.withOpacity(0.15),
              thumbColor: _enabled ? Colors.white : _subText,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: _enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}