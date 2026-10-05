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
/// as files, off the main thread: the first chime after the bells are turned
/// on (or after launch) builds all eleven tunes there and rings once its own
/// is ready, so a tap never waits on the math. The session is `.ambient`: the
/// ringer switch silences it and it never stops her music. The engine runs
/// only while a bell rings, stopping a few seconds after the last.
@MainActor
final class AttendanceBells {
    static let shared = AttendanceBells()
    /// Each app keeps its own; the name dates from when only the Assistant rang.
    static let enabledKey = "Assistant.bellsOn"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    nonisolated enum Chime: Hashable, Sendable {
        /// The `count`th child here (from 1), which picks the note.
        case here(count: Int)
        case away
        case everyoneMarked
        /// Everyone marked on the hundredth day of school.
        case hundredthDay
    }

    private static let logger = Logger.app(category: "bells")

    /// The white-note bells: C major from middle C to the C above.
    nonisolated static let scale: [Double] = [261.63, 293.66, 329.63, 349.23, 392.00, 440.00, 493.88, 523.25]

    /// Up the scale and back down, then up again: C D E F G A B C′ B A G F E D.
    nonisolated static let climb: [Int] = Array(0..<scale.count) + Array((1..<(scale.count - 1)).reversed())

    /// The bell for the `count`th child here.
    nonisolated static func note(forHereCount count: Int) -> Double {
        scale[noteIndex(forHereCount: count)]
    }

    /// Which of the eight bells the `count`th child here rings.
    nonisolated static func noteIndex(forHereCount count: Int) -> Int {
        climb[max(count - 1, 0) % climb.count]
    }

    /// What a chime sounds like, so every child who rings the same bell
    /// shares one tune: eight bells, the damped low C and the two runs.
    nonisolated enum Tune: Hashable, Sendable, CaseIterable {
        case bell(Int)
        case away
        case everyoneMarked
        case hundredthDay

        static var allCases: [Tune] {
            AttendanceBells.scale.indices.map(Tune.bell) + [.away, .everyoneMarked, .hundredthDay]
        }
    }

    nonisolated static func tune(for chime: Chime) -> Tune {
        switch chime {
        case .here(let count): .bell(noteIndex(forHereCount: count))
        case .away: .away
        case .everyoneMarked: .everyoneMarked
        case .hundredthDay: .hundredthDay
        }
    }

    private static let sampleRate = 44_100.0
    private let engine = AVAudioEngine()
    /// A few players, so quick taps ring over each other instead of queuing.
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    private var buffers: [Tune: AVAudioPCMBuffer] = [:]
    /// Building the tunes, off the main thread, while any are missing.
    private var building: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    private init() {}

    func play(_ chime: Chime) {
        guard Self.isOn, let format else { return }
        let tune = Self.tune(for: chime)
        if let buffer = buffers[tune] {
            ring(buffer, format: format)
            return
        }
        // Not built yet: build them all, then ring this one (if the bells
        // are still on by then).
        Task {
            await buildTunes()
            guard Self.isOn, let buffer = buffers[tune] else { return }
            ring(buffer, format: format)
        }
    }

    /// Builds every tune off the main thread, once; later callers wait for
    /// the same build.
    private func buildTunes() async {
        if buffers.count == Tune.allCases.count { return }
        if let building {
            await building.value
            return
        }
        let task = Task {
            let rendered = await Self.renderAll(sampleRate: Self.sampleRate)
            guard let format else { return }
            for (tune, samples) in rendered {
                buffers[tune] = Self.buffer(from: samples, format: format)
            }
        }
        building = task
        await task.value
        building = nil
    }

    private func ring(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
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

    /// Every tune's samples, built off the main thread.
    @concurrent
    nonisolated static func renderAll(sampleRate: Double) async -> [Tune: [Float]] {
        var rendered: [Tune: [Float]] = [:]
        for tune in Tune.allCases {
            rendered[tune] = render(notes(for: tune), sampleRate: sampleRate)
        }
        return rendered
    }

    /// The notes struck in a tune.
    nonisolated private static func notes(for tune: Tune) -> [Tone] {
        switch tune {
        case .bell(let index):
            [Tone(frequency: scale[index], start: 0, level: 0.5)]
        case .away:
            [Tone(frequency: scale[0], start: 0, level: 0.4, damped: 0.25)]
        case .everyoneMarked:
            run(Array(0..<scale.count), spacing: 0.11)
        case .hundredthDay:
            run(Array(0..<scale.count) + Array((0..<(scale.count - 1)).reversed()), spacing: 0.1)
        }
    }

    /// Samples into a buffer the players can schedule (a copy, on the main
    /// actor; the math is already done).
    private static func buffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(samples.count)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        return buffer
    }

    /// The bells at `indexes` struck one after another, `spacing` seconds
    /// apart; each is damped as the next rings so the run stays clear, and the
    /// last one rings out.
    nonisolated private static func run(_ indexes: [Int], spacing: Double) -> [Tone] {
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
    nonisolated private struct Tone {
        let frequency: Double
        let start: Double
        let level: Double
        var damped: Double?
    }

    /// A bell's overtone: its pitch as a multiple of the note's, its level,
    /// and how fast it dies away.
    nonisolated private struct Partial {
        let ratio: Double
        let level: Double
        let decay: Double
    }

    /// A brass bell: the octave and the twelfth strong (they carry the pitch
    /// on a phone speaker, which is thin at middle C), a slightly sharp
    /// fourth and a high shimmer, and a long ring.
    nonisolated private static let partials = [
        Partial(ratio: 1.0, level: 1.0, decay: 1.1), Partial(ratio: 2.0, level: 0.6, decay: 1.8),
        Partial(ratio: 3.0, level: 0.45, decay: 2.6), Partial(ratio: 4.07, level: 0.18, decay: 4.0),
        Partial(ratio: 5.4, level: 0.1, decay: 6.0)
    ]

    /// How long a struck bell is let ring, in seconds.
    nonisolated private static let ringLength = 2.2

    /// Each note as a few partials with a quick attack and a decay that is
    /// faster for the higher ones, which is most of what makes a bell a bell.
    /// A damped note dies within a few hundredths of a second. The whole chime
    /// is scaled down if its notes together would clip.
    nonisolated private static func render(_ notes: [Tone], sampleRate rate: Double) -> [Float] {
        let length = (notes.map(\.start).max() ?? 0) + ringLength
        var samples = [Float](repeating: 0, count: Int(length * rate))
        for index in samples.indices {
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
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        if peak > 0.9 {
            let scale = 0.9 / peak
            for index in samples.indices { samples[index] *= scale }
        }
        return samples
    }
}
#endif
