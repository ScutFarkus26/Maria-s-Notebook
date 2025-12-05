import Foundation
import SwiftData

enum WorkCheckInStatus: String, Codable, CaseIterable {
    case scheduled = "Scheduled"
    case completed = "Completed"
    case skipped = "Skipped"
}

@Model final class WorkCheckIn: Identifiable {
    @Attribute(.unique) var id: UUID
    var workID: UUID
    @Relationship var work: WorkModel?
    var date: Date
    private var statusRaw: String
    var note: String
    var purpose: String = ""
    
    var status: WorkCheckInStatus {
        get {
            WorkCheckInStatus(rawValue: statusRaw) ?? .scheduled
        }
        set {
            statusRaw = newValue.rawValue
        }
    }
    
    init(id: UUID = UUID(), workID: UUID, date: Date = Date(), status: WorkCheckInStatus = .scheduled, purpose: String = "", note: String = "", work: WorkModel? = nil) {
        self.id = id
        self.workID = workID
        self.date = date
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
        self.date = date
        if let note = note { self.note = note }
    }

    func reschedule(to date: Date, note: String? = nil, in _: ModelContext) {
        self.status = .scheduled
        self.date = date
        if let note = note { self.note = note }
    }

    func skip(note: String? = nil, at date: Date = Date(), in _: ModelContext) {
        self.status = .skipped
        self.date = date
        if let note = note { self.note = note }
    }
}

extension WorkModel {
    func addCheckIn(date: Date, status: WorkCheckInStatus = .scheduled, purpose: String = "", note: String = "", in context: ModelContext) {
        let ci = WorkCheckIn(workID: self.id, date: date, status: status, purpose: purpose, note: note, work: self)
        context.insert(ci)
        self.checkIns.append(ci)
    }

    @discardableResult
    func scheduleCheckIn(on date: Date, purpose: String = "", note: String = "", in context: ModelContext) -> WorkCheckIn {
        let ci = WorkCheckIn(workID: self.id, date: date, status: .scheduled, purpose: purpose, note: note, work: self)
        context.insert(ci)
        self.checkIns.append(ci)
        return ci
    }

    func markCheckInCompleted(_ checkIn: WorkCheckIn, note: String? = nil, at date: Date = Date(), in context: ModelContext) {
        checkIn.markCompleted(note: note, at: date, in: context)
    }
}

