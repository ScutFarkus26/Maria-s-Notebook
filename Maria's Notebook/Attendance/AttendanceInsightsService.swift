// AttendanceInsightsService.swift
// Aggregates CDAttendanceRecord data into view-ready summaries for the Mac attendance view.
// Pattern mirrors AttendanceTardyReport: one range fetch, in-memory grouping.

import Foundation
import CoreData
import OSLog

// MARK: - View-Ready Models

/// Per-day attendance tally used by the month heatmap.
struct DayAttendanceCounts: Sendable, Equatable {
    var present: Int = 0
    var absent: Int = 0
    var tardy: Int = 0
    var leftEarly: Int = 0
    var unmarked: Int = 0

    var total: Int { present + absent + tardy + leftEarly + unmarked }
    var hasAnyMarked: Bool { (total - unmarked) > 0 }
}

/// Class-wide summary for an arbitrary date window.
struct AttendanceClassSummary: Sendable, Equatable {
    /// Days in the window that had at least one marked record.
    var schoolDays: Int = 0
    var totalStudentDays: Int = 0
    var presentCount: Int = 0
    var absentCount: Int = 0
    var tardyCount: Int = 0
    var leftEarlyCount: Int = 0

    /// Present + Tardy + LeftEarly all counted as "showed up that day".
    var attendedCount: Int { presentCount + tardyCount + leftEarlyCount }

    /// Attendance rate (0...1). Returns nil if there's no data.
    var attendanceRate: Double? {
        guard totalStudentDays > 0 else { return nil }
        return Double(attendedCount) / Double(totalStudentDays)
    }

    /// On-time rate (0...1) — present out of attended. Returns nil if nobody attended.
    var onTimeRate: Double? {
        guard attendedCount > 0 else { return nil }
        return Double(presentCount) / Double(attendedCount)
    }
}

/// One row in the "students to watch" card.
struct AttendanceWatchListEntry: Sendable, Identifiable, Equatable {
    let id: UUID
    let studentID: UUID
    let fullName: String
    let absentCount: Int
    let tardyCount: Int
    /// Last 10 school-day statuses, oldest → newest. Missing days are `.unmarked`.
    let recentPattern: [AttendanceStatus]
}

/// One notable event within a recent-activity day (one student's status change).
struct AttendanceActivityEvent: Sendable, Identifiable, Equatable {
    let id: String
    let studentName: String
    let status: AttendanceStatus
    let reason: AbsenceReason
}

/// One day in the recent activity card.
struct AttendanceRecentActivityEntry: Sendable, Identifiable, Equatable {
    let id: String
    let date: Date
    let events: [AttendanceActivityEvent]
}

// MARK: - Service

@MainActor
enum AttendanceInsightsService {
    static let logger = Logger.attendance

    /// Returns per-day counts for every day in the inclusive range. Days with no records
    /// get a zeroed `DayAttendanceCounts`.
    static func dayCounts(in range: ClosedRange<Date>, context: NSManagedObjectContext) -> [Date: DayAttendanceCounts] {
        let records = fetchRecords(in: range, context: context, fetchLabel: "dayCounts")
        var counts: [Date: DayAttendanceCounts] = [:]
        for record in records {
            guard let date = record.date else { continue }
            let day = AppCalendar.startOfDay(date)
            var bucket = counts[day] ?? DayAttendanceCounts()
            switch record.status {
            case .present: bucket.present += 1
            case .absent: bucket.absent += 1
            case .tardy: bucket.tardy += 1
            case .leftEarly: bucket.leftEarly += 1
            case .unmarked: bucket.unmarked += 1
            }
            counts[day] = bucket
        }
        return counts
    }

