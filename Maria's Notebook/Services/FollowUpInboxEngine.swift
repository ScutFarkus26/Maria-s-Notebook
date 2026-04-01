// swiftlint:disable file_length
import SwiftUI
import CoreData
import OSLog

// MARK: - Follow-Up Inbox Item
struct FollowUpInboxItem: Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case lessonFollowUp
        case workCheckIn
        case workReview

        var label: String {
            switch self {
            case .lessonFollowUp: return "Lesson"
            case .workCheckIn: return "Check-In"
            case .workReview: return "Review"
            }
        }

        var icon: String {
            switch self {
            case .lessonFollowUp: return "text.book.closed"
            case .workCheckIn: return "checklist"
            case .workReview: return "eye"
            }
        }

        var tint: Color {
            switch self {
            case .lessonFollowUp: return .orange
            case .workCheckIn: return .blue
            case .workReview: return .purple
            }
        }
    }

    enum Bucket: Int, Comparable, CaseIterable {
        case overdue = 0
        case dueToday = 1
        case inbox = 2
        case upcoming = 3

        static func < (lhs: Bucket, rhs: Bucket) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .overdue: return "Overdue"
            case .dueToday: return "Due Today"
            case .inbox: return "Needs Scheduling"
            case .upcoming: return "Upcoming"
            }
        }
    }

    // Stable id derived from type + underlying id
    let id: String

    // Underlying references for navigation
    let underlyingID: UUID

    // Display
    let childID: UUID?
    let childName: String
    let title: String
    let kind: Kind
    let statusText: String
    let ageDays: Int
    let bucket: Bucket

    // Sorting composite (bucket, age desc, then childName, then title)
    var sortKey: String {
        let age = String(format: "%04d", ageDays)
        return "\(bucket.rawValue)|\(String(age.reversed()))|\(childName.lowercased())|\(title.lowercased())"
    }
}

// MARK: - Engine
// swiftlint:disable:next type_body_length
struct FollowUpInboxEngine {
    private static let logger = Logger.inbox

    // MARK: - Helper Methods

    private static func safeFetch<T: NSManagedObject>(
        _ request: NSFetchRequest<T>, context: NSManagedObjectContext,
        label: String = #function
    ) -> [T] {
        do {
            return try context.fetch(request)
        } catch {
            logger.warning("Failed to fetch \(T.self, privacy: .public): \(error.localizedDescription)")
            return []
        }
    }
    struct Constants {
        var lessonFollowUpOverdueDays: Int = 7
        var workStaleOverdueDays: Int = 5
        var reviewStaleDays: Int = 3
    }

    // MARK: - Helper Types

    private struct WorkDisplayFields {
        let childID: UUID?
        let childName: String
        let lessonTitle: String
    }

    // MARK: - Compute Context

    /// Bundles shared lookup data used across all follow-up rules.
    private struct ComputeContext {
        let lessonsByID: [UUID: CDLesson]
        let studentsByID: [UUID: CDStudent]
        let lasByID: [UUID: CDLessonAssignment]
        let openWorkModels: [CDWorkModel]
        let checkInsByWorkID: [UUID: [CDWorkCheckIn]]
        let notesByWorkID: [UUID: [CDNote]]
        let nonSchoolDaysSet: Set<Date>
        let schoolDayOverridesSet: Set<Date>
        let constants: Constants
        let context: NSManagedObjectContext
    }

    // MARK: - Main Entry Point

    static func computeItems(
        lessons: [CDLesson],
        students: [CDStudent],
        lessonAssignments: [CDLessonAssignment],
        context: NSManagedObjectContext,
        constants: Constants = Constants()
    ) -> [FollowUpInboxItem] {
        let ctx = buildContext(
            lessons: lessons, students: students,
            lessonAssignments: lessonAssignments,
            context: context, constants: constants
        )

        var results: [FollowUpInboxItem] = []
        results.append(contentsOf: computeLessonFollowUpItems(
            ctx: ctx, lessonAssignments: lessonAssignments
        ))
        let (workItems, addedIDs) = computeWorkStaleItems(ctx: ctx)
        results.append(contentsOf: workItems)
        results.append(contentsOf: computeUnscheduledWorkItems(
            ctx: ctx, addedWorkIDs: addedIDs
        ))
        return sortResults(results)
    }

