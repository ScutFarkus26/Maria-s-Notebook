// PieMenu.swift
// Pie menu components for RootView quick actions

import SwiftUI

// MARK: - Pie Menu Action

enum PieMenuAction: String, CaseIterable, Hashable {
    case newPresentation
    case newWorkItem
    case recordPractice
    case newTodo
    case newNote

    var icon: String {
        switch self {
        case .newPresentation: return "person.crop.rectangle.stack"
        case .newWorkItem: return "tray.and.arrow.down"
        case .recordPractice: return "figure.run"
        case .newTodo: return "checklist.checked"
        case .newNote: return "square.and.pencil"
        }
    }

    var label: String {
        switch self {
        case .newPresentation: return "Present"
        case .newWorkItem: return "Work"
        case .recordPractice: return "Practice"
        case .newTodo: return "Todo"
        case .newNote: return "Note"
        }
    }

    var color: Color {
        switch self {
        case .newPresentation: return .blue
        case .newWorkItem: return .orange
        case .recordPractice: return .pink
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
        case .recordPractice:
            return [Color.pink, Color.red]
        case .newTodo:
            return [Color.mint, Color.green]
        case .newNote:
            return [Color.purple, Color.indigo]
        }
    }

    private var caseIndex: Int {
        Self.allCases.firstIndex(of: self)!
    }

    private static var segmentSize: Double {
        360.0 / Double(allCases.count)
    }

    var startAngle: Double {
        -180.0 + Double(caseIndex) * Self.segmentSize
    }

    var endAngle: Double {
        startAngle + Self.segmentSize
    }

    var centerAngle: Double {
        (startAngle + endAngle) / 2
    }

    var animationDelay: Double {
        Double(caseIndex) * 0.025
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
                            ? [action.gradientColors[0].opacity(UIConstants.OpacityConstants.barelyTransparent), action.gradientColors[1].opacity(UIConstants.OpacityConstants.barelyTransparent)]
                            : [action.gradientColors[0].opacity(0.55), action.gradientColors[1].opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            slice
                .strokeBorder(
                    isHighlighted ? Color.white.opacity(UIConstants.OpacityConstants.barelyTransparent) : Color.white.opacity(UIConstants.OpacityConstants.statusBg),
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
            .shadow(color: .black.opacity(UIConstants.OpacityConstants.moderate), radius: 2, x: 0, y: 1)
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
