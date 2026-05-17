import SwiftUI
import CoreData

/// A Browse-mode lesson card: wraps `PaperLessonCard` with selection styling
/// and (on macOS) hover-revealed quick action buttons. Tap and context menu
/// gestures are applied by the caller.
struct LessonBrowseCard: View {
    let lesson: CDLesson
    let isSelected: Bool
    let hasAppeared: Bool
    let statusCount: Int?
    let lastPresentedDate: Date?
    let onGiveLesson: (() -> Void)?
    let onLocateInMap: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        let card = PaperLessonCard(
            lesson: lesson,
            statusCount: statusCount,
            lastPresentedDate: lastPresentedDate
        )

        let baseView = Group {
            card
        }
        .when(hasAppeared) { view in
            view.transition(.opacity.combined(with: .scale(scale: 0.98)))
        }

        return baseView
            .overlay(alignment: .bottom) {
                hoverActionsOverlay
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .contentShape(Rectangle())
            #if os(macOS)
            .onHover { hovering in
                adaptiveWithAnimation(.easeInOut(duration: 0.18)) {
                    isHovered = hovering
                }
            }
            #endif
    }

    @ViewBuilder
    private var hoverActionsOverlay: some View {
        #if os(macOS)
        if isHovered, onGiveLesson != nil || onLocateInMap != nil {
            HStack(spacing: 6) {
                if let onGiveLesson {
                    quickActionButton(
                        title: "Give",
                        icon: "person.crop.circle.badge.checkmark",
                        action: onGiveLesson
                    )
                }
                if let onLocateInMap {
                    quickActionButton(
                        title: "Map",
                        icon: "chart.bar.doc.horizontal",
                        action: onLocateInMap
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(.regularMaterial)
            )
            .padding(.bottom, 10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        #else
        EmptyView()
        #endif
    }

    private func quickActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
            )
        }
        .buttonStyle(.plain)
    }
}
