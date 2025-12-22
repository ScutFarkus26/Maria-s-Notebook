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
    @State private var selectedSL: SLToken? = nil
    @State private var selectedContract: ContractToken? = nil

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
            if overdue.isEmpty && dueToday.isEmpty && upcoming.isEmpty {
                ContentUnavailableView("Nothing due", systemImage: "tray", description: Text("You're all caught up."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
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
