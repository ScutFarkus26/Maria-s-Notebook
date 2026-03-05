// LessonsFilterState.swift
// Added debounced search text (200ms delay) to prevent heavy filter recomputation on every keystroke.
// The debouncedSearchText property updates after user stops typing, reducing database queries.

import Foundation
import SwiftUI

@Observable
@MainActor
final class LessonsFilterState {
    var selectedSubject: String?
    var selectedGroup: String?
    var searchText: String = "" {
        didSet {
            scheduleDebounce()
        }
    }
    var expandedSubjects: Set<String> = []

    var sourceFilter: LessonSource? // nil means All
    var personalKindFilter: PersonalLessonKind? // nil means All Types

    // New filter properties for chip bar
    var hasAttachmentFilter: Bool = false
    var needsAttentionFilter: Bool = false

    // Debounced search text for filtering (updates ~200ms after user stops typing)
    private(set) var debouncedSearchText: String = ""
    
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(200)
    
    init() {
        // Initialize debounced text to current search text
        debouncedSearchText = searchText
    }
    
    private func scheduleDebounce() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: debounceInterval)
                debouncedSearchText = searchText
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    /// Load from persisted raw strings (typically stored via SceneStorage in the view)
    func loadFromPersisted(
        subjectRaw: String,
        groupRaw: String,
        searchRaw: String,
        expandedRaw: String,
        sourceRaw: String,
        personalKindRaw: String,
        hasAttachmentRaw: String = "",
        needsAttentionRaw: String = ""
    ) {
        self.selectedSubject = subjectRaw.trimmed().isEmpty ? nil : subjectRaw
        self.selectedGroup = groupRaw.trimmed().isEmpty ? nil : groupRaw
        self.searchText = searchRaw
        self.expandedSubjects = LessonsFilterPersistence.deserializeExpandedSubjects(expandedRaw)
        self.sourceFilter = sourceRaw.trimmed().isEmpty ? nil : LessonSource(rawValue: sourceRaw)
        self.personalKindFilter = personalKindRaw.trimmed().isEmpty ? nil : PersonalLessonKind(rawValue: personalKindRaw)
        self.hasAttachmentFilter = hasAttachmentRaw == "true"
        self.needsAttentionFilter = needsAttentionRaw == "true"
    }

    /// Create the raw strings suitable for persistence
    func makePersisted() -> (
        subjectRaw: String,
        groupRaw: String,
        searchRaw: String,
        expandedRaw: String,
        sourceRaw: String,
        personalKindRaw: String,
        hasAttachmentRaw: String,
        needsAttentionRaw: String
    ) {
        let subjectRaw = (selectedSubject?.trimmed() ?? "")
        let groupRaw = (selectedGroup?.trimmed() ?? "")
        let searchRaw = searchText
        let expandedRaw = LessonsFilterPersistence.serializeExpandedSubjects(expandedSubjects)
        let sourceRaw = sourceFilter?.rawValue ?? ""
        let personalKindRaw = personalKindFilter?.rawValue ?? ""
        let hasAttachmentRaw = hasAttachmentFilter ? "true" : ""
        let needsAttentionRaw = needsAttentionFilter ? "true" : ""
        return (subjectRaw, groupRaw, searchRaw, expandedRaw, sourceRaw, personalKindRaw, hasAttachmentRaw, needsAttentionRaw)
    }
}
