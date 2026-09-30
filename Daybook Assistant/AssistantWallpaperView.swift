import SwiftUI

/// One background, drawn in code in a light and a dark version. None of them
/// runs on a timer: a frosted tile over a moving picture is re-blurred every
/// frame, which is the heat the efficiency work took out. Cosmic changes only
/// when a child is marked, Seasons only with the day on screen, and Sky's
/// tint (in `AssistantBackdrop`) every five minutes.
struct AssistantWallpaperView: View {
    let wallpaper: AssistantWallpaper
    /// The day on screen, for Seasons.
    var date = Date()
    /// How much of the class is here, 0 to 1: Cosmic's sky fills with stars.
    var hereFraction: Double = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        switch wallpaper {
        case .sky, .plain:
            Color(.systemGroupedBackground)
        case .cosmic:
            CosmicWallpaper(isDark: isDark, hereFraction: hereFraction)
        case .seasons:
            SeasonsWallpaper(season: AssistantWallpaper.season(for: date), isDark: isDark)
        case .beadChains:
            BeadChainsWallpaper(isDark: isDark)
        case .pinkTower:
            PinkTowerWallpaper(isDark: isDark)
        case .photo:
            PhotoWallpaper(isDark: isDark)
        }
    }
}

// MARK: - Cosmic

/// Deep space in the dark, a pale periwinkle dawn in the light, and a sky
/// that fills with stars as the children come in: under half at the start of
/// the morning, all of them once everyone's here.
private struct CosmicWallpaper: View {
    let isDark: Bool
    let hereFraction: Double

    private struct Star {
        let x: Double
        let y: Double
        let size: Double
        let brightness: Double
    }

    private static let stars: [Star] = {
        var random = SeededRandom(seed: 0xC05_A1C)
        return (0..<120).map { _ in
            Star(
                x: .random(in: 0...1, using: &random),
                y: .random(in: 0...1, using: &random),
                size: .random(in: 0.8...2.4, using: &random),
                brightness: .random(in: 0.45...1, using: &random)
            )
        }
    }()

    static func visibleStars(hereFraction: Double) -> Int {
        let share = 0.4 + 0.6 * min(max(hereFraction, 0), 1)
        return Int((Double(stars.count) * share).rounded())
    }

    var body: some View {
        let visible = Self.visibleStars(hereFraction: hereFraction)
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: isDark ? Self.darkColors : Self.lightColors
        )
        .overlay {
            Canvas { context, size in
                let starColor = isDark ? Color.white : Color(red: 0.32, green: 0.30, blue: 0.62)
                for star in Self.stars.prefix(visible) {
                    let center = CGPoint(x: star.x * size.width, y: star.y * size.height)
                    let level = star.brightness * (isDark ? 0.85 : 0.45)
                    if star.size > 2.1 {
                        // The brightest few get a soft glow.
                        let glow = star.size * 3.5
                        context.fill(
                            Path(ellipseIn: CGRect(x: center.x - glow / 2, y: center.y - glow / 2,
                                                   width: glow, height: glow)),
                            with: .color(starColor.opacity(level * 0.18))
                        )
                    }
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - star.size / 2, y: center.y - star.size / 2,
                                               width: star.size, height: star.size)),
                        with: .color(starColor.opacity(level))
                    )
                }
            }
        }
    }

    private static let darkColors: [Color] = [
        rgb(0.04, 0.05, 0.16), rgb(0.08, 0.07, 0.22), rgb(0.14, 0.08, 0.28),
        rgb(0.07, 0.07, 0.22), rgb(0.24, 0.12, 0.40), rgb(0.12, 0.08, 0.30),
        rgb(0.05, 0.05, 0.18), rgb(0.10, 0.08, 0.26), rgb(0.06, 0.05, 0.18)
    ]

    private static let lightColors: [Color] = [
        rgb(0.80, 0.83, 0.98), rgb(0.84, 0.84, 0.99), rgb(0.88, 0.84, 0.98),
        rgb(0.86, 0.87, 0.99), rgb(0.94, 0.86, 0.96), rgb(0.88, 0.86, 0.98),
        rgb(0.93, 0.92, 0.99), rgb(0.95, 0.92, 0.98), rgb(0.93, 0.91, 0.98)
    ]
}

