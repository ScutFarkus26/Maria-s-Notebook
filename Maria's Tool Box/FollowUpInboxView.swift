import SwiftUI
import SwiftData

struct FollowUpInboxView: View {
    @Environment(\.modelContext) private var modelContext

    // Step 2 — Local rule constants (no settings yet)
    private let lessonFollowUpOverdueDays: Int = 7
    private let workStaleOverdueDays: Int = 5
    private let reviewStaleDays: Int = 3

    // Data sources
    @Query private var lessons: [Lesson]
    @Query private var students: [Student]
    @Query private var studentLessons: [StudentLesson]
    @Query private var contracts: [WorkContract]
    @Query private var planItems: [WorkPlanItem]
    @Query private var notes: [ScopedNote]

    @Query(filter: #Predicate<WorkNote> { $0.isLessonToGive == true }, sort: [
        SortDescriptor(\WorkNote.createdAt, order: .reverse)
    ]) private var lessonReminderNotes: [WorkNote]

    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    private var visibleStudents: [Student] {
        TestStudentsFilter.filterVisible(students, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    // Simple filter control
    private enum Filter: String, CaseIterable, Identifiable { case all = "All", overdue = "Overdue", today = "Due Today"; var id: String { rawValue } }
    @State private var filter: Filter = .all

    // Sheet selections
    private struct SLToken: Identifiable { let id: UUID }
    private struct ContractToken: Identifiable { let id: UUID }
    private struct WorkToken: Identifiable { let id: UUID }
    @State private var selectedSL: SLToken? = nil
    @State private var selectedContract: ContractToken? = nil
    @State private var selectedWork: WorkToken? = nil

    private var items: [FollowUpInboxItem] {
        let constants = FollowUpInboxEngine.Constants(
            lessonFollowUpOverdueDays: lessonFollowUpOverdueDays,
            workStaleOverdueDays: workStaleOverdueDays,
            reviewStaleDays: reviewStaleDays
        )
        return FollowUpInboxEngine.computeItems(
            lessons: lessons,
            students: visibleStudents,
            studentLessons: studentLessons,
            contracts: contracts,
            planItems: planItems,
            notes: notes,
            modelContext: modelContext,
            constants: constants
        )
    }

    private var itemsFiltered: [FollowUpInboxItem] {
        switch filter {
        case .all: return items
        case .overdue: return items.filter { $0.bucket == .overdue }
        case .today: return items.filter { $0.bucket == .dueToday }
        }
    }

    private var overdue: [FollowUpInboxItem] { itemsFiltered.filter { $0.bucket == .overdue } }
    private var dueToday: [FollowUpInboxItem] { itemsFiltered.filter { $0.bucket == .dueToday } }
    private var upcoming: [FollowUpInboxItem] { itemsFiltered.filter { $0.bucket == .upcoming } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if overdue.isEmpty && dueToday.isEmpty && upcoming.isEmpty && lessonReminderNotes.isEmpty {
                ContentUnavailableView("Nothing due", systemImage: "tray", description: Text("You're all caught up."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !lessonReminderNotes.isEmpty {
                        Section("Lessons to Give") {
                            ForEach(lessonReminderNotes, id: \.id) { note in
                                lessonReminderRow(note)
                            }
                        }
                    }
                    if !overdue.isEmpty {
                        Section("Overdue") {
                            ForEach(overdue, id: \.id) { item in
                                row(item)
                            }
                        }
                    }
                    if !dueToday.isEmpty {
                        Section("Due Today") {
                            ForEach(dueToday, id: \.id) { item in
                                row(item)
                            }
                        }
                    }
                    if !upcoming.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcoming, id: \.id) { item in
                                row(item)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .sheet(item: $selectedSL) { token in
            let targetID = token.id
            let fetch = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == targetID })
            if let sl = try? modelContext.fetch(fetch).first {
                StudentLessonDetailView(studentLesson: sl) { selectedSL = nil }
            } else {
                ContentUnavailableView("Lesson not found", systemImage: "exclamationmark.triangle")
            }
        }
        .sheet(item: $selectedContract) { token in
            let targetID = token.id
            let fetch = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == targetID })
            if let c = try? modelContext.fetch(fetch).first {
                WorkContractDetailSheet(contract: c) { selectedContract = nil }
            } else {
                ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
            }
        }
        .sheet(item: $selectedWork) { token in
            WorkDetailContainerView(workID: token.id) {
                selectedWork = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray")
                .imageScale(.large)
                .foregroundStyle(.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Follow-Up Inbox").font(.title3.weight(.semibold))
                Text("Overdue and due-today follow-ups for lessons and work.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
        }
        .padding(.horizontal, 4)
    }

    private func studentName(for note: WorkNote) -> String {
        if let s = note.student { return StudentFormatter.displayName(for: s) }
        if let sid = note.work?.participants.first?.studentID,
           let s = students.first(where: { $0.id == sid }) {
            return StudentFormatter.displayName(for: s)
        }
        return "Unknown student"
    }

    private func workTitle(for note: WorkNote) -> String? {
        guard let w = note.work else { return nil }
        let trimmed = w.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // Fallback to lesson name if available through StudentLesson
        if let slID = w.studentLessonID,
           let sl = studentLessons.first(where: { $0.id == slID }),
           let lesson = lessons.first(where: { $0.id == sl.lessonID }) {
            return lesson.name
        }
        return nil
    }

    @ViewBuilder
    private func lessonReminderRow(_ note: WorkNote) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(studentName(for: note))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let wt = workTitle(for: note) {
                        Text("from: \(wt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(note.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(note.createdAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let w = note.work {
                selectedWork = WorkToken(id: w.id)
            } else if let s = note.student {
                NotificationCenter.default.post(name: Notification.Name("OpenStudentDetailRequested"), object: s.id)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Clear") {
                note.isLessonToGive = false
                try? modelContext.save()
            }.tint(.blue)
        }
    }

    @ViewBuilder
    private func row(_ item: FollowUpInboxItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Kind tag
            HStack(spacing: 6) {
                Image(systemName: item.kind.icon)
                Text(item.kind.label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(item.kind.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(item.kind.tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !item.childName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(item.childName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(item.statusText)
                    .font(.caption)
                    .foregroundStyle(item.bucket == .overdue ? .red : .secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { open(item) }
    }

    private func open(_ item: FollowUpInboxItem) {
        switch item.kind {
        case .lessonFollowUp:
            selectedSL = SLToken(id: item.underlyingID)
        case .workCheckIn, .workReview:
            selectedContract = ContractToken(id: item.underlyingID)
        }
    }
}

#Preview {
    FollowUpInboxView()
}
/*
Sanity checklist:
 • Add note works
 • Lesson to give appears in Planning
 • Clear removes from Planning but keeps note attached to work
 • Delete note works and cascades appropriately
*/

