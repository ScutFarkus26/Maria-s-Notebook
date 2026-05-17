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
                areaColor: selectedArea.map { AppColors.color(forArea: $0) } ?? .accentColor,
                onTap: { introductionToShow = intro }
            )
        case .lesson(let lesson):
            card(lesson)
        }
    }

    @ViewBuilder
    func card(_ lesson: CDLesson) -> some View {
        cardBase(lesson)
            .modifier(LessonCardTapModifier(lesson: lesson, onTap: onTapLesson))
            #if os(macOS)
            .overlay(RightClickCatcher(onRightClick: { onGiveLesson?(lesson) }))
            #endif
            .contextMenu { cardContextMenu(lesson) }
    }

    private func cardBase(_ lesson: CDLesson) -> some View {
        LessonBrowseCard(
            lesson: lesson,
            isSelected: selectedLessonID == lesson.id,
            hasAppeared: hasAppeared,
            statusCount: lesson.id.flatMap { statusCounts?[$0] },
            lastPresentedDate: lesson.id.flatMap { lastPresentedDates?[$0] },
            onGiveLesson: onGiveLesson.map { handler in { handler(lesson) } },
            onLocateInMap: onLocateInMap.map { handler in { handler(lesson) } }
        )
    }

    @ViewBuilder
    private func cardContextMenu(_ lesson: CDLesson) -> some View {
        Button {
            onGiveLesson?(lesson)
        } label: {
            Label("Give Lesson", systemImage: "person.crop.circle.badge.checkmark")
        }
        if let onLocateInMap {
            Button {
                onLocateInMap(lesson)
            } label: {
                Label("Locate in Map", systemImage: "chart.bar.doc.horizontal")
            }
        }
        if let onReorderInOutline {
            Divider()
            Button {
                onReorderInOutline(lesson)
            } label: {
                Label("Reorder in Outline…", systemImage: "list.bullet.indent")
            }
        }
    }
}

private struct LessonCardTapModifier: ViewModifier {
    let lesson: CDLesson
    let onTap: (CDLesson) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.highPriorityGesture(TapGesture(count: 1).onEnded { onTap(lesson) })
        #else
        content.onTapGesture { onTap(lesson) }
        #endif
    }
}
