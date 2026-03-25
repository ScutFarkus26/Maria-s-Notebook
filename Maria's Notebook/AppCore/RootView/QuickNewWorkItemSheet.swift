// QuickNewWorkItemSheet.swift
// Quick creation sheet for new work items.
//
// Sections live in:
// - QuickNewWorkItemSheet+Sections.swift  (lesson, student, details, kindButton)
// - QuickNewWorkItemSheet+Actions.swift   (saveWorkItem, check-in reason helpers)

import SwiftUI
import SwiftData

struct QuickNewWorkItemSheet: View {
    /// Optional callback when work is created and user wants to view details immediately
    var onCreatedAndOpen: ((UUID) -> Void)?

    /// Pre-fill support for opening from checklist batch actions
    private var preSelectedLessonID: UUID?
    private var preSelectedStudentIDs: Set<UUID>

    init(
        preSelectedLessonID: UUID? = nil,
        preSelectedStudentIDs: Set<UUID> = [],
        onCreatedAndOpen: ((UUID) -> Void)? = nil
    ) {
        self.preSelectedLessonID = preSelectedLessonID
        self.preSelectedStudentIDs = preSelectedStudentIDs
        self.onCreatedAndOpen = onCreatedAndOpen
        _selectedLessonID = State(initialValue: preSelectedLessonID)
        _selectedStudentIDs = State(initialValue: preSelectedStudentIDs)
    }

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Environment(SaveCoordinator.self) var saveCoordinator

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query(sort: [SortDescriptor(\Lesson.subject), SortDescriptor(\Lesson.sortIndex)])
    var allLessons: [Lesson]

    @Query(sort: Student.sortByName)
    private var allStudentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    var allStudents: [Student] {
        TestStudentsFilter.filterVisible(
            allStudentsRaw.uniqueByID.filter(\.isEnrolled),
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    @State var selectedLessonID: UUID?
    @State var selectedStudentIDs: Set<UUID> = []
    @State var workTitle: String = ""
    @State var workKind: WorkKind = .practiceLesson
    @State var dueDate: Date?
    @State var hasDueDate: Bool = false
    @State var lessonSearchText: String = ""
    @State var isSaving: Bool = false

    // Sample work template selection
    @State var selectedSampleWorkID: UUID?

    // Check-in states
    @State var hasCheckIn: Bool = false
    @State var checkInDate: Date = Date()
    @State var checkInReason: CheckInMigrationService.CheckInReason = .progressCheck
    @State var checkInStyle: CheckInStyle = .flexible

    // Popover states
    @State var showingLessonPopover: Bool = false
    @State var showingStudentPopover: Bool = false
    @FocusState var lessonFieldFocused: Bool

    var filteredLessons: [Lesson] {
        let query = lessonSearchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allLessons }
        return allLessons.filter {
            $0.name.lowercased().contains(query) ||
            $0.subject.lowercased().contains(query) ||
            $0.group.lowercased().contains(query)
        }
    }

    var selectedLesson: Lesson? {
        guard let id = selectedLessonID else { return nil }
        return allLessons.first { $0.id == id }
    }

    var selectedStudents: [Student] {
        allStudents.filter { selectedStudentIDs.contains($0.id) }
    }

    var canSave: Bool {
        selectedLessonID != nil && !selectedStudentIDs.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("New Work")
                        .font(AppTheme.ScaledFont.titleXLarge)

                    // Lesson Section
                    lessonSection()

                    Divider()

                    // Student Section
                    studentSection()

                    Divider()

                    // Details Section
                    detailsSection()
                }
                .padding(AppTheme.Spacing.large)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if onCreatedAndOpen != nil && selectedStudentIDs.count == 1 {
                    Button("Create & Open") { saveWorkItem(andOpen: true) }
                        .disabled(!canSave || isSaving)
                }
                Button("Create") { saveWorkItem(andOpen: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || isSaving)
            }
            .padding(AppTheme.Spacing.medium)
            .background(.bar)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: UIConstants.SheetSize.medium.width, minHeight: UIConstants.SheetSize.medium.height)
        #endif
        .onAppear {
            // Auto-fill lesson name when pre-populated from checklist
            if let lessonID = preSelectedLessonID,
               let lesson = allLessons.first(where: { $0.id == lessonID }) {
                lessonSearchText = lesson.name
                if workTitle.isEmpty {
                    workTitle = lesson.name
                }
            }
        }
    }
}
