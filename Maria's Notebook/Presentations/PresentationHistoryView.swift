import SwiftUI
import SwiftData

struct PresentationHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    // Fetch Presentations sorted by presentedAt descending
    @Query(sort: [
        SortDescriptor(\Presentation.presentedAt, order: .reverse),
        SortDescriptor(\Presentation.createdAt, order: .reverse)
    ]) private var presentations: [Presentation]
    // Fetch Lessons
    @Query private var lessons: [Lesson]
    // Fetch Students
    @Query private var students: [Student]
    // Fetch all ScopedNotes with non-nil presentationID
    @Query(filter: #Predicate<ScopedNote> { $0.presentationID != nil }) private var allPresentationNotes: [ScopedNote]

    @State private var selectedPresentation: Presentation? = nil
    @State private var notesCountCache: [String: Int] = [:]
    @State private var studentNameCache: [UUID: String] = [:]
    @State private var lessonTitleCache: [UUID: String] = [:]
    @State private var hasBuiltCachesOnce: Bool = false

    // Maps for quick lookup
    private var lessonsByID: [UUID: Lesson] {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }
    private var studentsByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
    }

    // Group presentations by day (start of day)
    private func dayKey(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private var groupedByDay: [(day: Date, items: [Presentation])] {
        let dict = Dictionary(grouping: presentations) { p in
            dayKey(p.presentedAt)
        }
        .mapValues { arr in arr.sorted { lhs, rhs in lhs.presentedAt > rhs.presentedAt } }
        let days = dict.keys.sorted(by: >)
        return days.map { ($0, dict[$0] ?? []) }
    }

    // Date formatters
    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()

    private func buildCaches() {
        #if DEBUG
        let t0 = Date()
        #endif
        // Build notes count cache from allPresentationNotes
        var counts: [String: Int] = [:]
        for n in allPresentationNotes {
            if let pid = n.presentationID { counts[pid, default: 0] += 1 }
        }
        notesCountCache = counts
        // Build student name cache
        var sNames: [UUID: String] = [:]
        for s in students {
            sNames[s.id] = StudentFormatter.displayName(for: s)
        }
        studentNameCache = sNames
        // Build lesson title cache (prefer name)
        var lTitles: [UUID: String] = [:]
        for l in lessons {
            let t = l.name.trimmingCharacters(in: .whitespacesAndNewlines)
            lTitles[l.id] = t.isEmpty ? "Lesson" : t
        }
        lessonTitleCache = lTitles
        #if DEBUG
        let dt = Date().timeIntervalSince(t0) * 1000
        print("[DEBUG] PresentationHistoryView caches build took \(Int(dt)) ms")
        #endif
    }

    // Resolve title: prefer lessonTitleSnapshot else lookup lesson by ID
    private func title(for p: Presentation) -> String {
        let snap = (p.lessonTitleSnapshot ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !snap.isEmpty { return snap }
        if let lid = UUID(uuidString: p.lessonID), let t = lessonTitleCache[lid], !t.isEmpty {
            return t
        }
        return "Lesson"
    }

    // Student names or count string
    private func studentNamesOrCount(for p: Presentation) -> String {
        let ids: [UUID] = p.studentIDs.compactMap { UUID(uuidString: $0) }
        let names: [String] = ids.compactMap { studentNameCache[$0] }
        if names.isEmpty { return "0 students" }
        if names.count <= 3 {
            return names.joined(separator: ", ")
        } else {
            return "\(names.count) students"
        }
    }

    var body: some View {
        Group {
            if presentations.isEmpty {
                ContentUnavailableView(
                    "No Presentations Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Present lessons to see them here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedByDay, id: \.day) { entry in
                            Section {
                                ForEach(entry.items, id: \.id) { p in
                                    row(for: p)
                                        .onTapGesture { selectedPresentation = p }
                                }
                            } header: {
                                Text(Self.dayFormatter.string(from: entry.day))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 12)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(item: $selectedPresentation) { p in
            PresentationDetailSheet(presentationID: p.id) {
                selectedPresentation = nil
            }
        }
        .task {
            #if DEBUG
            let t0 = Date()
            #endif
            if !hasBuiltCachesOnce {
                buildCaches()
                hasBuiltCachesOnce = true
            }
            #if DEBUG
            let dt = Date().timeIntervalSince(t0) * 1000
            print("[DEBUG] PresentationHistoryView initial load took \(Int(dt)) ms")
            #endif
        }
        .onChange(of: allPresentationNotes.map(\.id)) { _, _ in
            buildCaches()
        }
        .onChange(of: lessons.map(\.id)) { _, _ in
            buildCaches()
        }
        .onChange(of: students.map(\.id)) { _, _ in
            buildCaches()
        }
    }

    @ViewBuilder
    private func row(for p: Presentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: p))
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    Text(Self.timeFormatter.string(from: p.presentedAt))
                    Text("•")
                    Text(studentNamesOrCount(for: p))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if notesCountCache[p.id.uuidString, default: 0] > 0 {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

#Preview {
    PresentationHistoryView()
}
