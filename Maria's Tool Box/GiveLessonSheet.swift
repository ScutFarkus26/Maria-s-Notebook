import SwiftUI
import SwiftData
import Foundation
import Combine

struct GiveLessonSheet: View {
    // MARK: - Configuration
    
    let initialLesson: Lesson?
    var onDone: (() -> Void)?
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - State
    
    @StateObject private var viewModel: GiveLessonViewModel
    
    @Query private var queriedStudents: [Student]
    @Query private var queriedLessons: [Lesson]
    
    @State private var showingAddStudentSheet: Bool = false
    @State private var showingStudentPickerPopover: Bool = false
    @State private var showFollowUpField: Bool = false
    @State private var saveAlert: (title: String, message: String)?
    
    enum FocusField: Hashable { case lesson, notes, followUp }
    @FocusState private var focusedField: FocusField?
    
    // MARK: - Initialization
    
    init(
        lesson: Lesson? = nil,
        preselectedStudentIDs: [UUID] = [],
        startGiven: Bool = false,
        allStudents: [Student] = [],
        allLessons: [Lesson] = [],
        onDone: (() -> Void)? = nil
    ) {
        self.initialLesson = lesson
        self.onDone = onDone
        
        _viewModel = StateObject(wrappedValue: GiveLessonViewModel(
            selectedStudentIDs: Set(preselectedStudentIDs),
            selectedLessonID: lesson?.id,
            mode: startGiven ? .given : .plan
        ))
    }
    
    // MARK: - Computed Properties
    
    private var lessonsSource: [Lesson] {
        queriedLessons
    }
    
    private var studentsSource: [Student] {
        queriedStudents
    }
    
    private var resolvedLesson: Lesson? {
        if let id = viewModel.selectedLessonID {
            return lessonsSource.first(where: { $0.id == id })
        } else {
            return initialLesson
        }
    }
    
    private var subjectColor: Color {
        if let subject = resolvedLesson?.subject,
           !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppColors.color(forSubject: subject)
        }
        return .accentColor
    }
    
    private var lessonFocusBinding: Binding<Bool> {
        Binding(
            get: { focusedField == .lesson },
            set: { focusedField = $0 ? .lesson : nil }
        )
    }
    
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { saveAlert != nil },
            set: { if !$0 { saveAlert = nil } }
        )
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            
            Divider()
                .opacity(0.7)
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    lessonSection
                    studentsSection
                    statusSection
                    notesSection
                    moreOptionsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .onAppear(perform: setupView)
        .onDisappear(perform: cleanupView)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $showingAddStudentSheet) {
            AddStudentView()
        }
        .alert(saveAlert?.title ?? "Error", isPresented: alertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveAlert?.message ?? "")
        }
        .overlay(keyboardShortcuts)
        .frame(minWidth: 720, minHeight: 640)
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        HStack(spacing: 10) {
            if resolvedLesson != nil {
                Circle()
                    .fill(subjectColor)
                    .frame(width: 10, height: 10)
                    .transition(.scale.combined(with: .opacity))
            }
            Text("Give Lesson")
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.horizontal)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: resolvedLesson?.id)
    }
    
    private var lessonSection: some View {
        LessonSection(
            viewModel: viewModel,
            resolvedLesson: resolvedLesson,
            lessonDisplayTitle: viewModel.lessonDisplayTitle(for:),
            isFocused: lessonFocusBinding
        )
    }
    
    private var studentsSection: some View {
        StudentsSection(
            viewModel: viewModel,
            subjectColor: subjectColor,
            displayName: viewModel.displayName(for:),
            showingAddStudentSheet: $showingAddStudentSheet,
            showingStudentPickerPopover: $showingStudentPickerPopover
        )
    }
    
    private var statusSection: some View {
        StatusSection(
            viewModel: viewModel,
            subjectColor: subjectColor
        )
    }
    
    private var notesSection: some View {
        GiveLessonNotesSection(
            notes: $viewModel.notes,
            focusedField: $focusedField
        )
    }
    
    private var moreOptionsSection: some View {
        MoreOptionsSection(
            viewModel: viewModel,
            subjectColor: subjectColor,
            showFollowUpField: $showFollowUpField,
            focusedField: $focusedField
        )
    }
    
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                dismiss()
            }
            Spacer()
            Button(viewModel.mode == .plan ? "Save Plan" : "Mark as Given") {
                saveStudentLesson()
            }
            .disabled(!viewModel.isValid)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(.bar)
    }
    
    private var keyboardShortcuts: some View {
        KeyboardShortcutsOverlay(
            focusLesson: { focusedField = .lesson },
            openStudents: { showingStudentPickerPopover = true },
            focusNotes: { focusedField = .notes },
            toggleStatus: viewModel.toggleMode
        )
    }
    
    // MARK: - Helper Methods
    
    private func setupView() {
        viewModel.configure(lessons: lessonsSource, students: studentsSource)
    }
    
    private func cleanupView() {
        showingStudentPickerPopover = false
        showingAddStudentSheet = false
        focusedField = nil
        viewModel.reset()
    }
    
    private func saveStudentLesson() {
        guard resolvedLesson != nil else { return }
        
        do {
            try viewModel.save(context: modelContext, resolvedLesson: resolvedLesson)
            onDone?()
            dismiss()
        } catch let error as GiveLessonViewModel.SaveError {
            switch error {
            case .persistFailed:
                saveAlert = (title: error.title, message: error.localizedDescription)
            case .missingLesson:
                // Handled inline; do nothing
                break
            }
        } catch {
            saveAlert = (title: "Save Failed", message: error.localizedDescription)
        }
    }
}

