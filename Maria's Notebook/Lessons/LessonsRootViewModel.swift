import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
final class LessonsRootViewModel: ObservableObject {
    @Published private(set) var filteredLessons: [Lesson] = []
    
    init() { }
    
    func recomputeFilteredLessons(all lessons: [Lesson], filterState: LessonsFilterState, using filterer: LessonsViewModel) {
        self.filteredLessons = filterer.filteredLessons(
            lessons: lessons,
            sourceFilter: filterState.sourceFilter,
            personalKindFilter: filterState.personalKindFilter,
            searchText: filterState.searchText,
            selectedSubject: filterState.selectedSubject,
            selectedGroup: filterState.selectedGroup
        )
    }
    
    @discardableResult
    func createStudentLesson(basedOn lesson: Lesson?, in context: ModelContext) -> StudentLesson {
        let lessonID = lesson?.id ?? UUID()
        let newSL = StudentLesson(
            id: UUID(),
            lessonID: lessonID,
            studentIDs: [],
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        if let base = lesson { newSL.lesson = base }
        newSL.syncSnapshotsFromRelationships()
        context.insert(newSL)
        context.safeSave()
        return newSL
    }
    
    func seedSamplesIfNeeded(lessons: [Lesson], into context: ModelContext) {
        guard lessons.isEmpty else { return }
        let samples = [
            Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Intro to base-10", writeUp: "A foundational presentation of the decimal system."),
            Lesson(name: "Parts of Speech", subject: "Language", group: "Grammar", subheading: "Nouns and Verbs", writeUp: "Identify and classify parts of speech in simple sentences.")
        ]
        for l in samples { context.insert(l) }
        context.safeSave()
    }
}
