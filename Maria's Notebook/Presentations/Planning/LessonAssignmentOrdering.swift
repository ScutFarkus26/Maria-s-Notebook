// LessonAssignmentOrdering.swift
// The one comparison that decides the order of presentations within a day.
//
// `scheduledFor` carries the guide's dragged order as second-spaced times. Two
// things make a bare comparison on it unreliable: Swift's sort is not stable,
// and every row written before ordering existed still sits at midnight, so a
// whole day of legacy rows is a single tie. A tie that resolves differently on
// each refetch reads as the calendar shuffling itself.
//
// `createdAt` then `id` break the tie deterministically, so an untouched day
// keeps one order for good. The first drag on that day rewrites it properly.

import Foundation

enum LessonAssignmentOrdering {
    static func isOrderedBefore(_ lhs: CDLessonAssignment, _ rhs: CDLessonAssignment) -> Bool {
        let left = lhs.scheduledFor ?? .distantPast
        let right = rhs.scheduledFor ?? .distantPast
        if left != right { return left < right }

        let leftCreated = lhs.createdAt ?? .distantPast
        let rightCreated = rhs.createdAt ?? .distantPast
        if leftCreated != rightCreated { return leftCreated < rightCreated }

        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }
}
