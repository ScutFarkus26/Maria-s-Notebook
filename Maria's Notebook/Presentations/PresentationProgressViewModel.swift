import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class PresentationProgressViewModel: ObservableObject {
    // MARK: - Published State
    @Published private(set) var presentations: [PresentationWithCachedData] = []
    @Published private(set) var isLoading = false

    // MARK: - Dependencies
    private var modelContext: ModelContext?

    // MARK: - Cache
    private var lessonCache: [UUID: Lesson] = [:]
    private var lastPresentationIDs: Set<UUID> = []

    // MARK: - Public API
    func update(
        modelContext: ModelContext,
        presentations: [LessonAssignment],
        filterState: PresentationState?,
        searchText: String
    ) {
        self.modelContext = modelContext

        // Check if presentations changed
        let currentIDs = Set(presentations.map { $0.id })
        if currentIDs == lastPresentationIDs && !lessonCache.isEmpty {
            // Only re-filter, don't reload
            filterPresentations(presentations, filterState: filterState, searchText: searchText)
            return
        }

        lastPresentationIDs = currentIDs
        loadPresentations(presentations, filterState: filterState, searchText: searchText)
    }

    // MARK: - Private Methods
    private func loadPresentations(
        _ presentations: [LessonAssignment],
        filterState: PresentationState?,
        searchText: String
    ) {
        isLoading = true

        // Batch fetch all lessons
        let lessonIDs = presentations.compactMap { UUID(uuidString: $0.lessonID) }
        lessonCache = fetchLessons(lessonIDs)

        // Build cached data
        let cached = presentations.compactMap { presentation -> PresentationWithCachedData? in
            guard let lessonID = UUID(uuidString: presentation.lessonID),
                  let lesson = lessonCache[lessonID],
                  let context = modelContext else { return nil }

            let workStats = presentation.workCompletionStats(from: context)
            let practiceCount = presentation.fetchRelatedPracticeSessions(from: context).count

            return PresentationWithCachedData(
                presentation: presentation,
                lesson: lesson,
                workStats: workStats,
                practiceCount: practiceCount
            )
        }

        self.presentations = cached
        isLoading = false

        // Apply filter
        filterPresentations(presentations, filterState: filterState, searchText: searchText)
    }

    private func filterPresentations(
        _ presentations: [LessonAssignment],
        filterState: PresentationState?,
        searchText: String
    ) {
        var filtered = self.presentations

        // Filter by state
        if let state = filterState {
            filtered = filtered.filter { $0.presentation.state == state }
        }

        // Filter by search (use cached lesson)
        if !searchText.isEmpty {
            filtered = filtered.filter { cached in
                cached.lesson.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        self.presentations = filtered
    }

    private func fetchLessons(_ ids: [UUID]) -> [UUID: Lesson] {
        guard let modelContext = modelContext else { return [:] }

        let descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate<Lesson> { lesson in
                ids.contains(lesson.id)
            }
        )

        let lessons = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }
}

struct PresentationWithCachedData: Identifiable {
    let presentation: LessonAssignment
    let lesson: Lesson
    let workStats: (completed: Int, total: Int)
    let practiceCount: Int

    var id: UUID { presentation.id }
}
