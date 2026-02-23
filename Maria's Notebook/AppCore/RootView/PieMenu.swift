// PieMenu.swift
// Pie menu components for RootView quick actions

import SwiftUI

// MARK: - Pie Menu Action

enum PieMenuAction: CaseIterable {
    case newPresentation
    case newWorkItem

    var icon: String {
        switch self {
        case .newPresentation: return "person.crop.rectangle.stack"
        case .newWorkItem: return "tray.and.arrow.down"
        }
    }

    var label: String {
        switch self {
        case .newPresentation: return "Present"
        case .newWorkItem: return "Work"
        }
    }

    var color: Color {
        switch self {
        case .newPresentation: return .blue
        case .newWorkItem: return .orange
        }
    }
}

// MARK: - Pie Menu Segment

struct PieMenuSegment: View {
    let action: PieMenuAction
    let isTop: Bool
    let isExpanded: Bool
    let isHighlighted: Bool
    let radius: CGFloat

    private let segmentAngle: Double = 180 // Each segment covers 180 degrees (half circle)
    private let innerRadius: CGFloat = 35

    var body: some View {
        ZStack {
            // Segment background
            PieSlice(
                startAngle: .degrees(isTop ? -180 : 0),
                endAngle: .degrees(isTop ? 0 : 180),
                innerRadius: innerRadius,
                outerRadius: radius
            )
            .fill(
                isHighlighted
                    ? action.color.opacity(0.9)
                    : Color.white.opacity(0.15)
            )
            .overlay(
                PieSlice(
                    startAngle: .degrees(isTop ? -180 : 0),
                    endAngle: .degrees(isTop ? 0 : 180),
                    innerRadius: innerRadius,
                    outerRadius: radius
                )
                .strokeBorder(
                    isHighlighted ? action.color : Color.white.opacity(0.3),
                    lineWidth: 1.5
                )
            )

            // Icon only, centered in segment
            Image(systemName: action.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isHighlighted ? .white : .white.opacity(0.9))
                .offset(y: isTop ? -(innerRadius + radius) / 2 : (innerRadius + radius) / 2)
        }
        .scaleEffect(isExpanded ? 1.0 : 0.01)
        .opacity(isExpanded ? 1.0 : 0.0)
    }
}

// MARK: - Pie Slice Shape

struct PieSlice: InsettableShape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let adjustedOuterRadius = outerRadius - insetAmount
        let adjustedInnerRadius = innerRadius + insetAmount

        var path = Path()

        // Start at inner arc
        let innerStart = CGPoint(
            x: center.x + adjustedInnerRadius * cos(CGFloat(startAngle.radians)),
            y: center.y + adjustedInnerRadius * sin(CGFloat(startAngle.radians))
        )
        path.move(to: innerStart)

        // Draw outer arc
        let outerStart = CGPoint(
            x: center.x + adjustedOuterRadius * cos(CGFloat(startAngle.radians)),
            y: center.y + adjustedOuterRadius * sin(CGFloat(startAngle.radians))
        )
        path.addLine(to: outerStart)
        path.addArc(
            center: center,
            radius: adjustedOuterRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        // Draw line to inner arc end
        let innerEnd = CGPoint(
            x: center.x + adjustedInnerRadius * cos(CGFloat(endAngle.radians)),
            y: center.y + adjustedInnerRadius * sin(CGFloat(endAngle.radians))
        )
        path.addLine(to: innerEnd)

        // Draw inner arc back
        path.addArc(
            center: center,
            radius: adjustedInnerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )

        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var slice = self
        slice.insetAmount += amount
        return slice
    }
}
