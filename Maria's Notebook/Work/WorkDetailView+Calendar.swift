import SwiftUI
import CoreData
import Foundation

// MARK: - Calendar & Scheduling

extension WorkDetailView {

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func calendarSection() -> some View {
        DetailSectionCard(title: "Scheduled Check-Ins", icon: "calendar.badge.checkmark", accentColor: .blue) {
            VStack(alignment: .leading, spacing: 16) {
                // Display existing check-ins
                if !checkIns.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(checkIns.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) { item in
                            checkInRow(item)
                        }
                    }
                    .padding(.bottom, 8)
                }

                Divider()

                // Add new check-in section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Schedule New Check-In")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        DatePicker("", selection: $viewModel.newPlanDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)

                        Menu {
                            // Phase 6: Simple string-based purposes
                            Button {
                                viewModel.newPlanPurpose = "progressCheck"
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle")
                                    Text("Progress Check")
                                }
                            }
                            Button {
                                viewModel.newPlanPurpose = "assessment"
                            } label: {
                                HStack {
                                    Image(systemName: "chart.bar")
                                    Text("Assessment")
                                }
                            }
                            Button {
                                viewModel.newPlanPurpose = "dueDate"
                            } label: {
                                HStack {
                                    Image(systemName: "calendar.badge.exclamationmark")
                                    Text("Due Date")
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 12, weight: .medium))
                                Text(viewModel.newPlanPurpose.isEmpty ? "Progress Check" : viewModel.newPlanPurpose)
                                    .font(AppTheme.ScaledFont.captionSemibold)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                addPlan()
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.blue)
                        }
                        .accessibilityLabel("Add plan")
                        .buttonStyle(.plain)
                    }

                    // Optional note field
                    TextField("Add a note (optional)", text: $viewModel.newPlanNote)
                        .font(AppTheme.ScaledFont.caption)
                        .padding(AppTheme.Spacing.small)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                        )
                }
            }
        }
    }

    @ViewBuilder
    func checkInRow(_ item: WorkCheckIn) -> some View {
        WorkCheckInRow(
            checkIn: item,
            onEditNote: { _ in
                // TODO: Implement note editing for check-ins
            },
            onSetStatus: { id, status in
                // Update the check-in status
                if let checkIn = checkIns.first(where: { $0.id != nil && $0.id == id }) {
                    checkIn.status = status
                    saveCoordinator.save(modelContext, reason: "Update check-in status")
                }
            },
            onDelete: { deleteCheckIn($0) }
        )
    }

    func addPlan() {
        guard let work = viewModel.work else { return }
        let note = viewModel.newPlanNote.trimmed().isEmpty ? nil : viewModel.newPlanNote.trimmed()

        // PHASE 6: Create WorkCheckIn only (WorkPlanItem removed)
        let checkIn = CDWorkCheckIn(context: modelContext)
        checkIn.workID = work.id?.uuidString ?? ""
        checkIn.date = viewModel.newPlanDate
        checkIn.status = .scheduled
        checkIn.purpose = viewModel.newPlanPurpose
        if let note {
            checkIn.setLegacyNoteText(note, in: modelContext)
        }

        saveCoordinator.save(modelContext, reason: "Adding check-in")

        // Reset form fields
        viewModel.newPlanDate = Date()
        viewModel.newPlanPurpose = "progressCheck"
        viewModel.newPlanNote = ""
    }

    func deleteCheckIn(_ item: WorkCheckIn) {
        modelContext.delete(item)
        saveCoordinator.save(modelContext, reason: "Deleting check-in")
    }
}
