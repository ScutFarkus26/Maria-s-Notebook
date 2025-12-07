import SwiftUI
import SwiftData

struct OpenWorkListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [
        SortDescriptor(\WorkModel.createdAt, order: .reverse)
    ]) private var allWorks: [WorkModel]

    @Query private var lessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]

    @State private var selectedWork: WorkModel? = nil

    private var lessonsByID: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }

    private var studentLessonsByID: [UUID: StudentLesson] {
        Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
    }

    private var openWorks: [WorkModel] {
        allWorks.filter { $0.isOpen }
    }

    private func iconAndColor(for type: WorkModel.WorkType) -> (String, Color) {
        switch type {
        case .research: return ("magnifyingglass", .teal)
        case .followUp: return ("bolt.fill", .orange)
        case .practice: return ("arrow.triangle.2.circlepath", .purple)
        }
    }

    private func linkedStudentLesson(for work: WorkModel) -> StudentLesson? {
        guard let id = work.studentLessonID else { return nil }
        return studentLessonsByID[id]
    }

    private func linkedLesson(for work: WorkModel) -> Lesson? {
        guard let sl = linkedStudentLesson(for: work) else { return nil }
        return lessonsByID[sl.lessonID]
    }

    private func workTitle(_ work: WorkModel) -> String {
        let title = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let lesson = linkedLesson(for: work) { return "\(work.workType.rawValue): \(lesson.name)" }
        return work.workType.rawValue
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

    var body: some View {
        NavigationStack {
            List(openWorks) { work in
                Button {
                    selectedWork = work
                } label: {
                    HStack(spacing: 12) {
                        let (icon, color) = iconAndColor(for: work.workType)
                        Image(systemName: icon)
                            .foregroundStyle(color)
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
                        let openCount = work.participants.filter { $0.completedAt == nil }.count
                        if openCount > 0 {
                            Text("\(openCount)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(color.opacity(0.15)))
                                .foregroundStyle(color)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Open Work")
        }
        .sheet(item: $selectedWork) { work in
            WorkDetailContainerView(workID: work.id) {
                selectedWork = nil
            }
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizing(.fitted)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
    }
}

#Preview {
    Text("OpenWorkListView requires live data")
}
