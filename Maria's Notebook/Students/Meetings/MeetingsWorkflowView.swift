import SwiftUI
import CoreData

/// A dedicated workflow view for conducting weekly student meetings.
/// Provides a queue of students, context pane, and meeting form in a focused layout.
struct MeetingsWorkflowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // MARK: - Queries

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true), NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)])
    private var studentsRaw: FetchedResults<CDStudent>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudentMeeting.date, ascending: false)])
    private var allMeetings: FetchedResults<CDStudentMeeting>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)])
    private var allWorkModels: FetchedResults<CDWorkModel>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)])
    private var allLessonAssignments: FetchedResults<CDLessonAssignment>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)])
    private var lessons: FetchedResults<CDLesson>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDMeetingTemplate.sortOrder, ascending: true)])
    private var meetingTemplates: FetchedResults<CDMeetingTemplate>

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(Array(studentsRaw).uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    // MARK: - State

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDScheduledMeeting.date, ascending: true)])
    private var scheduledMeetingsQuery: FetchedResults<CDScheduledMeeting>

    @State private var selectedStudentID: UUID?
    @State private var searchText: String = ""
    @State private var showCompletedThisWeek: Bool = false
    @State private var orderedStudentIDs: [UUID] = []
    @State private var selectedAgeRanges: Set<AgeRange> = []
    @State private var studentForMeetingDatePicker: CDStudent?

    // Meeting frequency threshold (persisted)
    @AppStorage(UserDefaultsKeys.meetingsWorkflowDaysSinceThreshold) private var daysSinceThreshold: Int = 7

    // Work age threshold for overdue
    @SyncedAppStorage("WorkAge.overdueDays") private var workOverdueDays: Int = 14

    // UserDefaults key for persisting custom order
    private static let customOrderKey = "MeetingsWorkflow.customStudentOrder"

    // MARK: - Computed Properties

    private var scheduledMeetingDates: [UUID: Date] {
        var result: [UUID: Date] = [:]
        for sm in scheduledMeetingsQuery {
            for studentIDString in sm.allStudentIDs {
                if let sid = UUID(uuidString: studentIDString) {
                    if let existing = result[sid] {
                        result[sid] = min(existing, sm.date ?? .distantFuture)
                    } else {
                        result[sid] = sm.date
                    }
                }
            }
        }
        return result
    }

    private var selectedStudent: CDStudent? {
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
            let hasRecentMeeting = studentMeetings.contains { ($0.date ?? .distantPast) >= thresholdDate }
            return !hasRecentMeeting
        }
        return Set(needsMeeting.compactMap(\.id))
    }

    /// Ordered list of students needing meetings
    private var studentsNeedingMeeting: [CDStudent] {
        // Start with ordered IDs that are still valid
        var result: [CDStudent] = []
        var addedIDs = Set<UUID>()

        for id in orderedStudentIDs where studentsNeedingMeetingSet.contains(id) {
            if let student = students.first(where: { $0.id == id }) {
                result.append(student)
                addedIDs.insert(id)
            }
        }

        // Add any students not yet in the ordered list (alphabetically)
        for student in students where student.id.map({ studentsNeedingMeetingSet.contains($0) && !addedIDs.contains($0) }) ?? false {
            result.append(student)
        }

        return result
    }

    /// Students who have had a meeting within the threshold
    private var studentsWithRecentMeeting: [CDStudent] {
        students.filter { student in
            let studentMeetings = meetingsFor(student)
            return studentMeetings.contains { ($0.date ?? .distantPast) >= thresholdDate }
        }
    }

    /// Filter students based on search and age.
    /// Search brings matching students to the top rather than hiding non-matches.
    private var filteredStudentsNeedingMeeting: [CDStudent] {
        var result = studentsNeedingMeeting

        // Age filter
        if !selectedAgeRanges.isEmpty {
            result = result.filter { AgeRange.matchesAny($0.birthday ?? Date(), in: selectedAgeRanges) }
        }

        // Search: bring matching students to the top
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            let (matching, rest) = result.partitioned { student in
                student.firstName.lowercased().contains(search) ||
                student.lastName.lowercased().contains(search)
            }
            result = matching + rest
        }

        return result
    }

    private var filteredStudentsCompleted: [CDStudent] {
        var result = studentsWithRecentMeeting

        // Age filter
        if !selectedAgeRanges.isEmpty {
            result = result.filter { AgeRange.matchesAny($0.birthday ?? Date(), in: selectedAgeRanges) }
        }

        // Search: bring matching students to the top
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            let (matching, rest) = result.partitioned { student in
                student.firstName.lowercased().contains(search) ||
                student.lastName.lowercased().contains(search)
            }
            result = matching + rest
        }

        return result
    }

    private func meetingsFor(_ student: CDStudent) -> [CDStudentMeeting] {
        let studentIDString = student.id?.uuidString ?? ""
        return allMeetings.filter { $0.studentID == studentIDString }
    }

    private func lastMeetingFor(_ student: CDStudent) -> CDStudentMeeting? {
        meetingsFor(student).first
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            MeetingsQueueSidebar(
                studentsNeedingMeeting: filteredStudentsNeedingMeeting,
                studentsCompleted: filteredStudentsCompleted,
                selectedStudentID: $selectedStudentID,
                searchText: $searchText,
                showCompletedThisWeek: $showCompletedThisWeek,
                daysSinceThreshold: $daysSinceThreshold,
                selectedAgeRanges: $selectedAgeRanges,
                lastMeetingFor: lastMeetingFor,
                onMove: moveStudent,
                scheduledMeetingDates: scheduledMeetingDates,
                onScheduleMeeting: handleScheduleMeeting,
                onPickMeetingDate: { student in
                    studentForMeetingDatePicker = student
                }
            )
            .frame(width: 250)

            Divider()

            if let student = selectedStudent {
                MeetingSessionView(
                    student: student,
                    allWorkModels: Array(allWorkModels),
                    allLessonAssignments: Array(allLessonAssignments),
                    lessons: Array(lessons),
                    meetings: meetingsFor(student),
                    meetingTemplates: Array(meetingTemplates),
                    workOverdueDays: workOverdueDays,
                    onComplete: {
                        moveToNextStudent()
                    }
                )
                .frame(maxWidth: .infinity)
            } else {
                emptyState
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Meetings")
        .inlineNavigationTitle()
        .onAppear {
            loadCustomOrder()
        }
        .sheet(item: $studentForMeetingDatePicker) { student in
            MeetingDatePickerSheet(studentName: student.fullName) { date in
                if let studentID = student.id {
                    MeetingScheduler.scheduleMeeting(
                        studentID: studentID,
                        date: date,
                        context: viewContext
                    )
                }
            }
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

    // MARK: - Meeting Scheduling

    private func handleScheduleMeeting(student: CDStudent, date: Date?) {
        guard let studentID = student.id else { return }
        if let date {
            MeetingScheduler.scheduleMeeting(studentID: studentID, date: date, context: viewContext)
        } else {
            MeetingScheduler.clearMeetings(studentID: studentID, context: viewContext)
        }
    }

    // MARK: - Custom Order

    private func loadCustomOrder() {
        if let saved = UserDefaults.standard.array(forKey: Self.customOrderKey) as? [String] {
            orderedStudentIDs = saved.compactMap { UUID(uuidString: $0) }
        }
    }

    private func saveCustomOrder() {
        let strings = orderedStudentIDs.map(\.uuidString)
        UserDefaults.standard.set(strings, forKey: Self.customOrderKey)
    }

    private func moveStudent(from source: IndexSet, to destination: Int) {
        var ids = filteredStudentsNeedingMeeting.compactMap(\.id)
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
