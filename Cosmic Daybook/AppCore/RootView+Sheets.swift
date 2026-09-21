import SwiftUI
import OSLog

// MARK: - Sheet Types & Content

extension RootView {

    /// The one sheet the root can show at a time. What used to sit beside a
    /// Bool (the command bar's pre-filled lesson, students, and todo title)
    /// rides along as an associated value, so nothing needs resetting on
    /// dismiss. The two store-driven alerts keep their own bindings.
    enum ActiveSheet: Identifiable {
        case presentationDraft(UUID)
        case newWorkItem(lessonID: UUID?, studentIDs: Set<UUID>)
        case workDetail(UUID)
        case recordPractice
        case newTodo(initialTitle: String)
        case search
        case quickNote(QuickNoteParams)
        case commandBar

        var id: String {
            switch self {
            case .presentationDraft(let id): return "presentationDraft_\(id.uuidString)"
            case .newWorkItem: return "newWorkItem"
            case .workDetail(let id): return "workDetail_\(id.uuidString)"
            case .recordPractice: return "recordPractice"
            case .newTodo: return "newTodo"
            case .search: return "search"
            case .quickNote(let params): return "quickNote_\(params.id.uuidString)"
            case .commandBar: return "commandBar"
            }
        }
    }

    /// A Bool binding for a caller that still flips a flag (the glass button):
    /// `true` presents `sheet`; `false` dismisses it only while it is the one up.
    func isPresenting(_ sheet: ActiveSheet) -> Binding<Bool> {
        Binding(
            get: { activeSheet?.id == sheet.id },
            set: { isPresented in
                if isPresented {
                    activeSheet = sheet
                } else if activeSheet?.id == sheet.id {
                    activeSheet = nil
                }
            }
        )
    }

    @ViewBuilder
    func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .presentationDraft(let draftID):
            PresentationDraftSheet(id: draftID) {
                activeSheet = nil
            }
            .largeSheetSizing()
        case .newWorkItem(let lessonID, let studentIDs):
            QuickNewWorkItemSheet(
                preSelectedLessonID: lessonID,
                preSelectedStudentIDs: studentIDs
            ) { workID in
                openWorkDetailAfterDismiss(workID)
            }
        case .workDetail(let workID):
            WorkDetailView(workID: workID, onDone: { activeSheet = nil })
                .largeSheetSizing()
        case .recordPractice:
            RecordPracticeSheet()
                .largeSheetSizing()
        case .newTodo(let initialTitle):
            newTodoSheet(initialTitle: initialTitle)
        case .search:
            AppSearchView()
        case .quickNote(let params):
            QuickNoteSheet(
                initialStudentIDs: params.studentIDs,
                initialBodyText: params.bodyText,
                initialTags: params.tags
            )
        case .commandBar:
            commandBarSheet
        }
    }

    private func newTodoSheet(initialTitle: String) -> some View {
        NavigationStack {
            NewTodoForm(initialTitle: initialTitle)
                .navigationTitle("New Todo")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            activeSheet = nil
                        }
                    }
                }
        }
    }

    private var commandBarSheet: some View {
        CommandBarSheet(
            onPresentation: { draftID in
                activeSheet = .presentationDraft(draftID)
            },
            onWorkItem: { lessonID, studentIDs in
                activeSheet = .newWorkItem(lessonID: lessonID, studentIDs: studentIDs)
            },
            onNote: { studentIDs, bodyText, inferredTags in
                activeSheet = .quickNote(QuickNoteParams(
                    studentIDs: studentIDs,
                    bodyText: bodyText,
                    tags: inferredTags
                ))
            },
            onTodo: { titleText in
                activeSheet = .newTodo(initialTitle: titleText)
            }
        )
    }

    /// Delay slightly to allow the sheet dismiss animation to complete.
    private func openWorkDetailAfterDismiss(_ workID: UUID) {
        Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                Self.logger.warning("Failed to sleep before opening work detail: \(error)")
            }
            activeSheet = .workDetail(workID)
        }
    }
}
