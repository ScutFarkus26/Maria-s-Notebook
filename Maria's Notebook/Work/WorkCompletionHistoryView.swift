import SwiftUI
import SwiftData

/// A reusable list view that displays completion history for a given work.
/// Optionally filter by a specific student.
struct WorkCompletionHistoryView: View {
    let workID: UUID
    var studentID: UUID? = nil

    @Environment(\.modelContext) private var modelContext

    @State private var records: [WorkCompletionRecord] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if records.isEmpty {
                ContentUnavailableView(
                    "No Completions Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("When students complete this work, entries will appear here.")
                )
            } else {
                List {
                    ForEach(records) { record in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(record.completedAt.formatted(date: .abbreviated, time: .omitted)) • \(record.completedAt.formatted(date: .omitted, time: .shortened))")
                                if !record.note.trimmed().isEmpty {
                                    Text(record.note)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Completed on \(record.completedAt.formatted(date: .numeric, time: .shortened))")
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(record: record)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.inset)
            }
        }
        .task(id: workID.uuidString + (studentID?.uuidString ?? "all")) {
            await reload()
        }
        .navigationTitle("Completion History")
        .toolbar {
            #if os(iOS)
            EditButton()
            #endif
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Prefer using the service if available.
            if let serviceRecords = try? WorkCompletionService.records(for: workID, studentID: studentID, in: modelContext) {
                self.records = serviceRecords
                return
            }
            // Fallback direct fetch.
            // CloudKit compatibility: Convert UUIDs to strings for comparison
            let workIDString = workID.uuidString
            let predicate: Predicate<WorkCompletionRecord>
            if let studentID {
                let studentIDString = studentID.uuidString
                predicate = #Predicate { $0.workID == workIDString && $0.studentID == studentIDString }
            } else {
                predicate = #Predicate { $0.workID == workIDString }
            }
            let descriptor = FetchDescriptor<WorkCompletionRecord>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
            )
            self.records = modelContext.safeFetch(descriptor)
        }
    }

    private func delete(at offsets: IndexSet) {
        let recordsToDelete = offsets.map { records[$0] }
        deleteRecords(recordsToDelete)
    }

    private func delete(record: WorkCompletionRecord) {
        deleteRecords([record])
    }

    private func deleteRecords(_ recordsToDelete: [WorkCompletionRecord]) {
        for record in recordsToDelete {
            modelContext.delete(record)
        }
        do {
            try modelContext.save()
            let idsToRemove = Set(recordsToDelete.map { $0.id })
            records.removeAll { idsToRemove.contains($0.id) }
        } catch {
            Task { await reload() }
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        WorkCompletionHistoryView(workID: UUID())
    }
}

#Preview("With Sample Data") {
    struct PreviewHost: View {
        @Environment(\.modelContext) private var modelContext
        @State private var workID = UUID()
        @State private var studentA = UUID()
        @State private var studentB = UUID()

        var body: some View {
            NavigationStack {
                WorkCompletionHistoryView(workID: workID)
                    .task {
                        // Seed some sample records in memory
                        let now = Date()
                        let items: [WorkCompletionRecord] = [
                            WorkCompletionRecord(workID: workID, studentID: studentA, completedAt: now.addingTimeInterval(-3600), note: "First try"),
                            WorkCompletionRecord(workID: workID, studentID: studentB, completedAt: now.addingTimeInterval(-1800), note: "Assisted"),
                            WorkCompletionRecord(workID: workID, studentID: studentA, completedAt: now.addingTimeInterval(-600), note: "Independent")
                        ]
                        items.forEach { modelContext.insert($0) }
                        try? modelContext.save()
                    }
            }
        }
    }

    return PreviewContainer(PreviewHost())
}

/// A lightweight in-memory container for previews.
/// Note: This preview only uses WorkCompletionRecord; ScopedNote is not required here.
private struct PreviewContainer<Content: View>: View {
    private let content: Content
    init(_ content: Content) { self.content = content }

    var body: some View {
        content
            .modelContainer(ModelContainer.previewContainer(for: Schema([WorkCompletionRecord.self])))
    }
}
