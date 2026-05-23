// ═══════════════════════════════════════════════════════════════
//  audio_effects_channel.dart
//  الجسر بين Flutter و Swift Plugin
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/services.dart';

class AudioEffectsChannel {
  static const _channel = MethodChannel('com.mustami3.audio_effects');

  // Singleton
  static final AudioEffectsChannel instance = AudioEffectsChannel._();
  AudioEffectsChannel._();

  // ── تفعيل/تعطيل المؤثرات ──
  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setEnabled', enabled);
    } catch (_) {}
  }

  // ── ضبط نطاق واحد في المعادل (-12 إلى +12 dB) ──
  Future<void> setBandLevel(int band, double level) async {
    try {
      await _channel.invokeMethod('setBandLevel', {'band': band, 'level': level});
    } catch (_) {}
  }

  // ── ضبط كل نطاقات المعادل دفعة واحدة ──
  Future<void> setAllBands(List<double> levels) async {
    try {
      await _channel.invokeMethod('setAllBands', levels);
    } catch (_) {}
  }

  // ── تعزيز الجهير ──
  Future<void> setBassBoost({required double gain, required double freq}) async {
    try {
      await _channel.invokeMethod('setBassBoost', {'gain': gain, 'freq': freq});
    } catch (_) {}
  }

  // ── تعزيز الصوت ──
  Future<void> setVocalBoost({required double gain, required double freq}) async {
    try {
      await _channel.invokeMethod('setVocalBoost', {'gain': gain, 'freq': freq});
    } catch (_) {}
  }

  // ── الطبقة العالية ──
  Future<void> setTreble(double gain) async {
    try {
      await _channel.invokeMethod('setTreble', gain);
    } catch (_) {}
  }

  // ── مستوى الصوت (-12 إلى +12 dB) ──
  Future<void> setVolume(double db) async {
    try {
      await _channel.invokeMethod('setVolume', db);
    } catch (_) {}
  }

  // ── إعادة تعيين الكل ──
  Future<void> resetAll() async {
    try {
      await _channel.invokeMethod('resetAll');
    } catch (_) {}
  }
}