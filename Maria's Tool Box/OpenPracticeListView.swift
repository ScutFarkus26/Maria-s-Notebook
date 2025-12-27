import SwiftUI
import SwiftData

struct OpenPracticeListView: View {
    @Environment(\.modelContext) private var modelContext

    // Pull everything and filter in-memory for maximum compatibility
    @Query(sort: [
        SortDescriptor(\WorkModel.createdAt, order: .reverse)
    ]) private var allWorks: [WorkModel]

    @Query private var lessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]

    private var lessonsByID: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }

    private var studentLessonsByID: [UUID: StudentLesson] {
        Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
    }

    private var openPractice: [WorkModel] {
        allWorks.filter { $0.workType == .practice && $0.isOpen }
    }

    private func workTitle(_ work: WorkModel) -> String {
        let title = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let lesson = linkedLesson(for: work) { return "Practice: \(lesson.name)" }
        return "Practice"
    }

    private func workSubtitle(_ work: WorkModel) -> String {
        let date: Date = {
            if let sl = linkedStudentLesson(for: work) {
                return sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
            }
            return work.createdAt
        }()
        let dateString = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        if let lesson = linkedLesson(for: work) {
            let subject = lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            return subject.isEmpty ? dateString : "\(subject) • \(dateString)"
        }
        return dateString
    }

    private func linkedStudentLesson(for work: WorkModel) -> StudentLesson? {
        guard let id = work.studentLessonID else { return nil }
        return studentLessonsByID[id]
    }

    private func linkedLesson(for work: WorkModel) -> Lesson? {
        guard let sl = linkedStudentLesson(for: work) else { return nil }
        return lessonsByID[sl.lessonID]
    }

    var body: some View {
        NavigationStack {
            List(openPractice) { work in
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workTitle(work))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(workSubtitle(work))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    // Open participant count indicator
                    let openCount = (work.participants ?? []).filter { $0.completedAt == nil }.count
                    if openCount > 0 {
                        Text("\(openCount)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                            .foregroundStyle(Color.purple)
                    }
                }
            }
            .navigationTitle("Open Practice")
        }
    }
}

#Preview {
    Text("OpenPracticeListView requires live data")
}
