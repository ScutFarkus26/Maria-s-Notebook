import SwiftUI
import SwiftData

struct ObservationHeatmapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\Student.firstName),
        SortDescriptor(\Student.lastName)
    ]) private var allStudents: [Student]
    
    @State private var studentObservations: [StudentObservation] = []
    @State private var showingQuickNote: Bool = false
    @State private var selectedStudentID: UUID? = nil
    
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
            let allMeetings: [StudentMeeting] = (try? context.fetch(FetchDescriptor<StudentMeeting>())) ?? []
            
            // 2) Fetch all WorkContracts once
            let allContracts: [WorkContract] = (try? context.fetch(FetchDescriptor<WorkContract>())) ?? []
            
            // 3) Fetch all Notes once
            let allNotes: [Note] = (try? context.fetch(FetchDescriptor<Note>())) ?? []
            
            // 4) Fetch all Presentations once
            let allPresentations: [Presentation] = (try? context.fetch(FetchDescriptor<Presentation>())) ?? []
            
            // Build dictionaries for O(1) lookup
            
            // StudentMeetings grouped by studentID (String) -> most recent date with content
            var meetingsByStudentID: [String: Date] = [:]
            for meeting in allMeetings {
                let hasContent = !meeting.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !meeting.focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !meeting.requests.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !meeting.guideNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                
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
            
            // WorkContracts grouped by studentID (String) -> set of contract IDs
            var contractIDsByStudentID: [String: Set<UUID>] = [:]
            for contract in allContracts {
                contractIDsByStudentID[contract.studentID, default: []].insert(contract.id)
            }
            
            // Presentations by ID
            var presentationsByID: [UUID: Presentation] = [:]
            for presentation in allPresentations {
                presentationsByID[presentation.id] = presentation
            }
            
            // Notes by studentID (from scope, workContract, and presentation)
            // Group 1: Notes with student scope - map by studentID
            var studentScopedNotesByStudentID: [UUID: [Note]] = [:]
            // Group 2: Notes with workContract relationships - map by contractID
            var contractNotesByContractID: [UUID: Note] = [:]
            // Group 3: Notes with presentation relationships - map by presentationID
            var presentationNotesByPresentationID: [UUID: Note] = [:]
            
            for note in allNotes {
                // Group 1: Student-scoped notes (only .student(let id) scope, matching original logic)
                if case .student(let studentID) = note.scope {
                    studentScopedNotesByStudentID[studentID, default: []].append(note)
                }
                
                // Group 2: WorkContract notes
                if let contract = note.workContract {
                    // Store the most recent note per contract
                    if let existing = contractNotesByContractID[contract.id] {
                        let existingDate = max(existing.updatedAt, existing.createdAt)
                        let noteDate = max(note.updatedAt, note.createdAt)
                        if noteDate > existingDate {
                            contractNotesByContractID[contract.id] = note
                        }
                    } else {
                        contractNotesByContractID[contract.id] = note
                    }
                }
                
                // Group 3: Presentation notes
                if let presentation = note.presentation {
                    // Store the most recent note per presentation
                    if let existing = presentationNotesByPresentationID[presentation.id] {
                        let existingDate = max(existing.updatedAt, existing.createdAt)
                        let noteDate = max(note.updatedAt, note.createdAt)
                        if noteDate > existingDate {
                            presentationNotesByPresentationID[presentation.id] = note
                        }
                    } else {
                        presentationNotesByPresentationID[presentation.id] = note
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
                
                // 2) Check WorkContract notes
                if let contractIDs = contractIDsByStudentID[studentIDString] {
                    for contractID in contractIDs {
                        if let note = contractNotesByContractID[contractID] {
                            let noteDate = max(note.updatedAt, note.createdAt)
                            if mostRecentDate == nil || noteDate > mostRecentDate! {
                                mostRecentDate = noteDate
                            }
                        }
                    }
                }
                
                // 3) Check Presentation notes
                for (presentationID, presentation) in presentationsByID {
                    if presentation.studentIDs.contains(studentIDString) {
                        if let note = presentationNotesByPresentationID[presentationID] {
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
        let allNotes: [Note] = (try? modelContext.fetch(noteDesc)) ?? []
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
        
        // 2) Check Note linked to this student's WorkContracts
        let sid = student.id.uuidString
        let workFetch = FetchDescriptor<WorkContract>(
            predicate: #Predicate<WorkContract> { $0.studentID == sid }
        )
        let contracts: [WorkContract] = (try? modelContext.fetch(workFetch)) ?? []
        let contractIDs = Set(contracts.map { $0.id })
        
        if !contractIDs.isEmpty {
            let noteSort: [SortDescriptor<Note>] = [
                SortDescriptor(\Note.updatedAt, order: .reverse),
                SortDescriptor(\Note.createdAt, order: .reverse)
            ]
            let noteFetch = FetchDescriptor<Note>(
                predicate: #Predicate<Note> { $0.workContract != nil },
                sortBy: noteSort
            )
            let notes: [Note] = (try? modelContext.fetch(noteFetch)) ?? []
            
            for note in notes {
                guard let contract = note.workContract, contractIDs.contains(contract.id) else { continue }
                let noteDate = max(note.updatedAt, note.createdAt)
                if mostRecentDate == nil || noteDate > mostRecentDate! {
                    mostRecentDate = noteDate
                }
            }
        }
        
        // 3) Check Note linked to Presentations that include this student
        let studentIDString = student.id.uuidString
        let presentationNoteFetch = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.presentation != nil },
            sortBy: [
                SortDescriptor(\Note.updatedAt, order: .reverse),
                SortDescriptor(\Note.createdAt, order: .reverse)
            ]
        )
        let presentationNotes: [Note] = (try? modelContext.fetch(presentationNoteFetch)) ?? []
        
        let allPresentations: [Presentation] = (try? modelContext.fetch(FetchDescriptor<Presentation>())) ?? []
        // Build dictionary safely, handling potential duplicates by keeping the first occurrence
        var presentationsByID: [UUID: Presentation] = [:]
        for presentation in allPresentations {
            if presentationsByID[presentation.id] == nil {
                presentationsByID[presentation.id] = presentation
            }
        }
        
        for note in presentationNotes {
            guard let presentation = note.presentation,
                  presentation.studentIDs.contains(studentIDString) else {
                continue
            }
            
            let noteDate = max(note.updatedAt, note.createdAt)
            if mostRecentDate == nil || noteDate > mostRecentDate! {
                mostRecentDate = noteDate
            }
        }
        
        // 4) Check StudentMeeting records for this student
        let meetingFetch = FetchDescriptor<StudentMeeting>(
            predicate: #Predicate<StudentMeeting> { $0.studentID == studentIDString },
            sortBy: [SortDescriptor(\StudentMeeting.date, order: .reverse)]
        )
        let studentMeetings: [StudentMeeting] = (try? modelContext.fetch(meetingFetch)) ?? []
        
        for meeting in studentMeetings {
            // Check if meeting has any content
            let hasContent = !meeting.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            !meeting.focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            !meeting.requests.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            !meeting.guideNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
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
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(statusText)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
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

