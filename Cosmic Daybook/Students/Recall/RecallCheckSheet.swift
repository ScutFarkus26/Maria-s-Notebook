// RecallCheckSheet.swift
// The tap-through recall check for one frontier lesson: pick an outcome (still has it / shaky /
// forgotten), optionally add a note, and record it. The lessons this frontier covers are shown
// for context — they're marked retained automatically when the frontier is "still has it".
// (Optional photo capture + per-covered-lesson "check anyway" override are planned follow-ups.)

import SwiftUI

struct RecallCheckSheet: View {
    let entry: RecallQueueEntry
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var outcome: RecallOutcome?
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.frontierLessonName).font(.headline)
                        Text("\(entry.area) · \(entry.sequence)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let mastered = entry.frontierMasteredAt {
                            Text("Mastered \(mastered.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("How did the recall go?") {
                    HStack(spacing: 8) {
                        outcomeButton(.retained, "Still has it")
                        outcomeButton(.shaky, "Shaky")
                        outcomeButton(.forgotten, "Forgotten")
                    }
                }

                Section("Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if entry.coversCount > 0 {
                    Section("Covered by this (\(entry.coversCount))") {
                        ForEach(entry.coveredLessons, id: \.lessonID) { covered in
                            Text(covered.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("Marked retained automatically when you record “still has it.”")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle("Recall check")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record") { record() }
                        .disabled(outcome == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func outcomeButton(_ value: RecallOutcome, _ title: String) -> some View {
        CanonicalPillButton(title, isSelected: outcome == value) { outcome = value }
    }

    private func record() {
        guard let outcome else { return }
        let service = RecallService(
            context: viewContext,
            saveCoordinator: saveCoordinator,
            schoolYearStore: dependencies.schoolYearStore
        )
        service.record(entry: entry, outcome: outcome, note: note)
        onComplete()
        dismiss()
    }
}
