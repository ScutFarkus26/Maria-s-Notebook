// RecallCheckSheet.swift
// The iPhone's recall check, from the Class Grid's Recall view (the Mac and iPad
// show the same check beside the queue: RecallCheckForm). For one frontier lesson:
// pick an outcome (still has it / shaky / forgotten), optionally add a note, and
// record it. The lessons this frontier covers are shown for context — they're
// marked retained automatically when the frontier is "still has it".
// (Optional photo capture + per-covered-lesson "check anyway" override are planned follow-ups.)

import SwiftUI

struct RecallCheckSheet: View {
    let entry: RecallQueueEntry
    var studentName: String = ""
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
                        Text([studentName, entry.area, entry.sequence].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let mastered = entry.frontierMasteredAt {
                            Text("Mastered \(mastered.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    HStack(spacing: 8) {
                        ForEach(RecallCheckText.outcomes, id: \.self) { value in
                            outcomeButton(value, RecallCheckText.title(value))
                        }
                    }
                } header: {
                    Text("How did the recall go?")
                } footer: {
                    if let outcome {
                        Text(RecallCheckText.consequence(of: outcome, coversCount: entry.coversCount))
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
        AppPillButton(title, isSelected: outcome == value, metrics: .snug) { outcome = value }
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
