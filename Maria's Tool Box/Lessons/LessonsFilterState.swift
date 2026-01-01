import Foundation
import SwiftUI
import Combine

final class LessonsFilterState: ObservableObject {
    @Published var selectedSubject: String? = nil
    @Published var selectedGroup: String? = nil
    @Published var searchText: String = ""
    @Published var expandedSubjects: Set<String> = []

    @Published var sourceFilter: LessonSource? = nil // nil means All
    @Published var personalKindFilter: PersonalLessonKind? = nil // nil means All Types

    /// Load from persisted raw strings (typically stored via SceneStorage in the view)
    func loadFromPersisted(subjectRaw: String, groupRaw: String, searchRaw: String, expandedRaw: String, sourceRaw: String, personalKindRaw: String) {
        self.selectedSubject = subjectRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subjectRaw
        self.selectedGroup = groupRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : groupRaw
        self.searchText = searchRaw
        self.expandedSubjects = LessonsFilterPersistence.deserializeExpandedSubjects(expandedRaw)
        self.sourceFilter = sourceRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : LessonSource(rawValue: sourceRaw)
        self.personalKindFilter = personalKindRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : PersonalLessonKind(rawValue: personalKindRaw)
    }

    /// Create the raw strings suitable for persistence
    func makePersisted() -> (subjectRaw: String, groupRaw: String, searchRaw: String, expandedRaw: String, sourceRaw: String, personalKindRaw: String) {
        let subjectRaw = (selectedSubject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        let groupRaw = (selectedGroup?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        let searchRaw = searchText
        let expandedRaw = LessonsFilterPersistence.serializeExpandedSubjects(expandedSubjects)
        let sourceRaw = sourceFilter?.rawValue ?? ""
        let personalKindRaw = personalKindFilter?.rawValue ?? ""
        return (subjectRaw, groupRaw, searchRaw, expandedRaw, sourceRaw, personalKindRaw)
    }
}

