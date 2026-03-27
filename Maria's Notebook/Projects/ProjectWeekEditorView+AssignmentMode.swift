import SwiftUI

// MARK: - Assignment Mode Section

extension ProjectWeekEditorView {

    @ViewBuilder
    var assignmentModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $assignmentMode) {
                ForEach(SessionAssignmentMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(assignmentMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if assignmentMode == .choice {
                choiceModeConfiguration
            }
        }
    }

    @ViewBuilder
    var choiceModeConfiguration: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Students pick")
                Stepper("\(minSelections)", value: $minSelections, in: 1...10)
                    .fixedSize()
                Text("of")
                Stepper("\(maxSelections == 0 ? "∞" : "\(maxSelections)")", value: $maxSelections, in: 0...10)
                    .fixedSize()
            }
            .font(.subheadline)

            Divider()

            Text("Offered Works")
                .font(.subheadline).fontWeight(.medium)

            ForEach(Array(offeredWorks.enumerated()), id: \.element.id) { index, _ in
                HStack(alignment: .top) {
                    VStack(spacing: 4) {
                        TextField("Title", text: Binding(
                            get: { offeredWorks[index].title },
                            set: { offeredWorks[index].title = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        TextField("Instructions (optional)", text: Binding(
                            get: { offeredWorks[index].instructions },
                            set: { offeredWorks[index].instructions = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    }
                    Button {
                        offeredWorks.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(AppColors.destructive)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                offeredWorks.append(TemplateOfferedWork())
            } label: {
                Label("Add Work Offer", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)

            if offeredWorks.count < minSelections {
                Text("Add at least \(minSelections) work offers")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
            }
        }
        .padding(.leading, 8)
    }
}
