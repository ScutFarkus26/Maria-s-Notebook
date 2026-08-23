import CoreData
import CoreGraphics
import Foundation

// The guide's personal annotations on their teaching albums: bookmarks, page
// notes, text highlights, Apple Pencil ink, recent visits, and where they left
// off in each album. All live in the private store — these are one teacher's
// working marks, not classroom data an assistant should see.
//
// `albumID` is the PDF's filename, which is how the album library identifies
// albums on disk. It is a plain String foreign key by construction.

@objc(CDAlbumBookmark)
public class CDAlbumBookmark: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var albumID: String
    @NSManaged public var pageIndex: Int32
    @NSManaged public var lessonTitle: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AlbumBookmark", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.albumID = ""
        self.pageIndex = 0
        self.lessonTitle = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

@objc(CDAlbumPageNote)
public class CDAlbumPageNote: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var albumID: String
    @NSManaged public var pageIndex: Int32
    @NSManaged public var lessonTitle: String
    @NSManaged public var text: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AlbumPageNote", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.albumID = ""
        self.pageIndex = 0
        self.lessonTitle = ""
        self.text = ""
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

@objc(CDAlbumRecentVisit)
public class CDAlbumRecentVisit: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var albumID: String
    @NSManaged public var pageIndex: Int32
    @NSManaged public var lessonTitle: String
    @NSManaged public var visitedAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AlbumRecentVisit", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.albumID = ""
        self.pageIndex = 0
        self.lessonTitle = ""
        self.visitedAt = Date()
        self.modifiedAt = Date()
    }
}

@objc(CDAlbumReadingPosition)
public class CDAlbumReadingPosition: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var albumID: String
    @NSManaged public var pageIndex: Int32
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AlbumReadingPosition", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.albumID = ""
        self.pageIndex = 0
        self.modifiedAt = Date()
    }
}

/// A text highlight on a page: rectangles in PDF page space, plus the
/// highlighted text itself so highlights stay searchable and listable.
@objc(CDAlbumHighlight)
public class CDAlbumHighlight: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var albumID: String
    @NSManaged public var pageIndex: Int32
    @NSManaged public var lessonTitle: String
    @NSManaged public var text: String
    @NSManaged public var colorName: String
    /// JSON-encoded [[x, y, width, height]] in page space.
    @NSManaged public var rectsData: Data?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AlbumHighlight", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.albumID = ""
        self.pageIndex = 0
        self.lessonTitle = ""
        self.text = ""
        self.colorName = "yellow"
        self.rectsData = nil
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

extension CDAlbumHighlight {
    var rects: [CGRect] {
        get { Self.decode(rectsData) }
        set { rectsData = Self.encode(newValue) }
    }

    nonisolated static func encode(_ rects: [CGRect]) -> Data {
        let raw = rects.map { [$0.origin.x, $0.origin.y, $0.width, $0.height] }
        return (try? JSONEncoder().encode(raw)) ?? Data()
    }

    nonisolated static func decode(_ data: Data?) -> [CGRect] {
        guard let data, let raw = try? JSONDecoder().decode([[Double]].self, from: data) else {
            return []
        }
        return raw.compactMap { v in
            v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : nil
        }
    }

    /// Rectangles as plain numbers, for backup export.
    var rectValues: [[Double]] {
        rects.map { [$0.origin.x, $0.origin.y, $0.width, $0.height] }
    }

    func setRectValues(_ values: [[Double]]) {
        rects = values.compactMap { v in
            v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : nil
        }
    }
}

/// Apple Pencil / finger ink for one album page, stored as PencilKit drawing
/// data so markup follows the guide across devices.
@objc(CDAlbumPageInk)
public class CDAlbumPageInk: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var albumID: String
    @NSManaged public var pageIndex: Int32
    @NSManaged public var drawingData: Data?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "AlbumPageInk", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.albumID = ""
        self.pageIndex = 0
        self.drawingData = nil
        self.modifiedAt = Date()
    }
}
