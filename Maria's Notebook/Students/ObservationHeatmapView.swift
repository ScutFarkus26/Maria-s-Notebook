// swiftlint:disable file_length
import SwiftUI
import CoreData
import OSLog

// swiftlint:disable:next type_body_length
struct ObservationHeatmapView: View {
    private static let logger = Logger.students
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true), NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)])
    private var allStudentsRaw: FetchedResults<CDStudent>
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    private var allStudents: [CDStudent] { Array(allStudentsRaw).uniqueByID }
    
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
            let lookups = buildObservationLookups()
            var observations: [StudentObservation] = []

            for student in allStudents {
                let mostRecentDate = findMostRecentDateFromLookups(for: student, lookups: lookups)
                let daysSince = calculateDaysSince(date: mostRecentDate)
                observations.append(StudentObservation(
                    student: student,
                    daysSinceLastObservation: daysSince,
                    mostRecentDate: mostRecentDate
                ))
            }

            sortObservationsByUrgency(&observations)
            studentObservations = observations
        }
    }

    /// Pre-fetched lookup tables for O(1) per-student observation checks.
    private struct ObservationLookups {
        var meetingsByStudentID: [String: Date] = [:]
        var workIDsByStudentID: [String: Set<UUID>] = [:]
        var lessonAssignmentsByID: [UUID: CDLessonAssignment] = [:]
        var studentScopedNotesByStudentID: [UUID: [CDNote]] = [:]
        var workNotesByWorkID: [UUID: CDNote] = [:]
        var presentationNotesByPresentationID: [UUID: CDNote] = [:]
    }

    /// Fetches all entities once and builds lookup dictionaries.
    private func buildObservationLookups() -> ObservationLookups {
        var lookups = ObservationLookups()
        let context = viewContext

        let allMeetings = (try? context.fetch(NSFetchRequest<CDStudentMeeting>(entityName: "StudentMeeting"))) ?? []
        let allWorkModels = (try? context.fetch(NSFetchRequest<CDWorkModel>(entityName: "WorkModel"))) ?? []
        let allNotes = (try? context.fetch(NSFetchRequest<CDNote>(entityName: "Note"))) ?? []
        let allAssignments = (try? context.fetch(NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"))) ?? []

        buildMeetingLookup(from: allMeetings, into: &lookups)
        for work in allWorkModels {
            guard let workID = work.id else { continue }
            lookups.workIDsByStudentID[work.studentID, default: []].insert(workID)
        }
        for assignment in allAssignments {
            guard let assignmentID = assignment.id else { continue }
            lookups.lessonAssignmentsByID[assignmentID] = assignment
        }
        buildNoteLookups(from: allNotes, into: &lookups)

        return lookups
    }

    /// Groups meetings by studentID, keeping the most recent date with content.
    private func buildMeetingLookup(from meetings: [CDStudentMeeting], into lookups: inout ObservationLookups) {
        for meeting in meetings {
            let hasContent = !meeting.reflection.trimmed().isEmpty ||
                            !meeting.focus.trimmed().isEmpty ||
                            !meeting.requests.trimmed().isEmpty ||
                            !meeting.guideNotes.trimmed().isEmpty
            guard hasContent else { continue }

            let meetingDate = meeting.date ?? .distantPast
            if let existing = lookups.meetingsByStudentID[meeting.studentID] {
                if meetingDate > existing { lookups.meetingsByStudentID[meeting.studentID] = meetingDate }
            } else {
                lookups.meetingsByStudentID[meeting.studentID] = meetingDate
            }
        }
    }

    /// Groups notes by scope (student, work, presentation), keeping the most recent per key.
    private func buildNoteLookups(from notes: [CDNote], into lookups: inout ObservationLookups) {
        for note in notes {
            if case .student(let studentID) = note.scope {
                lookups.studentScopedNotesByStudentID[studentID, default: []].append(note)
            }
            if let work = note.work, let workID = work.id {
                updateMostRecentNote(for: workID, note: note, in: &lookups.workNotesByWorkID)
            }
            if let assignment = note.lessonAssignment, let assignmentID = assignment.id {
                updateMostRecentNote(
                    for: assignmentID, note: note, in: &lookups.presentationNotesByPresentationID
                )
            }
        }
    }

    /// Keeps the most recent note per key in a dictionary.
    private func updateMostRecentNote(for key: UUID, note: CDNote, in dict: inout [UUID: CDNote]) {
        let noteDate = max(note.updatedAt ?? .distantPast, note.createdAt ?? .distantPast)
        if let existing = dict[key] {
            let existingDate = max(existing.updatedAt ?? .distantPast, existing.createdAt ?? .distantPast)
            if noteDate > existingDate { dict[key] = note }
        } else {
            dict[key] = note
        }
    }

    // Finds the most recent observation date for a student using pre-built lookups.
    // swiftlint:disable:next cyclomatic_complexity
    private func findMostRecentDateFromLookups(
        for student: CDStudent, lookups: ObservationLookups
    ) -> Date? {
        var mostRecentDate: Date?
        let studentIDString = student.id?.uuidString ?? ""

        // 1) CDStudent-scoped notes
        if let sid = student.id, let studentNotes = lookups.studentScopedNotesByStudentID[sid] {
            for note in studentNotes {
                let noteDate = max(note.updatedAt ?? .distantPast, note.createdAt ?? .distantPast)
                if mostRecentDate == nil || noteDate > mostRecentDate! { mostRecentDate = noteDate }
            }
        }
        // 2) CDWorkModel notes
        if let workIDs = lookups.workIDsByStudentID[studentIDString] {
            for workID in workIDs {
                if let note = lookups.workNotesByWorkID[workID] {
                    let noteDate = max(note.updatedAt ?? .distantPast, note.createdAt ?? .distantPast)
                    if mostRecentDate == nil || noteDate > mostRecentDate! { mostRecentDate = noteDate }
                }
            }
        }
        // 3) CDLessonAssignment notes
        for (assignmentID, assignment) in lookups.lessonAssignmentsByID
            where assignment.studentIDs.contains(studentIDString) {
            if let note = lookups.presentationNotesByPresentationID[assignmentID] {
                let noteDate = max(note.updatedAt ?? .distantPast, note.createdAt ?? .distantPast)
                if mostRecentDate == nil || noteDate > mostRecentDate! { mostRecentDate = noteDate }
            }
        }
        // 4) CDStudentMeeting records
        if let meetingDate = lookups.meetingsByStudentID[studentIDString] {
            if mostRecentDate == nil || meetingDate > mostRecentDate! { mostRecentDate = meetingDate }
        }

        return mostRecentDate
    }

    /// Sorts observations: Red (most overdue) first, then Yellow, then Green.
    private func sortObservationsByUrgency(_ observations: inout [StudentObservation]) {
        observations.sort { lhs, rhs in
            let lhsStatus = observationStatus(for: lhs.daysSinceLastObservation)
            let rhsStatus = observationStatus(for: rhs.daysSinceLastObservation)
            if lhsStatus != rhsStatus { return lhsStatus.rawValue > rhsStatus.rawValue }
            return lhs.daysSinceLastObservation > rhs.daysSinceLastObservation
        }
    }

    /// Per-student fetch version (used by synchronous `calculateObservations`).
    private func findMostRecentNoteDate(for student: CDStudent) -> Date? {
        var mostRecentDate: Date?
        let studentIDString = student.id?.uuidString ?? ""

        // 1) CDStudent-scoped notes
        mostRecentDate = findMostRecentStudentScopedNoteDate(for: student)

        // 2) CDLessonAssignment notes
        mostRecentDate = findMostRecentPresentationNoteDate(
            studentIDString: studentIDString, current: mostRecentDate
        )

        // 3) CDStudentMeeting records
        mostRecentDate = findMostRecentMeetingDate(
            studentIDString: studentIDString, current: mostRecentDate
        )

        return mostRecentDate
    }

    private func findMostRecentStudentScopedNoteDate(for student: CDStudent) -> Date? {
        let noteDesc = NSFetchRequest<CDNote>(entityName: "Note")
        let allNotes = (try? viewContext.fetch(noteDesc)) ?? []
        var mostRecent: Date?
        for note in allNotes {
            guard case .student(let id) = note.scope, id == student.id else { continue }
            let noteDate = max(note.updatedAt ?? .distantPast, note.createdAt ?? .distantPast)
            if mostRecent == nil || noteDate > mostRecent! { mostRecent = noteDate }
        }
        return mostRecent
    }

    private func findMostRecentPresentationNoteDate(
        studentIDString: String, current: Date?
    ) -> Date? {
        let fetch: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
        fetch.predicate = NSPredicate(format: "lessonAssignment != nil")
        let notes = (try? viewContext.fetch(fetch)) ?? []
        var mostRecent = current
        for note in notes {
            guard let pres = note.lessonAssignment,
                  pres.studentIDs.contains(studentIDString) else { continue }
            let noteDate = max(note.updatedAt ?? .distantPast, note.createdAt ?? .distantPast)
            if mostRecent == nil || noteDate > mostRecent! { mostRecent = noteDate }
        }
        return mostRecent
    }

    private func findMostRecentMeetingDate(studentIDString: String, current: Date?) -> Date? {
        let fetch: NSFetchRequest<CDStudentMeeting> = NSFetchRequest(entityName: "StudentMeeting")
        fetch.predicate = NSPredicate(format: "studentID == %@", studentIDString as CVarArg)
        fetch.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudentMeeting.date, ascending: false)]
        let meetings = (try? viewContext.fetch(fetch)) ?? []
        var mostRecent = current
        for meeting in meetings {
            let hasContent = !meeting.reflection.trimmed().isEmpty ||
                            !meeting.focus.trimmed().isEmpty ||
                            !meeting.requests.trimmed().isEmpty ||
                            !meeting.guideNotes.trimmed().isEmpty
            if hasContent {
                let meetingDate = meeting.date ?? .distantPast
                if mostRecent == nil || meetingDate > mostRecent! { mostRecent = meetingDate }
            }
        }
        return mostRecent
    }
    
    private func calculateDaysSince(date: Date?) -> Int {
        guard let date else {
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
    let student: CDStudent
    let daysSinceLastObservation: Int
    let mostRecentDate: Date?
    
    init(student: CDStudent, daysSinceLastObservation: Int, mostRecentDate: Date?) {
        self.id = student.id ?? UUID()
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
            return .red.opacity(UIConstants.OpacityConstants.semi)
        } else if days > 7 {
            return .red.opacity(UIConstants.OpacityConstants.semi)
        } else if days >= 3 {
            return .yellow.opacity(UIConstants.OpacityConstants.semi)
        } else {
            return .green.opacity(UIConstants.OpacityConstants.semi)
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
                    .stroke(Color.primary.opacity(UIConstants.OpacityConstants.light), lineWidth: 1)
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
