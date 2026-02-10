import SwiftUI
import SwiftData

/// A dedicated workflow view for conducting weekly student meetings.
/// Provides a queue of students, context pane, and meeting form in a focused layout.
struct MeetingsWorkflowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // MARK: - Queries

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)])
    private var studentsRaw: [Student]

    @Query(sort: [SortDescriptor(\StudentMeeting.date, order: .reverse)])
    private var allMeetings: [StudentMeeting]

    @Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)])
    private var allWorkModels: [WorkModel]

    @Query(sort: [SortDescriptor(\StudentLesson.givenAt, order: .reverse)])
    private var allStudentLessons: [StudentLesson]

    @Query(sort: [SortDescriptor(\Lesson.name)])
    private var lessons: [Lesson]

    @Query(sort: [SortDescriptor(\MeetingTemplate.sortOrder)])
    private var meetingTemplates: [MeetingTemplate]

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    // MARK: - State

    @State private var selectedStudentID: UUID? = nil
    @State private var searchText: String = ""
    @State private var showCompletedThisWeek: Bool = false
    @State private var orderedStudentIDs: [UUID] = []
    @State private var selectedAgeRanges: Set<AgeRange> = []

    // Meeting frequency threshold (persisted)
    @AppStorage("MeetingsWorkflow.daysSinceThreshold") private var daysSinceThreshold: Int = 7

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
                    allStudentLessons: allStudentLessons,
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

// MARK: - Queue Sidebar (Separate View)

struct MeetingsQueueSidebar: View {
    let studentsNeedingMeeting: [Student]
    let studentsCompleted: [Student]
    @Binding var selectedStudentID: UUID?
    @Binding var searchText: String
    @Binding var showCompletedThisWeek: Bool
    @Binding var daysSinceThreshold: Int
    @Binding var selectedAgeRanges: Set<AgeRange>
    let lastMeetingFor: (Student) -> StudentMeeting?
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        List(selection: $selectedStudentID) {
            // Threshold picker and age filter at top
            Section {
                MeetingThresholdPicker(days: $daysSinceThreshold, showCompleted: $showCompletedThisWeek)
                AgeFilterPicker(selectedAgeRanges: $selectedAgeRanges)
            }

            Section("Needs Meeting (\(studentsNeedingMeeting.count))") {
                ForEach(studentsNeedingMeeting) { student in
                    StudentQueueRow(
                        student: student,
                        lastMeeting: lastMeetingFor(student),
                        isSelected: selectedStudentID == student.id,
                        showCheckmark: false
                    )
                    .tag(student.id)
                }
                .onMove(perform: searchText.isEmpty ? onMove : nil)
            }

            if showCompletedThisWeek {
                Section("Met Recently (\(studentsCompleted.count))") {
                    ForEach(studentsCompleted) { student in
                        StudentQueueRow(
                            student: student,
                            lastMeeting: lastMeetingFor(student),
                            isSelected: selectedStudentID == student.id,
                            showCheckmark: true
                        )
                        .tag(student.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search students")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 220)
        #endif
    }
}

// MARK: - Meeting Threshold Picker

struct MeetingThresholdPicker: View {
    @Binding var days: Int
    @Binding var showCompleted: Bool
    @State private var isExpanded = false

    private let presets = [3, 5, 7, 14, 21, 30]

    var body: some View {
        VStack(spacing: 8) {
            // Top row: threshold pill + show completed toggle
            HStack(spacing: 8) {
                // Tappable pill showing current value
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption)

                        Text("Last \(days)d")
                            .font(.subheadline.weight(.medium))

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(.accent)
                }
                .buttonStyle(.plain)

                // Show completed toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showCompleted.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.caption)

                        Text("Done")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(showCompleted ? Color.green.opacity(0.15) : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(showCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Expanded picker
            if isExpanded {
                VStack(spacing: 8) {
                    // Quick presets
                    HStack(spacing: 6) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    days = preset
                                }
                            } label: {
                                Text("\(preset)")
                                    .font(.caption.weight(days == preset ? .semibold : .regular))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(days == preset ? Color.accentColor : Color.primary.opacity(0.06))
                                    )
                                    .foregroundStyle(days == preset ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Fine-tune stepper
                    HStack(spacing: 12) {
                        Button {
                            if days > 1 { days -= 1 }
                        } label: {
                            Image(systemName: "minus")
                                .font(.caption.weight(.medium))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .disabled(days <= 1)

                        Text("\(days) day\(days == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60)

                        Button {
                            if days < 90 { days += 1 }
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.medium))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .disabled(days >= 90)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Student Queue Row

struct StudentQueueRow: View {
    let student: Student
    let lastMeeting: StudentMeeting?
    var isSelected: Bool = false
    var showCheckmark: Bool = false
    
    @Environment(\.modelContext) private var modelContext

    private var daysSinceLastMeeting: Int? {
        guard let lastMeeting = lastMeeting else { return nil }
        return Calendar.current.dateComponents([.day], from: lastMeeting.date, to: Date()).day
    }
    
    private var isAbsentToday: Bool {
        modelContext.attendanceStatus(for: student.id, on: Date()) == .absent
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Text(student.initials)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.accent)
            }
            .overlay(
                Circle()
                    .stroke(isAbsentToday ? Color.red : Color.clear, lineWidth: 1.5)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(StudentFormatter.displayName(for: student))
                    .font(.subheadline.weight(.medium))

                if let days = daysSinceLastMeeting {
                    Text("\(days) days ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No prior meetings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Age Filter Picker

struct AgeFilterPicker: View {
    @Binding var selectedAgeRanges: Set<AgeRange>
    
    private var displayText: String {
        if selectedAgeRanges.isEmpty {
            return "All Ages"
        } else if selectedAgeRanges.count == 1, let first = selectedAgeRanges.first {
            return first.rawValue
        } else {
            return "\(selectedAgeRanges.count) Ages"
        }
    }
    
    var body: some View {
        Menu {
            Button("All Ages") {
                selectedAgeRanges.removeAll()
            }
            
            Divider()
            
            ForEach(AgeRange.allCases) { range in
                Button(action: {
                    if selectedAgeRanges.contains(range) {
                        selectedAgeRanges.remove(range)
                    } else {
                        selectedAgeRanges.insert(range)
                    }
                }) {
                    HStack {
                        if selectedAgeRanges.contains(range) {
                            Image(systemName: "checkmark")
                        }
                        Text(range.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                
                Text(displayText)
                    .font(.subheadline.weight(.medium))
                
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selectedAgeRanges.isEmpty ? Color.primary.opacity(0.06) : Color.accentColor.opacity(0.12))
            )
            .foregroundStyle(selectedAgeRanges.isEmpty ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Preview

#Preview {
    MeetingsWorkflowView()
        .previewEnvironment()
}
