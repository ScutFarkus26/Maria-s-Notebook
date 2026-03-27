import SwiftUI

// MARK: - Work Draft Card Views

extension UnifiedPresentationWorkflowPanel {

    @ViewBuilder
    func workDraftCard(draft: WorkItemDraft, studentID: UUID) -> some View {
        WorkflowCard {
            VStack(alignment: .leading, spacing: 14) {
                WorkflowTextField(
                    label: "Title",
                    text: draftBinding(for: draft, studentID: studentID, keyPath: \.title),
                    placeholder: "Work Title"
                )

                workDraftKindSection(draft: draft, studentID: studentID)
                workDraftStatusSection(draft: draft, studentID: studentID)

                WorkDatesRow(
                    checkInDate: draftBinding(for: draft, studentID: studentID, keyPath: \.checkInDate),
                    dueDate: draftBinding(for: draft, studentID: studentID, keyPath: \.dueDate),
                    defaultCheckInDate: presentationViewModel.defaultCheckInDate,
                    defaultDueDate: presentationViewModel.defaultDueDate
                )

                WorkflowTextField(
                    label: "Notes",
                    text: draftBinding(for: draft, studentID: studentID, keyPath: \.notes),
                    placeholder: "Add notes...",
                    axis: .vertical,
                    lineLimit: 2...
                )

                if draft.status == .complete {
                    workDraftCompletionSection(draft: draft, studentID: studentID)
                }

                HStack {
                    WorkflowInfoHint(text: "Full editor available after saving")
                    Spacer()
                    WorkflowDeleteButton {
                        removeWorkDraft(studentID: studentID, draftID: draft.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func workDraftKindSection(draft: WorkItemDraft, studentID: UUID) -> some View {
        LabeledFieldSection(label: "Type") {
            HStack(spacing: 8) {
                PillButtonGroup(
                    items: WorkKind.allCases,
                    selection: draft.kind,
                    color: { $0.color },
                    icon: { $0.iconName },
                    label: { $0.shortLabel },
                    isSelected: { $0 == draft.kind },
                    onSelect: { kind in
                        updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.kind = kind }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func workDraftStatusSection(draft: WorkItemDraft, studentID: UUID) -> some View {
        LabeledFieldSection(label: "Status") {
            HStack(spacing: 8) {
                PillButtonGroup(
                    items: WorkStatus.allCases,
                    selection: draft.status,
                    color: { $0.color },
                    icon: { $0.iconName },
                    label: { $0.displayName },
                    isSelected: { $0 == draft.status },
                    onSelect: { status in
                        updateWorkDraft(studentID: studentID, draftID: draft.id) { $0.status = status }
                    }
                )
                Spacer()
            }
        }
    }

    // MARK: - Completion Details Section

    @ViewBuilder
    func workDraftCompletionSection(draft: WorkItemDraft, studentID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ExpandableSectionButton(
                title: "Completion Details",
                isExpanded: draft.showMoreDetails,
                action: {
                    adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                        updateWorkDraft(studentID: studentID, draftID: draft.id) {
                            $0.showMoreDetails.toggle()
                        }
                    }
                }
            )

            if draft.showMoreDetails {
                VStack(alignment: .leading, spacing: 12) {
                    // Outcome picker
                    LabeledFieldSection(label: "Outcome") {
                        FlowLayout(spacing: 8) {
                            PillButtonGroup(
                                items: CompletionOutcome.allCases,
                                selection: draft.completionOutcome,
                                color: { $0.color },
                                icon: { $0.iconName },
                                label: { $0.displayName },
                                isSelected: { $0 == draft.completionOutcome },
                                onSelect: { outcome in
                                    updateWorkDraft(studentID: studentID, draftID: draft.id) {
                                        $0.completionOutcome = outcome
                                    }
                                }
                            )
                        }
                    }

                    // Completion note
                    WorkflowTextField(
                        label: "Completion Note",
                        text: draftBinding(for: draft, studentID: studentID, keyPath: \.completionNote),
                        placeholder: "Add completion note...",
                        axis: .vertical,
                        lineLimit: 2...
                    )
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .cardBackground(color: Color.green.opacity(0.08), cornerRadius: 10)
    }
}
