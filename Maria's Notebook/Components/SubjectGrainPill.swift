import SwiftUI

// MARK: - Subject Micro-Pattern Definitions

/// Defines the micro-pattern associated with a subject.
/// Each pattern renders a subtle, repeating motif that gives the pill a tactile identity.
enum SubjectMicroPattern {
    case waves        // Science, physics — sinusoidal undulation
    case grid         // Math, geometry — structured lattice
    case columns      // History, culture — architectural verticals
    case organic      // Botany, zoology — soft leaf-like curves
    case dots         // Sensorial — scattered tactile points
    case staves       // Music — horizontal staff lines
    case brushStroke  // Art — diagonal sweeps
    case radial       // Geography — concentric arcs
    case zigzag       // Practical life — woven/textile pattern
    case script       // Language, reading, writing — flowing baseline curves
    case hearts       // Grace & courtesy — gentle heart-rhythm waves
    case fallback     // Unknown subjects — sparse diagonal hash

    private static let patternMap: [String: SubjectMicroPattern] = [
        "math": .grid, "mathematics": .grid, "geometry": .grid,
        "science": .waves,
        "history": .columns, "culture": .columns,
        "language": .script, "language arts": .script, "reading": .script, "writing": .script,
        "botany": .organic, "zoology": .organic,
        "sensorial": .dots,
        "music": .staves,
        "art": .brushStroke,
        "geography": .radial,
        "practical life": .zigzag,
        "grace & courtesy": .hearts, "grace and courtesy": .hearts
    ]

    /// Maps a subject string to its characteristic micro-pattern.
    static func pattern(for subject: String) -> SubjectMicroPattern {
        let key = subject.lowercased().trimmingCharacters(in: .whitespaces)
        return patternMap[key] ?? .fallback
    }
}

// MARK: - Grain Texture Layer

/// Renders a pseudo-random noise grain using Canvas.
/// The grain is deterministic (seeded by position) so it doesn't flicker on redraw.
private struct GrainTexture: View {
    let color: Color
    /// Opacity of individual grain dots. Keep very low for watermark feel.
    let intensity: CGFloat

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 3
            let cols = Int(size.width / step)
            let rows = Int(size.height / step)

            for row in 0..<rows {
                for col in 0..<cols {
                    // Simple deterministic hash for pseudo-random opacity
                    let seed = (row &* 2654435761) ^ (col &* 2246822519)
                    let hash = UInt32(bitPattern: Int32(truncatingIfNeeded: seed))
                    let noise = CGFloat(hash % 256) / 255.0

                    // Only draw ~40% of cells to keep it sparse
                    guard noise > 0.6 else { continue }

                    let alpha = (noise - 0.6) / 0.4 * intensity
                    let x = CGFloat(col) * step
                    let y = CGFloat(row) * step

                    context.fill(
                        Path(CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(color.opacity(alpha))
                    )
                }
            }
        }
    }
}

// MARK: - Micro-Pattern Layer

/// Renders the subject-specific vector pattern using Canvas.
/// Strokes are intentionally thin and low-opacity to stay below conscious perception
/// at normal reading distance, creating a subliminal tactile texture.
private struct MicroPatternLayer: View {
    let pattern: SubjectMicroPattern
    let color: Color
    /// Master opacity for the entire pattern layer.
    let opacity: CGFloat

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            var path = Path()

