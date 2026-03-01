import SwiftUI
import SwiftData
import OSLog

struct ObservationHeatmapView: View {
    private static let logger = Logger.students
    @Environment(\.modelContext) private var modelContext
    @Query(sort: Student.sortByName)
    private var allStudentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var allStudents: [Student] { allStudentsRaw.uniqueByID }
    
    @State private var studentObservations: [StudentObservation] = []
    @State private var showingQuickNote: Bool = false
    @State private var selectedStudentID: UUID?
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: 12)
            ], spacing: 12) {
                ForEach(studentObservations) { observation in
                    StudentObservationCard(
                        observation: observation,
                        onTap: {
                            selectedStudentID = observation.student.id
                            showingQuickNote = true
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Observation Heatmap")
        .onAppear {
            calculateObservationsAsync()
        }
        .onChange(of: allStudents.count) { _, _ in
            calculateObservationsAsync()
        }
        .sheet(isPresented: $showingQuickNote) {
            if let studentID = selectedStudentID {
                QuickNoteSheet(initialStudentID: studentID)
            } else {
                QuickNoteSheet()
            }
        }
    }
    
    private func calculateObservations() {
        var observations: [StudentObservation] = []
        
        for student in allStudents {
            let mostRecentDate = findMostRecentNoteDate(for: student)
            let daysSince = calculateDaysSince(date: mostRecentDate)
            
            observations.append(StudentObservation(
                student: student,
                daysSinceLastObservation: daysSince,
                mostRecentDate: mostRecentDate
            ))
        }
        
        // Sort: Red (most days) at top, then Yellow, then Green
        observations.sort { lhs, rhs in
            // First sort by observation status (Red > Yellow > Green)
            let lhsStatus = observationStatus(for: lhs.daysSinceLastObservation)
            let rhsStatus = observationStatus(for: rhs.daysSinceLastObservation)
            
            if lhsStatus != rhsStatus {
                return lhsStatus.rawValue > rhsStatus.rawValue
            }
            
            // If same status, sort by days (more days = higher priority)
            return lhs.daysSinceLastObservation > rhs.daysSinceLastObservation
        }
        
        studentObservations = observations
    }
    
    private func calculateObservationsAsync() {
        Task { @MainActor in
            let context = modelContext
            let students = allStudents
            
            // 1) Fetch all StudentMeetings once
            let allMeetings: [StudentMeeting]
            do {
                allMeetings = try context.fetch(FetchDescriptor<StudentMeeting>())
            } catch {
                Self.logger.warning("Failed to fetch StudentMeetings: \(error)")
                allMeetings = []
            }

            // 2) Fetch all WorkModels once (preferred)
            let allWorkModels: [WorkModel]
            do {
                allWorkModels = try context.fetch(FetchDescriptor<WorkModel>())
            } catch {
                Self.logger.warning("Failed to fetch WorkModels: \(error)")
                allWorkModels = []
            }

            // 3) Fetch all Notes once
            let allNotes: [Note]
            do {
                allNotes = try context.fetch(FetchDescriptor<Note>())
            } catch {
                Self.logger.warning("Failed to fetch Notes: \(error)")
                allNotes = []
            }
            
            // Build dictionaries for O(1) lookup

            // StudentMeetings grouped by studentID (String) -> most recent date with content
            var meetingsByStudentID: [String: Date] = [:]
            for meeting in allMeetings {
                let hasContent = !meeting.reflection.trimmed().isEmpty ||
                                !meeting.focus.trimmed().isEmpty ||
                                !meeting.requests.trimmed().isEmpty ||
                                !meeting.guideNotes.trimmed().isEmpty
                
                if hasContent {
                    if let existing = meetingsByStudentID[meeting.studentID] {
                        if meeting.date > existing {
                            meetingsByStudentID[meeting.studentID] = meeting.date
                        }
                    } else {
                        meetingsByStudentID[meeting.studentID] = meeting.date
                    }
                }
            }
            
            // WorkModels grouped by studentID (String) -> set of work IDs
            var workIDsByStudentID: [String: Set<UUID>] = [:]
            for work in allWorkModels {
                workIDsByStudentID[work.studentID, default: []].insert(work.id)
            }

            // LessonAssignments by ID (for mapping presentation notes)
            var lessonAssignmentsByID: [UUID: LessonAssignment] = [:]
            let allLessonAssignments: [LessonAssignment]
            do {
                allLessonAssignments = try context.fetch(FetchDescriptor<LessonAssignment>())
            } catch {
                Self.logger.warning("Failed to fetch LessonAssignments: \(error)")
                allLessonAssignments = []
            }
            for assignment in allLessonAssignments {
                lessonAssignmentsByID[assignment.id] = assignment
            }

            // Notes by studentID (from scope, work, and lessonAssignment)
            // Group 1: Notes with student scope - map by studentID
            var studentScopedNotesByStudentID: [UUID: [Note]] = [:]
            // Group 2: Notes with work relationships - map by workID
            var workNotesByWorkID: [UUID: Note] = [:]
            // Group 3: Notes with presentation relationships - map by presentationID
            var presentationNotesByPresentationID: [UUID: Note] = [:]
            
            for note in allNotes {
                // Group 1: Student-scoped notes (only .student(let id) scope, matching original logic)
                if case .student(let studentID) = note.scope {
                    studentScopedNotesByStudentID[studentID, default: []].append(note)
                }
                
                // Group 2: WorkModel notes (preferred)
                if let work = note.work {
                    // Store the most recent note per work
                    if let existing = workNotesByWorkID[work.id] {
                        let existingDate = max(existing.updatedAt, existing.createdAt)
                        let noteDate = max(note.updatedAt, note.createdAt)
                        if noteDate > existingDate {
                            workNotesByWorkID[work.id] = note
                        }
                    } else {
                        workNotesByWorkID[work.id] = note
                    }
                }
                
                // Group 3: Presentation notes (from Presentation - the unified model)
                if let assignment = note.lessonAssignment {
                    // Store the most recent note per LessonAssignment
                    if let existing = presentationNotesByPresentationID[assignment.id] {
                        let existingDate = max(existing.updatedAt, existing.createdAt)
                        let noteDate = max(note.updatedAt, note.createdAt)
                        if noteDate > existingDate {
                            presentationNotesByPresentationID[assignment.id] = note
                        }
                    } else {
                        presentationNotesByPresentationID[assignment.id] = note
                    }
                }
            }

            // Compute most recent date for each student
            var observations: [StudentObservation] = []
            
            for student in students {
                var mostRecentDate: Date? = nil
                let studentIDString = student.id.uuidString
                
                // 1) Check student-scoped notes
                if let studentNotes = studentScopedNotesByStudentID[student.id] {
                    for note in studentNotes {
                        let noteDate = max(note.updatedAt, note.createdAt)
                        if mostRecentDate == nil || noteDate > mostRecentDate! {
                            mostRecentDate = noteDate
                        }
                    }
                }
                
                // 2) Check WorkModel notes (preferred)
                if let workIDs = workIDsByStudentID[studentIDString] {
                    for workID in workIDs {
                        if let note = workNotesByWorkID[workID] {
                            let noteDate = max(note.updatedAt, note.createdAt)
                            if mostRecentDate == nil || noteDate > mostRecentDate! {
                                mostRecentDate = noteDate
                            }
                        }
                    }
                }
                
                // 3) Check LessonAssignment notes
                for (assignmentID, assignment) in lessonAssignmentsByID {
                    if assignment.studentIDs.contains(studentIDString) {
                        if let note = presentationNotesByPresentationID[assignmentID] {
                            let noteDate = max(note.updatedAt, note.createdAt)
                            if mostRecentDate == nil || noteDate > mostRecentDate! {
                                mostRecentDate = noteDate
                            }
                        }
                    }
                }
                
                // 4) Check StudentMeeting records
                if let meetingDate = meetingsByStudentID[studentIDString] {
                    if mostRecentDate == nil || meetingDate > mostRecentDate! {
                        mostRecentDate = meetingDate
                    }
                }
                
                let daysSince = calculateDaysSince(date: mostRecentDate)
                observations.append(StudentObservation(
                    student: student,
                    daysSinceLastObservation: daysSince,
                    mostRecentDate: mostRecentDate
                ))
            }
            
            // Sort: Red (most days) at top, then Yellow, then Green
            observations.sort { lhs, rhs in
                // First sort by observation status (Red > Yellow > Green)
                let lhsStatus = observationStatus(for: lhs.daysSinceLastObservation)
                let rhsStatus = observationStatus(for: rhs.daysSinceLastObservation)
                
                if lhsStatus != rhsStatus {
                    return lhsStatus.rawValue > rhsStatus.rawValue
                }
                
                // If same status, sort by days (more days = higher priority)
                return lhs.daysSinceLastObservation > rhs.daysSinceLastObservation
            }
            
            // Update studentObservations
            studentObservations = observations
        }
    }
    
    private func findMostRecentNoteDate(for student: Student) -> Date? {
        var mostRecentDate: Date? = nil
        
        // 1) Check general Note objects where scope matches .student(student.id)
        let noteSort: [SortDescriptor<Note>] = [
            SortDescriptor(\Note.updatedAt, order: .reverse),
            SortDescriptor(\Note.createdAt, order: .reverse)
        ]
        let noteDesc = FetchDescriptor<Note>(sortBy: noteSort)
        let allNotes: [Note]
        do {
            allNotes = try modelContext.fetch(noteDesc)
        } catch {
            Self.logger.warning("Failed to fetch notes: \(error)")
            allNotes = []
        }
        let visibleNotes = allNotes.filter { note in
            if case .student(let id) = note.scope { return id == student.id }
            return false
        }
        
        for note in visibleNotes {
            let noteDate = max(note.updatedAt, note.createdAt)
            if mostRecentDate == nil || noteDate > mostRecentDate! {
                mostRecentDate = noteDate
            }
        }
        
        // 2) Check LessonAssignment notes that include this student
        let studentIDString = student.id.uuidString
        let presentationNoteFetch = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.lessonAssignment != nil }
        )
        let presentationNotes: [Note]
        do {
            presentationNotes = try modelContext.fetch(presentationNoteFetch)
        } catch {
            Self.logger.warning("Failed to fetch presentation notes: \(error)")
            presentationNotes = []
        }

        for note in presentationNotes {
            guard let pres = note.lessonAssignment,
                  pres.studentIDs.contains(studentIDString) else {
                continue
            }

            let noteDate = max(note.updatedAt, note.createdAt)
            if mostRecentDate == nil || noteDate > mostRecentDate! {
                mostRecentDate = noteDate
            }
        }

        // 3) Check StudentMeeting records for this student
        let meetingFetch = FetchDescriptor<StudentMeeting>(
            predicate: #Predicate<StudentMeeting> { $0.studentID == studentIDString },
            sortBy: [SortDescriptor(\StudentMeeting.date, order: .reverse)]
        )
        let studentMeetings: [StudentMeeting]
        do {
            studentMeetings = try modelContext.fetch(meetingFetch)
        } catch {
            Self.logger.warning("Failed to fetch student meetings: \(error)")
            studentMeetings = []
        }

        for meeting in studentMeetings {
            // Check if meeting has any content
            let hasContent = !meeting.reflection.trimmed().isEmpty ||
                            !meeting.focus.trimmed().isEmpty ||
                            !meeting.requests.trimmed().isEmpty ||
                            !meeting.guideNotes.trimmed().isEmpty
            
            if hasContent {
                if mostRecentDate == nil || meeting.date > mostRecentDate! {
                    mostRecentDate = meeting.date
                }
            }
        }
        
        return mostRecentDate
    }
    
    private func calculateDaysSince(date: Date?) -> Int {
        guard let date = date else {
            // No observation found - return a large number to indicate never observed
            return Int.max
        }
        
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day], from: date, to: now)
        return components.day ?? Int.max
    }
    
    private func observationStatus(for days: Int) -> ObservationStatus {
        if days == Int.max {
            return .red // Never observed
        } else if days > 7 {
            return .red
        } else if days >= 3 {
            return .yellow
        } else {
            return .green
        }
    }
}

