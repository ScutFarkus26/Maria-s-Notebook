import Foundation
import CoreData

/// One of the guide's planned lessons, trimmed to what the Daybook Assistant
/// may know: the day, the half or the time, its place in the half, and the
/// children. Never a lesson's name, nor anything that leads to one: the key is
/// the planned presentation's ID, which the Assistant can't look up, since
/// presentations and lessons aren't in the share.
///
/// In the classroom share (schema 20). Written only by the guide's devices
/// (`ScheduleBookingPublisher`), for today through 13 days ahead; older ones
/// are removed. Two devices can each write one for the same presentation, so
/// readers group by `presentationID` and take the newest.
///
/// **No text attribute, ever.** `TimetableBookingAllowlistTests` lists the
/// entity's attributes against an allowlist.
@objc(CDTimetableBooking)
nonisolated public class CDTimetableBooking: NSManagedObject {
    @NSManaged public var id: UUID?
    /// The planned presentation's `id`, as a string.
    @NSManaged public var presentationID: String
    /// The day it's planned for (start of day).
    @NSManaged public var day: Date?
    /// A `ScheduleDayHalf` raw value.
    @NSManaged public var halfRaw: String
    /// A set time, minutes after midnight; -1 when only a half was planned.
    @NSManaged public var minute: Int64
    /// Its place in the half.
    @NSManaged public var order: Int64
    /// The children, a JSON string array (`CloudKitStringArrayStorage`).
    @NSManaged public var _studentIDsData: Data?
    /// The presentation's `modifiedAt` when this was written: a device that
    /// knows only an older presentation never writes over it.
    @NSManaged public var sourceModifiedAt: Date?
    @NSManaged public var createdAt: Date?
    @NSManaged public var modifiedAt: Date?

    @discardableResult
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "TimetableBooking", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        let now = Date()
        self.createdAt = now
        self.modifiedAt = now
    }
}

nonisolated extension CDTimetableBooking: Identifiable {}

nonisolated extension CDTimetableBooking {
    var half: ScheduleDayHalf {
        get { ScheduleDayHalf(rawValue: halfRaw) ?? .morning }
        set { halfRaw = newValue.rawValue }
    }

    /// The set time, or nil when only a half was planned.
    var setMinute: Int? {
        get { minute >= 0 ? Int(minute) : nil }
        set { minute = Int64(newValue ?? -1) }
    }

    var studentIDs: [String] {
        get { CloudKitStringArrayStorage.decode(from: _studentIDsData) }
        set { _studentIDsData = newValue.isEmpty ? nil : CloudKitStringArrayStorage.encode(newValue) }
    }

    /// The newest of one presentation's bookings: the latest
    /// `sourceModifiedAt`, then `modifiedAt`, then the higher `id`, the same
    /// answer on every device.
    static func newest(of rows: [CDTimetableBooking]) -> CDTimetableBooking? {
        rows.max { lhs, rhs in
            let source = (lhs.sourceModifiedAt ?? .distantPast, rhs.sourceModifiedAt ?? .distantPast)
            if source.0 != source.1 { return source.0 < source.1 }
            let modified = (lhs.modifiedAt ?? .distantPast, rhs.modifiedAt ?? .distantPast)
            if modified.0 != modified.1 { return modified.0 < modified.1 }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }

    /// One booking per presentation, the newest of each: what a reader shows
    /// while two devices' copies wait to be folded. Both apps read through this.
    static func newestPerPresentation(_ rows: [CDTimetableBooking]) -> [CDTimetableBooking] {
        Dictionary(grouping: rows) { $0.presentationID.uppercased() }.values.compactMap { newest(of: $0) }
    }
}

nonisolated extension ScheduleLessonSnapshot {
    /// A booking as the Assistant reads it: no title. Nil for a booking whose
    /// presentation ID isn't one.
    init?(booking: CDTimetableBooking) {
        guard let id = UUID(uuidString: booking.presentationID) else { return nil }
        self.init(
            id: id,
            title: nil,
            half: booking.half,
            minute: booking.setMinute,
            order: Int(booking.order),
            studentIDs: booking.studentIDs
        )
    }
}
