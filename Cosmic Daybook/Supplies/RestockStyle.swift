// RestockStyle.swift
// Restock's colors and the level glyph: three bars for Stocked, one for Low,
// none for Out (and Out solid), so the level reads by shape and never by
// color alone.

import SwiftUI

enum RestockStyle {
    /// Tiles and row cards.
    static let tileRadius: CGFloat = 14

    /// Out: a solid burnt orange with white on it (5.6:1).
    static let outFill = Color(red: 0.706, green: 0.220, blue: 0.043)
    static let outDetail = Color(red: 1.0, green: 0.882, blue: 0.820)

    /// Low: a pale amber with an amber edge.
    static let lowFill = Color(
        light: Color(red: 1.0, green: 0.953, blue: 0.878),
        dark: Color(red: 0.255, green: 0.176, blue: 0.075)
    )
    static let lowStroke = Color(red: 0.851, green: 0.541, blue: 0.110)
    static let lowText = Color(
        light: Color(red: 0.361, green: 0.180, blue: 0.0),
        dark: Color(red: 1.0, green: 0.851, blue: 0.659)
    )
    static let lowBar = Color(
        light: Color(red: 0.706, green: 0.325, blue: 0.035),
        dark: Color(red: 0.941, green: 0.627, blue: 0.251)
    )
    static let lowBarOff = Color(
        light: Color(red: 0.945, green: 0.839, blue: 0.678),
        dark: Color(red: 0.420, green: 0.290, blue: 0.125)
    )
}

/// Three small bars: as many filled as the level has (Stocked 3, Low 1),
/// and on Out three empty outlines.
struct RestockLevelBars: View {
    let level: RestockLevel

    private var filled: Int {
        switch level {
        case .stocked: 3
        case .low: 1
        case .out: 0
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                bar(isOn: index < filled)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func bar(isOn: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        switch level {
        case .stocked:
            shape.fill(isOn ? Color.primary.opacity(0.7) : Color.primary.opacity(0.12))
                .frame(width: 12, height: 6)
        case .low:
            shape.fill(isOn ? RestockStyle.lowBar : RestockStyle.lowBarOff)
                .frame(width: 12, height: 6)
        case .out:
            shape.strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
                .frame(width: 12, height: 6)
        }
    }
}

/// The small tag on a need's row: Out (solid), Low (outlined) or One-off.
struct RestockTag: View {
    /// The staple's level, or nil for a one-off.
    let level: RestockLevel?

    var body: some View {
        Text(level?.displayName ?? "One-off")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                if level == .low {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(RestockStyle.lowStroke, lineWidth: 1)
                }
            }
            .fixedSize()
    }

    private var foreground: Color {
        switch level {
        case .out: .white
        case .low: RestockStyle.lowText
        default: .secondary
        }
    }

    private var background: Color {
        switch level {
        case .out: RestockStyle.outFill
        case .low: RestockStyle.lowFill
        default: Color.primary.opacity(0.07)
        }
    }
}
