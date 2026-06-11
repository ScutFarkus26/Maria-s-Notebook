// ObservationPatternsDashboard.swift
// Dashboard showing observation tag patterns over time per student.
// Fetches Notes containing Montessori observation tags and displays frequency charts.

import SwiftUI
import CoreData
import Charts

// MARK: - Supporting Types

enum ObservationTimeRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"

    var id: String { rawValue }

    func dateRange(from now: Date) -> (start: Date, end: Date) {
        let calendar = AppCalendar.shared
        switch self {
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .month:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        case .quarter:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return (start, now)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return (start, now)
        }
    }
}

struct TagCount: Identifiable {
    let id = UUID()
    let tagName: String
    let count: Int
    let color: Color
}

struct StudentObservationSummary: Identifiable {
    let id: UUID
    let name: String
    let initials: String
    let levelColor: Color
    let observationCount: Int
    let topTags: [String]
}

// MARK: - ViewModel

@Observable
@MainActor
final class ObservationPatternsViewModel {
    private(set) var tagCounts: [TagCount] = []
    private(set) var studentSummaries: [StudentObservationSummary] = []
    private(set) var totalObservations: Int = 0
    private(set) var studentsObserved: Int = 0
    private(set) var totalEnrolled: Int = 0
    private(set) var isLoading = false
    var timeRange: ObservationTimeRange = .month

    func loadData(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }

        let allObservationTags = MontessoriObservationTags.allTags + DevelopmentalCharacteristic.allTags
        let range = timeRange.dateRange(from: Date())

        let descriptor = {
            let r = NSFetchRequest<CDNote>(entityName: "Note")
            r.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)]
            return r
        }()
        let observationNotes = context.safeFetch(descriptor).filter { note in
            guard let createdAt = note.createdAt else { return false }
            let tags = (note.tags as? [String]) ?? []
            return createdAt >= range.start && createdAt <= range.end
            && tags.contains { !TagHelper.tagName($0).isEmpty }
            && tags.contains { tag in
                let name = TagHelper.tagName(tag)
                return allObservationTags.contains { TagHelper.tagName($0) == name }
            }
        }

        totalObservations = observationNotes.count
        tagCounts = computeTagCounts(from: observationNotes, allTags: allObservationTags)

        let students = TestStudentsFilter.filterVisible(
            context.safeFetch({
                let r = NSFetchRequest<CDStudent>(entityName: "Student")
                r.sortDescriptors = CDStudent.sortByName
                return r
            }()).filterEnrolled()
        )
        let observationMap = buildStudentObservationMap(from: observationNotes)
        let summaries = buildStudentSummaries(
            map: observationMap,
            students: students,
            allTags: allObservationTags
        )
        studentSummaries = summaries.sorted { $0.observationCount > $1.observationCount }
        totalEnrolled = students.count
        studentsObserved = summaries.filter { $0.observationCount > 0 }.count
    }

    // MARK: - Private Helpers

    private func computeTagCounts(from notes: [CDNote], allTags: [String]) -> [TagCount] {
        var tagCountMap: [String: Int] = [:]
        for note in notes {
            for tag in (note.tags as? [String]) ?? [] {
                let name = TagHelper.tagName(tag)
                guard allTags.contains(where: { TagHelper.tagName($0) == name }) else { continue }
                tagCountMap[tag, default: 0] += 1
            }
        }
        return tagCountMap
            .map { tag, count in
                let parsed = TagHelper.parseTag(tag)
                return TagCount(tagName: parsed.name, count: count, color: parsed.color.color)
            }
            .sorted { $0.count > $1.count }
    }

    private func buildStudentObservationMap(from notes: [CDNote]) -> [UUID: [CDNote]] {
        var map: [UUID: [CDNote]] = [:]
        for note in notes {
            switch note.scope {
            case .all:
                break
            case .student(let studentID):
                map[studentID, default: []].append(note)
            case .students(let studentIDs):
                for studentID in studentIDs {
                    map[studentID, default: []].append(note)
                }
            }
        }
        return map
    }

    private func buildStudentSummaries(
        map: [UUID: [CDNote]],
        students: [CDStudent],
        allTags: [String]
    ) -> [StudentObservationSummary] {
        students.compactMap { student in
            guard let studentID = student.id else { return nil }
            let notes = map[studentID] ?? []
            var tagCounts: [String: Int] = [:]
            for note in notes {
                for tag in (note.tags as? [String]) ?? [] {
                    let tagName = TagHelper.tagName(tag)
                    guard allTags.contains(where: { TagHelper.tagName($0) == tagName }) else { continue }
                    tagCounts[tag, default: 0] += 1
                }
            }
            let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
            return StudentObservationSummary(
                id: studentID,
                name: "\(student.firstName) \(student.lastName)",
                initials: "\(student.firstName.prefix(1))\(student.lastName.prefix(1))",
                levelColor: AppColors.color(forLevel: student.level),
                observationCount: notes.count,
                topTags: topTags
            )
        }
    }
}
