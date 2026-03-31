import SwiftUI
import CoreData

struct LessonItemFramePreference: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct LessonCardContainer: View {
    let lesson: CDLesson
    let isDragging: Bool
    let isHover: Bool
    let isSelected: Bool
    let hasAppeared: Bool
    let gridNamespace: Namespace.ID
    let disableAnimations: Bool
    let shouldMeasureFrames: Bool
    let shouldUseMatchedGeometry: Bool
    let statusCount: Int?
    let lastPresentedDate: Date?

    var body: some View {
        let card = PaperLessonCard(
            lesson: lesson,
            statusCount: statusCount,
            lastPresentedDate: lastPresentedDate
        )

        let baseView = Group {
            if shouldUseMatchedGeometry {
                card.matchedGeometryEffect(id: lesson.id, in: gridNamespace)
            } else {
                card
            }
        }
        .when(hasAppeared) { view in
            view.transition(.opacity.combined(with: .scale(scale: 0.98)))
        }

        let overlaidView = baseView
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isDragging ? Color.accentColor.opacity(0.6) : Color.clear,
                        lineWidth: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isHover ? Color.accentColor.opacity(UIConstants.OpacityConstants.statusBg) : Color.clear,
                        style: StrokeStyle(lineWidth: 2, dash: [6, 6])
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

        overlaidView
            .transaction { tx in
                if disableAnimations { tx.animation = nil }
            }
            .contentShape(Rectangle())
            .background(
                Group {
                    if shouldMeasureFrames {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: LessonItemFramePreference.self,
                                value: [lesson.id ?? UUID(): proxy.frame(in: .named("lessonsGridScroll"))]
                            )
                        }
                    }
                }
            )
    }
}
