import SwiftUI
import SwiftData

// MARK: - Sheet Types & Content

extension PlanningWeekViewContent {

    enum ActiveSheet: Identifiable {
        case presentationDetail(UUID)
        case quickActions(UUID)
        case giveLessonDraft(UUID)
        case addLesson
        case inbox
        case aiPlanning

        var id: String {
            switch self {
            case .presentationDetail(let id): return "detail_\(id.uuidString)"
            case .quickActions(let id): return "quick_\(id.uuidString)"
            case .giveLessonDraft(let id): return "giveLessonDraft_\(id.uuidString)"
            case .addLesson: return "addLesson"
            case .inbox: return "inbox"
            case .aiPlanning: return "aiPlanning"
            }
        }
    }

    @ViewBuilder
    func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .presentationDetail(let id):
            sheetForAssignment(id: id) { la in
                PresentationDetailView(lessonAssignment: la) { activeSheet = nil }
            }
        case .quickActions(let id):
            sheetForAssignment(id: id) { la in
                PresentationQuickActionsView(lessonAssignment: la) { activeSheet = nil }
            }
        case .giveLessonDraft(let id):
            sheetForGiveLessonDraft(id: id)
        case .addLesson:
            AddLessonView(defaultSubject: nil, defaultGroup: nil)
                .largeSheetSizing()
                .onDisappear {
                    onRefreshNeeded?()
                }
        case .inbox:
            InboxViewContent(
                lessonAssignments: inboxLessons,
                orderedUnscheduledLessons: orderedUnscheduledLessons,
                inboxOrderRaw: $inboxOrderRaw,
                onOpenDetails: { id in activeSheet = .presentationDetail(id) },
                onQuickActions: { id in activeSheet = .quickActions(id) },
                onPlanNext: { la in planNextLesson(for: la) },
                onUpdateOrder: { newOrderRaw in
                    inboxOrderRaw = newOrderRaw
                    saveCoordinator.save(modelContext, reason: "Updating inbox order")
                    onRefreshNeeded?()
                }
            )
            .largeSheetSizing()
        case .aiPlanning:
            AIPlanningAssistantView(mode: .wholeClass)
        }
    }

    // MARK: - Sheet Helpers

    @ViewBuilder
    private func sheetForAssignment<Content: View>(
        id: UUID,
        @ViewBuilder content: (LessonAssignment) -> Content
    ) -> some View {
        if let la = fetchLessonAssignment(by: id) {
            content(la)
        } else {
            ProgressView("Loading…")
                .frame(minWidth: 320, minHeight: 240)
                .task {
                    try? await Task.sleep(for: .milliseconds(100))
                    activeSheet = nil
                }
        }
    }

    @ViewBuilder
    private func sheetForGiveLessonDraft(id: UUID) -> some View {
        if let la = fetchLessonAssignment(by: id) {
            PresentationDetailView(lessonAssignment: la) { activeSheet = nil }
                .largeSheetSizing()
                .onDisappear {
                    if let current = fetchLessonAssignment(by: id) {
                        if current.lesson == nil && current.studentIDs.isEmpty {
                            modelContext.delete(current)
                            presentationRepository.save(reason: "Deleting empty draft")
                            onRefreshNeeded?()
                        }
                    }
                }
        } else {
            ProgressView("Preparing…")
                .frame(minWidth: 320, minHeight: 240)
                .task {
                    try? await Task.sleep(for: .milliseconds(100))
                    if case .giveLessonDraft(let currentId) = activeSheet, currentId == id {
                        activeSheet = nil
                    }
                }
        }
    }

    func fetchLessonAssignment(by id: UUID) -> LessonAssignment? {
        if let found = inboxLessons.first(where: { $0.id == id }) {
            return found
        }
        // Fallback to SwiftData fetch (PlanningWeekViewContent works with SwiftData LessonAssignment)
        var fetch = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == id })
        fetch.fetchLimit = 1
        return try? modelContext.fetch(fetch).first
    }
}