    /// Builds a class-wide summary for `range`. Pair with a second call over the prior
    /// equal-length window to compute a comparison delta.
    static func classSummary(
        in range: ClosedRange<Date>,
        students: [CDStudent],
        context: NSManagedObjectContext
    ) -> AttendanceClassSummary {
        let studentIDs = Set(students.map(\.cloudKitKey))
        let records = fetchRecords(in: range, context: context, fetchLabel: "classSummary")

        var summary = AttendanceClassSummary()
        var daysWithMarks: Set<Date> = []

        for record in records where studentIDs.contains(record.studentID) {
            guard let date = record.date else { continue }
            let day = AppCalendar.startOfDay(date)
            switch record.status {
            case .present:
                summary.presentCount += 1
                daysWithMarks.insert(day)
            case .absent:
                summary.absentCount += 1
                daysWithMarks.insert(day)
            case .tardy:
                summary.tardyCount += 1
                daysWithMarks.insert(day)
            case .leftEarly:
                summary.leftEarlyCount += 1
                daysWithMarks.insert(day)
            case .unmarked:
                break
            }
        }

        summary.schoolDays = daysWithMarks.count
        summary.totalStudentDays = summary.presentCount
            + summary.absentCount
            + summary.tardyCount
            + summary.leftEarlyCount
        return summary
    }

    /// Single-range fetch helper used across all aggregations.
    static func fetchRecords(
        in range: ClosedRange<Date>,
        context: NSManagedObjectContext,
        fetchLabel: String
    ) -> [CDAttendanceRecord] {
        let start = AppCalendar.startOfDay(range.lowerBound)
        let end = AppCalendar.startOfDay(range.upperBound)
        let request = NSFetchRequest<CDAttendanceRecord>(entityName: "AttendanceRecord")
        request.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, end as NSDate)
        do {
            return try context.fetch(request)
        } catch {
            let label = fetchLabel
            let message = error.localizedDescription
            logger.warning("\(label, privacy: .public) fetch failed: \(message, privacy: .public)")
            return []
        }
    }
}

// MARK: - Watch List

extension AttendanceInsightsService {
    /// Returns up to `limit` students with the highest combined absence+tardy count in `range`.
    /// Each entry includes a 10-school-day recent-pattern strip ending at `range.upperBound`.
    static func watchList(
        in range: ClosedRange<Date>,
        students: [CDStudent],
        context: NSManagedObjectContext,
        limit: Int = 5
    ) -> [AttendanceWatchListEntry] {
        let end = AppCalendar.startOfDay(range.upperBound)
        let (absentByID, tardyByID) = tallyAbsencesAndTardies(in: range, context: context)
        let patternRange = patternDayRange(endingAt: end, count: 10, context: context)
        let patternRecords = recentPatternRecords(in: patternRange, context: context)

        let candidates: [AttendanceWatchListEntry] = students.compactMap { student in
            buildWatchEntry(
                for: student,
                absentByID: absentByID,
                tardyByID: tardyByID,
                patternDays: patternRange,
                patternRecords: patternRecords
            )
        }

        return candidates
            .sorted(by: watchListOrder)
            .prefix(limit)
            .map { $0 }
    }

    private static func tallyAbsencesAndTardies(
        in range: ClosedRange<Date>,
        context: NSManagedObjectContext
    ) -> (absent: [String: Int], tardy: [String: Int]) {
        let records = fetchRecords(in: range, context: context, fetchLabel: "watchList")
        var absentByID: [String: Int] = [:]
        var tardyByID: [String: Int] = [:]
        for record in records {
            switch record.status {
            case .absent: absentByID[record.studentID, default: 0] += 1
            case .tardy: tardyByID[record.studentID, default: 0] += 1
            default: break
            }
        }
        return (absentByID, tardyByID)
    }

    private static func buildWatchEntry(
        for student: CDStudent,
        absentByID: [String: Int],
        tardyByID: [String: Int],
        patternDays: [Date],
        patternRecords: [CDAttendanceRecord]
    ) -> AttendanceWatchListEntry? {
        let key = student.cloudKitKey
        let absent = absentByID[key] ?? 0
        let tardy = tardyByID[key] ?? 0
        guard absent + tardy > 0, let id = student.id else { return nil }
        let pattern = buildPattern(forStudent: key, days: patternDays, records: patternRecords)
        return AttendanceWatchListEntry(
            id: id,
            studentID: id,
            fullName: student.fullName,
            absentCount: absent,
            tardyCount: tardy,
            recentPattern: pattern
        )
    }

    private static func watchListOrder(
        _ lhs: AttendanceWatchListEntry,
        _ rhs: AttendanceWatchListEntry
    ) -> Bool {
        let lhsScore = lhs.absentCount * 2 + lhs.tardyCount
        let rhsScore = rhs.absentCount * 2 + rhs.tardyCount
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
    }
}

