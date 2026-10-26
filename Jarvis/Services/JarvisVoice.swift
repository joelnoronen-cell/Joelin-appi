import AVFoundation
import Observation

/// Jarvis' speaking voice. Prefers the best installed voice for the chosen
/// accent – a British voice by default, as any proper butler AI should.
@MainActor
@Observable
final class JarvisVoice {
    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeechDelegate()

    init() {
        synthesizer.delegate = delegate
        delegate.onFinish = { [weak self] in
            self?.didFinish()
        }
    }

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        utterance.pitchMultiplier = 0.96
        utterance.preUtteranceDelay = 0.05
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        didFinish()
    }

    private func didFinish() {
        guard !synthesizer.isSpeaking else { return }
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let language = UserDefaults.standard.string(forKey: SettingsKey.voiceAccent) ?? "en-GB"
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
            var score = 0
            switch voice.quality {
            case .premium: score += 20
            case .enhanced: score += 10
            default: break
            }
            if voice.gender == .male { score += 5 }
            return score
        }
        return candidates.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: language)
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (@MainActor () -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        notify()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        notify()
    }

    private func notify() {
        let handler = onFinish
        Task { @MainActor in
            handler?()
        }
    }
}