// MARK: - Seasons

/// The season's colors, with its leaves, snowflakes, blossoms or suns
/// scattered faintly, most of them toward the top.
private struct SeasonsWallpaper: View {
    let season: AssistantWallpaper.Season
    let isDark: Bool

    private struct Scatter {
        let x: Double
        let y: Double
        let scale: Double
        let angle: Double
        let symbol: Int
    }

    private static func scatter(for season: AssistantWallpaper.Season) -> [Scatter] {
        let seed: UInt64 = switch season {
        case .autumn: 0xA07
        case .winter: 0x5A0
        case .spring: 0xB10
        case .summer: 0x5E0
        }
        var random = SeededRandom(seed: seed)
        return (0..<24).map { _ in
            Scatter(
                x: .random(in: 0...1, using: &random),
                // Weighted toward the top, where the grid is thinner.
                y: pow(.random(in: 0...1, using: &random), 1.6),
                scale: .random(in: 0.6...1.35, using: &random),
                angle: .random(in: -40...40, using: &random),
                symbol: Int.random(in: 0...1, using: &random)
            )
        }
    }

    private var symbols: [(name: String, color: Color)] {
        switch season {
        case .autumn: [("leaf.fill", rgb(0.93, 0.50, 0.15)), ("leaf.fill", rgb(0.80, 0.25, 0.15))]
        case .winter: [("snowflake", rgb(0.40, 0.66, 0.95)), ("snowflake", rgb(0.62, 0.78, 0.98))]
        case .spring: [("camera.macro", rgb(0.95, 0.50, 0.70)), ("leaf.fill", rgb(0.40, 0.70, 0.35))]
        case .summer: [("sun.max.fill", rgb(0.98, 0.72, 0.18)), ("cloud.fill", rgb(0.58, 0.76, 0.95))]
        }
    }

    private var gradient: [Color] {
        switch (season, isDark) {
        case (.autumn, false): [rgb(1.00, 0.92, 0.82), rgb(0.98, 0.95, 0.90)]
        case (.autumn, true): [rgb(0.21, 0.12, 0.08), rgb(0.11, 0.08, 0.07)]
        case (.winter, false): [rgb(0.88, 0.94, 1.00), rgb(0.96, 0.97, 1.00)]
        case (.winter, true): [rgb(0.07, 0.11, 0.20), rgb(0.05, 0.06, 0.11)]
        case (.spring, false): [rgb(0.94, 0.98, 0.89), rgb(1.00, 0.94, 0.96)]
        case (.spring, true): [rgb(0.08, 0.15, 0.10), rgb(0.13, 0.08, 0.12)]
        case (.summer, false): [rgb(1.00, 0.96, 0.83), rgb(0.89, 0.95, 1.00)]
        case (.summer, true): [rgb(0.17, 0.13, 0.06), rgb(0.06, 0.09, 0.16)]
        }
    }

    var body: some View {
        let placements = Self.scatter(for: season)
        let symbols = symbols
        LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
            .overlay {
                Canvas { context, size in
                    context.opacity = isDark ? 0.16 : 0.24
                    for item in placements {
                        guard let symbol = context.resolveSymbol(id: item.symbol) else { continue }
                        var copy = context
                        copy.translateBy(x: item.x * size.width, y: item.y * size.height)
                        copy.rotate(by: .degrees(item.angle))
                        copy.scaleBy(x: item.scale, y: item.scale)
                        copy.draw(symbol, at: .zero)
                    }
                } symbols: {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                        Image(systemName: symbol.name)
                            .font(.system(size: 26))
                            .foregroundStyle(symbol.color)
                            .tag(index)
                    }
                }
                .mask(clearUnderHeader)
            }
    }
}

// MARK: - Bead chains

/// The bead chains laid diagonally across the page, one color to a chain in
/// bead-stair order (1 red, 2 green, 3 pink … 10 gold), each chain made of
/// bars of its own number of beads.
private struct BeadChainsWallpaper: View {
    let isDark: Bool