    // MARK: - Context Builder

    private static func buildContext(
        lessons: [CDLesson], students: [CDStudent],
        lessonAssignments: [CDLessonAssignment],
        context: NSManagedObjectContext, constants: Constants
    ) -> ComputeContext {
        let lessonsByID = lessons.toDictionary(by: { $0.id ?? UUID() })
        let studentsByID = students.toDictionary(by: { $0.id ?? UUID() })
        let lasByID = lessonAssignments.toDictionary(by: { $0.id ?? UUID() })
        let openWorkModels = fetchOpenWorkModels(context: context)
        let (nsdSet, sdoSet) = fetchSchoolDaySets(context: context)
        let checkInsByWorkID = openWorkModels.reduce(into: [UUID: [CDWorkCheckIn]]()) {
            $0[$1.id ?? UUID()] = ($1.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
        }
        let notesByWorkID = openWorkModels.reduce(into: [UUID: [CDNote]]()) {
            $0[$1.id ?? UUID()] = ($1.unifiedNotes?.allObjects as? [CDNote]) ?? []
        }
        return ComputeContext(
            lessonsByID: lessonsByID, studentsByID: studentsByID, lasByID: lasByID,
            openWorkModels: openWorkModels, checkInsByWorkID: checkInsByWorkID,
            notesByWorkID: notesByWorkID, nonSchoolDaysSet: nsdSet,
            schoolDayOverridesSet: sdoSet, constants: constants,
            context: context
        )
    }

    private static func fetchOpenWorkModels(context: NSManagedObjectContext) -> [CDWorkModel] {
        let completeRaw = WorkStatus.complete.rawValue
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "statusRaw != %@", completeRaw)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return safeFetch(request, context: context, label: "computeItems")
            .filter(\.isOpen)
    }

    private static func fetchSchoolDaySets(
        context: NSManagedObjectContext
    ) -> (nonSchoolDays: Set<Date>, overrides: Set<Date>) {
        let nonSchoolDays = safeFetch(
            CDFetchRequest(CDNonSchoolDay.self), context: context, label: "computeItems"
        )
        let nsdSet = Set(nonSchoolDays.compactMap { $0.date }.map { AppCalendar.startOfDay($0) })
        let overrides = safeFetch(
            CDFetchRequest(CDSchoolDayOverride.self), context: context, label: "computeItems"
        )
        let sdoSet = Set(overrides.compactMap { $0.date }.map { AppCalendar.startOfDay($0) })
        return (nsdSet, sdoSet)
    }

    // MARK: - Shared Helpers

    private static func childDisplayName(
        for ids: [UUID], studentsByID: [UUID: CDStudent]
    ) -> (UUID?, String) {
        if ids.count == 1, let id = ids.first, let s = studentsByID[id] {
            return (id, cdStudentDisplayName(s))
        }
        return (nil, ids.isEmpty ? "Student" : "Group")
    }

