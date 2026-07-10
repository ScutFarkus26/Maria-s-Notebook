import SwiftUI
import CoreData

struct AddStudentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var nickname = ""
    @State private var birthday = Date()
    @State private var startDate = Date()
    @State private var level: CDStudent.Level = .lower

    private var repository: StudentRepository {
        StudentRepository(context: managedObjectContext, saveCoordinator: saveCoordinator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text("Add Student")
                .font(AppTheme.ScaledFont.titleLarge)

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
                        Text("Lower").tag(CDStudent.Level.lower)
                        Text("Upper").tag(CDStudent.Level.upper)
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
                    repository.createStudent(
                        firstName: firstName,
                        lastName: lastName,
                        birthday: birthday,
                        nickname: nickname.isEmpty ? nil : nickname,
                        level: level,
                        dateStarted: startDate
                    )
                    if repository.save(reason: "Adding student") {
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
