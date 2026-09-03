// LessonsRootViewPanes.swift
// Column panes for LessonsRootView - extracted for maintainability

import SwiftUI
import CoreData
import OSLog

nonisolated private let logger = Logger.lessons

// MARK: - LessonsRootView Panes Extension

extension LessonsRootView {

    // MARK: - Lessons Content Column

    @ViewBuilder
    var lessonsContentColumn: some View {
        if showingParshas {
            ParshaBrowseView { lesson in
                selectedLessonDetail = lesson
            }
        } else {
            mapContentColumn
        }
    }

    // MARK: - Map Content Column

    @ViewBuilder
    private var mapContentColumn: some View {
        VStack(spacing: 0) {
            lessonsFilterBar
            Divider()
            mapOrThreadView
        }
    }

    @ViewBuilder
    private var mapOrThreadView: some View {
        if let focusedThread {
            let lessonsInThread: [CDLesson] = lessonsForThread(focusedThread)
            let sequences: [String] = groupsForSelectedArea
            LessonsScopeThreadFocusView(
                threadKey: focusedThread,
                lessons: lessonsInThread,
                sequences: sequences,
                isEditing: isEditingMap,
                onBack: { self.focusedThread = nil },
                onSelectLesson: { lesson in selectedLessonDetail = lesson },
                onMoveLessonEarlier: { lesson in
                    moveLessonInSequence(
                        lesson: lesson,
                        direction: -1,
                        sequence: focusedThread.sequence,
                        ungroupedLabel: "Ungrouped"
                    )
                },
                onMoveLessonLater: { lesson in
                    moveLessonInSequence(
                        lesson: lesson,
                        direction: 1,
                        sequence: focusedThread.sequence,
                        ungroupedLabel: "Ungrouped"
                    )
                },
                onMoveLessonToSequence: { lesson, targetSequence in
                    moveLessonToSequence(lesson: lesson, newSequence: targetSequence)
                },
                onCreateLessonAfter: { lesson in
                    addLessonContext = AddLessonContext(source: lesson)
                },
                onReorderLessons: { source, destination in
                    let groupLessons = lessonsForSequence(focusedThread.sequence, ungroupedLabel: "Ungrouped")
                    moveLessonsInArea(from: source, to: destination, in: groupLessons)
                }
            )
        } else {
            LessonsScopeMapView(
                lessons: filteredLessonsForMap,
                selectedArea: selectedArea,
                spine: Binding(
                    get: { mapSpine },
                    set: { mapSpineRaw = $0.rawValue }
                ),
                isEditing: isEditingMap,
                onSelectThread: { key in
                    self.focusedThread = key
                    if !key.area.isEmpty {
                        filterState.selectedArea = key.area
                    }
                    syncReorderableSequences()
                },
                onMoveSequences: { source, destination, area in
                    let currentSequences = reorderableSequences.isEmpty
                        ? helper.groups(for: area, lessons: Array(lessons))
                        : reorderableSequences
                    moveSequences(from: source, to: destination, in: currentSequences, overrideArea: area)
                },
                onConfigureTrack: { key in
                    handleConfigureTrack(key.sequence, area: key.area)
                },
                onReorderSections: { key in
                    handleReorderSections(key.sequence, area: key.area)
                },
                onFocusArea: { area in
                    filterState.selectedArea = area
                    syncReorderableSequences()
                },
                onClearAreaFocus: {
                    filterState.selectedArea = nil
                    isEditingMap = false
                }
            )
        }
    }

    /// Lessons filtered for the map view — applies chip-bar filters but not the search text
    /// (search text filtering is handled via lessonsForArea which already applies it).
    private var filteredLessonsForMap: [CDLesson] {
        var result = lessonsForArea

        if let source = filterState.sourceFilter {
            result = result.filter { $0.source == source }
        }
        if let kind = filterState.personalKindFilter {
            result = result.filter { $0.personalKind == kind }
        }
        if filterState.hasAttachmentFilter {
            result = result.filter { $0.pagesFileBookmark != nil || $0.pagesFileRelativePath != nil }
        }
        if filterState.needsAttentionFilter, let counts = statusCounts {
            result = result.filter { guard let id = $0.id else { return false }; return counts[id, default: 0] > 0 }
        }

        return result
    }

    private var lessonsFilterBar: some View {
        LessonsFilterChipBar(
            sourceFilter: $filterState.sourceFilter,
            personalKindFilter: $filterState.personalKindFilter,
            formatFilter: $filterState.formatFilter,
            hasAttachmentFilter: $filterState.hasAttachmentFilter,
            needsAttentionFilter: $filterState.needsAttentionFilter
        )
    }

    // MARK: - Navigation helpers

    /// Switches to Map mode focused on the lesson's (area, sequence) thread.
    /// Used by the "Locate in Map" action from the detail pane.
    func locateLessonInMap(_ lesson: CDLesson) {
        let area = lesson.area.trimmed()
        guard !area.isEmpty else { return }
        showingParshas = false
        focusedThread = ThreadKey(area: area, sequence: lesson.sequence)
        filterState.selectedArea = area
        syncReorderableSequences()
        selectedLessonDetail = lesson
    }

    /// Returns the lessons that belong to a (area, sequence) thread.
    /// An empty sequence string in the key denotes the synthetic "ungrouped" bucket.
    private func lessonsForThread(_ key: ThreadKey) -> [CDLesson] {
        let areaKey = key.area.trimmed().lowercased()
        let sequenceKey = key.sequence.trimmed().lowercased()
        let isUngroupedBucket = sequenceKey.isEmpty

        return lessons.filter { lesson in
            guard lesson.area.trimmed().lowercased() == areaKey else { return false }
            let lessonSequenceTrimmed = lesson.sequence.trimmed().lowercased()
            if isUngroupedBucket {
                return lessonSequenceTrimmed.isEmpty
            }
            return lessonSequenceTrimmed == sequenceKey
        }
    }

    // MARK: - Track / Section sheet helpers

    private func handleReorderSections(_ sequence: String, area: String) {
        reorderSectionsItem = SectionReorderItem(area: area, sequence: sequence)
    }

    private func handleConfigureTrack(_ sequence: String, area: String) {
        trackSettingsItem = TrackSettingsItem(area: area, sequence: sequence)
    }

    // MARK: - Lesson Detail Pane (Right)

    func lessonDetailPane(lesson: CDLesson) -> some View {
        LessonDetailView(
            lesson: lesson,
            allLessons: Array(lessons),
            onSave: { _ in
                saveCoordinator.save(viewContext, reason: "Update lesson")
            },
            onDone: {
                selectedLessonDetail = nil
            },
            onLocateInMap: { lesson in
                locateLessonInMap(lesson)
            },
            onSchedule: { lesson in
                lessonToSchedule = lesson
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.paneBackground)
    }

    // MARK: - Reorder helper (still used by reordering extension)

    func lessonsForSequence(_ sequence: String, ungroupedLabel: String) -> [CDLesson] {
        lessonsForArea.filter { lesson in
            let lessonSequenceTrimmed = lesson.sequence.trimmed()
            if sequence == ungroupedLabel {
                return lessonSequenceTrimmed.isEmpty
            } else {
                return lessonSequenceTrimmed.caseInsensitiveCompare(sequence.trimmed()) == .orderedSame
            }
        }.sorted { lhs, rhs in
            if lhs.orderInSequence != rhs.orderInSequence {
                return lhs.orderInSequence < rhs.orderInSequence
            }
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }
}
