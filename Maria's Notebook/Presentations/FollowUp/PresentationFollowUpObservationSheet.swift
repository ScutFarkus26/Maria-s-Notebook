import SwiftUI

@MainActor
struct PresentationFollowUpObservationSheet: View {
    let row: CDLessonPresentation
    let studentName: String
    let lessonName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var evidence: Set<PresentationFollowUpEvidence>
    @State private var note: String
    @State private var resolution: PresentationFollowUpResolution?
    @State private var saveErrorMessage: String?

    init(row: CDLessonPresentation, studentName: String, lessonName: String) {
        self.row = row
        self.studentName = studentName
        self.lessonName = lessonName
        _evidence = State(initialValue: row.followUpEvidence)
        _note = State(initialValue: row.followUpNote ?? "")
        _resolution = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    contextHeader
                    evidenceSection
                    noteSection
                    decisionSection
                }
                .padding(20)
            }
            .navigationTitle("Record Observation")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Observation") { save() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 620, idealHeight: 700)
        .presentationSizingFitted()
        #else
        .presentationDetents([.large])
        #endif
        .alert("Couldn’t Save Observation", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "The observation could not be saved.")
        }
    }
}

private extension PresentationFollowUpObservationSheet {
    var contextHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(studentName)
                .font(.title3.weight(.semibold))
            Text(lessonName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Record only what you observed. You can keep following without choosing an outcome.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
    }

    var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What did you observe?")
                .font(.headline)

            ForEach(PresentationFollowUpEvidence.allCases) { item in
                Button {
                    if evidence.contains(item) {
                        evidence.remove(item)
                    } else {
                        evidence.insert(item)
                    }
                } label: {
                    HStack {
                        Image(systemName: evidence.contains(item) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(evidence.contains(item) ? Color.accentColor : .secondary)
                        Text(item.title)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(evidence.contains(item) ? .isSelected : [])
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Brief factual note")
                .font(.headline)
            TextField("What did the child do?", text: $note, axis: .vertical)
                .lineLimit(3...7)
                .textFieldStyle(.roundedBorder)
        }
    }

    var decisionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What comes next?")
                .font(.headline)
            Text("Optional — leave this unselected to keep watching.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(PresentationFollowUpResolution.allCases) { item in
                Button {
                    resolution = resolution == item ? nil : item
                } label: {
                    HStack {
                        Image(systemName: item.systemImage)
                        Text(item.title)
                        Spacer()
                        if resolution == item {
                            Image(systemName: "checkmark")
                        }
                    }
                    .padding(10)
                    .foregroundStyle(resolution == item ? Color.accentColor : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(resolution == item ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.025))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    func save() {
        PresentationFollowUpService.saveObservation(
            evidence: evidence,
            note: note,
            for: row
        )

        switch resolution {
        case .supportOrRepresent:
            PresentationFollowUpService.setAction(.planSupport, for: [row])
        case .readyForNextPresentation:
            PresentationFollowUpService.setAction(.planNextPresentation, for: [row])
        case .continueIndependentWork, .noFurtherFollowUp:
            if let resolution {
                PresentationFollowUpService.resolve(resolution, row: row)
            }
        case nil:
            break
        }

        guard saveCoordinator.save(viewContext, reason: "Saving presentation follow-up observation") else {
            saveErrorMessage = saveCoordinator.lastSaveErrorMessage ?? "The observation could not be saved."
            return
        }
        ToastService.shared.showSuccess("Observation saved")
        dismiss()
    }
}
