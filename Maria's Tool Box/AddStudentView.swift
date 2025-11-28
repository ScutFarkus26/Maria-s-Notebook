import SwiftUI
import SwiftData

struct AddStudentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var birthday = Date()
    @State private var level: Student.Level = .lower

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text("Add Student")
                .font(.system(size: AppTheme.FontSize.titleLarge, weight: .bold, design: .rounded))

            Form {
                Section {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                }

                Section {
                    DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                }

                Section {
                    Picker("Level", selection: $level) {
                        Text("Lower").tag(Student.Level.lower)
                        Text("Upper").tag(Student.Level.upper)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Add") {
                    let newStudent = Student(
                        firstName: firstName,
                        lastName: lastName,
                        birthday: birthday,
                        level: level
                    )
                    modelContext.insert(newStudent)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(firstName.isEmpty || lastName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420, height: 420)
    }
}
