#if os(iOS)
import SwiftUI

// MARK: - Motion

/// What a tile does when she marks it: a small springy bounce (a squeeze for
/// Absent), the green spreading out from her finger when the child comes in,
/// (and, drawn outside the tile, sparkles when it's their birthday:
/// `BirthdaySparkles`). All of it is over in under a second
/// and none of it moves the tile off its place. With Reduce Motion on, the
/// mark just fades in.
struct TileTapMotion {
    var scale: CGFloat = 1
    /// How far the green has spread, 0 to 1 (1 covers the tile).
    var spread: CGFloat = 1

    /// Which way a mark went, for its motion.
    enum Kind {
        case here
        case away
        case cleared

        init(_ status: AttendanceStatus) {
            switch status {
            case .present, .tardy, .leftEarly: self = .here
            case .absent: self = .away
            case .unmarked: self = .cleared
            }
        }
    }

    @KeyframesBuilder<TileTapMotion>
    static func keyframes(for kind: Kind, reduceMotion: Bool) -> some Keyframes<TileTapMotion> {
        KeyframeTrack(\.scale) {
            if reduceMotion {
                LinearKeyframe(1, duration: 0.01)
            } else {
                switch kind {
                case .here: SpringKeyframe(1.06, duration: 0.12, spring: .snappy)
                case .away: SpringKeyframe(0.93, duration: 0.12, spring: .snappy)
                case .cleared: SpringKeyframe(0.97, duration: 0.1, spring: .snappy)
                }
                SpringKeyframe(1, duration: 0.3, spring: .bouncy)
            }
        }
        KeyframeTrack(\.spread) {
            if kind == .here && !reduceMotion {
                MoveKeyframe(0)
                CubicKeyframe(1, duration: 0.32)
            } else {
                LinearKeyframe(1, duration: 0.01)
            }
        }
    }
}

/// The ripple that runs across the grid when everyone's marked: each tile
/// swells and brightens a moment, a little after the one before it.
struct TileRipple {
    var scale: CGFloat = 1
    var glow: Double = 0

    @KeyframesBuilder<TileRipple>
    static func keyframes(delay: Double, reduceMotion: Bool) -> some Keyframes<TileRipple> {
        KeyframeTrack(\.scale) {
            if reduceMotion {
                LinearKeyframe(1, duration: 0.01)
            } else if delay > 0 {
                // A zero-length hold leaves the first tile undrawn: skip it.
                LinearKeyframe(1, duration: delay)
                SpringKeyframe(1.05, duration: 0.14, spring: .snappy)
                SpringKeyframe(1, duration: 0.35, spring: .bouncy)
            } else {
                SpringKeyframe(1.05, duration: 0.14, spring: .snappy)
                SpringKeyframe(1, duration: 0.35, spring: .bouncy)
            }
        }
        KeyframeTrack(\.glow) {
            if reduceMotion {
                LinearKeyframe(0, duration: 0.01)
            } else if delay > 0 {
                LinearKeyframe(0, duration: delay)
                LinearKeyframe(0.45, duration: 0.12)
                LinearKeyframe(0, duration: 0.4)
            } else {
                LinearKeyframe(0.45, duration: 0.12)
                LinearKeyframe(0, duration: 0.4)
            }
        }
    }
}

// MARK: - Pieces

/// What a tile rests on before any green: the card, frosted glass over a
/// picture, or nothing (absent on Sky or Plain).
enum TileBase: Equatable {
    case card
    case frosted
    case thinFrost
    case clear

    /// The unmarked card, or nothing for absent; frosted over a picture so
    /// the outline and dashes still read.
    init(status: AttendanceStatus, quietBackdrop: Bool) {
        switch (status == .absent, quietBackdrop) {
        case (false, true): self = .card
        case (false, false): self = .frosted
        case (true, true): self = .clear
        case (true, false): self = .thinFrost
        }
    }
}

/// The tile's fill: its resting base, with the green of a child who is here
/// on top, drawn as a circle from `origin` that `spread` grows to cover it.
struct TileFill<S: Shape>: View {
    let shape: S
    let base: TileBase
    let isHere: Bool
    let origin: CGPoint?
    let spread: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = origin ?? CGPoint(x: size.width / 2, y: size.height / 2)
            // Far enough from any point in the tile to reach every corner.
            let reach = 2 * hypot(size.width, size.height) * spread
            ZStack {
                switch base {
                case .card: shape.fill(Color(.secondarySystemGroupedBackground))
                case .frosted: shape.fill(.regularMaterial)
                case .thinFrost: shape.fill(.ultraThinMaterial)
                case .clear: EmptyView()
                }
                shape.fill(Color.green)
                    .opacity(isHere ? 1 : 0)
                    .mask {
                        Circle()
                            .frame(width: reach, height: reach)
                            .position(center)
                    }
            }
        }
    }
}

/// Sparkles bursting out from the edge of a birthday child's tile as they're
/// marked in, over the tiles around it. `progress` runs 0 to 1; they show
/// only in between.
struct BirthdaySparkles: View {
    let progress: CGFloat

    static func keyframes() -> some Keyframes<CGFloat> {
        KeyframeTrack {
            MoveKeyframe(0)
            LinearKeyframe(1, duration: 0.9)
        }
    }

    private static let colors: [Color] = [.pink, .orange, .yellow, .mint, .cyan, .purple]
    private static let count = 10

    var body: some View {
        if progress > 0 && progress < 1 {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    ForEach(0..<Self.count, id: \.self) { index in
                        let angle = Double(index) / Double(Self.count) * 2 * .pi
                        // From just inside the edge out past it, on an ellipse
                        // the tile's shape.
                        let spreadX = size.width / 2 - 6 + 34 * progress
                        let spreadY = size.height / 2 - 6 + 26 * progress
                        Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "star.fill")
                            .font(.system(size: CGFloat(8 + (index % 3) * 3), weight: .bold))
                            .foregroundStyle(Self.colors[index % Self.colors.count])
                            .scaleEffect(1.3 - 0.7 * progress)
                            .offset(x: cos(angle) * spreadX, y: sin(angle) * spreadY)
                            .opacity(Double(1 - progress))
                    }
                }
                .frame(width: size.width, height: size.height)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A waving hand rising out of the corner of a returning child's tile as
/// they're marked in: it waves twice and fades. `progress` runs 0 to 1; it
/// shows only in between.
struct WelcomeWave: View {
    let progress: CGFloat

    static func keyframes() -> some Keyframes<CGFloat> {
        KeyframeTrack {
            MoveKeyframe(0)
            LinearKeyframe(1, duration: 1.0)
        }
    }

    var body: some View {
        if progress > 0 && progress < 1 {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.teal)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .rotationEffect(.degrees(sin(Double(progress) * .pi * 4) * 20), anchor: .bottomTrailing)
                .scaleEffect(0.7 + 0.4 * min(progress * 3, 1))
                .offset(x: 4, y: -6 - 30 * progress)
                .opacity(progress < 0.7 ? 1 : Double((1 - progress) / 0.3))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension AttendanceTile {

    /// A birthday tile's party-colored edge, around whatever the mark's shape
    /// is (dashed still means absent).
    static let partyColors = AngularGradient(
        colors: [.pink, .orange, .yellow, .mint, .cyan, .purple, .pink],
        center: .center
    )

    /// What's under the green (`TileBase`).
    var baseFill: TileBase {
        TileBase(status: row.status, quietBackdrop: quietBackdrop)
    }
}
#endif
