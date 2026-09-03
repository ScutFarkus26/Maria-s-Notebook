import CoreData
import Foundation

struct FollowingPresentationChild: Identifiable {
    let row: CDLessonPresentation
    let studentName: String

    var id: NSManagedObjectID { row.objectID }
}

struct FollowingPresentationGroup: Identifiable {
    let id: UUID
    let assignment: CDLessonAssignment?
    let lessonName: String
    let presentedAt: Date
    let children: [FollowingPresentationChild]
    let schoolDaysSincePresentation: Int

    var earliestReviewAt: Date? {
        children.compactMap { $0.row.followUpReviewAt }.min()
    }

    var actionSummary: String {
        let actions = Set(children.compactMap { $0.row.followUpAction })
        return actions.count == 1
            ? (actions.first?.shortTitle ?? "Keep Watching")
            : "Individual Follow-Up"
    }

    var childNames: String {
        children.map(\.studentName).joined(separator: ", ")
    }
}

@MainActor
enum FollowingPresentationsService {
    static func groups(
        rows: [CDLessonPresentation],
        assignments: [CDLessonAssignment],
        lessons: [CDLesson],
        students: [CDStudent],
        studentID: UUID? = nil,
        searchText: String = "",
        searchTokens: [String] = [],
        context: NSManagedObjectContext,
        asOf date: Date = Date()
    ) -> [FollowingPresentationGroup] {
        let assignmentByID = Dictionary(
            assignments.compactMap { assignment in
                assignment.id.map { ($0, assignment) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let lessonByID = Dictionary(
            lessons.compactMap { lesson in lesson.id.map { ($0, lesson) } },
            uniquingKeysWith: { first, _ in first }
        )
        let studentByID = Dictionary(
            students.compactMap { student in student.id.map { ($0, student) } },
            uniquingKeysWith: { first, _ in first }
        )

        let openRows = deduplicated(rows).filter { row in
            guard row.hasOpenFollowUp else { return false }
            if let studentID {
                return row.studentID == studentID.uuidString
            }
            return true
        }
        let grouped = Dictionary(grouping: openRows) { row in
            row.presentationID ?? "row:\(row.id?.uuidString ?? row.objectID.uriRepresentation().absoluteString)"
        }

        let normalizedSearch = searchText.trimmed().lowercased()
        let normalizedTokens = searchTokens.map { $0.trimmed().lowercased() }.filter { !$0.isEmpty }

        return grouped.compactMap { key, groupRows -> FollowingPresentationGroup? in
            guard let first = groupRows.first else { return nil }
            let presentationID = first.presentationID.flatMap(UUID.init(uuidString:))
            let assignment = presentationID.flatMap { assignmentByID[$0] }
            let lessonID = UUID(uuidString: first.lessonID) ?? assignment?.lessonIDUUID
            let lessonName = lessonID.flatMap { lessonByID[$0]?.name }
                ?? assignment?.lessonTitleSnapshot
                ?? "Lesson"
            let presentedAt = groupRows.compactMap(\.presentedAt).min()
                ?? assignment?.presentedAt
                ?? first.createdAt
                ?? date
            let children = groupRows.compactMap { row -> FollowingPresentationChild? in
                guard let id = UUID(uuidString: row.studentID) else { return nil }
                let name = studentByID[id].map(StudentFormatter.displayName(for:)) ?? "Child"
                return FollowingPresentationChild(row: row, studentName: name)
            }
            .sorted { $0.studentName.localizedCaseInsensitiveCompare($1.studentName) == .orderedAscending }
            guard !children.isEmpty else { return nil }

            let id = presentationID ?? first.id ?? UUID()
            let age = LessonAgeHelper.schoolDaysSinceCreation(
                createdAt: presentedAt,
                asOf: date,
                using: context
            )
            let result = FollowingPresentationGroup(
                id: id,
                assignment: assignment,
                lessonName: lessonName,
                presentedAt: presentedAt,
                children: children,
                schoolDaysSincePresentation: age
            )
            let haystack = "\(lessonName) \(result.childNames) \(result.actionSummary)".lowercased()
            guard normalizedSearch.isEmpty || haystack.contains(normalizedSearch) else { return nil }
            guard normalizedTokens.allSatisfy(haystack.contains) else { return nil }
            return result
        }
        .sorted(by: sortGroups)
    }

    /// Cloud sync can briefly leave more than one physical row for the same
    /// child and presentation. Keep the newest logical row so the guide never
    /// sees the same child twice or an older unresolved state.
    private static func deduplicated(
        _ rows: [CDLessonPresentation]
    ) -> [CDLessonPresentation] {
        var seenStableIDs = Set<String>()
        var seenLogicalKeys = Set<String>()

        return rows.sorted(by: isNewer).filter { row in
            let stableID = row.id?.uuidString
                ?? row.objectID.uriRepresentation().absoluteString
            let presentationKey = row.presentationID ?? "row:\(stableID)"
            let logicalKey = "\(presentationKey)|\(row.studentID)"
            return seenStableIDs.insert(stableID).inserted
                && seenLogicalKeys.insert(logicalKey).inserted
        }
    }

    private static func isNewer(
        _ lhs: CDLessonPresentation,
        _ rhs: CDLessonPresentation
    ) -> Bool {
        let leftDate = lhs.followUpUpdatedAt
            ?? lhs.lastObservedAt
            ?? lhs.presentedAt
            ?? lhs.createdAt
            ?? .distantPast
        let rightDate = rhs.followUpUpdatedAt
            ?? rhs.lastObservedAt
            ?? rhs.presentedAt
            ?? rhs.createdAt
            ?? .distantPast
        if leftDate != rightDate { return leftDate > rightDate }
        let leftID = lhs.id?.uuidString ?? lhs.objectID.uriRepresentation().absoluteString
        let rightID = rhs.id?.uuidString ?? rhs.objectID.uriRepresentation().absoluteString
        return leftID < rightID
    }

    private static func sortGroups(
        _ lhs: FollowingPresentationGroup,
        _ rhs: FollowingPresentationGroup
    ) -> Bool {
        switch (lhs.earliestReviewAt, rhs.earliestReviewAt) {
        case let (left?, right?):
            if left != right { return left < right }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        if lhs.presentedAt != rhs.presentedAt { return lhs.presentedAt < rhs.presentedAt }
        return lhs.lessonName.localizedCaseInsensitiveCompare(rhs.lessonName) == .orderedAscending
    }
}
