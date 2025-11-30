import SwiftUI
import SwiftData

struct AddLessonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var subject: String = ""
    @State private var group: String = ""
    @State private var subheading: String = ""
    @State private var writeUp: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Lesson")
                .font(.system(size: AppTheme.FontSize.titleLarge, weight: .bold, design: .rounded))

            Form {
                Section("Basics") {
                    TextField("Lesson Name", text: $name)
                    TextField("Subject", text: $subject)
                    TextField("Group", text: $group)
                    TextField("Subheading", text: $subheading)
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
                    modelContext.insert(newLesson)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 520)
    }
}

#Preview {
    AddLessonView()
}
