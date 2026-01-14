import SwiftUI
import SwiftData

struct TopicDetailView: View, Identifiable {
    let id = UUID()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    let topicID: UUID
    var onSave: (CommunityTopic) -> Void

    @StateObject private var vm = TopicDetailViewModel()

    // Ephemeral input state for adding content
    @State private var newSolutionTitle: String = ""
    @State private var newSolutionDetails: String = ""
    @State private var newSolutionProposedBy: String = ""

    @State private var newNoteSpeaker: String = ""
    @State private var newNoteContent: String = ""

    @State private var showingImagePicker = false

    var body: some View {
        ScrollView {
            if vm.isLoading || vm.topic == nil {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading topic…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(spacing: 20) {
                    TopicBasicsSection(title: $vm.title, issue: $vm.issue, broughtBy: $vm.raisedBy)
                    CreatedDateSection(createdDate: $vm.createdAt)

                    TagsSection(tags: vm.topic?.tags ?? [], tagsDraft: $vm.tagsDraft)

                    ResolutionSection(addressed: $vm.addressed, addressedDate: $vm.addressedDate, resolution: $vm.resolution)

                    ProposedSolutionsSection(
                        solutions: vm.proposedSolutions,
                        newSolutionTitle: $newSolutionTitle,
                        newSolutionDetails: $newSolutionDetails,
                        newSolutionProposedBy: $newSolutionProposedBy,
                        onToggleAdopted: { s in
                            vm.toggleSolutionAdopted(s)
                            _ = saveCoordinator.save(modelContext, reason: "Toggle solution adopted")
                        },
                        onDelete: { s in
                            vm.deleteSolution(context: modelContext, s)
                            _ = saveCoordinator.save(modelContext, reason: "Delete solution")
                        },
                        onAdd: {
                            let title = newSolutionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            let details = newSolutionDetails.trimmingCharacters(in: .whitespacesAndNewlines)
                            let proposedBy = newSolutionProposedBy.trimmingCharacters(in: .whitespacesAndNewlines)
                            vm.addSolution(context: modelContext, title: title, details: details, proposedBy: proposedBy)
                            _ = saveCoordinator.save(modelContext, reason: "Add proposed solution")
                            newSolutionTitle = ""; newSolutionDetails = ""; newSolutionProposedBy = ""
                        }
                    )

                    AttachmentsSection(
                        attachments: vm.attachments,
                        showingImagePicker: $showingImagePicker,
                        onDelete: { a in
                            vm.deleteAttachment(context: modelContext, a)
                            _ = saveCoordinator.save(modelContext, reason: "Delete attachment")
                        }
                    )

                    MeetingNotesSection(
                        notes: vm.notes,
                        newNoteSpeaker: $newNoteSpeaker,
                        newNoteContent: $newNoteContent,
                        onDelete: { n in
                            vm.deleteNote(context: modelContext, n)
                            _ = saveCoordinator.save(modelContext, reason: "Delete note")
                        },
                        onAdd: {
                            let speaker = newNoteSpeaker.trimmingCharacters(in: .whitespacesAndNewlines)
                            let content = newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !content.isEmpty else { return }
                            vm.addNote(context: modelContext, speaker: speaker, content: content)
                            _ = saveCoordinator.save(modelContext, reason: "Add note")
                            newNoteSpeaker = ""; newNoteContent = ""
                        }
                    )
                }
                .padding()
            }
        }
        .navigationTitle("Topic Details")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let t = vm.topic else { return }
                    vm.persistChanges(context: modelContext)
                    onSave(t)
                    dismiss()
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        if let t = vm.topic {
                            let markdown = MarkdownExporter.markdown(for: t)
                            MarkdownExporter.presentShare(markdown)
                        }
                    } label: {
                        Label("Share as Markdown", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .task(id: topicID) {
            #if DEBUG
            if let start = DebugTiming.lastTopicTapAt {
                let ms = Date().timeIntervalSince(start) * 1000.0
                print("[DEBUG] First frame after tap: \(String(format: "%.1f", ms)) ms")
            }
            #endif
            await vm.load(context: modelContext, topicID: topicID)
        }
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
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
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
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
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
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                }
            }
        }
    }
}

private struct ProposedSolutionsSection: View {
    let solutions: [ProposedSolution]
    @Binding var newSolutionTitle: String
    @Binding var newSolutionDetails: String
    @Binding var newSolutionProposedBy: String

    var onToggleAdopted: (ProposedSolution) -> Void
    var onDelete: (ProposedSolution) -> Void
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
                                Text(s.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : s.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if s.isAdopted { Label("Adopted", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.green) }
                                Spacer()
                                Menu {
                                    Button(s.isAdopted ? "Unmark Adopted" : "Mark Adopted", systemImage: "checkmark.circle") {
                                        onToggleAdopted(s)
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        onDelete(s)
                                    }
                                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                            }
                            if !s.proposedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Proposed by: \(s.proposedBy)").font(.caption).foregroundStyle(.secondary)
                            }
                            if !s.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(s.details).font(.caption)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }
                }

                Divider().padding(.vertical, 4)

                TextField("Solution title", text: $newSolutionTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Proposed by (optional)", text: $newSolutionProposedBy)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $newSolutionDetails).frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))

                HStack {
                    Spacer()
                    Button("Add Solution", action: onAdd)
                        .buttonStyle(.bordered)
                        .disabled(newSolutionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && newSolutionDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct AttachmentsSection: View {
    let attachments: [CommunityAttachment]
    @Binding var showingImagePicker: Bool
    var onDelete: (CommunityAttachment) -> Void

    var body: some View {
        GroupBox("Attachments") {
            VStack(alignment: .leading, spacing: 10) {
                if attachments.isEmpty {
                    Text("No attachments yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(attachments) { a in
                        HStack(spacing: 8) {
                            Image(systemName: a.kind == .photo ? "photo" : "paperclip")
                            Text(a.filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (a.kind == .photo ? "Photo" : "File") : a.filename)
                                .font(.subheadline)
                            Spacer()
                            Menu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    onDelete(a)
                                }
                            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        showingImagePicker = true
                    } label: { Label("Add Photo", systemImage: "photo.on.rectangle") }
                    .buttonStyle(.bordered)

                    Button {
                        // Placeholder for document picker integration
                    } label: { Label("Add File", systemImage: "paperclip") }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct MeetingNotesSection: View {
    let notes: [Note]
    @Binding var newNoteSpeaker: String
    @Binding var newNoteContent: String

    var onDelete: (Note) -> Void
    var onAdd: () -> Void

    var body: some View {
        GroupBox("Meeting Notes") {
            VStack(alignment: .leading, spacing: 10) {
                if notes.isEmpty {
                    Text("No notes yet.").foregroundStyle(.secondary)
                } else {
                    let sortedNotes: [Note] = notes.sorted { $0.createdAt < $1.createdAt }
                    ForEach(sortedNotes) { n in
                        HStack(alignment: .top, spacing: 8) {
                            if let reporterName = n.reporterName, !reporterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(reporterName).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                            }
                            Text(n.body).font(.subheadline)
                            Spacer()
                            Menu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    onDelete(n)
                                }
                            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }
                }

                Divider().padding(.vertical, 4)

                TextField("Speaker (optional)", text: $newNoteSpeaker)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $newNoteContent).frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))

                HStack {
                    Spacer()
                    Button("Add Note", action: onAdd)
                        .buttonStyle(.bordered)
                        .disabled(newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

