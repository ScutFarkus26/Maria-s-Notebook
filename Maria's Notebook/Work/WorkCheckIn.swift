import Foundation
import SwiftData

enum WorkCheckInStatus: String, Codable, CaseIterable {
    case scheduled = "Scheduled"
    case completed = "Completed"
    case skipped = "Skipped"
}

@Model final class WorkCheckIn: Identifiable {
    var id: UUID = UUID()
    // CloudKit compatibility: Store UUID as string
    var workID: String = ""
    @Relationship var work: WorkModel?
    var date: Date = Date()
    private var statusRaw: String = WorkCheckInStatus.scheduled.rawValue
    var note: String = ""
    var purpose: String = ""
    
    var status: WorkCheckInStatus {
        get {
            WorkCheckInStatus(rawValue: statusRaw) ?? .scheduled
        }
        set {
            statusRaw = newValue.rawValue
        }
    }
    
    // Computed property for backward compatibility with UUID
    var workIDUUID: UUID? {
        get { UUID(uuidString: workID) }
        set { workID = newValue?.uuidString ?? "" }
    }
    
    init(id: UUID = UUID(), workID: UUID, date: Date = Date(), status: WorkCheckInStatus = .scheduled, purpose: String = "", note: String = "", work: WorkModel? = nil) {
        self.id = id
        // CloudKit compatibility: Store UUID as string
        self.workID = workID.uuidString
        let cal = AppCalendar.shared
        self.date = cal.startOfDay(for: date)
        self.statusRaw = status.rawValue
        self.purpose = purpose
        self.note = note
        self.work = work
    }
    
    // Convenience flags
    var isScheduled: Bool { status == .scheduled }
    var isCompleted: Bool { status == .completed }
    var isUpcoming: Bool { status == .scheduled && date > Date() }

    // Mutating helpers
    func markCompleted(note: String? = nil, at date: Date = Date(), in _: ModelContext) {
        self.status = .completed
        let cal = AppCalendar.shared
        self.date = cal.startOfDay(for: date)
        if let note = note { self.note = note }
    }

    func reschedule(to date: Date, note: String? = nil, in _: ModelContext) {
        self.status = .scheduled
        let cal = AppCalendar.shared
        self.date = cal.startOfDay(for: date)
        if let note = note { self.note = note }
    }

    func skip(note: String? = nil, at date: Date = Date(), in _: ModelContext) {
        self.status = .skipped
        let cal = AppCalendar.shared
        self.date = cal.startOfDay(for: date)
        if let note = note { self.note = note }
    }
}

extension WorkModel {
    func addCheckIn(date: Date, status: WorkCheckInStatus = .scheduled, purpose: String = "", note: String = "", in context: ModelContext) {
        let ci = WorkCheckIn(workID: self.id, date: date, status: status, purpose: purpose, note: note, work: self)
        context.insert(ci)
        if self.checkIns == nil { self.checkIns = [] }
        self.checkIns = (self.checkIns ?? []) + [ci]
    }

    @discardableResult
    func scheduleCheckIn(on date: Date, purpose: String = "", note: String = "", in context: ModelContext) -> WorkCheckIn {
        let ci = WorkCheckIn(workID: self.id, date: date, status: .scheduled, purpose: purpose, note: note, work: self)
        context.insert(ci)
        if self.checkIns == nil { self.checkIns = [] }
        self.checkIns = (self.checkIns ?? []) + [ci]
        return ci
    }

    func markCheckInCompleted(_ checkIn: WorkCheckIn, note: String? = nil, at date: Date = Date(), in context: ModelContext) {
        checkIn.markCompleted(note: note, at: date, in: context)
    }
}

