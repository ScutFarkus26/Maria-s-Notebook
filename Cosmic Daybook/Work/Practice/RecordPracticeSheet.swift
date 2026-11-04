// RecordPracticeSheet.swift
// CDLesson-first practice recording sheet, launched from the pie menu.
// Flow: pick a lesson → see students with open practice work as chips → record observation.

import OSLog
import SwiftUI
import CoreData

struct RecordPracticeSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @Environment(SaveCoordinator.self) var saveCoordinator

    @Environment(\.dependencies) private var dependencies
    @TestStudentVisibility private var testStudents

    var allStudents: [CDStudent] {
        WorkSheetRoster.students(enrolled: dependencies.roster.enrolled, testStudents: testStudents)
    }
    var allLessons: [CDLesson] { dependencies.lessonCatalog.all }
    @FetchRequest(sortDescriptors: []) private var allWork: FetchedResults<CDWorkModel>

    // CDLesson selection
    @State var lessonPickerVM = LessonPickerViewModel()
    @State private var lessonSearchFocused = true

    // CDStudent selection
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

    /// Children the opener named (the command bar's "Maya practiced the stamp
    /// game"). Empty from the floating button and File › New.
    private let initialStudentIDs: Set<UUID>

    /// The children named by the opener who are on the roster the chips show.
    private var keptInitialStudentIDs: Set<UUID> {
        WorkSheetRoster.keptPrefill(initialStudentIDs, roster: allStudents)
    }

    /// - Parameters:
    ///   - lessonID: the lesson to start on; nil starts on the lesson picker.
    ///   - studentIDs: children to start selected, shown as chips even when
    ///     they have no open practice work for the lesson.
    init(lessonID: UUID? = nil, studentIDs: Set<UUID> = []) {
        _lessonPickerVM = State(initialValue: LessonPickerViewModel(selectedLessonID: lessonID))
        _lessonSearchFocused = State(initialValue: lessonID == nil)
        _selectedStudentIDs = State(initialValue: studentIDs)
        _manuallyAddedStudentIDs = State(initialValue: studentIDs)
        initialStudentIDs = studentIDs
    }

    // MARK: - Computed

    private var selectedLesson: CDLesson? {
        guard let lessonID = lessonPickerVM.selectedLessonID else { return nil }
        return dependencies.lessonCatalog.lesson(id: lessonID)
    }

    /// Open practice work items for the selected lesson
    var openPracticeWork: [CDWorkModel] {
        guard let lessonID = lessonPickerVM.selectedLessonID else { return [] }
        return Self.openPracticeWork(in: allWork, lessonID: lessonID)
    }

    /// The open practice work for `lessonID` among `works`.
    static func openPracticeWork(in works: some Sequence<CDWorkModel>, lessonID: UUID) -> [CDWorkModel] {
        // Untagged work is Practice, as it is everywhere else (`displayKind`);
        // matching the stored kind left out older untagged work, so its child
        // got no chip and no work item (bug hunt 2026-11-03 #43).
        let lessonIDString = lessonID.uuidString
        return works.filter { work in
            work.lessonID == lessonIDString &&
            work.displayKind == .practiceLesson &&
            work.isOpen
        }
    }

    /// Students who have open practice work for the selected lesson
    var studentsWithOpenWork: [(student: CDStudent, workItem: CDWorkModel)] {
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
        Set(studentsWithOpenWork.compactMap { $0.student.id })
    }

    /// All chip-visible students: those with open work + manually added
    var chipStudents: [CDStudent] {
        let ids = practiceStudentIDs.union(manuallyAddedStudentIDs)
        return allStudents
            .filter { guard let sid = $0.id else { return false }; return ids.contains(sid) }
            .sorted { $0.firstName < $1.firstName }
    }

    /// Students matching the search query (excluding those already shown as chips)
    var searchResults: [CDStudent] {
        guard !studentSearchText.isEmpty else { return [] }
        let chipIDs = Set(chipStudents.compactMap(\.id))
        let query = studentSearchText.lowercased()
        return allStudents
            .filter { guard let sid = $0.id else { return false }; return !chipIDs.contains(sid) }
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
                // Named children who aren't on the chips' roster can't be
                // seen or taken off, so they don't stay selected.
                selectedStudentIDs = WorkSheetRoster.keptPrefill(selectedStudentIDs, roster: allStudents)
                manuallyAddedStudentIDs = keptInitialStudentIDs
                // Started on a lesson with nobody named: select its children
                // with open practice work, as picking the lesson does.
                if initialStudentIDs.isEmpty, lessonPickerVM.selectedLessonID != nil, selectedStudentIDs.isEmpty {
                    selectedStudentIDs = practiceStudentIDs
                }
            }
            .onChange(of: lessonPickerVM.selectedLessonID) { _, _ in
                // Pre-select all students with open practice work for this lesson,
                // keeping any the sheet was opened with (the command bar's names).
                selectedStudentIDs = practiceStudentIDs.union(keptInitialStudentIDs)
                manuallyAddedStudentIDs = keptInitialStudentIDs
                studentSearchText = ""
            }
        }
    }

    // MARK: - CDLesson Section

    private var lessonSection: some View {
        LessonPickerSection(
            viewModel: lessonPickerVM,
            resolvedLesson: selectedLesson,
            isFocused: $lessonSearchFocused
        )
    }

}
