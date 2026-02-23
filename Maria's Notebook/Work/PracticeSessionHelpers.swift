import SwiftUI
import SwiftData

// MARK: - Student Category Types

enum StudentCategory: Int, Comparable {
    case withInitialStudent = 1    // Students who had lesson with initial student
    case practicing = 2             // Students practicing same lesson (active work)
    case recentlyPassed = 3        // Students who recently completed (within 30 days)
    case pastPractice = 4          // Students who practiced in the past
    case neverReceived = 5         // Students who never received the lesson

    static func < (lhs: StudentCategory, rhs: StudentCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .withInitialStudent:
            return "Learned Together"
        case .practicing:
            return "Currently Practicing"
        case .recentlyPassed:
            return "Recently Completed"
        case .pastPractice:
            return "Practiced Before"
        case .neverReceived:
            return "Never Received Lesson"
        }
    }
}

struct CategorizedStudent {
    let student: Student
    let category: StudentCategory
    let work: WorkModel?
    let daysSinceCompletion: Int?
    let lastPracticeDate: Date?
}

// MARK: - Student Categorization Helper

struct StudentCategorizer {
    let initialWorkItem: WorkModel
    let allWork: [WorkModel]
    let allLessonAssignments: [LessonAssignment]
    let allPracticeSessions: [PracticeSession]
    let coLearnerIDs: Set<UUID>

    func categorize(_ student: Student) -> CategorizedStudent {
        let lessonID = initialWorkItem.lessonID

        // Find work for this student and lesson
        let studentWork = allWork.filter {
            $0.studentID == student.id.uuidString &&
            $0.lessonID == lessonID &&
            $0.id != initialWorkItem.id
        }

        // Check if they're a co-learner
        if coLearnerIDs.contains(student.id) {
            let activeWork = studentWork.first { $0.status != .complete }
            return CategorizedStudent(
                student: student,
                category: .withInitialStudent,
                work: activeWork,
                daysSinceCompletion: nil,
                lastPracticeDate: nil
            )
        }

        // Check for active work (practicing)
        if let activeWork = studentWork.first(where: { $0.status != .complete }) {
            return CategorizedStudent(
                student: student,
                category: .practicing,
                work: activeWork,
                daysSinceCompletion: nil,
                lastPracticeDate: nil
            )
        }

        // Check for completed work (recently passed)
        if let completedWork = studentWork.first(where: { $0.status == .complete }) {
            let daysSince = completedWork.completedAt.map {
                Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? Int.max
            } ?? Int.max

            if daysSince <= 30 {
                return CategorizedStudent(
                    student: student,
                    category: .recentlyPassed,
                    work: completedWork,
                    daysSinceCompletion: daysSince,
                    lastPracticeDate: completedWork.completedAt
                )
            }
        }

        // Check for past practice sessions
        let practiceSessions = allPracticeSessions.filter { session in
            session.studentIDs.contains(student.id.uuidString) &&
            session.workItemIDs.contains { workID in
                if let work = allWork.first(where: { $0.id.uuidString == workID }) {
                    return work.lessonID == lessonID
                }
                return false
            }
        }.sorted { $0.date > $1.date }

        if let lastSession = practiceSessions.first {
            return CategorizedStudent(
                student: student,
                category: .pastPractice,
                work: nil,
                daysSinceCompletion: nil,
                lastPracticeDate: lastSession.date
            )
        }

        // Check if student has received the lesson at all
        let hasReceivedLesson = allLessonAssignments.contains { lessonAssignment in
            guard let lessonUUID = UUID(uuidString: lessonID) else { return false }
            return lessonAssignment.lessonIDUUID == lessonUUID &&
                   lessonAssignment.studentUUIDs.contains(student.id) &&
                   lessonAssignment.isPresented
        }

        if hasReceivedLesson {
            return CategorizedStudent(
                student: student,
                category: .pastPractice,
                work: nil,
                daysSinceCompletion: nil,
                lastPracticeDate: nil
            )
        }

        // Never received the lesson
        return CategorizedStudent(
            student: student,
            category: .neverReceived,
            work: nil,
            daysSinceCompletion: nil,
            lastPracticeDate: nil
        )
    }

    /// Get co-learner IDs from the initial lesson assignment
    static func getCoLearnerIDs(
        for workItem: WorkModel,
        allLessonAssignments: [LessonAssignment]
    ) -> Set<UUID> {
        guard let lessonUUID = UUID(uuidString: workItem.lessonID),
              let studentUUID = UUID(uuidString: workItem.studentID) else {
            return []
        }

        guard let lessonAssignment = allLessonAssignments.first(where: { lessonAssignment in
            lessonAssignment.lessonIDUUID == lessonUUID &&
            lessonAssignment.studentUUIDs.contains(studentUUID)
        }) else {
            return []
        }

        return Set(lessonAssignment.studentUUIDs)
    }

    /// Sort categorized students by priority and internal ordering
    static func sort(_ students: [CategorizedStudent]) -> [CategorizedStudent] {
        students.sorted { lhs, rhs in
            // First sort by category
            if lhs.category != rhs.category {
                return lhs.category < rhs.category
            }

            // Within category, sort by specific criteria
            switch lhs.category {
            case .withInitialStudent, .practicing:
                // Alphabetical
                return StudentFormatter.displayName(for: lhs.student) < StudentFormatter.displayName(for: rhs.student)

            case .recentlyPassed:
                // Most recently completed first
                if let lDays = lhs.daysSinceCompletion, let rDays = rhs.daysSinceCompletion {
                    return lDays < rDays
                }
                return false

            case .pastPractice:
                // Most recent practice first
                if let lDate = lhs.lastPracticeDate, let rDate = rhs.lastPracticeDate {
                    return lDate > rDate
                }
                return false

            case .neverReceived:
                // Alphabetical
                return StudentFormatter.displayName(for: lhs.student) < StudentFormatter.displayName(for: rhs.student)
            }
        }
    }
}

// MARK: - Student Category Row Component

struct StudentCategoryRow: View {
    let categorizedStudent: CategorizedStudent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "square")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text(StudentFormatter.displayName(for: categorizedStudent.student))
                        .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)

                    // Show work title or status info
                    if let work = categorizedStudent.work {
                        Text(work.title)
                            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else if let days = categorizedStudent.daysSinceCompletion {
                        Text("Completed \(days) day\(days == 1 ? "" : "s") ago")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                            .foregroundStyle(.green)
                    } else if let date = categorizedStudent.lastPracticeDate {
                        Text("Last practiced \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 16))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Section View

struct StudentCategorySection: View {
    let category: StudentCategory
    let students: [CategorizedStudent]
    let onStudentTap: (Student) -> Void

    var body: some View {
        if !students.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Category header
                Text(category.label)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.top, category == .withInitialStudent ? 0 : 8)

                // Students in this category
                ForEach(students, id: \.student.id) { categorizedStudent in
                    StudentCategoryRow(categorizedStudent: categorizedStudent) {
                        onStudentTap(categorizedStudent.student)
                    }
                }
            }
        }
    }
}
