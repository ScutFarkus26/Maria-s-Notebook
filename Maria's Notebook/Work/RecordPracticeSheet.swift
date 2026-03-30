// RecordPracticeSheet.swift
// Lesson-first practice recording sheet, launched from the pie menu.
// Flow: pick a lesson → see students with open practice work as chips → record observation.

import OSLog
import SwiftUI
import SwiftData

struct RecordPracticeSheet: View {
    static let logger = Logger.work

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    @Query private var allStudentsRaw: [Student]
    var allStudents: [Student] { allStudentsRaw.filter(\.isEnrolled) }
    @Query var allLessons: [Lesson]
    @Query private var allWork: [WorkModel]

    // Lesson selection
    @State var lessonPickerVM = LessonPickerViewModel()
    @State private var lessonSearchFocused = true

    // Student selection
    @State var selectedStudentIDs: Set<UUID> = []
    @State var manuallyAddedStudentIDs: Set<UUID> = []
    @State var studentSearchText: String = ""

    // Session basics
    @State var sessionDate: Date = Date()
    @State var hasDuration: Bool = false
    @State var durationMinutes: Int = 20

    // Quality metrics
    @State var practiceQuality: Int?
    @State var independenceLevel: Int?

    // Observable behaviors
    @State var askedForHelp: Bool = false
    @State var helpedPeer: Bool = false
    @State var struggledWithConcept: Bool = false
    @State var madeBreakthrough: Bool = false
    @State var needsReteaching: Bool = false
    @State var readyForCheckIn: Bool = false
    @State var readyForAssessment: Bool = false

    // Next steps
    @State var scheduleCheckIn: Bool = false
    @State var checkInDate: Date = Date().addingTimeInterval(24 * 60 * 60)
    @State var followUpActions: String = ""
    @State var materialsUsed: String = ""

    // Notes
    @State var sessionNotes: String = ""

    // MARK: - Computed

    private var selectedLesson: Lesson? {
        guard let lessonID = lessonPickerVM.selectedLessonID else { return nil }
        return allLessons.first { $0.id == lessonID }
    }

    /// Open practice work items for the selected lesson
    var openPracticeWork: [WorkModel] {
        guard let lessonID = lessonPickerVM.selectedLessonID else { return [] }
        let lessonIDString = lessonID.uuidString
        return allWork.filter { work in
            work.lessonID == lessonIDString &&
            work.kindRaw == WorkKind.practiceLesson.rawValue &&
            work.isOpen
        }
    }

    /// Students who have open practice work for the selected lesson
    var studentsWithOpenWork: [(student: Student, workItem: WorkModel)] {
        openPracticeWork.compactMap { work in
            guard let studentID = UUID(uuidString: work.studentID),
                  let student = allStudents.first(where: { $0.id == studentID }) else {
                return nil
            }
            return (student: student, workItem: work)
        }
        .sorted { $0.student.firstName < $1.student.firstName }
    }

    /// IDs of students who have open practice work (for chip display)
    var practiceStudentIDs: Set<UUID> {
        Set(studentsWithOpenWork.map { $0.student.id })
    }

    /// All chip-visible students: those with open work + manually added
    var chipStudents: [Student] {
        let ids = practiceStudentIDs.union(manuallyAddedStudentIDs)
        return allStudents
            .filter { ids.contains($0.id) }
            .sorted { $0.firstName < $1.firstName }
    }

    /// Students matching the search query (excluding those already shown as chips)
    var searchResults: [Student] {
        guard !studentSearchText.isEmpty else { return [] }
        let chipIDs = Set(chipStudents.map(\.id))
        let query = studentSearchText.lowercased()
        return allStudents
            .filter { !chipIDs.contains($0.id) }
            .filter {
                $0.firstName.lowercased().contains(query) ||
                $0.lastName.lowercased().contains(query)
            }
            .sorted { $0.firstName < $1.firstName }
    }

    var canSave: Bool {
        selectedLesson != nil && !selectedStudentIDs.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        lessonSection

                        if selectedLesson != nil {
                            Divider()
                            studentChipsSection

                            Divider()
                            dateSection

                            Divider()
                            durationSection

                            Divider()
                            qualityMetricsSection

                            Divider()
                            behaviorsSection

                            Divider()
                            notesSection

                            Divider()
                            nextStepsSection
                        }
                    }
                    .padding(24)
                }

                if selectedLesson != nil {
                    Divider()
                    bottomBar
                }
            }
            .navigationTitle("Record Practice")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                lessonPickerVM.configure(lessons: allLessons, students: allStudents)
            }
            .onChange(of: lessonPickerVM.selectedLessonID) { _, _ in
                // Pre-select all students with open practice work for this lesson
                selectedStudentIDs = practiceStudentIDs
                manuallyAddedStudentIDs = []
                studentSearchText = ""
            }
        }
    }

    // MARK: - Lesson Section

    private var lessonSection: some View {
        LessonPickerSection(
            viewModel: lessonPickerVM,
            resolvedLesson: selectedLesson,
            isFocused: $lessonSearchFocused
        )
    }

}
