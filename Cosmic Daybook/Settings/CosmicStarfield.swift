import SwiftUI

// MARK: - Cosmic Starfield

/// A still field of small stars: the "cosmic" accent the footer's easter egg turns on
/// (`UserDefaultsKeys.settingsCosmicAccent`). The stars are drawn once in a `Canvas`
/// from a fixed layout; nothing animates, so the accent costs nothing while it sits there.
struct CosmicStarfield: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let stars = CosmicStarLayout.stars
        // Indigo stars read on a light background, white ones on a dark one.
        let color: Color = colorScheme == .dark ? .white : .indigo
        let strength = colorScheme == .dark ? 1.0 : 0.6
        Canvas { context, size in
            for star in stars {
                let center = CGPoint(x: star.x * size.width, y: star.y * size.height)
                var starContext = context
                starContext.opacity = star.brightness * strength
                if star.sparkles {
                    let sparkle = CosmicStarLayout.sparklePath(at: center, radius: star.radius * 2.4)
                    starContext.fill(sparkle, with: .color(color))
                } else {
                    let rect = CGRect(
                        x: center.x - star.radius, y: center.y - star.radius,
                        width: star.radius * 2, height: star.radius * 2
                    )
                    starContext.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Header Accent

/// The cosmic accent for the Settings header: a faint indigo wash with the starfield,
/// shown only while the footer's easter egg is on. Place it behind the header.
struct CosmicHeaderAccent: View {
    @AppStorage(UserDefaultsKeys.settingsCosmicAccent) private var isOn = false

    var body: some View {
        if isOn {
            ZStack {
                LinearGradient(
                    colors: [Color.indigo.opacity(UIConstants.OpacityConstants.medium), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                CosmicStarfield()
            }
            .clipShape(RoundedRectangle(cornerRadius: SettingsStyle.cornerRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }
}

// MARK: - Layout

/// One star, in unit coordinates so the same sky fits any frame.
nonisolated struct CosmicStar: Sendable {
    let x: Double
    let y: Double
    let radius: Double
    let brightness: Double
    let sparkles: Bool
}

nonisolated enum CosmicStarLayout {
    /// The same sky every time: a seeded generator, so the stars never jump between redraws.
    static let stars: [CosmicStar] = makeStars(count: 36, seed: 0xC05_A1C)

    static func makeStars(count: Int, seed: UInt64) -> [CosmicStar] {
        var generator = SeededStarGenerator(state: seed)
        return (0..<count).map { index in
            CosmicStar(
                x: generator.nextUnit(),
                y: generator.nextUnit(),
                radius: 0.5 + generator.nextUnit() * 0.8,
                brightness: 0.25 + generator.nextUnit() * 0.6,
                // Every ninth star is a little four-point sparkle.
                sparkles: index.isMultiple(of: 9)
            )
        }
    }

    /// A four-point star: two thin diamonds crossed at `center`.
    static func sparklePath(at center: CGPoint, radius: Double) -> Path {
        let waist = radius * 0.22
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + waist, y: center.y - waist))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x + waist, y: center.y + waist))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - waist, y: center.y + waist))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x - waist, y: center.y - waist))
        path.closeSubpath()
        return path
    }
}

/// SplitMix64: tiny, deterministic, and plenty random for scattering stars.
nonisolated private struct SeededStarGenerator {
    var state: UInt64

    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct CosmicStarfieldPreview: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            SettingsCategoryHeader(category: .overview)
                .padding(AppTheme.Spacing.small)
                .background { CosmicStarfield() }
            CosmicStarfield()
                .frame(height: 120)
                .background(Color.indigo.opacity(UIConstants.OpacityConstants.light))
        }
        .padding()
    }
}

#Preview {
    CosmicStarfieldPreview()
}
