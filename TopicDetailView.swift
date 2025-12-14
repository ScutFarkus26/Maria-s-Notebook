import SwiftUI
import SwiftData

struct TopicDetailView: View, Identifiable {
    let id = UUID()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    var topic: CommunityTopic
    var onSave: (CommunityTopic) -> Void

    @State private var title: String = ""
    @State private var issue: String = ""
    @State private var resolution: String = ""
    @State private var addressed: Bool = false
    @State private var addressedDate: Date = Date()
    @State private var createdDate: Date = Date()

    @State private var newSolutionTitle: String = ""
    @State private var newSolutionDetails: String = ""
    @State private var newSolutionProposedBy: String = ""

    @State private var newNoteSpeaker: String = ""
    @State private var newNoteContent: String = ""

    @State private var tagsDraft: String = ""
    @State private var broughtBy: String = ""
    @State private var showingImagePicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TopicBasicsSection(title: $title, issue: $issue, broughtBy: $broughtBy)
                CreatedDateSection(createdDate: $createdDate)
                
                TagsSection(topic: topic, tagsDraft: $tagsDraft)

                ResolutionSection(addressed: $addressed, addressedDate: $addressedDate, resolution: $resolution)

                ProposedSolutionsSection(topic: topic, newSolutionTitle: $newSolutionTitle, newSolutionDetails: $newSolutionDetails, newSolutionProposedBy: $newSolutionProposedBy)

                AttachmentsSection(topic: topic, showingImagePicker: $showingImagePicker)

                MeetingNotesSection(topic: topic, newNoteSpeaker: $newNoteSpeaker, newNoteContent: $newNoteContent)
            }
            .padding()
        }
        .navigationTitle("Topic Details")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        shareMarkdown()
                    } label: {
                        Label("Share as Markdown", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            title = topic.title
            issue = topic.issueDescription
            broughtBy = topic.raisedBy
            resolution = topic.resolution
            createdDate = topic.createdAt
            addressed = topic.isResolved
            addressedDate = topic.addressedDate ?? Date()
            tagsDraft = topic.tags.joined(separator: ", ")
        }
    }

    private func updateTags() {
        let tags = tagsDraft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        topic.tags = tags
    }

    private func save() {
        updateTags()
        topic.title = title
        topic.issueDescription = issue
        topic.raisedBy = broughtBy
        topic.resolution = resolution
        topic.createdAt = createdDate
        topic.addressedDate = addressed ? addressedDate : nil
        onSave(topic)
        dismiss()
    }

    private func addNote() {
        let speakerTrimmed = newNoteSpeaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentTrimmed = newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speakerTrimmed.isEmpty && !contentTrimmed.isEmpty else { return }
        let note = MeetingNote(speaker: speakerTrimmed, content: contentTrimmed)
        modelContext.insert(note)
        topic.notes.append(note)
        _ = saveCoordinator.save(modelContext, reason: "Add note")
        newNoteSpeaker = ""
        newNoteContent = ""
    }

    private func deleteNote(_ note: MeetingNote) {
        if let index = topic.notes.firstIndex(where: { $0.id == note.id }) {
            topic.notes.remove(at: index)
            modelContext.delete(note)
            _ = saveCoordinator.save(modelContext, reason: "Delete note")
        }
    }

    private func shareMarkdown() {
        let markdown = MarkdownExporter.markdown(for: topic)
        MarkdownExporter.presentShare(markdown)
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
    var topic: CommunityTopic
    @Binding var tagsDraft: String

    var body: some View {
        GroupBox("Tags") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Comma-separated")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("e.g., Safety, Environment, Curriculum", text: $tagsDraft)
                    .textFieldStyle(.roundedBorder)
                if !topic.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(topic.tags, id: \.self) { tag in
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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    var topic: CommunityTopic
    @Binding var newSolutionTitle: String
    @Binding var newSolutionDetails: String
    @Binding var newSolutionProposedBy: String

    var body: some View {
        GroupBox("Proposed Solutions") {
            VStack(alignment: .leading, spacing: 10) {
                if topic.proposedSolutions.isEmpty {
                    Text("No solutions yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(topic.proposedSolutions) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(s.title.isEmpty ? "Untitled" : s.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if s.isAdopted { Label("Adopted", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.green) }
                                Spacer()
                                Menu {
                                    Button(s.isAdopted ? "Unmark Adopted" : "Mark Adopted", systemImage: "checkmark.circle") {
                                        s.isAdopted.toggle()
                                        _ = saveCoordinator.save(modelContext, reason: "Toggle solution adopted")
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        modelContext.delete(s)
                                        _ = saveCoordinator.save(modelContext, reason: "Delete solution")
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
                    Button("Add Solution") {
                        let s = ProposedSolution(title: newSolutionTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 details: newSolutionDetails.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 proposedBy: newSolutionProposedBy.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 topic: topic)
                        topic.proposedSolutions.append(s)
                        _ = saveCoordinator.save(modelContext, reason: "Add proposed solution")
                        newSolutionTitle = ""; newSolutionDetails = ""; newSolutionProposedBy = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(newSolutionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && newSolutionDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct AttachmentsSection: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    var topic: CommunityTopic
    @Binding var showingImagePicker: Bool

    var body: some View {
        GroupBox("Attachments") {
            VStack(alignment: .leading, spacing: 10) {
                if topic.attachments.isEmpty {
                    Text("No attachments yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(topic.attachments) { a in
                        HStack(spacing: 8) {
                            Image(systemName: a.kind == .photo ? "photo" : "paperclip")
                            Text(a.filename.isEmpty ? (a.kind == .photo ? "Photo" : "File") : a.filename)
                                .font(.subheadline)
                            Spacer()
                            Menu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    modelContext.delete(a)
                                    _ = saveCoordinator.save(modelContext, reason: "Delete attachment")
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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    var topic: CommunityTopic
    @Binding var newNoteSpeaker: String
    @Binding var newNoteContent: String

    var body: some View {
        GroupBox("Meeting Notes") {
            VStack(alignment: .leading, spacing: 10) {
                if topic.notes.isEmpty {
                    Text("No notes yet.").foregroundStyle(.secondary)
                } else {
                    let sortedNotes: [MeetingNote] = topic.notes.sorted { $0.createdAt < $1.createdAt }
                    ForEach(sortedNotes) { n in
                        HStack(alignment: .top, spacing: 8) {
                            if !n.speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(n.speaker).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                            }
                            Text(n.content).font(.subheadline)
                            Spacer()
                            Menu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    modelContext.delete(n)
                                    _ = saveCoordinator.save(modelContext, reason: "Delete note")
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
                    Button("Add Note") {
                        let n = MeetingNote(speaker: newNoteSpeaker.trimmingCharacters(in: .whitespacesAndNewlines),
                                            content: newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines),
                                            topic: topic)
                        topic.notes.append(n)
                        _ = saveCoordinator.save(modelContext, reason: "Add note")
                        newNoteSpeaker = ""; newNoteContent = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(newNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

