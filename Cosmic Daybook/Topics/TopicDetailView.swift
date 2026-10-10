import SwiftUI
import CoreData

/// One community topic, in a sheet on iPhone and iPad (inside a navigation
/// stack, so its Cancel and Save show) and in its own window on the Mac.
/// Field edits are written only by Save; Cancel, a swipe down and the
/// window's close button ask before throwing them away (bug hunt 2026-10-10,
/// P2 #18).
struct TopicDetailView: View, Identifiable {
    let id = UUID()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    let topic: CDCommunityTopicEntity

    @State private var vm: TopicDetailViewModel
    @State private var isConfirmingDiscard = false

    init(topic: CDCommunityTopicEntity) {
        self.topic = topic
        let model = TopicDetailViewModel()
        model.bind(topic: topic)
        self.vm = model
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TopicBasicsSection(title: $vm.title, issue: $vm.issue, broughtBy: $vm.raisedBy)
                CreatedDateSection(createdDate: $vm.createdAt)

                TagsSection(tags: vm.topic?.tags ?? [], tagsDraft: $vm.tagsDraft)

                ResolutionSection(
                    addressed: $vm.addressed,
                    addressedDate: $vm.addressedDate,
                    resolution: $vm.resolution
                )

                ProposedSolutionsSection(
                    solutions: vm.proposedSolutions,
                    newSolutionTitle: $vm.newSolutionTitle,
                    newSolutionDetails: $vm.newSolutionDetails,
                    newSolutionProposedBy: $vm.newSolutionProposedBy,
                    onToggleAdopted: { s in
                        vm.toggleSolutionAdopted(s)
                        saveCoordinator.save(viewContext, reason: "Toggle solution adopted")
                    },
                    onDelete: { s in
                        vm.deleteSolution(context: viewContext, s)
                        saveCoordinator.save(viewContext, reason: "Delete solution")
                    },
                    onAdd: {
                        vm.addPendingSolution(context: viewContext)
                        saveCoordinator.save(viewContext, reason: "Add proposed solution")
                    }
                )

                // Attachments came only from old backups: Add Photo and Add
                // File were never hooked up, so they are gone, and the
                // section shows only when a topic has some.
                if !vm.attachments.isEmpty {
                    AttachmentsSection(
                        attachments: vm.attachments,
                        onDelete: { a in
                            vm.deleteAttachment(context: viewContext, a)
                            saveCoordinator.save(viewContext, reason: "Delete attachment")
                        }
                    )
                }

                TopicMeetingNotesSection(
                    notes: vm.notes,
                    newNoteSpeaker: $vm.newNoteSpeaker,
                    newNoteContent: $vm.newNoteContent,
                    onDelete: { n in
                        vm.deleteNote(context: viewContext, n)
                        saveCoordinator.save(viewContext, reason: "Delete note")
                    },
                    onAdd: {
                        vm.addPendingNote(context: viewContext)
                        saveCoordinator.save(viewContext, reason: "Add note")
                    }
                )
            }
            .padding()
        }
        .navigationTitle("Topic Details")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if vm.hasUnsavedChanges {
                        isConfirmingDiscard = true
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    if let t = vm.topic {
                        ShareLink(item: MarkdownExporter.markdown(for: t)) {
                            Label("Share as Markdown", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .confirmationDialog(
            "Discard your changes to this topic?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        // A swipe down (iPhone, iPad) or the close button (Mac) would drop
        // the edits without asking; with edits waiting, Cancel or Save it is.
        .interactiveDismissDisabled(vm.hasUnsavedChanges)
        #if os(macOS)
        .windowDismissBehavior(vm.hasUnsavedChanges ? .disabled : .automatic)
        #endif
        .saveErrorAlert()
    }

    /// Writes the edits, and any solution or note typed but not added, and
    /// closes. If the save fails, the coordinator's alert says so and the
    /// topic stays open with the edits.
    private func save() {
        guard vm.topic != nil else { return }
        vm.persistChanges(context: viewContext)
        guard saveCoordinator.save(viewContext, reason: "Update community topic") else { return }
        vm.markSaved()
        dismiss()
    }
}

private struct TopicBasicsSection: View {
    @Binding var title: String
    @Binding var issue: String
    @Binding var broughtBy: String

    var body: some View {
        GroupBox("Topic") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Raised by (optional)", text: $broughtBy)
                    .textFieldStyle(.roundedBorder)
                Text("Issue")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $issue).frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                    )
            }
        }
    }
}

