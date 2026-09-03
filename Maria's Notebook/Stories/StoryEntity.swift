import Foundation
import CoreData

@objc(CDStory)
public class CDStory: NSManagedObject {
    // MARK: - Core Data Properties
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var summary: String
    @NSManaged public var gradeMinRaw: String
    @NSManaged public var gradeMaxRaw: String
    @NSManaged public var themes: NSObject?
    @NSManaged public var pdfFileBookmark: Data?
    @NSManaged public var pdfFileRelativePath: String
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var generatedCoverData: Data?
    @NSManaged public var pageCount: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var analysisStatusRaw: String
    @NSManaged public var analysisErrorMessage: String
    @NSManaged public var analysisModelVersion: String
    @NSManaged public var extractedTextHash: String
    @NSManaged public var userEditedTitle: Bool
    @NSManaged public var userEditedThemes: Bool
    @NSManaged public var relatedLessonIDsRaw: String
    @NSManaged public var relatedLessonReasonsJSON: String
    @NSManaged public var relatedLessonsAnalyzedAt: Date?

    // MARK: - Convenience Initializer
    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Story", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.summary = ""
        self.gradeMinRaw = ""
        self.gradeMaxRaw = ""
        self.themes = nil
        self.pdfFileBookmark = nil
        self.pdfFileRelativePath = ""
        self.thumbnailData = nil
        self.generatedCoverData = nil
        self.pageCount = 0
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.analysisStatusRaw = StoryAnalysisStatus.pending.rawValue
        self.analysisErrorMessage = ""
        self.analysisModelVersion = ""
        self.extractedTextHash = ""
        self.userEditedTitle = false
        self.userEditedThemes = false
        self.relatedLessonIDsRaw = ""
        self.relatedLessonReasonsJSON = ""
        self.relatedLessonsAnalyzedAt = nil
    }
}

// MARK: - Computed Properties

extension CDStory {
    /// Themes as a Swift `[String]` array.
    var themesArray: [String] {
        get { (themes as? [String]) ?? [] }
        set { themes = newValue as NSArray }
    }

    var analysisStatus: StoryAnalysisStatus {
        get { StoryAnalysisStatus(rawValue: analysisStatusRaw) ?? .pending }
        set { analysisStatusRaw = newValue.rawValue }
    }

    var gradeMin: StoryGrade? {
        get { StoryGrade(rawValue: gradeMinRaw) }
        set { gradeMinRaw = newValue?.rawValue ?? "" }
    }

    var gradeMax: StoryGrade? {
        get { StoryGrade(rawValue: gradeMaxRaw) }
        set { gradeMaxRaw = newValue?.rawValue ?? "" }
    }

    /// The grade band, if both ends are set.
    var gradeBand: StoryGradeBand? {
        guard let min = gradeMin, let max = gradeMax else { return nil }
        return StoryGradeBand(min: min, max: max)
    }

    /// Display string for the title with a graceful fallback.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Story" : trimmed
    }
}

// MARK: - Fetch Helpers

extension CDStory {
    /// Default sort: most recently created first.
    static func defaultSortDescriptors() -> [NSSortDescriptor] {
        [NSSortDescriptor(keyPath: \CDStory.createdAt, ascending: false)]
    }
}

// MARK: - Related Lessons

extension CDStory {
    /// Persisted lesson UUIDs (parsed from `relatedLessonIDsRaw`, comma-separated).
    var relatedLessonUUIDs: [UUID] {
        relatedLessonIDsRaw
            .split(separator: ",")
            .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Reasons keyed by lesson UUID string. Backed by `relatedLessonReasonsJSON`.
    var relatedLessonReasons: [String: String] {
        guard !relatedLessonReasonsJSON.isEmpty,
              let data = relatedLessonReasonsJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    /// Persists a freshly computed set of `LessonMatch` results onto this story.
    func storeRelatedLessons(_ matches: [(lessonID: UUID, reason: String)]) {
        relatedLessonIDsRaw = matches.map { $0.lessonID.uuidString }.joined(separator: ",")
        var reasons: [String: String] = [:]
        for match in matches {
            reasons[match.lessonID.uuidString] = match.reason
        }
        if let data = try? JSONEncoder().encode(reasons),
           let str = String(data: data, encoding: .utf8) {
            relatedLessonReasonsJSON = str
        } else {
            relatedLessonReasonsJSON = ""
        }
        relatedLessonsAnalyzedAt = Date()
        modifiedAt = Date()
    }

    /// Loads the persisted matches as live `CDLesson` objects paired with their reasons.
    /// Skips IDs that no longer resolve to a lesson (e.g. deleted).
    func loadRelatedLessons(in context: NSManagedObjectContext) -> [(lesson: CDLesson, reason: String)] {
        let ids = relatedLessonUUIDs
        guard !ids.isEmpty else { return [] }
        let reasons = relatedLessonReasons
        var results: [(CDLesson, String)] = []
        for id in ids {
            if let lesson = context.object(CDLesson.self, id: id) {
                let reason = reasons[id.uuidString] ?? ""
                results.append((lesson, reason))
            }
        }
        return results
    }
}
