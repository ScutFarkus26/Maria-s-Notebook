import AVFoundation
import OSLog

/// Soft bells as she marks, off until she turns them on in Classroom. Each
/// child marked here rings the next note up a pentatonic scale, so the
/// morning climbs as the class fills; an absence is one low note, and
/// everyone marked plays a short rising run.
///
/// The tones are made here (a few decaying partials, bell-like), not shipped
/// as files. The session is `.ambient`: the ringer switch silences it and it
/// never stops her music. The engine runs only while a bell rings, stopping
/// a few seconds after the last.
@MainActor
final class AssistantBells {
    static let shared = AssistantBells()
    static let enabledKey = "Assistant.bellsOn"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    enum Chime: Hashable {
        /// The `count`th child here (from 1), which picks the note.
        case here(count: Int)
        case away
        case everyoneMarked
    }

    private static let logger = Logger.app(category: "bells")

    /// C major pentatonic from C5, two octaves.
    static let scale: [Double] = [
        523.25, 587.33, 659.25, 783.99, 880.00,
        1046.50, 1174.66, 1318.51, 1567.98, 1760.00
    ]

    /// The note for the `count`th child here, climbing and starting over at
    /// the top.
    static func note(forHereCount count: Int) -> Double {
        scale[max(count - 1, 0) % scale.count]
    }

    private let engine = AVAudioEngine()
    /// A few players, so quick taps ring over each other instead of queuing.
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var buffers: [Chime: AVAudioPCMBuffer] = [:]
    private var stopTask: Task<Void, Never>?

    private init() {}

    func play(_ chime: Chime) {
        guard Self.isOn, let format, let buffer = buffer(for: chime, format: format) else { return }
        do {
            try start(format: format)
        } catch {
            Self.logger.error("Bells couldn't start: \(error.localizedDescription, privacy: .public)")
            return
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
        scheduleStop()
    }

    // MARK: - Engine

    private func start(format: AVAudioFormat) throws {
        if players.isEmpty {
            for _ in 0..<4 {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                players.append(player)
            }
            engine.mainMixerNode.outputVolume = 0.5
        }
        guard !engine.isRunning else { return }
        try AVAudioSession.sharedInstance().setCategory(.ambient)
        try engine.start()
    }

    private func scheduleStop() {
        stopTask?.cancel()
        stopTask = Task {
            guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            players.forEach { $0.stop() }
            engine.stop()
        }
    }

    // MARK: - Tones

    private func buffer(for chime: Chime, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if let cached = buffers[chime] { return cached }
        let notes: [Tone]
        switch chime {
        case .here(let count):
            notes = [Tone(frequency: Self.note(forHereCount: count), start: 0, level: 0.5)]
        case .away:
            notes = [Tone(frequency: 392.00, start: 0, level: 0.35)]
        case .everyoneMarked:
            notes = [523.25, 659.25, 783.99, 1046.50].enumerated().map { index, frequency in
                Tone(frequency: frequency, start: 0.10 + 0.12 * Double(index), level: index == 3 ? 0.45 : 0.4)
            }
        }
        let buffer = Self.render(notes, format: format)
        buffers[chime] = buffer
        return buffer
    }

    /// One struck note in a chime: its pitch, when it starts (seconds into
    /// the chime) and how loud.
    private struct Tone {
        let frequency: Double
        let start: Double
        let level: Double
    }

    /// A bell's overtone: its pitch as a multiple of the note's, its level,
    /// and how fast it dies away.
    private struct Partial {
        let ratio: Double
        let level: Double
        let decay: Double
    }

    private static let partials = [
        Partial(ratio: 1.0, level: 1.0, decay: 3.2), Partial(ratio: 2.0, level: 0.35, decay: 5.0),
        Partial(ratio: 3.0, level: 0.15, decay: 7.0), Partial(ratio: 4.2, level: 0.08, decay: 9.0)
    ]

    /// Each note as a few partials with a quick attack and a decay that is
    /// faster for the higher ones, which is most of what makes a bell a bell.
    private static func render(
        _ notes: [Tone],
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let ring = 1.4
        let length = (notes.map(\.start).max() ?? 0) + ring
        let frames = AVAudioFrameCount(length * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            let time = Double(index) / rate
            var value = 0.0
            for note in notes where time >= note.start {
                let local = time - note.start
                let attack = min(local / 0.006, 1)
                for partial in partials {
                    value += note.level * partial.level * attack * exp(-partial.decay * local)
                        * sin(2 * .pi * note.frequency * partial.ratio * local)
                }
            }
            samples[index] = Float(value * 0.3)
        }
        return buffer
    }
}
