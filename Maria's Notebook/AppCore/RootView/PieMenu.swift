// PieMenu.swift
// Pie menu components for RootView quick actions

import SwiftUI

// MARK: - Pie Menu Action

enum PieMenuAction: String, CaseIterable, Hashable {
    case newPresentation
    case newWorkItem
    case newTodo
    case newNote

    var icon: String {
        switch self {
        case .newPresentation: return "person.crop.rectangle.stack"
        case .newWorkItem: return "tray.and.arrow.down"
        case .newTodo: return "checklist.checked"
        case .newNote: return "square.and.pencil"
        }
    }

    var label: String {
        switch self {
        case .newPresentation: return "Present"
        case .newWorkItem: return "Work"
        case .newTodo: return "Todo"
        case .newNote: return "Note"
        }
    }

    var color: Color {
        switch self {
        case .newPresentation: return .blue
        case .newWorkItem: return .orange
        case .newTodo: return .green
        case .newNote: return .purple
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .newPresentation:
            return [Color.cyan, Color.blue]
        case .newWorkItem:
            return [Color.orange, Color.pink]
        case .newTodo:
            return [Color.mint, Color.green]
        case .newNote:
            return [Color.purple, Color.indigo]
        }
    }

    var startAngle: Double {
        switch self {
        case .newPresentation: return -180
        case .newWorkItem: return -90
        case .newTodo: return 0
        case .newNote: return 90
        }
    }

    var endAngle: Double {
        startAngle + 90
    }

    var centerAngle: Double {
        (startAngle + endAngle) / 2
    }

    var animationDelay: Double {
        switch self {
        case .newPresentation: return 0.00
        case .newWorkItem: return 0.03
        case .newTodo: return 0.06
        case .newNote: return 0.09
        }
    }
}

// MARK: - Pie Menu Segment

struct PieMenuSegment: View {
    let action: PieMenuAction
    let isExpanded: Bool
    let isHighlighted: Bool
    let radius: CGFloat

    private let innerRadius: CGFloat = 35

    var body: some View {
        let slice = PieSlice(
            startAngle: .degrees(action.startAngle),
            endAngle: .degrees(action.endAngle),
            innerRadius: innerRadius,
            outerRadius: radius
        )

        ZStack {
            slice
                .fill(
                    LinearGradient(
                        colors: isHighlighted
                            ? [action.gradientColors[0].opacity(0.95), action.gradientColors[1].opacity(0.95)]
                            : [action.gradientColors[0].opacity(0.55), action.gradientColors[1].opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            slice
                .strokeBorder(
                    isHighlighted ? Color.white.opacity(0.95) : Color.white.opacity(0.35),
                    lineWidth: isHighlighted ? 2.4 : 1.2
                )

            VStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(action.label)
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
            }
            .foregroundStyle(.white)
            .offset(iconOffset)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .scaleEffect(isExpanded ? (isHighlighted ? 1.08 : 1.0) : 0.2)
        .rotationEffect(.degrees(isExpanded ? 0 : 14))
        .opacity(isExpanded ? 1.0 : 0.0)
        .adaptiveAnimation(
            .spring(response: 0.42, dampingFraction: 0.68)
                .delay(action.animationDelay),
            value: isExpanded
        )
        .adaptiveAnimation(.easeInOut(duration: 0.15), value: isHighlighted)
    }

    private var iconOffset: CGSize {
        let iconRadius = (innerRadius + radius) / 2
        let radians = action.centerAngle * .pi / 180
        return CGSize(width: cos(radians) * iconRadius, height: sin(radians) * iconRadius)
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

        let innerStart = CGPoint(
            x: center.x + adjustedInnerRadius * cos(CGFloat(startAngle.radians)),
            y: center.y + adjustedInnerRadius * sin(CGFloat(startAngle.radians))
        )
        path.move(to: innerStart)

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

        let innerEnd = CGPoint(
            x: center.x + adjustedInnerRadius * cos(CGFloat(endAngle.radians)),
            y: center.y + adjustedInnerRadius * sin(CGFloat(endAngle.radians))
        )
        path.addLine(to: innerEnd)

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
