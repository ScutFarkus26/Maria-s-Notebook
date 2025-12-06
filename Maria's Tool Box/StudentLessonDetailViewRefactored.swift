import SwiftUI
import SwiftData

struct StudentLessonDetailViewRefactored: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query private var lessons: [Lesson]
    @Query private var studentsAll: [Student]
    @Query private var studentLessonsAll: [StudentLesson]
    @Query private var workModels: [WorkModel]
    
    @State private var viewModel: StudentLessonDetailViewModel
    
    let onDone: (() -> Void)?
    
    init(studentLesson: StudentLesson, onDone: (() -> Void)? = nil) {
        self.onDone = onDone
        
        // Initialize the view model - will be updated with modelContext in onAppear
        // Create a temporary container for initial setup (will be replaced with actual context in onAppear)
        let tempContainer = try! ModelContainer(for: StudentLesson.self)
        let tempViewModel = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: ModelContext(tempContainer)
        )
        _viewModel = State(initialValue: tempViewModel)
    }
    
    // MARK: - Computed Properties
    
    private var lessonObject: Lesson? {
        lessons.first(where: { $0.id == viewModel.studentLesson.lessonID })
    }
    
    private var lessonName: String {
        lessonObject?.name ?? "Lesson"
    }
    
    private var subject: String {
        lessonObject?.subject ?? ""
    }
    
    private var subjectColor: Color {
        AppColors.color(forSubject: subject)
    }
    
    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { viewModel.selectedStudentIDs.contains($0.id) }
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }
    
    private var nextLessonInGroup: Lesson? {
        viewModel.getNextLessonInGroup(from: lessons)
    }
    
    private var canPlanNext: Bool {
        guard let nextLesson = nextLessonInGroup else { return false }
        return viewModel.canPlanNextLesson(
            nextLesson: nextLesson,
            existingStudentLessons: studentLessonsAll
        )
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            contentScrollView
        }
        .frame(minWidth: 680, minHeight: 600)
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .alert("Delete Lesson?", isPresented: $viewModel.showDeleteAlert) {
            Button("Delete", role: .destructive, action: deleteLesson)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $viewModel.showingAddStudentSheet) {
            AddStudentView()
        }
        .sheet(isPresented: $viewModel.showingMoveStudentsSheet) {
            MoveStudentsSheet(
                lessonName: lessonName,
                students: selectedStudentsList,
                studentsToMove: $viewModel.studentsToMove,
                selectedStudentIDs: viewModel.selectedStudentIDs,
                onMove: {
                    viewModel.moveStudentsToNewLesson(
                        students: studentsAll,
                        lessons: lessons
                    )
                    viewModel.showingMoveStudentsSheet = false
                },
                onCancel: {
                    viewModel.studentsToMove = []
                    viewModel.showingMoveStudentsSheet = false
                }
            )
        }
        .overlay(alignment: .top) {
            bannerOverlay
        }
        .onAppear {
            // Re-attach with real modelContext (consider migrating to @StateObject + attachContext())
            // Update view model with the actual modelContext
            viewModel = StudentLessonDetailViewModel(
                studentLesson: viewModel.studentLesson,
                modelContext: modelContext
            )
        }
    }
    
    // MARK: - View Components
    
    private var header: some View {
        HStack {
            Text("Student Lesson")
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }
    
    private var contentScrollView: some View {
        ScrollView {
            VStack(spacing: 28) {
                StudentLessonSummarySection(
                    lessonName: lessonName,
                    subject: subject,
                    subjectColor: subjectColor,
                    students: selectedStudentsList,
                    canMoveStudents: selectedStudentsList.count > 1 && !viewModel.isPresented,
                    onMoveStudents: {
                        viewModel.studentsToMove = []
                        viewModel.showingMoveStudentsSheet = true
                    },
                    onAddRemoveStudents: {
                        viewModel.showingStudentPickerPopover = true
                    },
                    onRemoveStudent: { student in
                        viewModel.selectedStudentIDs.remove(student.id)
                    }
                )
                .popover(isPresented: $viewModel.showingStudentPickerPopover, arrowEdge: .top) {
                    StudentPickerPopover(
                        students: studentsAll,
                        selectedIDs: $viewModel.selectedStudentIDs,
                        onDone: { viewModel.showingStudentPickerPopover = false }
                    )
                }
                
                StudentLessonScheduleSection(
                    statusText: viewModel.scheduleStatusText,
                    isScheduled: viewModel.scheduledFor != nil
                )
                
                StudentLessonPresentedSection(
                    isPresented: $viewModel.isPresented,
                    givenAt: $viewModel.givenAt
                )
                
                StudentLessonNextLessonSection(
                    isPresented: viewModel.isPresented,
                    nextLesson: nextLessonInGroup,
                    canPlanNext: canPlanNext,
                    onPlanNext: {
                        guard let nextLesson = nextLessonInGroup else { return }
                        viewModel.planNextLessonInGroup(
                            nextLesson: nextLesson,
                            students: studentsAll,
                            lessons: lessons
                        )
                    }
                )
                
                StudentLessonFlagsSection(
                    needsPractice: $viewModel.needsPractice,
                    needsAnotherPresentation: $viewModel.needsAnotherPresentation
                )
                
                StudentLessonFollowUpSection(followUpWork: $viewModel.followUpWork)
                
                StudentLessonNotesSection(notes: $viewModel.notes)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
    }
    
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button(role: .destructive) {
                    viewModel.showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismissView()
                }
                
                Button("Save") {
                    saveLesson()
                }
                .bold()
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
    
    @ViewBuilder
    private var bannerOverlay: some View {
        if viewModel.showPlannedBanner {
            PlannedLessonBanner()
        } else if viewModel.showMovedBanner {
            MovedStudentsBanner(studentNames: viewModel.movedStudentNames)
        }
    }
    
    // MARK: - Actions
    
    private func saveLesson() {
        do {
            try viewModel.save(
                students: studentsAll,
                lessons: lessons,
                workModels: workModels
            )
            dismissView()
        } catch {
            // Handle error - could show an alert
            print("Failed to save: \(error)")
        }
    }
    
    private func deleteLesson() {
        do {
            try viewModel.delete()
            dismissView()
        } catch {
            // Handle error
            print("Failed to delete: \(error)")
        }
    }
    
    private func dismissView() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}

// MARK: - Preview
#Preview {
    Text("StudentLessonDetailView preview requires real model data")
}
