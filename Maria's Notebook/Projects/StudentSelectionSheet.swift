import SwiftUI
import SwiftData

/// Sheet for recording a student's work selections in choice mode
struct StudentSelectionSheet: View {
    let session: ProjectSession
    let studentID: String
    let studentName: String
    let offeredWorks: [WorkModel]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var selectedWorkIDs: Set<UUID> = []

    init(session: ProjectSession, studentID: String, studentName: String, offeredWorks: [WorkModel]) {
        self.session = session
        self.studentID = studentID
        self.studentName = studentName
        self.offeredWorks = offeredWorks

        // Initialize with current selections
        let currentSelections = offeredWorks.filter { work in
            (work.participants ?? []).contains { $0.studentID == studentID }
        }.map(\.id)
        _selectedWorkIDs = State(initialValue: Set(currentSelections))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Select Work for \(studentName)")
                    .font(.title3).fontWeight(.semibold)

                selectionProgressView
            }

            Divider()

            // Work selection list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(offeredWorks) { work in
                        workSelectionRow(work)
                    }
                }
            }

            Divider()

            // Action buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { saveSelections() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        .presentationSizingFitted()
    #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
    }

    // MARK: - Selection Progress

    @ViewBuilder
    private var selectionProgressView: some View {
        let count = selectedWorkIDs.count
        let min = session.minSelections
        let max = session.maxSelections

        HStack(spacing: 8) {
            if min > 0 && count < min {
                Label("Select at least \(min)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
            } else if max > 0 && count >= max {
                Label("\(count) selected (max reached)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.success)
            } else {
                let maxText = max > 0 ? " (max \(max))" : ""
                Label("\(count) selected\(maxText)", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Work Row

    @ViewBuilder
    private func workSelectionRow(_ work: WorkModel) -> some View {
        let isSelected = selectedWorkIDs.contains(work.id)
        let canToggle = isSelected || canSelectMore

        Button {
            if canToggle {
                toggleSelection(work)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.blue : (canToggle ? Color.secondary : Color.gray.opacity(0.3)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(work.title.isEmpty ? "Untitled" : work.title)
                        .font(.headline)
                        .foregroundStyle(canToggle ? .primary : .secondary)

                    if !work.latestUnifiedNoteText.isEmpty {
                        Text(work.latestUnifiedNoteText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let due = work.dueAt {
                        Label {
                            Text(due, format: Date.FormatStyle().month().day())
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(UIConstants.OpacityConstants.light) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
    }

    // MARK: - Logic

    private var canSelectMore: Bool {
        session.maxSelections == 0 || selectedWorkIDs.count < session.maxSelections
    }

    private var isValid: Bool {
        selectedWorkIDs.count >= session.minSelections
    }

    private func toggleSelection(_ work: WorkModel) {
        if selectedWorkIDs.contains(work.id) {
            selectedWorkIDs.remove(work.id)
        } else if canSelectMore {
            selectedWorkIDs.insert(work.id)
        }
    }

    private func saveSelections() {
        let service = SessionWorkAssignmentService(context: modelContext)
        guard let studentUUID = UUID(uuidString: studentID) else { return }

        // Determine what changed
        let currentSelections = Set(offeredWorks.filter { work in
            (work.participants ?? []).contains { $0.studentID == studentID }
        }.map(\.id))

        let toAdd = selectedWorkIDs.subtracting(currentSelections)
        let toRemove = currentSelections.subtracting(selectedWorkIDs)

        // Add new selections
        for workID in toAdd {
            if let work = offeredWorks.first(where: { $0.id == workID }) {
                service.recordSelection(work: work, studentID: studentUUID)
            }
        }

        // Remove deselected
        for workID in toRemove {
            if let work = offeredWorks.first(where: { $0.id == workID }) {
                service.removeSelection(work: work, studentID: studentUUID)
            }
        }

        saveCoordinator.save(modelContext, reason: "Update Student Selections")
        dismiss()
    }
}