// MARK: - Supporting Types

struct StudentObservation: Identifiable {
    let id: UUID
    let student: Student
    let daysSinceLastObservation: Int
    let mostRecentDate: Date?
    
    init(student: Student, daysSinceLastObservation: Int, mostRecentDate: Date?) {
        self.id = student.id
        self.student = student
        self.daysSinceLastObservation = daysSinceLastObservation
        self.mostRecentDate = mostRecentDate
    }
}

enum ObservationStatus: Int {
    case green = 0
    case yellow = 1
    case red = 2
}

struct StudentObservationCard: View {
    let observation: StudentObservation
    let onTap: () -> Void
    
    private var backgroundColor: Color {
        let days = observation.daysSinceLastObservation
        if days == Int.max {
            return .red.opacity(0.3)
        } else if days > 7 {
            return .red.opacity(0.3)
        } else if days >= 3 {
            return .yellow.opacity(0.3)
        } else {
            return .green.opacity(0.3)
        }
    }
    
    private var statusText: String {
        let days = observation.daysSinceLastObservation
        if days == Int.max {
            return "Never observed"
        } else if days == 0 {
            return "Today"
        } else if days == 1 {
            return "1 day ago"
        } else {
            return "\(days) days ago"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(StudentFormatter.displayName(for: observation.student))
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                
                Text(statusText)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ObservationHeatmapView()
            .previewEnvironment()
    }
}

