import SwiftUI
import CoreData

// MARK: - Gestures

extension LessonsCardsGridView {

    func nearestTargetID(from startCenter: CGPoint, translation: CGSize, centers: [UUID: CGPoint]) -> UUID? {
        let endCenter = CGPoint(x: startCenter.x + translation.width, y: startCenter.y + translation.height)
        return centers.min(by: { lhs, rhs in
            let dl = hypot(lhs.value.x - endCenter.x, lhs.value.y - endCenter.y)
            let dr = hypot(rhs.value.x - endCenter.x, rhs.value.y - endCenter.y)
            return dl < dr
        })?.key
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func longPressThenDrag(for lesson: CDLesson) -> some Gesture {
        let press = LongPressGesture(minimumDuration: 0.25)
        let drag = DragGesture(minimumDistance: 1)
        return press.sequenced(before: drag)
            .onChanged { value in
                guard isManualMode else { return }
                switch value {
                case .first(true):
                    draggingLessonID = lesson.id
                case .second(true, let drag?):
                    if draggingLessonID == nil { draggingLessonID = lesson.id }
                    let subsetIDs = lessons.compactMap(\.id)
                    let centers: [UUID: CGPoint] = subsetIDs.reduce(into: [:]) { dict, id in
                        if let rect = itemFrames[id] { dict[id] = CGPoint(x: rect.midX, y: rect.midY) }
                    }
                    if let lessonID = lesson.id, let startCenter = centers[lessonID] {
                        let translation = drag.translation
                        let targetID = nearestTargetID(
                            from: startCenter, translation: translation, centers: centers
                        )
                        if let targetID {
                            hoverTargetID = targetID
                        }
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                defer {
                    hoverTargetID = nil
                    draggingLessonID = nil
                }
                guard isManualMode else { return }
                guard let fromIndex = lessons.firstIndex(where: { $0.id == lesson.id }) else { return }

                let subsetIDs = lessons.compactMap(\.id)
                let centers: [UUID: CGPoint] = subsetIDs.reduce(into: [:]) { dict, id in
                    if let rect = itemFrames[id] { dict[id] = CGPoint(x: rect.midX, y: rect.midY) }
                }

                let toIndex: Int
                if let hID = hoverTargetID, let idx = subsetIDs.firstIndex(of: hID) {
                    toIndex = idx
                } else {
                    var translation = CGSize.zero
                    if case .second(true, let drag?) = value { translation = drag.translation }
                    if let lessonID = lesson.id,
                       let startCenter = centers[lessonID],
                       let targetID = nearestTargetID(
                           from: startCenter, translation: translation, centers: centers
                       ),
                       let idx = subsetIDs.firstIndex(of: targetID) {
                        toIndex = idx
                    } else {
                        return
                    }
                }

                if toIndex == fromIndex { return }
                onReorder?(lesson, fromIndex, toIndex, lessons)
            }
    }

    var gridAnimation: Animation? {
        if draggingLessonID != nil || !hasAppeared {
            return nil
        } else {
            return .spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)
        }
    }
}

#Preview {
    let ctx = CoreDataStack.preview.viewContext
    let lesson1 = CDLesson(context: ctx)
    lesson1.name = "Decimal System"
    lesson1.subject = "Math"
    lesson1.group = "Number Work"
    lesson1.subheading = "Introduction to base-10"

    let lesson2 = CDLesson(context: ctx)
    lesson2.name = "Parts of Speech"
    lesson2.subject = "Language"
    lesson2.group = "Grammar"
    lesson2.subheading = "Nouns and Verbs"

    return LessonsCardsGridView(
        lessons: [lesson1, lesson2],
        isManualMode: false,
        onTapLesson: { _ in },
        onReorder: nil,
        onGiveLesson: nil,
        selectedSubject: "Math",
        selectedLessonID: nil,
        lastPresentedDates: nil,
        showIntroductionCards: true
    )
    .previewEnvironment()
}
