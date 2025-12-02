import SwiftUI
import Foundation

struct WorkCardsGridView: View {
    let works: [WorkModel]
    let studentsByID: [UUID: Student]
    let lessonsByID: [UUID: Lesson]
    let studentLessonsByID: [UUID: StudentLesson]
    let onTapWork: ((WorkModel) -> Void)?

    init(
        works: [WorkModel],
        studentsByID: [UUID: Student],
        lessonsByID: [UUID: Lesson],
        studentLessonsByID: [UUID: StudentLesson],
        onTapWork: ((WorkModel) -> Void)? = nil
    ) {
        self.works = works
        self.studentsByID = studentsByID
        self.lessonsByID = lessonsByID
        self.studentLessonsByID = studentLessonsByID
        self.onTapWork = onTapWork
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 24)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(works, id: \.id) { work in
                    WorkCard(
                        work: work,
                        studentsByID: studentsByID,
                        lessonsByID: lessonsByID,
                        studentLessonsByID: studentLessonsByID
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onTapWork?(work) }
                }
            }
            .padding(24)
        }
    }
}

private struct WorkCard: View {
    let work: WorkModel
    let studentsByID: [UUID: Student]
    let lessonsByID: [UUID: Lesson]
    let studentLessonsByID: [UUID: StudentLesson]

    private var studentLessonSnapshotsByID: [UUID: StudentLessonSnapshot] {
        Dictionary(uniqueKeysWithValues: studentLessonsByID.map { ($0.key, $0.value.snapshot()) })
    }

    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var workTypeColor: Color {
        switch work.workType {
        case .research: return .teal
        case .followUp: return .orange
        case .practice: return .purple
        }
    }

    private var workTypeBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(workTypeColor).frame(width: 6, height: 6)
            Text(work.workType.rawValue)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(workTypeColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(workTypeColor.opacity(0.12)))
        .accessibilityLabel("Work type: \(work.workType.rawValue)")
    }

    private var linkedLessonLine: String {
        guard let slID = work.studentLessonID, let snap = studentLessonSnapshotsByID[slID] else { return "" }
        let lessonName = lessonsByID[snap.lessonID]?.name ?? "Lesson"
        let date = snap.scheduledFor ?? snap.givenAt ?? snap.createdAt
        let dateString = date.formatted(date: .numeric, time: .omitted)
        return "\(lessonName) • \(dateString)"
    }

    private var activeStudentNames: [String] {
        work.studentIDs.compactMap { id -> String? in
            guard let s = studentsByID[id] else { return nil }
            guard !work.isStudentCompleted(id) else { return nil }
            let parts = s.fullName.split(separator: " ")
            guard let first = parts.first else { return s.fullName }
            let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
            return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
        }
    }

    private var completedCount: Int {
        work.studentIDs.filter { work.isStudentCompleted($0) }.count
    }

    private var studentsLineView: some View {
        HStack(spacing: 4) {
            if !activeStudentNames.isEmpty {
                Text(activeStudentNames.count <= 3 ? activeStudentNames.joined(separator: ", ") : activeStudentNames.prefix(3).joined(separator: ", ") + ", +\(activeStudentNames.count - 3)")
            }
            if completedCount > 0 {
                Text("• \(completedCount) done")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var notesText: String {
        work.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var titleText: String {
        work.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if !titleText.isEmpty {
                    Text(titleText)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                } else {
                    Text(work.createdAt, style: .date)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                }
                if work.isCompleted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Completed")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                    }
                }
                Spacer(minLength: 0)
                workTypeBadge
            }
            if !titleText.isEmpty {
                Text(work.createdAt, style: .date)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            studentsLineView

            if !linkedLessonLine.isEmpty {
                Text(linkedLessonLine)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !notesText.isEmpty {
                Text(notesText)
                    .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }
}

#Preview {
    let studentA = Student(firstName: "Alex", lastName: "Rivera", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    let studentB = Student(firstName: "Blair", lastName: "Chen", birthday: Date(timeIntervalSince1970: 0), level: .lower)
    let lesson = Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Intro", writeUp: "")
    let sl = StudentLesson(lessonID: lesson.id, studentIDs: [studentA.id, studentB.id])
    let work = WorkModel(studentIDs: [studentA.id, studentB.id], workType: .practice, studentLessonID: sl.id, notes: "Practiced with golden beads.")

    return WorkCardsGridView(
        works: [work],
        studentsByID: [studentA.id: studentA, studentB.id: studentB],
        lessonsByID: [lesson.id: lesson],
        studentLessonsByID: [sl.id: sl]
    )
}
