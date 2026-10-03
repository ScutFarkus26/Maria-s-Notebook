import SwiftUI

/// The lessons a child asks for, as tokens. Typing finds catalog lessons
/// (they go to the inbox when the meeting completes); text that matches no
/// lesson stays as a dashed free-text token, written into the meeting's notes.
struct LessonRequestField: View {
    @Bindable var draft: MeetingDraftModel

    @Environment(\.dependencies) private var dependencies
    @State private var query = ""
    @FocusState private var isFocused: Bool

    private static let suggestionLimit = 6

    private var suggestions: [CDLesson] {
        let folded = query.trimmed().lowercased()
        guard !folded.isEmpty else { return [] }
        let chosen = Set(draft.requestLessonIDs)
        return Array(
            dependencies.lessonCatalog.sortedByAreaAndSortIndex
                .lazy
                .filter { lesson in
                    guard let id = lesson.id, !chosen.contains(id) else { return false }
                    return lesson.name.lowercased().contains(folded)
                }
                .prefix(Self.suggestionLimit)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(draft.requestLessonIDs, id: \.self) { id in
                    lessonToken(id)
                }
                ForEach(draft.requestTexts, id: \.self) { text in
                    textToken(text)
                }
                TextField("Find a lesson…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .frame(minWidth: 180)
                    .padding(.vertical, 5)
                    .onSubmit(submit)
            }

            if !query.trimmed().isEmpty {
                suggestionList
            }
        }
    }

    // MARK: - Tokens

    private func lessonToken(_ id: UUID) -> some View {
        let name = dependencies.lessonCatalog.lesson(id: id)?.name ?? "Lesson"
        return HStack(spacing: 6) {
            Image(systemName: "book.closed")
                .font(.caption)
            Text(name)
                .font(.subheadline)
            removeButton(name) { draft.requestLessonIDs.removeAll { $0 == id } }
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
        )
    }

    private func textToken(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.subheadline)
            removeButton(text) { draft.requestTexts.removeAll { $0 == text } }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        )
    }

    private func removeButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption2.weight(.semibold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(name)")
    }

    // MARK: - Suggestions

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { lesson in
                Button {
                    add(lesson)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AppColors.color(forArea: lesson.area))
                            .frame(width: 8, height: 8)
                        Text(lesson.name)
                        Spacer()
                        Text(lesson.area)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button {
                addText()
            } label: {
                Label("Add “\(query.trimmed())” as written", systemImage: "text.badge.plus")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .surface(
            UIConstants.CornerRadius.control,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.trace),
            stroke: Color.primary.opacity(UIConstants.OpacityConstants.subtle),
            style: .continuous
        )
    }

    // MARK: - Actions

    /// Return takes the first matching lesson, or keeps the text as written.
    private func submit() {
        if let first = suggestions.first {
            add(first)
        } else {
            addText()
        }
    }

    private func add(_ lesson: CDLesson) {
        guard let id = lesson.id else { return }
        draft.requestLessonIDs.append(id)
        query = ""
        isFocused = true
    }

    private func addText() {
        let text = query.trimmed()
        guard !text.isEmpty else { return }
        if !draft.requestTexts.contains(text) {
            draft.requestTexts.append(text)
        }
        query = ""
        isFocused = true
    }
}
