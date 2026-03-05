import Foundation
import SwiftData

@Model
final class Document: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var category: String = ""
    var uploadDate: Date = Date()
    
    @Attribute(.externalStorage)
    var pdfData: Data?
    
    @Relationship
    var student: Student?
    
    init(
        id: UUID = UUID(),
        title: String,
        category: String,
        uploadDate: Date = Date(),
        pdfData: Data? = nil,
        student: Student? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.uploadDate = uploadDate
        self.pdfData = pdfData
        self.student = student
    }
}
