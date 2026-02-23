import Foundation
import FoundationModels

/// Service that uses Apple Intelligence to extract student names from todo text
@MainActor
final class TodoStudentSuggestionService {
    
    @Generable(description: "Extracted student names from text")
    struct ExtractedNames {
        @Guide(description: "Array of student first names or full names mentioned in the text")
        var studentNames: [String]
    }
    
    /// Extract potential student names from todo text using Apple Intelligence
    /// - Parameters:
    ///   - text: The todo title and notes combined
    ///   - availableStudents: List of students to help guide name recognition
    /// - Returns: Array of extracted student names
    static func extractStudentNames(from text: String, availableStudents: [Student]) async throws -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        // Build a prompt with context about available students
        let studentNames = availableStudents.map { $0.fullName }.joined(separator: ", ")
        let prompt = """
        Extract any student names mentioned in the following todo item text.
        
        Available students in the system: \(studentNames)
        
        Todo text: "\(text)"
        
        Return an array of student names that are mentioned or referenced in the todo text. \
        Match names to the available students list when possible. If no students are mentioned, return an empty array.
        """
        
        let session = LanguageModelSession(model: .default)
        
        do {
            let response = try await session.respond(
                to: prompt,
                generating: ExtractedNames.self
            )
            
            return response.content.studentNames
        } catch {
            // If Apple Intelligence is not available or fails, return empty array
            return []
        }
    }
    
    /// Match extracted names to actual Student objects
    /// - Parameters:
    ///   - extractedNames: Names extracted from text
    ///   - students: Available students to match against
    /// - Returns: Array of matching Student objects
    static func matchStudents(extractedNames: [String], from students: [Student]) -> [Student] {
        var matches: [Student] = []
        
        for name in extractedNames {
            let lowercasedName = name.lowercased()
            
            // Try exact full name match
            if let student = students.first(where: { $0.fullName.lowercased() == lowercasedName }) {
                if !matches.contains(where: { $0.id == student.id }) {
                    matches.append(student)
                }
                continue
            }
            
            // Try first name match
            if let student = students.first(where: { $0.firstName.lowercased() == lowercasedName }) {
                if !matches.contains(where: { $0.id == student.id }) {
                    matches.append(student)
                }
                continue
            }
            
            // Try last name match
            if let student = students.first(where: { $0.lastName.lowercased() == lowercasedName }) {
                if !matches.contains(where: { $0.id == student.id }) {
                    matches.append(student)
                }
                continue
            }
            
            // Try partial match in full name
            if let student = students.first(where: { $0.fullName.lowercased().contains(lowercasedName) }) {
                if !matches.contains(where: { $0.id == student.id }) {
                    matches.append(student)
                }
            }
        }
        
        return matches
    }
}
