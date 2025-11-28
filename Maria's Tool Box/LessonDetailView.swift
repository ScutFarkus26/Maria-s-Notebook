import SwiftUI
import SwiftData

struct LessonDetailView: View {
    var lesson: Lesson
    var onSave: (Lesson) -> Void
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isEditing = false
    @State private var draftName: String = ""
    @State private var draftSubject: String = ""
    @State private var draftGroup: String = ""
    @State private var draftSubheading: String = ""
    @State private var draftWriteUp: String = ""
    @State private var showDeleteAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Lesson Info")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Divider()
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 28) {
                    headerContent
                        .padding(.top, 36)

                    if isEditing {
                        editForm
                    } else {
                        infoSection
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .alert("Delete Lesson?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(lesson)
                if let onDone { onDone() } else { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear(perform: seedDrafts)
    }

    // MARK: - Subviews
    private var headerContent: some View {
        VStack(spacing: 12) {
            Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                .font(.system(size: AppTheme.FontSize.titleXLarge, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                if !lesson.subject.isEmpty {
                    Text(lesson.subject)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                if !lesson.group.isEmpty {
                    Text(lesson.group)
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoRow(icon: "text.book.closed", title: "Name", value: lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
            infoRow(icon: "graduationcap", title: "Subject", value: lesson.subject.isEmpty ? "—" : lesson.subject)
            infoRow(icon: "square.grid.2x2", title: "Group", value: lesson.group.isEmpty ? "—" : lesson.group)
            infoRow(icon: "text.bubble", title: "Subheading", value: lesson.subheading.isEmpty ? "—" : lesson.subheading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.plaintext")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Write Up")
                        .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if lesson.writeUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No write up yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(lesson.writeUp)
                        .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 8)
    }

    private var editForm: some View {
        VStack(spacing: 14) {
            TextField("Lesson Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Subject", text: $draftSubject)
                    .textFieldStyle(.roundedBorder)
                TextField("Group", text: $draftGroup)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("Subheading", text: $draftSubheading)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text("Write Up")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftWriteUp)
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
            }
        }
        .padding(.horizontal, 8)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                if isEditing {
                    Button("Cancel") { isEditing = false }
                    Button("Save") {
                        let updated = lesson
                        updated.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.subject = draftSubject.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.group = draftGroup.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.subheading = draftSubheading.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.writeUp = draftWriteUp
                        onSave(updated)
                        isEditing = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Edit") {
                        seedDrafts()
                        isEditing = true
                    }
                    Button("Delete", role: .destructive) {
                        showDeleteAlert = true
                    }
                    Button("Done") {
                        if let onDone { onDone() } else { dismiss() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func seedDrafts() {
        draftName = lesson.name
        draftSubject = lesson.subject
        draftGroup = lesson.group
        draftSubheading = lesson.subheading
        draftWriteUp = lesson.writeUp
    }
}

#Preview {
    LessonDetailView(
        lesson: Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Intro to base-10", writeUp: "This is a sample write up."),
        onSave: { _ in }
    )
}
