import Foundation

struct DragPayload {
    static let prefix = "STUDENT_TO_INBOX"

    static func encode(sourceID: UUID, lessonID: UUID, studentID: UUID) -> String {
        return "\(prefix):\(sourceID.uuidString):\(lessonID.uuidString):\(studentID.uuidString)"
    }

    static func decode(_ string: String) -> (sourceID: UUID, lessonID: UUID, studentID: UUID)? {
        let parts = string.split(separator: ":")
        guard parts.count == 4,
              parts[0] == prefix,
              let sourceID = UUID(uuidString: String(parts[1])),
              let lessonID = UUID(uuidString: String(parts[2])),
              let studentID = UUID(uuidString: String(parts[3])) else { return nil }
        return (sourceID, lessonID, studentID)
    }
}