            switch pattern {
            case .waves:
                // Horizontal sine waves
                let waveCount = 5
                let spacing = h / CGFloat(waveCount + 1)
                for i in 1...waveCount {
                    let baseY = spacing * CGFloat(i)
                    path.move(to: CGPoint(x: 0, y: baseY))
                    let segments = Int(w / 8)
                    for seg in 0...segments {
                        let x = CGFloat(seg) * 8
                        let yOffset = sin(CGFloat(seg) * 0.8 + CGFloat(i) * 0.5) * 3
                        path.addLine(to: CGPoint(x: x, y: baseY + yOffset))
                    }
                }

            case .grid:
                // Orthogonal grid lines
                let cellSize: CGFloat = 10
                var x: CGFloat = 0
                while x <= w {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                    x += cellSize
                }
                var y: CGFloat = 0
                while y <= h {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                    y += cellSize
                }

            case .columns:
                // Vertical columns with slight taper (architectural feel)
                let colWidth: CGFloat = 6
                let gap: CGFloat = 12
                var x: CGFloat = gap
                while x < w {
                    let rect = CGRect(x: x, y: h * 0.1, width: colWidth, height: h * 0.8)
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1.5, height: 1.5))
                    x += colWidth + gap
                }

            case .organic:
                // Gentle leaf-vein curves radiating from bottom-left
                for i in 0..<6 {
                    let angle = CGFloat(i) * .pi / 12 + .pi / 6
                    let length = min(w, h) * 0.9
                    let endX = cos(angle) * length
                    let endY = -sin(angle) * length
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addQuadCurve(
                        to: CGPoint(x: endX, y: h + endY),
                        control: CGPoint(x: endX * 0.4, y: h + endY * 0.3)
                    )
                }

            case .dots:
                // Scattered dots in a loose hex grid
                let spacing: CGFloat = 9
                var row = 0
                var y: CGFloat = spacing / 2
                while y < h {
                    let offset: CGFloat = (row % 2 == 0) ? 0 : spacing / 2
                    var x = offset + spacing / 2
                    while x < w {
                        path.addEllipse(in: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
                        x += spacing
                    }
                    y += spacing * 0.866 // hex row height
                    row += 1
                }

            case .staves:
                // Five horizontal staff lines (like sheet music)
                let staffTop = h * 0.2
                let staffBottom = h * 0.8
                let lineSpacing = (staffBottom - staffTop) / 4
                for i in 0..<5 {
                    let y = staffTop + CGFloat(i) * lineSpacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }

            case .brushStroke:
                // Diagonal sweeping lines
                let count = 7
                for i in 0..<count {
                    let startX = -w * 0.2 + CGFloat(i) * w * 0.2
                    path.move(to: CGPoint(x: startX, y: h))
                    path.addQuadCurve(
                        to: CGPoint(x: startX + w * 0.5, y: 0),
                        control: CGPoint(x: startX + w * 0.35, y: h * 0.3)
                    )
                }

            case .radial:
                // Concentric arcs from center
                let center = CGPoint(x: w * 0.5, y: h * 0.5)
                for i in 1...5 {
                    let radius = CGFloat(i) * min(w, h) * 0.12
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(-30),
                        endAngle: .degrees(210),
                        clockwise: false
                    )
                }

            case .zigzag:
                // Woven zigzag (textile feel)
                let amplitude: CGFloat = 4
                let period: CGFloat = 8
                let rowSpacing: CGFloat = 10
                var y: CGFloat = rowSpacing
                while y < h {
                    path.move(to: CGPoint(x: 0, y: y))
                    var x: CGFloat = 0
                    var up = true
                    while x < w {
                        x += period / 2
                        path.addLine(to: CGPoint(x: x, y: y + (up ? -amplitude : amplitude)))
                        up.toggle()
                    }
                    y += rowSpacing
                }

            case .script:
                // Flowing baseline curves (like cursive writing lines)
                let lineCount = 5
                let spacing = h / CGFloat(lineCount + 1)
                for i in 1...lineCount {
                    let baseY = spacing * CGFloat(i)
                    path.move(to: CGPoint(x: 0, y: baseY))
                    let segments = Int(w / 20)
                    for seg in 0..<segments {
                        let x0 = CGFloat(seg) * 20
                        let x1 = x0 + 20
                        let cpY = baseY + (seg % 2 == 0 ? -3 : 3)
                        path.addQuadCurve(
                            to: CGPoint(x: x1, y: baseY),
                            control: CGPoint(x: (x0 + x1) / 2, y: cpY)
                        )
                    }
                }

            case .hearts:
                // Gentle heart-rhythm wave (single smooth pulse)
                let lineCount = 4
                let spacing = h / CGFloat(lineCount + 1)
                for i in 1...lineCount {
                    let baseY = spacing * CGFloat(i)
                    path.move(to: CGPoint(x: 0, y: baseY))
                    var x: CGFloat = 0
                    while x < w {
                        // Flat segment
                        path.addLine(to: CGPoint(x: x + 12, y: baseY))
                        // Small bump up
                        path.addQuadCurve(
                            to: CGPoint(x: x + 20, y: baseY),
                            control: CGPoint(x: x + 16, y: baseY - 4)
                        )
                        // Flat
                        path.addLine(to: CGPoint(x: x + 24, y: baseY))
                        x += 28
                    }
                }

            case .fallback:
                // Sparse diagonal hash
                var x: CGFloat = -h
                while x < w {
                    path.move(to: CGPoint(x: x, y: h))
                    path.addLine(to: CGPoint(x: x + h, y: 0))
                    x += 14
                }
            }

            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                lineWidth: 0.8
            )
        }
    }
}

// MARK: - Combined Subject Grain Background

/// Composites the micro-pattern with a grain texture overlay.
/// The result is a colored, grainy watermark that gives each subject a unique tactile feel.
struct SubjectGrainBackground: View {
    let subject: String

    /// The subject's canonical color.
    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }

    private var microPattern: SubjectMicroPattern {
        SubjectMicroPattern.pattern(for: subject)
    }

    var body: some View {
        ZStack {
            // Base: very faint subject color wash
            subjectColor.opacity(0.04)

            // Layer 1: structural micro-pattern
            MicroPatternLayer(
                pattern: microPattern,
                color: subjectColor,
                opacity: 0.12
            )

            // Layer 2: grain texture for tactile depth
            GrainTexture(
                color: subjectColor,
                intensity: 0.15
            )
        }
        .drawingGroup() // Flatten layers for performance
    }
}

// MARK: - Subject Grain Pill

/// A pill component with a subject-specific grainy watermark background.
/// Use in presentation views, work item cards, and anywhere subjects need
/// a subtle visual identity beyond plain color.
struct SubjectGrainPill<Content: View>: View {
    let subject: String
    @ViewBuilder let content: () -> Content

    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(0.04))
                    .overlay {
                        SubjectGrainBackground(subject: subject)
                            .clipShape(Capsule())
                    }
            }
            .overlay {
                Capsule()
                    .stroke(subjectColor.opacity(0.15), lineWidth: 1)
            }
            .clipShape(Capsule())
    }
}

// MARK: - Convenience Wrapper

/// Quick subject pill with a leading color dot and text label.
struct SubjectGrainLabel: View {
    let subject: String
    let title: String

    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }

    var body: some View {
        SubjectGrainPill(subject: subject) {
            HStack(spacing: 8) {
                Circle()
                    .fill(subjectColor)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.primary)
            }
        }
    }
}
