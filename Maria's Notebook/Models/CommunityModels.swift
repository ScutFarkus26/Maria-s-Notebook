import Foundation

// MARK: - Community Attachment Kind

/// Kind of binary attachment associated with a community topic.
/// Extracted from the legacy CommunityAttachment @Model class for use by CD entities.
enum CommunityAttachmentKind: String, Codable, CaseIterable {
    case photo
    case file
}
