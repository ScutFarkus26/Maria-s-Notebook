import SwiftUI
import CoreData

struct DocumentImportSheet: View {
    let pdfURL: URL
    let pdfData: Data
    let student: CDStudent
    let onSave: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SaveCoordinator.self) private var saveCoordinator

    private var repository: DocumentRepository {
        DocumentRepository(context: managedObjectContext, saveCoordinator: saveCoordinator)
    }

    @State private var title: String
    @State private var category: String = "Progress Report"
    
    private let categoryOptions = ["Progress Report", "Standardized Test", "IEP/504", "Work Sample", "Other"]
    
    init(pdfURL: URL, pdfData: Data, student: CDStudent, onSave: @escaping () -> Void) {
        self.pdfURL = pdfURL
        self.pdfData = pdfData
        self.student = student
        self.onSave = onSave
        
        // Pre-fill title with filename (without extension)
        let filename = pdfURL.deletingPathExtension().lastPathComponent
        _title = State(initialValue: filename)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Document Details") {
                    TextField("Title", text: $title)
                    
                    Picker("Category", selection: $category) {
                        ForEach(categoryOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                }
            }
            .navigationTitle("Import Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDocument()
                    }
                    .disabled(title.trimmed().isEmpty)
                }
            }
        }
    }
    
    private func saveDocument() {
        let trimmedTitle = title.trimmed()
        guard !trimmedTitle.isEmpty else { return }

        // Look up CDStudent by ID for the Core Data repository
        let studentRepo = StudentRepository(context: managedObjectContext)
        let cdStudent = student.id.flatMap { studentRepo.fetchStudent(id: $0) }
        repository.createDocument(
            title: trimmedTitle,
            category: category,
            pdfData: pdfData,
            student: cdStudent
        )
        _ = repository.save(reason: "Import document for student")

        onSave()
        dismiss()
    }
}

#Preview {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext
    let student = Student(context: ctx)
    student.firstName = "Alan"
    student.lastName = "Turing"
    student.birthday = Date(timeIntervalSince1970: 0)
    student.level = .upper

    // Create dummy data
    let dummyData = Data("PDF content".utf8)
    let dummyURL = URL(fileURLWithPath: "/tmp/test.pdf")

    return DocumentImportSheet(
        pdfURL: dummyURL,
        pdfData: dummyData,
        student: student,
        onSave: {}
    )
    .previewEnvironment(using: stack)
}
