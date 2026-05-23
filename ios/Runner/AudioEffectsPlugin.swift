import AVFoundation
import Flutter
import UIKit

@objc class AudioEffectsPlugin: NSObject, FlutterPlugin {

    private var eqNode: AVAudioUnitEQ!
    private var engine = AVAudioEngine()
    private var isEnabled = false

    private let eqFrequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.mustami3.audio_effects",
            binaryMessenger: registrar.messenger()
        )
        let instance = AudioEffectsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.setupEngine()
    }

    private func setupEngine() {
        eqNode = AVAudioUnitEQ(numberOfBands: 10)
        for (i, freq) in eqFrequencies.enumerated() {
            let band = eqNode.bands[i]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0.0
            band.bypass = false
        }
        engine.attach(eqNode)
        engine.connect(eqNode, to: engine.mainMixerNode, format: nil)
        eqNode.bypass = true
        do {
            try engine.start()
        } catch {
            print("AudioEffectsPlugin error: \(error)")
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        // ── تفعيل / تعطيل ──
        case "setEnabled":
            if let enabled = call.arguments as? Bool {
                isEnabled = enabled
                eqNode.bypass = !enabled
            }
            result(nil)

        // ── ضبط نطاق واحد ──
        case "setBandLevel":
            guard let args = call.arguments as? [String: Any],
                  let band = args["band"] as? Int,
                  let level = args["level"] as? Double,
                  band >= 0 && band < 10 else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            eqNode.bands[band].gain = Float(level)
            result(nil)

        // ── ضبط كل النطاقات دفعة واحدة ──
        case "setAllBands":
            guard let levels = call.arguments as? [Double], levels.count == 10 else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            for i in 0..<10 {
                eqNode.bands[i].gain = Float(levels[i])
            }
            result(nil)

        // ── Bass Boost ──
        case "setBassBoost":
            guard let args = call.arguments as? [String: Any],
                  let gain = args["gain"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            eqNode.bands[0].gain = Float(gain) * 0.6
            eqNode.bands[1].gain = Float(gain) * 0.9
            eqNode.bands[2].gain = Float(gain) * 0.5
            result(nil)

        // ── Vocal Boost ──
        case "setVocalBoost":
            guard let args = call.arguments as? [String: Any],
                  let gain = args["gain"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            eqNode.bands[4].gain = Float(gain) * 0.4
            eqNode.bands[5].gain = Float(gain) * 0.8
            eqNode.bands[6].gain = Float(gain) * 0.9
            eqNode.bands[7].gain = Float(gain) * 0.4
            result(nil)

        // ── Treble ──
        case "setTreble":
            guard let gain = call.arguments as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            eqNode.bands[7].gain = Float(gain) * 0.5
            eqNode.bands[8].gain = Float(gain) * 0.8
            eqNode.bands[9].gain = Float(gain) * 0.6
            result(nil)

        // ── Volume ──
        case "setVolume":
            guard let db = call.arguments as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            // تحويل dB إلى قيمة خطية (0.0 - 2.0)
            let linear = Float(pow(10.0, db / 20.0))
            engine.mainMixerNode.outputVolume = min(max(linear, 0), 2)
            result(nil)

        // ── Reset All ──
        case "resetAll":
            for i in 0..<10 {
                eqNode.bands[i].gain = 0.0
            }
            engine.mainMixerNode.outputVolume = 1.0
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}