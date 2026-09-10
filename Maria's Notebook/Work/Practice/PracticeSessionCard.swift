import SwiftUI
import CoreData

/// Display card for a practice session
struct PracticeSessionCard: View {
    let session: CDPracticeSession
    let displayMode: DisplayMode
    /// Everyone and everything named by the practice history this card belongs
    /// to, fetched once by the parent. The card used to hold a `@FetchRequest`
    /// of the whole student table and another of the whole work table, so a
    /// work with ten sessions in its history carried twenty live
    /// fetched-results controllers.
    let allStudents: [CDStudent]
    let allWork: [CDWorkModel]
    var onTap: (() -> Void)?

    enum DisplayMode {
        case compact    // Minimal display
        case standard   // Normal card
        case expanded   // Full details
    }
    
    var students: [CDStudent] {
        allStudents.filter { student in
            session.studentIDsArray.contains(student.id?.uuidString ?? "")
        }.sorted { $0.firstName < $1.firstName }
    }

    var workItems: [CDWorkModel] {
        allWork.filter { work in
            session.workItemIDsArray.contains(work.id?.uuidString ?? "")
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
        DateFormatters.shortDate.string(from: date)
    }

    func formatDateLong(_ date: Date) -> String {
        DateFormatters.longDate.string(from: date)
    }
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct PracticeSessionCardPreview: View {
    var body: some View {
        let stack = CoreDataStack.preview
        let ctx = stack.viewContext

        let mary = CDStudent(context: ctx)
        mary.firstName = "Mary"; mary.lastName = "Smith"; mary.birthday = Date(); mary.level = .lower
        let danny = CDStudent(context: ctx)
        danny.firstName = "Danny"; danny.lastName = "Jones"; danny.birthday = Date(); danny.level = .lower

        let lesson = CDLesson(context: ctx)
        lesson.name = "Long Division"

        let work1 = CDWorkModel(context: ctx)
        work1.title = "Practice Long Division"
        work1.studentID = danny.id?.uuidString ?? ""
        work1.lessonID = lesson.id?.uuidString ?? ""
        let work2 = CDWorkModel(context: ctx)
        work2.title = "Practice Long Division"
        work2.studentID = mary.id?.uuidString ?? ""
        work2.lessonID = lesson.id?.uuidString ?? ""

        let groupSession = CDPracticeSession(context: ctx)
        groupSession.date = Date(); groupSession.duration = 1800
        groupSession.studentIDsArray = [danny.id?.uuidString ?? "", mary.id?.uuidString ?? ""]
        groupSession.workItemIDsArray = [work1.id?.uuidString ?? "", work2.id?.uuidString ?? ""]
        groupSession.sharedNotes = "Both students struggled with remainders but showed improvement by the end."
        groupSession.location = "Small table"

        let soloSession = CDPracticeSession(context: ctx)
        soloSession.date = Date().addingTimeInterval(-86400); soloSession.duration = 900
        soloSession.studentIDsArray = [danny.id?.uuidString ?? ""]
        soloSession.workItemIDsArray = [work1.id?.uuidString ?? ""]
        soloSession.sharedNotes = "Quick review session. Danny is getting better!"

        let students = [mary, danny]
        let work = [work1, work2]

        return ScrollView {
            VStack(spacing: 20) {
                Text("Compact").font(.headline)
                PracticeSessionCard(
                    session: groupSession, displayMode: .compact, allStudents: students, allWork: work
                )
                Text("Standard").font(.headline)
                PracticeSessionCard(
                    session: groupSession, displayMode: .standard, allStudents: students, allWork: work
                )
                Text("Expanded").font(.headline)
                PracticeSessionCard(
                    session: groupSession, displayMode: .expanded, allStudents: students, allWork: work
                )
                Text("Solo Session").font(.headline)
                PracticeSessionCard(
                    session: soloSession, displayMode: .standard, allStudents: students, allWork: work
                )
            }
            .padding()
        }
        .previewEnvironment(using: stack)
    }
}

#Preview("Practice Session Cards") {
    PracticeSessionCardPreview()
}
