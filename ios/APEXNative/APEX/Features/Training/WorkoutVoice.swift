import AVFoundation
import CryptoKit
import Foundation

/// One piece of a spoken line: a recorded clip when the app has it, otherwise the phone's own voice says `fallback`.
struct VoicePart: Equatable {
    let clip: URL?
    let fallback: String

    /// A line recorded for every language (`Tools/workout-voice/lines.mjs`), e.g. `count.3` or `set.set.2.4`.
    @MainActor
    static func line(_ id: String, fallback: String) -> VoicePart {
        let language = LanguageState.shared.language.rawValue
        return VoicePart(clip: Bundle.main.url(forResource: id, withExtension: "m4a", subdirectory: "WorkoutVoice/\(language)"),
                         fallback: fallback)
    }

    /// An exercise name, once its clip has been downloaded to this phone.
    @MainActor
    static func exercise(spoken: String) -> VoicePart {
        let file = WorkoutVoiceNames.file(spoken: spoken, language: LanguageState.shared.language.rawValue)
        return VoicePart(clip: FileManager.default.fileExists(atPath: file.path) ? file : nil, fallback: spoken)
    }

    /// The recorded call for this set, when one exists: "Set 2 of 4", "Round 1 of 3", "Hold 3 of 3".
    @MainActor
    static func setCall(noun: String, number: Int, total: Int, fallback: String) -> VoicePart {
        let known = ["set", "hold", "round", "exercise"].contains(noun) && (1...total).contains(number) && total <= 10
        return known ? line("set.\(noun).\(number).\(total)", fallback: fallback) : VoicePart(clip: nil, fallback: fallback)
    }
}

/// Exercise names are voiced once by the `workout-voice` server function and kept on this phone, so the
/// gym needs no signal. Names in a workout are fetched when it opens.
enum WorkoutVoiceNames {
    static func file(spoken: String, language: String) -> URL {
        let digest = SHA256.hash(data: Data("\(language)|\(spoken)".utf8)).map { String(format: "%02x", $0) }.joined()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "WorkoutVoice/\(language)/\(digest.prefix(32)).mp3")
    }

    /// Fetches the names this phone does not have yet, one at a time; a name that fails is tried next time.
    static func prefetch(_ names: [(name: String, spoken: String)], language: String) async {
        var seen = Set<String>()
        for entry in names where seen.insert(entry.spoken).inserted {
            let destination = file(spoken: entry.spoken, language: language)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            guard let data = try? await SupabaseService.shared.workoutVoiceClip(name: entry.name, spoken: entry.spoken, language: language),
                  !data.isEmpty else { continue }
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: destination, options: .atomic)
        }
    }
}

