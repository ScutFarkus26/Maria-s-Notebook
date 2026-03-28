import Foundation
import SwiftUI

public struct UnifiedNoteItem: Identifiable {
    public enum Source {
        case general
        case lesson
        case work
        case meeting
        case presentation
        case attendance
    }

    public let id: UUID
    public let date: Date
    public let body: String
    public let source: Source
    public let contextText: String
    public let color: Color
    public let associatedID: UUID?
    public let tags: [String]
    public let includeInReport: Bool
    public let needsFollowUp: Bool
    public let imagePath: String?
    public let reportedBy: String?
    public let reporterName: String?
    public let isPinned: Bool
}