    /// Formats a CDStudent display name in "FirstName L." format,
    /// mirroring StudentFormatter.displayName for Core Data entities.
    private static func cdStudentDisplayName(_ student: CDStudent) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private static func isNonSchoolDay(
        _ date: Date, nonSchoolDaysSet: Set<Date>, schoolDayOverridesSet: Set<Date>
    ) -> Bool {
        let day = AppCalendar.startOfDay(date)
        if nonSchoolDaysSet.contains(day) { return true }
        let weekday = AppCalendar.shared.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }
        if schoolDayOverridesSet.contains(day) { return false }
        return true
    }

    private static func schoolDaysSince(_ start: Date, ctx: ComputeContext) -> Int {
        let startDay = AppCalendar.startOfDay(start)
        let today = AppCalendar.startOfDay(Date())
        let cal = AppCalendar.shared
        let daysBetween = cal.dateComponents([.day], from: startDay, to: today).day ?? 0

        if daysBetween > BatchingConstants.maxDaysToIterate {
            return BatchingConstants.maxDaysToIterate
        }
        if daysBetween <= 0 { return 0 }

        var count = 0
        var cursor = startDay
        while cursor < today {
            if !isNonSchoolDay(cursor, nonSchoolDaysSet: ctx.nonSchoolDaysSet,
                               schoolDayOverridesSet: ctx.schoolDayOverridesSet) {
                count += 1
            }
            cursor = AppCalendar.addingDays(1, to: cursor)

            // Safety limit should never be hit due to guard above, but keep as failsafe
            assert(count < BatchingConstants.maxDaysToIterate, "Date iteration safety limit exceeded")
            if count > BatchingConstants.maxDaysToIterate { break }
        }
        return max(0, count)
    }

    private static func computeBucket(
        days: Int, threshold: Int
    ) -> FollowUpInboxItem.Bucket? {
        if days > threshold { return .overdue }
        if days == threshold { return .dueToday }
        let until = max(0, threshold - days)
        if (1...2).contains(until) { return .upcoming }
        return nil
    }

    private static func formatStatusText(
        bucket: FollowUpInboxItem.Bucket, days: Int,
        threshold: Int, suffix: String
    ) -> String {
        switch bucket {
        case .overdue: return "Overdue • \(days)d \(suffix)"
        case .dueToday: return "Due Today • \(days)d \(suffix)"
        case .upcoming:
            let until = max(0, threshold - days)
            return "Due in \(until)d • \(days)d \(suffix)"
        case .inbox:
            return "Needs scheduling • \(days)d \(suffix)"
        }
    }

    /// Computes school days since the last meaningful touch on a CDWorkModel.
    /// Mirrors WorkAgingPolicy.lastMeaningfulTouchDate logic for Core Data entities.
    private static func daysSinceLastTouch(
        for work: CDWorkModel,
        checkIns: [CDWorkCheckIn],
        notes: [CDNote],
        ctx: ComputeContext
    ) -> Int {
        let today = AppCalendar.startOfDay(Date())

        // 1) Explicit lastTouchedAt (highest priority)
        if let lastTouched = work.lastTouchedAt {
            let start = AppCalendar.startOfDay(lastTouched)
            return schoolDaysSince(start, ctx: ctx)
        }

        // 2) Most recent past completed check-in date
        let pastCheckInDates: [Date] = checkIns
            .filter { $0.status == .completed }
            .compactMap { $0.date }
            .map { AppCalendar.startOfDay($0) }
            .filter { $0 <= today }
        let latestCheckIn = pastCheckInDates.max()

        // 3) Most recent note timestamp
        let latestNote: Date? = notes.map {
            let updated = $0.updatedAt ?? Date.distantPast
            let created = $0.createdAt ?? Date.distantPast
            return max(updated, created)
        }.max()

        // 4) Status change timestamp (completedAt)
        let statusChange: Date? = work.completedAt.map { AppCalendar.startOfDay($0) }

        // 5) Fallbacks
        let assigned = AppCalendar.startOfDay(work.assignedAt ?? work.createdAt ?? Date())

        let touchDate = latestCheckIn ?? latestNote ?? statusChange ?? assigned
        return schoolDaysSince(touchDate, ctx: ctx)
    }

    /// Resolves display fields (childID, childName, lessonTitle) for a CDWorkModel.
    /// Shared by Rules 2/3 and Rule 4 to avoid duplication.
    private static func resolveWorkDisplayFields(
        work: CDWorkModel, ctx: ComputeContext
    ) -> WorkDisplayFields {
        let participants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        let participantIDs: [UUID] = participants.compactMap {
            UUID(uuidString: $0.studentID)
        }
        let studentIDs: [UUID] = {
            if !participantIDs.isEmpty { return participantIDs }
            if let presIDString = work.presentationID,
               let presUUID = UUID(uuidString: presIDString),
               let la = ctx.lasByID[presUUID] {
                return la.studentUUIDs
            }
            return []
        }()
        let studentName: String = {
            if let firstID = studentIDs.first, let s = ctx.studentsByID[firstID] {
                return cdStudentDisplayName(s)
            }
            return "Student"
        }()
        let lessonTitle: String = {
            if let lessonUUID = UUID(uuidString: work.lessonID), let l = ctx.lessonsByID[lessonUUID] {
                return LessonFormatter.titleOrFallback(l.name, fallback: "Lesson")
            }
            let trimmed = work.title.trimmed()
            return !trimmed.isEmpty ? trimmed : "Work"
        }()
        return WorkDisplayFields(childID: studentIDs.first, childName: studentName, lessonTitle: lessonTitle)
    }

    private static func sortResults(_ results: [FollowUpInboxItem]) -> [FollowUpInboxItem] {
        results.sorted { lhs, rhs in
            if lhs.bucket != rhs.bucket { return lhs.bucket < rhs.bucket }
            if lhs.ageDays != rhs.ageDays { return lhs.ageDays > rhs.ageDays }
            if lhs.childName.caseInsensitiveCompare(rhs.childName) != .orderedSame {
                return lhs.childName.localizedCaseInsensitiveCompare(rhs.childName) == .orderedAscending
            }
            if lhs.title.caseInsensitiveCompare(rhs.title) != .orderedSame {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Rule 1: CDLesson Follow-Up

    private static func computeLessonFollowUpItems(
        ctx: ComputeContext, lessonAssignments: [CDLessonAssignment]
    ) -> [FollowUpInboxItem] {
        var results: [FollowUpInboxItem] = []
        let presented = lessonAssignments.filter { $0.isPresented || $0.presentedAt != nil }

        // Build lookup sets from WorkModels to exclude lessons with any follow-up work
        let workByPresID: Set<UUID> = Set(ctx.openWorkModels.compactMap {
            $0.presentationID.flatMap { UUID(uuidString: $0) }
        })
        let workByLessonKey: Set<String> = Set(ctx.openWorkModels.map { work in
            "\(work.studentID.lowercased())|\(work.lessonID.lowercased())"
        })

        for la in presented {
            guard let laID = la.id else { continue }
            let presentedDate = la.presentedAt ?? la.createdAt ?? Date()
            let days = schoolDaysSince(presentedDate, ctx: ctx)

            let hasFollowUpWork = workByPresID.contains(laID) ||
                la.studentUUIDs.map { sid in
                    "\(sid.uuidString.lowercased())|\(la.lessonID.lowercased())"
                }.contains(where: { workByLessonKey.contains($0) })
            guard !hasFollowUpWork else { continue }

            let threshold = ctx.constants.lessonFollowUpOverdueDays
            guard let bucket = computeBucket(days: days, threshold: threshold) else { continue }

            let lessonTitle: String = {
                if let lessonUUID = la.lessonIDUUID, let l = ctx.lessonsByID[lessonUUID] {
                    return LessonFormatter.titleOrFallback(l.name, fallback: "Lesson")
                }
                return "Lesson"
            }()
            let (cid, cname) = childDisplayName(for: la.studentUUIDs, studentsByID: ctx.studentsByID)
            let status = formatStatusText(
                bucket: bucket, days: days, threshold: threshold, suffix: "since presented"
            )
            results.append(FollowUpInboxItem(
                id: "lessonFollowUp:\(laID.uuidString)", underlyingID: laID,
                childID: cid, childName: cname, title: lessonTitle, kind: .lessonFollowUp,
                statusText: status, ageDays: days, bucket: bucket
            ))
        }
        return results
    }

    // MARK: - Rules 2/3: Work Check-In & Review Stale

    private static func computeWorkStaleItems(
        ctx: ComputeContext
    ) -> ([FollowUpInboxItem], Set<UUID>) {
        var results: [FollowUpInboxItem] = []
        var addedWorkIDs: Set<UUID> = []

        for work in ctx.openWorkModels {
            guard let workID = work.id else { continue }
            let status = work.status
            let isActive = status == .active
            let isReview = status == .review
            guard isActive || isReview else { continue }

            let workCheckIns = ctx.checkInsByWorkID[workID] ?? []
            let workNotes = ctx.notesByWorkID[workID] ?? []
            let days = daysSinceLastTouch(
                for: work,
                checkIns: workCheckIns, notes: workNotes,
                ctx: ctx
            )

            let threshold = isActive ? ctx.constants.workStaleOverdueDays : ctx.constants.reviewStaleDays
            guard let bucket = computeBucket(days: days, threshold: threshold) else { continue }

            let fields = resolveWorkDisplayFields(work: work, ctx: ctx)
            let kind: FollowUpInboxItem.Kind = isActive ? .workCheckIn : .workReview
            let statusText = formatStatusText(
                bucket: bucket, days: days, threshold: threshold, suffix: "since touched"
            )
            results.append(FollowUpInboxItem(
                id: "\(kind.rawValue):\(workID.uuidString)", underlyingID: workID,
                childID: fields.childID, childName: fields.childName, title: fields.lessonTitle, kind: kind,
                statusText: statusText, ageDays: days, bucket: bucket
            ))
            addedWorkIDs.insert(workID)
        }
        return (results, addedWorkIDs)
    }

    // MARK: - Rule 4: Unscheduled Open Work

    private static func computeUnscheduledWorkItems(
        ctx: ComputeContext, addedWorkIDs: Set<UUID>
    ) -> [FollowUpInboxItem] {
        var results: [FollowUpInboxItem] = []

        for work in ctx.openWorkModels {
            guard let workID = work.id else { continue }
            let status = work.status
            guard status == .active || status == .review else { continue }
            guard !addedWorkIDs.contains(workID) else { continue }

            let workCheckIns = ctx.checkInsByWorkID[workID] ?? []
            let hasScheduledCheckIns = workCheckIns.contains { $0.status == .scheduled }
            guard !hasScheduledCheckIns && work.dueAt == nil else { continue }

            let fields = resolveWorkDisplayFields(work: work, ctx: ctx)
            let days = daysSinceLastTouch(
                for: work,
                checkIns: workCheckIns, notes: [],
                ctx: ctx
            )
            let statusText = "Needs scheduling • \(days)d since touched"
            let kind: FollowUpInboxItem.Kind = status == .active ? .workCheckIn : .workReview
            results.append(FollowUpInboxItem(
                id: "inbox:\(workID.uuidString)", underlyingID: workID,
                childID: fields.childID, childName: fields.childName, title: fields.lessonTitle, kind: kind,
                statusText: statusText, ageDays: days, bucket: .inbox
            ))
        }
        return results
    }

    // MARK: - CDStudent-Scoped Computation

    /// Compute items scoped to a specific student.
    /// This is used by the student checklist tab to get work items for that student.
    static func computeItems(
        for studentID: UUID,
        lessons: [CDLesson],
        students: [CDStudent],
        lessonAssignments: [CDLessonAssignment],
        context: NSManagedObjectContext,
        constants: Constants = Constants()
    ) -> [FollowUpInboxItem] {
        // Get all items and filter by student
        let allItems = computeItems(
            lessons: lessons,
            students: students,
            lessonAssignments: lessonAssignments,
            context: context,
            constants: constants
        )

        // Filter to items for this student
        return allItems.filter { item in
            item.childID == studentID
        }
    }
}
