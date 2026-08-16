import Foundation

struct PresentationFollowUpWorkDraft: Codable, Equatable, Sendable {
    let presentationID: UUID
    let studentIDs: [String]
    let title: String
    let kindRaw: String
    let sampleWorkID: UUID?
    let updatedAt: Date

    var kind: WorkKind {
        WorkKind(rawValue: kindRaw) ?? .followUpAssignment
    }
}

/// A lightweight recovery store for text that has been typed but not yet
/// committed with Add Work. This protects the draft from Mac window closure;
/// it never creates a real child-work record by itself.
@MainActor
enum PresentationFollowUpWorkDraftStore {
    private static let storageKey = "PresentationFollowUpWorkDrafts.v1"
    private static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    static func load(
        presentationID: UUID,
        studentIDs: [String],
        defaults: UserDefaults = .standard
    ) -> PresentationFollowUpWorkDraft? {
        drafts(defaults: defaults)[key(presentationID: presentationID, studentIDs: studentIDs)]
    }

    static func save(
        presentationID: UUID,
        studentIDs: [String],
        title: String,
        kind: WorkKind,
        sampleWorkID: UUID?,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        let trimmedTitle = title.trimmed()
        guard !trimmedTitle.isEmpty else {
            clear(
                presentationID: presentationID,
                studentIDs: studentIDs,
                defaults: defaults
            )
            return
        }

        let normalizedStudentIDs = normalized(studentIDs)
        var stored = drafts(defaults: defaults)
        stored[key(presentationID: presentationID, studentIDs: normalizedStudentIDs)] = .init(
            presentationID: presentationID,
            studentIDs: normalizedStudentIDs,
            title: title,
            kindRaw: kind.rawValue,
            sampleWorkID: sampleWorkID,
            updatedAt: now
        )
        write(stored, defaults: defaults)
    }

    static func clear(
        presentationID: UUID,
        studentIDs: [String],
        defaults: UserDefaults = .standard
    ) {
        var stored = drafts(defaults: defaults)
        stored.removeValue(forKey: key(presentationID: presentationID, studentIDs: studentIDs))
        write(stored, defaults: defaults)
    }

    static func mostRecent(
        presentationID: UUID,
        defaults: UserDefaults = .standard
    ) -> PresentationFollowUpWorkDraft? {
        drafts(defaults: defaults).values
            .filter { $0.presentationID == presentationID }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private static func drafts(
        defaults: UserDefaults
    ) -> [String: PresentationFollowUpWorkDraft] {
        guard let data = defaults.data(forKey: storageKey),
              var decoded = try? JSONDecoder().decode(
                [String: PresentationFollowUpWorkDraft].self,
                from: data
              ) else {
            return [:]
        }
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        decoded = decoded.filter { $0.value.updatedAt >= cutoff }
        return decoded
    }

    private static func write(
        _ drafts: [String: PresentationFollowUpWorkDraft],
        defaults: UserDefaults
    ) {
        if drafts.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(drafts) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func key(presentationID: UUID, studentIDs: [String]) -> String {
        "\(presentationID.uuidString)|\(normalized(studentIDs).joined(separator: ","))"
    }

    private static func normalized(_ studentIDs: [String]) -> [String] {
        Array(Set(studentIDs.filter { UUID(uuidString: $0) != nil })).sorted()
    }
}
