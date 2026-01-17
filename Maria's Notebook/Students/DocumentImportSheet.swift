import SwiftUI
import SwiftData

struct DocumentImportSheet: View {
    let pdfURL: URL
    let pdfData: Data
    let student: Student
    let onSave: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    
    @State private var title: String
    @State private var category: String = "Progress Report"
    
    private let categoryOptions = ["Progress Report", "Standardized Test", "IEP/504", "Work Sample", "Other"]
    
    init(pdfURL: URL, pdfData: Data, student: Student, onSave: @escaping () -> Void) {
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
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveDocument() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        let document = Document(
            title: trimmedTitle,
            category: category,
            uploadDate: Date(),
            pdfData: pdfData,
            student: student
        )
        
        modelContext.insert(document)
        _ = saveCoordinator.save(modelContext, reason: "Import document for student")
        
        onSave()
        dismiss()
    }
}

#Preview {
    let container = ModelContainer.preview
    let context = container.mainContext
    let student = Student(firstName: "Alan", lastName: "Turing", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    context.insert(student)
    
    // Create dummy data
    let dummyData = Data("PDF content".utf8)
    let dummyURL = URL(fileURLWithPath: "/tmp/test.pdf")
    
    return DocumentImportSheet(
        pdfURL: dummyURL,
        pdfData: dummyData,
        student: student,
        onSave: {}
    )
    .previewEnvironment(using: container)
}