// MARK: - Recent Activity

extension AttendanceInsightsService {
    /// Builds a compact log of the last `dayCount` school days (skipping days with no notable events).
    static func recentActivity(
        endingAt endDate: Date,
        dayCount: Int = 5,
        students: [CDStudent],
        context: NSManagedObjectContext
    ) -> [AttendanceRecentActivityEntry] {
        let nameByID: [String: String] = students.reduce(into: [:]) { acc, student in
            acc[student.cloudKitKey] = student.fullName
        }

        let schoolDays = recentSchoolDays(endingAt: endDate, count: dayCount, context: context)
        guard let earliest = schoolDays.last, let latest = schoolDays.first else { return [] }
        let records = fetchRecords(in: earliest...latest, context: context, fetchLabel: "recentActivity")

        var byDay: [Date: [CDAttendanceRecord]] = [:]
        for record in records {
            guard let date = record.date else { continue }
            byDay[AppCalendar.startOfDay(date), default: []].append(record)
        }

        var entries: [AttendanceRecentActivityEntry] = []
        for day in schoolDays {
            let dayRecords = byDay[day] ?? []
            let events = buildDayEvents(records: dayRecords, nameByID: nameByID)
            guard !events.isEmpty else { continue }
            entries.append(AttendanceRecentActivityEntry(id: AppCalendar.dayID(day), date: day, events: events))
        }
        return entries
    }

    private static func recentSchoolDays(
        endingAt endDate: Date,
        count: Int,
        context: NSManagedObjectContext
    ) -> [Date] {
        let cache = SchoolDayCache()
        cache.cacheSchoolDayData(for: endDate, viewContext: context)
        var schoolDays: [Date] = []
        var cursor = AppCalendar.startOfDay(endDate)
        var safety = 0
        while schoolDays.count < count && safety < 365 {
            if !cache.isNonSchoolDay(cursor) {
                schoolDays.append(cursor)
            }
            cursor = AppCalendar.addingDays(-1, to: cursor)
            safety += 1
        }
        return schoolDays
    }

    private static func buildDayEvents(
        records: [CDAttendanceRecord],
        nameByID: [String: String]
    ) -> [AttendanceActivityEvent] {
        var absent: [AttendanceActivityEvent] = []
        var tardy: [AttendanceActivityEvent] = []
        var leftEarly: [AttendanceActivityEvent] = []
        for record in records {
            guard let name = nameByID[record.studentID] else { continue }
            let firstName = name.components(separatedBy: " ").first ?? name
            let event = AttendanceActivityEvent(
                id: record.studentID + ":" + record.statusRaw,
                studentName: firstName,
                status: record.status,
                reason: record.absenceReason
            )
            switch record.status {
            case .absent: absent.append(event)
            case .tardy: tardy.append(event)
            case .leftEarly: leftEarly.append(event)
            default: break
            }
        }
        return absent + tardy + leftEarly
    }
}

// MARK: - Pattern Helpers

extension AttendanceInsightsService {
    static func patternDayRange(endingAt end: Date, count: Int, context: NSManagedObjectContext) -> [Date] {
        let cache = SchoolDayCache()
        cache.cacheSchoolDayData(for: end, viewContext: context)
        var days: [Date] = []
        var cursor = AppCalendar.startOfDay(end)
        var safety = 0
        while days.count < count && safety < 365 {
            if !cache.isNonSchoolDay(cursor) {
                days.append(cursor)
            }
            cursor = AppCalendar.addingDays(-1, to: cursor)
            safety += 1
        }
        return days.reversed()
    }

    static func recentPatternRecords(in days: [Date], context: NSManagedObjectContext) -> [CDAttendanceRecord] {
        guard let earliest = days.first, let latest = days.last else { return [] }
        return fetchRecords(in: earliest...latest, context: context, fetchLabel: "recentPattern")
    }

    static func buildPattern(
        forStudent studentID: String,
        days: [Date],
        records: [CDAttendanceRecord]
    ) -> [AttendanceStatus] {
        var byDay: [Date: AttendanceStatus] = [:]
        for record in records where record.studentID == studentID {
            guard let date = record.date else { continue }
            byDay[AppCalendar.startOfDay(date)] = record.status
        }
        return days.map { byDay[$0] ?? .unmarked }
    }
}
