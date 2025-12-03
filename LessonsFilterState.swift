import Foundation
import SwiftUI
import Combine

final class LessonsFilterState: ObservableObject {
    @Published var selectedSubject: String? = nil
    @Published var selectedGroup: String? = nil
    @Published var searchText: String = ""
    @Published var expandedSubjects: Set<String> = []

    /// Load from persisted raw strings (typically stored via SceneStorage in the view)
    func loadFromPersisted(subjectRaw: String, groupRaw: String, searchRaw: String, expandedRaw: String) {
        self.selectedSubject = subjectRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subjectRaw
        self.selectedGroup = groupRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : groupRaw
        self.searchText = searchRaw
        self.expandedSubjects = LessonsFilterPersistence.deserializeExpandedSubjects(expandedRaw)
    }

    /// Create the raw strings suitable for persistence
    func makePersisted() -> (subjectRaw: String, groupRaw: String, searchRaw: String, expandedRaw: String) {
        let subjectRaw = (selectedSubject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        let groupRaw = (selectedGroup?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        let searchRaw = searchText
        let expandedRaw = LessonsFilterPersistence.serializeExpandedSubjects(expandedSubjects)
        return (subjectRaw, groupRaw, searchRaw, expandedRaw)
    }
}

