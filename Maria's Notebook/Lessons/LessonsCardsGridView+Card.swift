import SwiftUI
import CoreData

// MARK: - Grid Item & Card

extension LessonsCardsGridView {

    @ViewBuilder
    func gridItemView(_ item: LessonsGridItem) -> some View {
        switch item {
        case .introduction(let intro):
            IntroductionCard(
                introduction: intro,
                subjectColor: selectedSubject.map { AppColors.color(forSubject: $0) } ?? .accentColor,
                onTap: { introductionToShow = intro }
            )
        case .lesson(let lesson):
            card(lesson)
        }
    }

    @ViewBuilder
    func card(_ lesson: CDLesson) -> some View {
        let isDragging = isManualMode && draggingLessonID == lesson.id
        let isHover = hoverTargetID == lesson.id
        let isSelected = selectedLessonID == lesson.id
        let shouldMeasureFrames = isManualMode && onReorder != nil

        LessonCardContainer(
            lesson: lesson,
            isDragging: isDragging,
            isHover: isHover,
            isSelected: isSelected,
            hasAppeared: hasAppeared,
            gridNamespace: gridNamespace,
            disableAnimations: draggingLessonID != nil,
            shouldMeasureFrames: shouldMeasureFrames,
            shouldUseMatchedGeometry: shouldMeasureFrames,
            statusCount: lesson.id.flatMap { statusCounts?[$0] },
            lastPresentedDate: lesson.id.flatMap { lastPresentedDates?[$0] }
        )
        .jiggle(isActive: isManualMode, seed: lessons.firstIndex(where: { $0.id == lesson.id }) ?? 0)
#if os(macOS)
        .highPriorityGesture(TapGesture(count: 1).onEnded { onTapLesson(lesson) })
#else
        .onTapGesture { onTapLesson(lesson) }
#endif
        .when(isManualMode && onReorder != nil) { view in
            view.simultaneousGesture(longPressThenDrag(for: lesson))
        }
        .when(!isManualMode && onActivateJiggle != nil) { view in
            view.onLongPressGesture(minimumDuration: 0.4) {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                onActivateJiggle?()
            }
        }
#if os(macOS)
        .overlay(RightClickCatcher(onRightClick: { onGiveLesson?(lesson) }))
#endif
#if !os(macOS)
        .contextMenu {
            Button {
                onGiveLesson?(lesson)
            } label: {
                Label("Give CDLesson", systemImage: "person.crop.circle.badge.checkmark")
            }
        }
#endif
    }
}
