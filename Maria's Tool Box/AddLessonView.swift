import SwiftUI
import SwiftData

struct AddLessonView: View {
    // Optional defaults to prefill when adding from a filtered Albums view
    let defaultSubject: String?
    let defaultGroup: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var subject: String = ""
    @State private var group: String = ""
    @State private var subheading: String = ""
    @State private var writeUp: String = ""
    @State private var showingBulkEntry: Bool = false

    @State private var source: LessonSource = .album
    @State private var personalKind: PersonalLessonKind = .personal

    init(defaultSubject: String? = nil, defaultGroup: String? = nil) {
        self.defaultSubject = defaultSubject?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.defaultGroup = defaultGroup?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Lesson")
                .font(.system(size: AppTheme.FontSize.titleLarge, weight: .bold, design: .rounded))

            HStack {
                Spacer()
                Button {
                    showingBulkEntry = true
                } label: {
                    Label("Bulk Entry…", systemImage: "square.grid.3x3")
                }
                .buttonStyle(.bordered)
            }

            Form {
                Section("Basics") {
                    TextField("Lesson Name", text: $name)
                    TextField("Subject", text: $subject)
                    TextField("Group", text: $group)
                    TextField("Subheading", text: $subheading)
                    Picker("Source", selection: $source) {
                        ForEach(LessonSource.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    if source == .personal {
                        Picker("Personal Type", selection: $personalKind) {
                            ForEach(PersonalLessonKind.allCases) { k in
                                Text(k.label).tag(k)
                            }
                        }
                    }
                }

                Section("Write Up") {
                    TextEditor(text: $writeUp)
                        .frame(minHeight: 140)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Add") {
                    let newLesson = Lesson(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                        group: group.trimmingCharacters(in: .whitespacesAndNewlines),
                        subheading: subheading.trimmingCharacters(in: .whitespacesAndNewlines),
                        writeUp: writeUp
                    )
                    newLesson.source = source
                    if source == .personal {
                        newLesson.personalKind = personalKind
                    } else {
                        newLesson.personalKind = nil
                    }
                    modelContext.insert(newLesson)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 520)
        .sheet(isPresented: $showingBulkEntry) {
            BulkLessonsEntryView(
                defaultSubject: subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultSubject : subject,
                defaultGroup: group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultGroup : group,
                onDone: { showingBulkEntry = false }
            )
#if os(macOS)
            .frame(minWidth: 720, minHeight: 560)
            .presentationSizingFitted()
#else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
#endif
        }
        .onAppear {
            if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let d = defaultSubject, !d.isEmpty { subject = d }
            if group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let g = defaultGroup, !g.isEmpty { group = g }
        }
    }
}

#Preview {
    AddLessonView()
}
