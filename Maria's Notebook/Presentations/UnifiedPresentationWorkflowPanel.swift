import SwiftUI
import SwiftData
import OSLog

/// Reusable panel component for presentation workflow (can be used in sheets or embedded)
/// Contains the split-panel UI for presentation notes and work item creation
struct UnifiedPresentationWorkflowPanel: View {
    static let logger = Logger.presentations

    // MARK: - Input

    @Bindable var presentationViewModel: PostPresentationFormViewModel
    let students: [Student]
    let lessonName: String
    let lessonID: UUID
    let onComplete: () -> Void
    let onCancel: () -> Void

    // Optional binding to trigger completion from external toolbar (for sheet context)
    var triggerCompletion: Binding<Bool>?

    // MARK: - Environment

    @Environment(\.modelContext) var modelContext
    @Environment(SaveCoordinator.self) var saveCoordinator

    @Query(sort: \Lesson.sortIndex) var lessons: [Lesson]
    @Query var lessonAssignments: [LessonAssignment]
    @Query(sort: \WorkModel.createdAt, order: .reverse) var allWorkModels: [WorkModel]

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // MARK: - State

    // Work drafts: studentID -> [WorkItemDraft]
    @State var workDrafts: [UUID: [WorkItemDraft]] = [:]

    @State var isSaving: Bool = false
    @State private var activePanel: PanelFocus = .presentation
    @State var showBulkAppliedToast: Bool = false
    @State var bulkAppliedMessage: String = ""
    @State private var showStudentNavigator: Bool = false
    @State var bulkCheckInStyle: CheckInStyle = .flexible
    @Namespace private var studentScrollAnchor

    private enum PanelFocus: Sendable {
        case presentation
        case work
    }

    // MARK: - Computed

    var sortedStudents: [Student] {
        students.sorted(by: StudentSortComparator.byFirstName)
    }

    // MARK: - Body

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                splitPanelLayout
            }
            #else
            splitPanelLayout
            #endif
        }
        .onAppear {
            let studentIDs = Set(students.map(\.id))
            presentationViewModel.resolveNextLesson(
                lessonID: lessonID,
                studentIDs: studentIDs,
                lessons: lessons,
                lessonAssignments: lessonAssignments
            )
        }
        .onChange(of: triggerCompletion?.wrappedValue) { _, newValue in
            if let newValue, newValue {
                completeWorkflow()
                triggerCompletion?.wrappedValue = false
            }
        }
        .overlay(alignment: .top) {
            if showBulkAppliedToast {
                toastView
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Toast View

    private var toastView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.success)
            Text(bulkAppliedMessage)
                .font(.workflowCallout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(UIConstants.OpacityConstants.light), radius: 8, y: 4)
        )
    }

    // MARK: - Split Panel Layout (iPad/macOS)

    private var splitPanelLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left Panel: Presentation
                presentationPanel
                    .frame(width: geometry.size.width * 0.45)
                    .background(Color.primary.opacity(UIConstants.OpacityConstants.ghost))

                Divider()

                // Right Panel: Work Creation
                workCreationPanel
                    .frame(width: geometry.size.width * 0.55)
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
    }

    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
        TabView(selection: $activePanel) {
            presentationPanel
                .tag(PanelFocus.presentation)
                .tabItem {
                    Label("Presentation", systemImage: SFSymbol.Education.bookFill)
                }

            workCreationPanel
                .tag(PanelFocus.work)
                .tabItem {
                    Label("Work Items", systemImage: SFSymbol.List.checklist)
                }
        }
    }
}
