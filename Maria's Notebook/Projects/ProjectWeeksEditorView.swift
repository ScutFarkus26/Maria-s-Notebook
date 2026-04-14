// ProjectWeeksEditorView removed — CDProjectTemplateWeek deprecated.
// InlineLessonPickerSheet retained for use elsewhere.

import SwiftUI
import CoreData

struct InlineLessonPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""

    let lessons: [CDLesson]
    var onChosen: (UUID?) -> Void

    init(lessons: [CDLesson], onChosen: @escaping (UUID?) -> Void) {
        self.lessons = lessons
        self.onChosen = onChosen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Lesson")
                .font(.title3).fontWeight(.semibold)
            TextField("Search…", text: $search)
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(filteredLessons, id: \.objectID) { lesson in
                    Button {
                        onChosen(lesson.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                                let subtitle: String = {
                                    switch (lesson.subject.isEmpty, lesson.group.isEmpty) {
                                    case (false, false): return "\(lesson.subject) • \(lesson.group)"
                                    case (false, true): return lesson.subject
                                    case (true, false): return lesson.group
                                    default: return ""
                                    }
                                }()
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding(16)
    #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
    #endif
    #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    #endif
    }

    private var filteredLessons: [CDLesson] {
        let q = search.trimmed()
        if q.isEmpty { return lessons }
        return lessons.filter { l in
            l.name.localizedCaseInsensitiveContains(q) ||
            l.subject.localizedCaseInsensitiveContains(q) ||
            l.group.localizedCaseInsensitiveContains(q)
        }
    }
}