    static let beadColors: [Color] = [
        rgb(0.86, 0.20, 0.20), rgb(0.20, 0.65, 0.30), rgb(0.95, 0.55, 0.70),
        rgb(0.98, 0.83, 0.25), rgb(0.45, 0.75, 0.95), rgb(0.70, 0.55, 0.85),
        rgb(0.92, 0.92, 0.90), rgb(0.55, 0.35, 0.20), rgb(0.15, 0.25, 0.60),
        rgb(0.85, 0.65, 0.20)
    ]

    var body: some View {
        LinearGradient(
            colors: isDark
                ? [rgb(0.09, 0.09, 0.11), rgb(0.06, 0.06, 0.08)]
                : [rgb(0.98, 0.97, 0.94), rgb(0.95, 0.94, 0.91)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            Canvas { context, size in
                let reach = hypot(size.width, size.height)
                context.translateBy(x: size.width / 2, y: size.height / 2)
                context.rotate(by: .degrees(-32))
                context.opacity = isDark ? 0.30 : 0.34
                let bead: CGFloat = 9
                let rowGap: CGFloat = 58
                var row = 0
                var y = -reach / 2
                while y < reach / 2 {
                    let number = row % 10 + 1
                    let color = Self.beadColors[number - 1]
                    // The chain's wire under its beads.
                    var wire = Path()
                    wire.move(to: CGPoint(x: -reach / 2, y: y))
                    wire.addLine(to: CGPoint(x: reach / 2, y: y))
                    context.stroke(wire, with: .color(isDark ? .white.opacity(0.25) : .black.opacity(0.18)),
                                   lineWidth: 1)
                    var x = -reach / 2 + CGFloat(row % 3) * 11
                    while x < reach / 2 {
                        for _ in 0..<number where x < reach / 2 {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x, y: y - bead / 2, width: bead, height: bead)),
                                with: .color(color)
                            )
                            x += bead + 1
                        }
                        x += 9
                    }
                    y += rowGap
                    row += 1
                }
            }
            .mask(clearUnderHeader)
        }
    }
}

// MARK: - Pink tower

/// Ten pink bands, deepening toward the bottom and growing like the cubes:
/// the first one the height of a centimeter cube, the last ten times it.
private struct PinkTowerWallpaper: View {
    let isDark: Bool

    var body: some View {
        Canvas { context, size in
            let top: SIMD3<Double> = isDark ? [0.16, 0.09, 0.12] : [1.00, 0.95, 0.96]
            let bottom: SIMD3<Double> = isDark ? [0.36, 0.15, 0.23] : [0.97, 0.75, 0.82]
            let unit = size.height / 55
            var y: CGFloat = 0
            for cube in 1...10 {
                let mix = top + (bottom - top) * (Double(cube - 1) / 9)
                let color = Color(red: mix.x, green: mix.y, blue: mix.z)
                let height = unit * CGFloat(cube)
                // A hair taller than its step, so no seam shows between bands.
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: height + 1)), with: .color(color))
                y += height
            }
        }
    }
}

// MARK: - Photo

/// Her photo, already blurred when she picked it, under a wash that keeps the
/// tiles and bars readable.
private struct PhotoWallpaper: View {
    let isDark: Bool
    private let photo = AssistantWallpaperPhoto.shared

    var body: some View {
        Color(.systemGroupedBackground)
            .overlay {
                if let image = photo.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay { isDark ? Color.black.opacity(0.45) : Color.white.opacity(0.55) }
            .clipped()
            .onAppear { photo.loadIfNeeded() }
    }
}

// MARK: - Helpers

/// A pattern's mask: clear behind the date header, fading in below it, so the
/// date never sits on beads or leaves.
private let clearUnderHeader = LinearGradient(
    stops: [.init(color: .clear, location: 0.06), .init(color: .black, location: 0.2)],
    startPoint: .top,
    endPoint: .bottom
)

private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
    Color(red: red, green: green, blue: blue)
}
