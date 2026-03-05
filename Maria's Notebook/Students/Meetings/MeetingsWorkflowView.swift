import SwiftUI
import SwiftData

/// A dedicated workflow view for conducting weekly student meetings.
/// Provides a queue of students, context pane, and meeting form in a focused layout.
struct MeetingsWorkflowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // MARK: - Queries

    @Query(sort: Student.sortByName)
    private var studentsRaw: [Student]

    @Query(sort: [SortDescriptor(\StudentMeeting.date, order: .reverse)])
    private var allMeetings: [StudentMeeting]

    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    private var allWorkModels: [WorkModel]

    @Query(sort: [SortDescriptor(\LessonAssignment.presentedAt, order: .reverse)])
    private var allLessonAssignments: [LessonAssignment]

    @Query(sort: [SortDescriptor(\Lesson.name)])
    private var lessons: [Lesson]

    @Query(sort: [SortDescriptor(\MeetingTemplate.sortOrder)])
    private var meetingTemplates: [MeetingTemplate]

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    // MARK: - State

    @State private var selectedStudentID: UUID?
    @State private var searchText: String = ""
    @State private var showCompletedThisWeek: Bool = false
    @State private var orderedStudentIDs: [UUID] = []
    @State private var selectedAgeRanges: Set<AgeRange> = []

    // Meeting frequency threshold (persisted)
    @AppStorage(UserDefaultsKeys.meetingsWorkflowDaysSinceThreshold) private var daysSinceThreshold: Int = 7

    // Work age threshold for overdue
    @SyncedAppStorage("WorkAge.overdueDays") private var workOverdueDays: Int = 14

    // UserDefaults key for persisting custom order
    private static let customOrderKey = "MeetingsWorkflow.customStudentOrder"

    // MARK: - Computed Properties

    private var selectedStudent: Student? {
        guard let id = selectedStudentID else { return nil }
        return students.first { $0.id == id }
    }

    private var thresholdDate: Date {
        Calendar.current.date(byAdding: .day, value: -daysSinceThreshold, to: Date()) ?? Date()
    }

    /// Students who haven't had a meeting within the threshold
    private var studentsNeedingMeetingSet: Set<UUID> {
        let needsMeeting = students.filter { student in
            let studentMeetings = meetingsFor(student)
            let hasRecentMeeting = studentMeetings.contains { $0.date >= thresholdDate }
            return !hasRecentMeeting
        }
        return Set(needsMeeting.map(\.id))
    }

    /// Ordered list of students needing meetings
    private var studentsNeedingMeeting: [Student] {
        // Start with ordered IDs that are still valid
        var result: [Student] = []
        var addedIDs = Set<UUID>()

        for id in orderedStudentIDs where studentsNeedingMeetingSet.contains(id) {
            if let student = students.first(where: { $0.id == id }) {
                result.append(student)
                addedIDs.insert(id)
            }
        }

        // Add any students not yet in the ordered list (alphabetically)
        for student in students where studentsNeedingMeetingSet.contains(student.id) && !addedIDs.contains(student.id) {
            result.append(student)
        }

        return result
    }

    /// Students who have had a meeting within the threshold
    private var studentsWithRecentMeeting: [Student] {
        students.filter { student in
            let studentMeetings = meetingsFor(student)
            return studentMeetings.contains { $0.date >= thresholdDate }
        }
    }

    /// Filter students based on search and age
    private var filteredStudentsNeedingMeeting: [Student] {
        var result = studentsNeedingMeeting
        
        // Search filter
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            result = result.filter {
                $0.firstName.lowercased().contains(search) ||
                $0.lastName.lowercased().contains(search)
            }
        }
        
        // Age filter
        if !selectedAgeRanges.isEmpty {
            result = result.filter { AgeRange.matchesAny($0.birthday, in: selectedAgeRanges) }
        }
        
        return result
    }

    private var filteredStudentsCompleted: [Student] {
        var result = studentsWithRecentMeeting
        
        // Search filter
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            result = result.filter {
                $0.firstName.lowercased().contains(search) ||
                $0.lastName.lowercased().contains(search)
            }
        }
        
        // Age filter
        if !selectedAgeRanges.isEmpty {
            result = result.filter { AgeRange.matchesAny($0.birthday, in: selectedAgeRanges) }
        }
        
        return result
    }

    private func meetingsFor(_ student: Student) -> [StudentMeeting] {
        let studentIDString = student.id.uuidString
        return allMeetings.filter { $0.studentID == studentIDString }
    }

    private func lastMeetingFor(_ student: Student) -> StudentMeeting? {
        meetingsFor(student).first
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            MeetingsQueueSidebar(
                studentsNeedingMeeting: filteredStudentsNeedingMeeting,
                studentsCompleted: filteredStudentsCompleted,
                selectedStudentID: $selectedStudentID,
                searchText: $searchText,
                showCompletedThisWeek: $showCompletedThisWeek,
                daysSinceThreshold: $daysSinceThreshold,
                selectedAgeRanges: $selectedAgeRanges,
                lastMeetingFor: lastMeetingFor,
                onMove: moveStudent
            )
        } detail: {
            if let student = selectedStudent {
                MeetingSessionView(
                    student: student,
                    allWorkModels: allWorkModels,
                    allLessonAssignments: allLessonAssignments,
                    lessons: lessons,
                    meetings: meetingsFor(student),
                    meetingTemplates: meetingTemplates,
                    workOverdueDays: workOverdueDays,
                    onComplete: {
                        moveToNextStudent()
                    }
                )
            } else {
                emptyState
            }
        }
        .navigationTitle("Meetings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadCustomOrder()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            Text("Select a Student")
                .font(.title2.weight(.medium))

            Text("Choose a student from the queue to start their weekly meeting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if !studentsNeedingMeeting.isEmpty {
                Button {
                    selectedStudentID = studentsNeedingMeeting.first?.id
                } label: {
                    Label("Start First Meeting", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func moveToNextStudent() {
        let queue = studentsNeedingMeeting
        if let currentIndex = queue.firstIndex(where: { $0.id == selectedStudentID }) {
            let nextIndex = currentIndex + 1
            if nextIndex < queue.count {
                selectedStudentID = queue[nextIndex].id
            } else if let first = queue.first, first.id != selectedStudentID {
                selectedStudentID = first.id
            } else {
                selectedStudentID = nil
            }
        } else if let first = queue.first {
            selectedStudentID = first.id
        }
    }

    // MARK: - Custom Order

    private func loadCustomOrder() {
        if let saved = UserDefaults.standard.array(forKey: Self.customOrderKey) as? [String] {
            orderedStudentIDs = saved.compactMap { UUID(uuidString: $0) }
        }
    }

    private func saveCustomOrder() {
        let strings = orderedStudentIDs.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: Self.customOrderKey)
    }

    private func moveStudent(from source: IndexSet, to destination: Int) {
        var ids = filteredStudentsNeedingMeeting.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        orderedStudentIDs = ids
        saveCustomOrder()
    }
}

// MARK: - Preview

#Preview {
    MeetingsWorkflowView()
        .previewEnvironment()
}