/// The rep beep and the spoken lines share one audio session and one engine, so they mix instead of ducking
/// each other. Only other apps' music is lowered while the workout talks.
@MainActor
final class WorkoutAudioCoach: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = WorkoutAudioCoach()
    private let speaker = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let tickPlayer = AVAudioPlayerNode()
    private let voicePlayer = AVAudioPlayerNode()
    private var tickBuffer: AVAudioPCMBuffer?
    private var format: AVAudioFormat?
    private var sessionActive = false
    private var queue: [VoicePart] = []
    /// Bumped by every stop, so a clip or sentence finishing late cannot start the next part of an old line.
    private var generation = 0
    private var completion: (@MainActor () -> Void)?
    private var speaking: ObjectIdentifier?

    override private init() {
        super.init()
        speaker.delegate = self
        engine.attach(tickPlayer)
        engine.attach(voicePlayer)
        // A fixed format: the hardware's can read 0 Hz before the session is set up, and connecting to that traps.
        // The recorded clips are made at this rate in mono.
        if let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) {
            self.format = format
            engine.connect(tickPlayer, to: engine.mainMixerNode, format: format)
            engine.connect(voicePlayer, to: engine.mainMixerNode, format: format)
            tickBuffer = Self.tick(format: format)
        }
        tickPlayer.volume = 0.55
    }

    /// Starts with the first word or beep, so a muted coach never lowers anyone's music; it then holds for the
    /// whole workout, so music is lowered once, not per rep.
    private func begin() {
        if !sessionActive {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            sessionActive = (try? session.setActive(true)) != nil
        }
        if !engine.isRunning { try? engine.start() }
    }

    /// Called when the player closes: other apps' audio comes back to full volume.
    func end() {
        stop()
        tickPlayer.stop()
        engine.stop()
        guard sessionActive else { return }
        sessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func tick() {
        guard let tickBuffer else { return }
        // A call or another app can stop the engine; the next rep picks it back up.
        if !engine.isRunning { begin() }
        guard engine.isRunning else { return }
        tickPlayer.scheduleBuffer(tickBuffer, at: nil, options: .interrupts)
        if !tickPlayer.isPlaying { tickPlayer.play() }
    }

    /// A short, soft-edged click: two tones that decay in 60 ms, quiet enough to sit under the voice.
    private static func tick(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        guard rate > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * 0.06)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = buffer.frameCapacity
        for frame in 0 ..< Int(buffer.frameLength) {
            let t = Double(frame) / rate
            let envelope = min(1, t / 0.002) * exp(-t * 70)
            let value = Float(envelope * (0.7 * sin(2 * .pi * 1_760 * t) + 0.3 * sin(2 * .pi * 2_640 * t)) * 0.8)
            for channel in 0 ..< Int(format.channelCount) { channels[channel][frame] = value }
        }
        return buffer
    }

    func stop() {
        generation += 1
        queue = []
        completion = nil
        speaking = nil
        voicePlayer.stop()
        speaker.stopSpeaking(at: .immediate)
    }

    /// Speaks the parts in order with a breath between them, then calls `onFinished`.
    func speak(_ parts: [VoicePart], enabled: Bool, onFinished: (@MainActor () -> Void)? = nil) {
        stop()
        guard enabled, !parts.isEmpty else { onFinished?(); return }
        begin()
        queue = parts
        completion = onFinished
        playNext()
    }

    /// A line with no recording, in the phone's own voice.
    func say(_ text: String, enabled: Bool, onFinished: (@MainActor () -> Void)? = nil) {
        speak([VoicePart(clip: nil, fallback: text)], enabled: enabled, onFinished: onFinished)
    }

    private func playNext() {
        guard !queue.isEmpty else {
            let callback = completion
            completion = nil
            callback?()
            return
        }
        let part = queue.removeFirst()
        let current = generation
        if let url = part.clip, let file = try? AVAudioFile(forReading: url), file.processingFormat == format, engine.isRunning {
            voicePlayer.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in self?.partFinished(current) }
            }
            if !voicePlayer.isPlaying { voicePlayer.play() }
            return
        }
        let utterance = AVSpeechUtterance(string: part.fallback)
        utterance.rate = 0.48
        utterance.volume = 0.82
        utterance.voice = AVSpeechSynthesisVoice(language: Self.speechLanguage)
        speaking = ObjectIdentifier(utterance)
        speaker.speak(utterance)
    }

    private func partFinished(_ finishedGeneration: Int) {
        guard finishedGeneration == generation else { return }
        // A breath between "Bulgarian split squat", "Set two of four" and "Right side".
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard let self, finishedGeneration == self.generation else { return }
            self.playNext()
        }
    }

    private static var speechLanguage: String {
        switch LanguageState.shared.language {
        case .english: "en-US"
        case .german: "de-DE"
        case .swissGerman: "de-CH"
        case .italian: "it-IT"
        case .spanish: "es-ES"
        case .portuguese: "pt-PT"
        case .japanese: "ja-JP"
        case .romanian: "ro-RO"
        case .thai: "th-TH"
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.utteranceEnded(identifier) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.utteranceEnded(identifier) }
    }

    private func utteranceEnded(_ identifier: ObjectIdentifier) {
        guard speaking == identifier else { return }
        speaking = nil
        partFinished(generation)
    }
}
