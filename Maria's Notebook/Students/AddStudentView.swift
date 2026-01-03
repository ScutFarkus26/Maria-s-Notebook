import SwiftUI
import SwiftData

struct AddStudentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var nickname = ""
    @State private var birthday = Date()
    @State private var startDate = Date()
    @State private var level: Student.Level = .lower

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text("Add Student")
                .font(.system(size: AppTheme.FontSize.titleLarge, weight: .bold, design: .rounded))

            Form {
                Section {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    TextField("Nickname (Optional)", text: $nickname)
                }

                Section {
                    DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                }

                Section {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
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
                        nickname: nickname.isEmpty ? nil : nickname,
                        level: level,
                        dateStarted: startDate
                    )
                    modelContext.insert(newStudent)
                    if saveCoordinator.save(modelContext, reason: "Adding student") {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(firstName.isEmpty || lastName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420, height: 420)
        .saveErrorAlert()
    }
}