private struct CreatedDateSection: View {
    @Binding var createdDate: Date

    var body: some View {
        GroupBox("Created") {
            DatePicker("Created Date", selection: $createdDate, displayedComponents: .date)
        }
    }
}

private struct TagsSection: View {
    let tags: [String]
    @Binding var tagsDraft: String

    var body: some View {
        GroupBox("Tags") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Comma-separated")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("e.g., Safety, Environment, Curriculum", text: $tagsDraft)
                    .textFieldStyle(.roundedBorder)
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .capsuleFill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ResolutionSection: View {
    @Binding var addressed: Bool
    @Binding var addressedDate: Date
    @Binding var resolution: String

    var body: some View {
        GroupBox("Resolution") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Resolved", isOn: $addressed)
                if addressed {
                    DatePicker("Addressed Date", selection: $addressedDate, displayedComponents: .date)
                    TextEditor(text: $resolution).frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                        )
                }
            }
        }
    }
}

private struct ProposedSolutionsSection: View {
    let solutions: [CDProposedSolutionEntity]
    @Binding var newSolutionTitle: String
    @Binding var newSolutionDetails: String
    @Binding var newSolutionProposedBy: String

    var onToggleAdopted: (CDProposedSolutionEntity) -> Void
    var onDelete: (CDProposedSolutionEntity) -> Void
    var onAdd: () -> Void

    var body: some View {
        GroupBox("Proposed Solutions") {
            VStack(alignment: .leading, spacing: 10) {
                if solutions.isEmpty {
                    Text("No solutions yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(solutions) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(s.title.trimmed().isEmpty ? "Untitled" : s.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if s.isAdopted {
                                    Label("Adopted", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption)
                                        .foregroundStyle(AppColors.success)
                                }
                                Spacer()
                                Menu {
                                    let adoptLabel = s.isAdopted ? "Unmark Adopted" : "Mark Adopted"
                                    Button(adoptLabel, systemImage: "checkmark.circle") {
                                        onToggleAdopted(s)
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        onDelete(s)
                                    }
                                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                            }
                            if !s.proposedBy.trimmed().isEmpty {
                                Text("Proposed by: \(s.proposedBy)").font(.caption).foregroundStyle(.secondary)
                            }
                            if !s.details.trimmed().isEmpty {
                                Text(s.details).font(.caption)
                            }
                        }
                        .padding(8)
                        .surface(
                            UIConstants.CornerRadius.medium,
                            fill: Color.primary.opacity(UIConstants.OpacityConstants.trace)
                        )
                    }
                }

                Divider().padding(.vertical, 4)

                TextField("Solution title", text: $newSolutionTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Proposed by (optional)", text: $newSolutionProposedBy)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $newSolutionDetails).frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                            .stroke(Color.primary.opacity(UIConstants.OpacityConstants.medium))
                    )

                HStack {
                    Spacer()
                    Button("Add Solution", action: onAdd)
                        .buttonStyle(.bordered)
                        .disabled(newSolutionTitle.trimmed().isEmpty && newSolutionDetails.trimmed().isEmpty)
                }
            }
        }
    }
}

private struct AttachmentsSection: View {
    let attachments: [CDCommunityAttachment]
    var onDelete: (CDCommunityAttachment) -> Void

    var body: some View {
        GroupBox("Attachments") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(attachments) { a in
                    HStack(spacing: 8) {
                        Image(systemName: a.kind == .photo ? "photo" : "paperclip")
                        Text(a.filename.trimmed().isEmpty ? (a.kind == .photo ? "Photo" : "File") : a.filename)
                            .font(.subheadline)
                        Spacer()
                        Menu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                onDelete(a)
                            }
                        } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                    }
                    .padding(8)
                    .surface(
                        UIConstants.CornerRadius.medium,
                        fill: Color.primary.opacity(UIConstants.OpacityConstants.trace)
                    )
                }
            }
        }
    }
}
