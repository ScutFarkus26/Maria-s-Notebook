#if os(iOS)
import AVFoundation
import OSLog

/// The Montessori bells as children are marked in on a phone's attendance
/// grid, off until turned on (the Assistant's Classroom sheet, the notebook's
/// attendance menu): the eight brass bells of the C major scale, middle C to the C
/// above. Each child marked here rings the next bell, up the scale and back
/// down again as the children do with the real bells, so the morning never
/// jumps from the top C to the bottom one. An absence is the low C struck and
/// damped at once, as with the felt damper; everyone marked runs up the
/// scale; and the hundredth day runs up and back down.
///
/// The tones are made here (a few decaying partials, bell-like), not shipped
/// as files. The session is `.ambient`: the ringer switch silences it and it
/// never stops her music. The engine runs only while a bell rings, stopping
/// a few seconds after the last.
@MainActor
final class AttendanceBells {
    static let shared = AttendanceBells()
    /// Each app keeps its own; the name dates from when only the Assistant rang.
    static let enabledKey = "Assistant.bellsOn"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    enum Chime: Hashable {
        /// The `count`th child here (from 1), which picks the note.
        case here(count: Int)
        case away
        case everyoneMarked
        /// Everyone marked on the hundredth day of school.
        case hundredthDay
    }

    private static let logger = Logger.app(category: "bells")

    /// The white-note bells: C major from middle C to the C above.
    static let scale: [Double] = [261.63, 293.66, 329.63, 349.23, 392.00, 440.00, 493.88, 523.25]

    /// Up the scale and back down, then up again: C D E F G A B C′ B A G F E D.
    static let climb: [Int] = Array(0..<scale.count) + Array((1..<(scale.count - 1)).reversed())

    /// The bell for the `count`th child here.
    static func note(forHereCount count: Int) -> Double {
        scale[climb[max(count - 1, 0) % climb.count]]
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
        // The Assistant runs on iOS 18; the throwing forms arrived in iOS 27.
        if #available(iOS 27.0, *) {
            do {
                try player.playAudio()
            } catch {
                Self.logger.error("A bell couldn't ring: \(error.localizedDescription, privacy: .public)")
                return
            }
        } else {
            player.play()
        }
        scheduleStop(after: max(4, Double(buffer.frameLength) / format.sampleRate + 0.5))
    }

    // MARK: - Engine

    private func start(format: AVAudioFormat) throws {
        if players.isEmpty {
            for _ in 0..<4 {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                if #available(iOS 27.0, *) {
                    try engine.connectNode(player, to: engine.mainMixerNode, format: format)
                } else {
                    engine.connect(player, to: engine.mainMixerNode, format: format)
                }
                players.append(player)
            }
            engine.mainMixerNode.outputVolume = 0.5
        }
        guard !engine.isRunning else { return }
        try AVAudioSession.sharedInstance().setCategory(.ambient)
        try engine.start()
    }

    private func scheduleStop(after seconds: Double) {
        stopTask?.cancel()
        stopTask = Task {
            guard (try? await Task.sleep(for: .seconds(seconds))) != nil else { return }
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
            notes = [Tone(frequency: Self.scale[0], start: 0, level: 0.4, damped: 0.25)]
        case .everyoneMarked:
            notes = Self.run(Array(0..<Self.scale.count), spacing: 0.11)
        case .hundredthDay:
            notes = Self.run(Array(0..<Self.scale.count) + Array((0..<(Self.scale.count - 1)).reversed()), spacing: 0.1)
        }
        let buffer = Self.render(notes, format: format)
        buffers[chime] = buffer
        return buffer
    }

    /// The bells at `indexes` struck one after another, `spacing` seconds
    /// apart; each is damped as the next rings so the run stays clear, and the
    /// last one rings out.
    private static func run(_ indexes: [Int], spacing: Double) -> [Tone] {
        indexes.enumerated().map { position, index in
            let isLast = position == indexes.count - 1
            return Tone(
                frequency: scale[index],
                start: 0.08 + spacing * Double(position),
                level: isLast ? 0.5 : 0.36,
                damped: isLast ? nil : spacing * 1.6
            )
        }
    }

    /// One struck note in a chime: its pitch, when it starts (seconds into
    /// the chime), how loud, and when (seconds after it's struck) the damper
    /// stops it, if it does.
    private struct Tone {
        let frequency: Double
        let start: Double
        let level: Double
        var damped: Double?
    }

    /// A bell's overtone: its pitch as a multiple of the note's, its level,
    /// and how fast it dies away.
    private struct Partial {
        let ratio: Double
        let level: Double
        let decay: Double
    }

    /// A brass bell: the octave and the twelfth strong (they carry the pitch
    /// on a phone speaker, which is thin at middle C), a slightly sharp
    /// fourth and a high shimmer, and a long ring.
    private static let partials = [
        Partial(ratio: 1.0, level: 1.0, decay: 1.1), Partial(ratio: 2.0, level: 0.6, decay: 1.8),
        Partial(ratio: 3.0, level: 0.45, decay: 2.6), Partial(ratio: 4.07, level: 0.18, decay: 4.0),
        Partial(ratio: 5.4, level: 0.1, decay: 6.0)
    ]

    /// How long a struck bell is let ring, in seconds.
    private static let ring = 2.2

    /// Each note as a few partials with a quick attack and a decay that is
    /// faster for the higher ones, which is most of what makes a bell a bell.
    /// A damped note dies within a few hundredths of a second. The whole chime
    /// is scaled down if its notes together would clip.
    private static func render(
        _ notes: [Tone],
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
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
                var envelope = min(local / 0.006, 1)
                if let damped = note.damped, local > damped {
                    envelope *= exp(-40 * (local - damped))
                }
                for partial in partials {
                    value += note.level * partial.level * envelope * exp(-partial.decay * local)
                        * sin(2 * .pi * note.frequency * partial.ratio * local)
                }
            }
            samples[index] = Float(value * 0.3)
        }
        var peak: Float = 0
        for index in 0..<Int(frames) { peak = max(peak, abs(samples[index])) }
        if peak > 0.9 {
            let scale = 0.9 / peak
            for index in 0..<Int(frames) { samples[index] *= scale }
        }
        return buffer
    }
}
#endif
