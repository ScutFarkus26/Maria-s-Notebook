import SwiftUI

/// On the hundredth day of school, when everyone's marked: a hundred pieces of
/// confetti in the bead-chain colors fall across the screen and are gone in
/// under two seconds. The frame-by-frame timeline exists only while they fall;
/// with Reduce Motion there are none.
struct HundredthDayConfetti: View {
    /// Bumped to set them falling.
    let trigger: Int

    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let duration = 1.8
    static let count = 100

    private struct Piece {
        let x: Double
        let delay: Double
        let speed: Double
        let sway: Double
        let phase: Double
        let spin: Double
        let width: Double
        let height: Double
        let color: Int
    }

    private static let pieces: [Piece] = {
        var random = WallpaperRandom(seed: 100)
        return (0..<count).map { index in
            Piece(
                x: .random(in: 0...1, using: &random),
                delay: .random(in: 0...0.35, using: &random),
                speed: .random(in: 0.7...1.15, using: &random),
                sway: .random(in: 8...26, using: &random),
                phase: .random(in: 0...(2 * .pi), using: &random),
                spin: .random(in: -8...8, using: &random),
                width: .random(in: 5...8, using: &random),
                height: .random(in: 8...13, using: &random),
                color: index % colors.count
            )
        }
    }()

    private static let colors: [Color] = [
        Color(red: 0.86, green: 0.20, blue: 0.20), Color(red: 0.20, green: 0.65, blue: 0.30),
        Color(red: 0.95, green: 0.55, blue: 0.70), Color(red: 0.98, green: 0.83, blue: 0.25),
        Color(red: 0.45, green: 0.75, blue: 0.95), Color(red: 0.70, green: 0.55, blue: 0.85),
        Color(red: 0.55, green: 0.35, blue: 0.20), Color(red: 0.15, green: 0.25, blue: 0.60),
        Color(red: 0.85, green: 0.65, blue: 0.20)
    ]

    var body: some View {
        ZStack {
            if let start {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let elapsed = timeline.date.timeIntervalSince(start)
                        Self.draw(in: &context, size: size, elapsed: elapsed)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            guard !reduceMotion else { return }
            start = .now
        }
        .task(id: start) {
            guard start != nil, (try? await Task.sleep(for: .seconds(Self.duration))) != nil else { return }
            start = nil
        }
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        let fade = elapsed > duration - 0.35 ? max(0, (duration - elapsed) / 0.35) : 1
        for piece in pieces {
            let time = elapsed - piece.delay
            guard time > 0 else { continue }
            let y = -20 + time * piece.speed * size.height
            let x = piece.x * size.width + sin(piece.phase + time * 5) * piece.sway
            var copy = context
            copy.opacity = fade
            copy.translateBy(x: x, y: y)
            copy.rotate(by: .radians(piece.phase + time * piece.spin))
            copy.fill(
                Path(CGRect(x: -piece.width / 2, y: -piece.height / 2, width: piece.width, height: piece.height)),
                with: .color(colors[piece.color])
            )
        }
    }
}
