// LessonsRootViewPanes.swift
// Column panes for LessonsRootView - extracted for maintainability

import SwiftUI
import CoreData
import OSLog

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
                onReorderLessons: { movedID, targetID in
                    moveLessonsInArea(moving: movedID, onto: targetID, sequence: focusedThread.sequence)
                }
            )
        } else {
            let layout = mapLayoutMemo.layout(
                for: filteredLessonsForMap,
                selectedArea: selectedArea,
                spine: mapSpine,
                in: viewContext
            )
            LessonsScopeMapView(
                layout: layout,
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
                onMoveSequences: { area, visibleOrder in
                    applySequenceOrder(visibleOrder, in: area)
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
            result = result.filter(\.hasAnyFile)
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
        // The card saves its own edits. `.id` gives each lesson a fresh card: without it,
        // clicking another lesson's pill kept the open card's drafts and file state, so
        // Save wrote lesson A over lesson B and Remove deleted A's file.
        LessonDetailView(
            lesson: lesson,
            allLessons: lessons,
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
        .id(lesson.objectID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.paneBackground)
    }

    // MARK: - Reorder helpers (used by the reordering extension)

    /// Every lesson in the selected area, whatever the filter chips hide: a reorder
    /// renumbers the whole sequence, never just the lessons on screen.
    func allLessonsInSelectedArea() -> [CDLesson] {
        guard let area = selectedArea?.trimmed(), !area.isEmpty else { return [] }
        return lessons
            .filter { !$0.isDeleted && $0.area.trimmed().caseInsensitiveCompare(area) == .orderedSame }
            .uniqueByID
    }

    /// One sequence of the selected area, every lesson in it, in map order.
    func lessonsForSequence(_ sequence: String, ungroupedLabel: String) -> [CDLesson] {
        LessonSequenceOrdering.sorted(allLessonsInSelectedArea().filter { lesson in
            let lessonSequenceTrimmed = lesson.sequence.trimmed()
            if sequence == ungroupedLabel {
                return lessonSequenceTrimmed.isEmpty
            } else {
                return lessonSequenceTrimmed.caseInsensitiveCompare(sequence.trimmed()) == .orderedSame
            }
        })
    }
}
