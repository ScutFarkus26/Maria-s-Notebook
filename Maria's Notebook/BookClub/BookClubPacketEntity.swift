import Foundation
import CoreData

@objc(CDBookClubPacket)
public class CDBookClubPacket: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var author: String
    @NSManaged public var gradeMinRaw: String
    @NSManaged public var gradeMaxRaw: String
    @NSManaged public var themes: NSObject?
    @NSManaged public var teachingNotes: String
    @NSManaged public var packetPDFBookmark: Data?
    @NSManaged public var packetPDFRelativePath: String
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var pageCount: Int32
    @NSManaged public var readingItemsJSON: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "BookClubPacket", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.title = ""
        self.author = ""
        self.gradeMinRaw = ""
        self.gradeMaxRaw = ""
        self.themes = nil
        self.teachingNotes = ""
        self.packetPDFBookmark = nil
        self.packetPDFRelativePath = ""
        self.thumbnailData = nil
        self.pageCount = 0
        self.readingItemsJSON = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

extension CDBookClubPacket {
    var themesArray: [String] {
        get { (themes as? [String]) ?? [] }
        set { themes = newValue as NSArray }
    }

    var gradeMin: StoryGrade? {
        get { StoryGrade(rawValue: gradeMinRaw) }
        set { gradeMinRaw = newValue?.rawValue ?? "" }
    }

    var gradeMax: StoryGrade? {
        get { StoryGrade(rawValue: gradeMaxRaw) }
        set { gradeMaxRaw = newValue?.rawValue ?? "" }
    }

    var gradeBand: StoryGradeBand? {
        guard let min = gradeMin, let max = gradeMax else { return nil }
        return StoryGradeBand(min: min, max: max)
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Book Club" : trimmed
    }

    var readingItems: [BookClubReadingItem] {
        get { BookClubReadingItem.decode(readingItemsJSON) }
        set { readingItemsJSON = BookClubReadingItem.encode(newValue) }
    }
}

extension CDBookClubPacket {
    static func defaultSortDescriptors() -> [NSSortDescriptor] {
        [NSSortDescriptor(keyPath: \CDBookClubPacket.createdAt, ascending: false)]
    }
}
