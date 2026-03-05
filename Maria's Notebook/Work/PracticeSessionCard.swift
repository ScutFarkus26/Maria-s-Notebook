import SwiftUI
import SwiftData

/// Display card for a practice session
struct PracticeSessionCard: View {
    let session: PracticeSession
    let displayMode: DisplayMode
    var onTap: (() -> Void)?
    
    @Query var allStudents: [Student]
    @Query var allWork: [WorkModel]
    
    enum DisplayMode {
        case compact    // Minimal display
        case standard   // Normal card
        case expanded   // Full details
    }
    
    var students: [Student] {
        allStudents.filter { student in
            session.studentIDs.contains(student.id.uuidString)
        }.sorted { $0.firstName < $1.firstName }
    }
    
    var workItems: [WorkModel] {
        allWork.filter { work in
            session.workItemIDs.contains(work.id.uuidString)
        }
    }
    
    var body: some View {
        switch displayMode {
        case .compact:
            compactView
        case .standard:
            standardView
        case .expanded:
            expandedView
        }
    }
    
    // MARK: - Helpers

    var studentNames: String {
        students.map { StudentFormatter.displayName(for: $0) }.joined(separator: ", ")
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    func formatDateLong(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Practice Session Cards") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: AppSchema.schema, configurations: config)
    let context = container.mainContext
    
    // Create sample students
    let mary = Student(firstName: "Mary", lastName: "Smith", birthday: Date(), level: .lower)
    let danny = Student(firstName: "Danny", lastName: "Jones", birthday: Date(), level: .lower)
    
    context.insert(mary)
    context.insert(danny)
    
    // Create sample lesson
    let lesson = Lesson()
    lesson.name = "Long Division"
    context.insert(lesson)
    
    // Create sample work
    let work1 = WorkModel(
        title: "Practice Long Division",
        studentID: danny.id.uuidString,
        lessonID: lesson.id.uuidString
    )
    let work2 = WorkModel(
        title: "Practice Long Division",
        studentID: mary.id.uuidString,
        lessonID: lesson.id.uuidString
    )
    
    context.insert(work1)
    context.insert(work2)
    
    // Create sample sessions
    let groupSession = PracticeSession(
        date: Date(),
        duration: 1800, // 30 minutes
        studentIDs: [danny.id.uuidString, mary.id.uuidString],
        workItemIDs: [work1.id.uuidString, work2.id.uuidString],
        sharedNotes: "Both students struggled with remainders but showed improvement " +
            "by the end. Need more practice with manipulatives.",
        location: "Small table"
    )
    
    let soloSession = PracticeSession(
        date: Date().addingTimeInterval(-86400), // Yesterday
        duration: 900, // 15 minutes
        studentIDs: [danny.id.uuidString],
        workItemIDs: [work1.id.uuidString],
        sharedNotes: "Quick review session. Danny is getting better!",
        location: nil
    )
    
    context.insert(groupSession)
    context.insert(soloSession)
    
    return ScrollView {
        VStack(spacing: 20) {
            Text("Compact")
                .font(.headline)
            PracticeSessionCard(session: groupSession, displayMode: .compact)
            
            Text("Standard")
                .font(.headline)
            PracticeSessionCard(session: groupSession, displayMode: .standard)
            
            Text("Expanded")
                .font(.headline)
            PracticeSessionCard(session: groupSession, displayMode: .expanded)
            
            Text("Solo Session")
                .font(.headline)
            PracticeSessionCard(session: soloSession, displayMode: .standard)
        }
        .padding()
    }
    .modelContainer(container)
}
