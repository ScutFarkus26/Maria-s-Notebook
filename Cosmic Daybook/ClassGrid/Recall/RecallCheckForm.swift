// RecallCheckForm.swift
// The recall check beside the Recall view's queue on the Mac and iPad: the
// lesson, the child, when it was mastered, the three outcomes with what each
// one does, an optional note, the lessons it also covers, and Skip / Record.
// The iPhone opens the same check as a sheet (RecallCheckSheet). Both record
// through RecallService, which never changes the mastery mark.

import SwiftUI

struct RecallCheckForm: View {
    let entry: RecallQueueEntry
    let studentName: String
    let onRecorded: () -> Void
    let onSkip: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var outcome: RecallOutcome?
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RECALL CHECK")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            heading
            outcomes
            Text(outcome.map { RecallCheckText.consequence(of: $0, coversCount: entry.coversCount) }
                 ?? "Pick how the recall went.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 5) {
                Text("Note (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("What you saw", text: $note, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(.roundedBorder)
            }
            if entry.coversCount > 0 {
                covers
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Spacer()
                Button("Skip", action: onSkip)
                    .buttonStyle(.bordered)
                    .help("Leave this one for now and go to the next")
                Button("Record", action: record)
                    .buttonStyle(.borderedProminent)
                    .disabled(outcome == nil)
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.frontierLessonName)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text([studentName, entry.area, entry.sequence].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let mastered = entry.frontierMasteredAt {
                Text("Mastered \(ChecklistCellCardText.shortDate(mastered))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outcomes: some View {
        HStack(spacing: 8) {
            ForEach(RecallCheckText.outcomes, id: \.self) { value in
                AppPillButton(RecallCheckText.title(value), isSelected: outcome == value, metrics: .snug) {
                    outcome = value
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How did the recall go?")
    }

    private var covers: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Also covers")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(entry.coveredLessons, id: \.lessonID) { covered in
                HStack(spacing: 8) {
                    ChecklistMark(status: .mastered, size: 11)
                    Text(covered.name)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
        }
    }

    private func record() {
        guard let outcome else { return }
        RecallService(
            context: viewContext, saveCoordinator: saveCoordinator, schoolYearStore: dependencies.schoolYearStore
        )
        .record(entry: entry, outcome: outcome, note: note)
        onRecorded()
    }
}

/// The words both recall checks use: the outcomes and what each one does.
enum RecallCheckText {
    static let outcomes: [RecallOutcome] = [.retained, .shaky, .forgotten]

    static func title(_ outcome: RecallOutcome) -> String {
        switch outcome {
        case .retained: "Still has it"
        case .shaky: "Shaky"
        case .forgotten: "Forgotten"
        }
    }

    /// What recording `outcome` does (`RecallService.record`), in plain words.
    static func consequence(of outcome: RecallOutcome, coversCount: Int) -> String {
        switch outcome {
        case .retained:
            let covers: String
            switch coversCount {
            case 0: covers = ""
            case 1: covers = ", and marks the 1 lesson it covers as kept"
            default: covers = ", and marks the \(coversCount) lessons it covers as kept"
            }
            return "Updates when mastery was last seen\(covers). Mastery isn't changed."
        case .shaky:
            return "Adds a follow-up: more practice on this lesson. Mastery isn't changed."
        case .forgotten:
            return "Adds a follow-up: present it again. Mastery isn't changed."
        }
    }
}
