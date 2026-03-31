import OSLog
import SwiftUI
import CoreData

/// A reusable list view that displays completion history for a given work.
/// Optionally filter by a specific student.
struct WorkCompletionHistoryView: View {
    private static let logger = Logger.work

    let workID: UUID
    var studentID: UUID?

    @Environment(\.managedObjectContext) private var modelContext

    @State private var records: [WorkCompletionRecord] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(AppColors.warning)
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
                                .foregroundStyle(AppColors.success)
                            VStack(alignment: .leading, spacing: 4) {
                                let completedDate = record.completedAt ?? Date()
                                let dateStr = completedDate.formatted(
                                    date: .abbreviated, time: .omitted
                                )
                                let timeStr = completedDate.formatted(
                                    date: .omitted, time: .shortened
                                )
                                Text("\(dateStr) • \(timeStr)")
                                let noteText = record.latestUnifiedNoteText.trimmed()
                                if !noteText.isEmpty {
                                    Text(noteText)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "Completed on \((record.completedAt ?? Date()).formatted(date: .numeric, time: .shortened))"
                        )
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

        let request = CDFetchRequest(CDWorkCompletionRecord.self)
        let workIDString = workID.uuidString
        if let studentID {
            let studentIDString = studentID.uuidString
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "workID == %@", workIDString),
                NSPredicate(format: "studentID == %@", studentIDString)
            ])
        } else {
            request.predicate = NSPredicate(format: "workID == %@", workIDString)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "completedAt", ascending: false)]

        do {
            self.records = try modelContext.fetch(request)
        } catch {
            Self.logger.warning("Failed to fetch WorkCompletionRecord: \(error)")
            self.records = []
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
            let idsToRemove = Set(recordsToDelete.compactMap(\.id))
            records.removeAll { guard let id = $0.id else { return false }; return idsToRemove.contains(id) }
        } catch {
            Task { await reload() }
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        WorkCompletionHistoryView(workID: UUID())
    }
    .previewEnvironment()
}
