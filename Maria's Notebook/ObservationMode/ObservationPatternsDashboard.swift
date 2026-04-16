// ObservationPatternsDashboard.swift
// Dashboard showing observation tag patterns over time per student.
// Fetches Notes containing Montessori observation tags and displays frequency charts.

import SwiftUI
import CoreData
import Charts

struct ObservationPatternsDashboard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = ObservationPatternsViewModel()

    var body: some View {
        content
            .navigationTitle("Observation Patterns")
            .onAppear { viewModel.loadData(context: viewContext) }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.tagCounts.isEmpty {
            emptyState
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Time range picker
                timeRangeRow
                    .padding(.horizontal)
                    .padding(.top, 12)

                // Summary
                summaryRow
                    .padding(.horizontal)

                // Observation coverage
                observationCoverageSection
                    .padding(.horizontal)

                // Tag frequency chart
                tagFrequencyChart
                    .padding(.horizontal)

                // Per-student breakdown
                studentBreakdown
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Time Range

    private var timeRangeRow: some View {
        HStack(spacing: 8) {
            ForEach(ObservationTimeRange.allCases) { range in
                timeRangeCapsule(range)
            }
            Spacer()
        }
    }

    private func timeRangeCapsule(_ range: ObservationTimeRange) -> some View {
        let isSelected = viewModel.timeRange == range
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.timeRange = range
                viewModel.loadData(context: viewContext)
            }
        } label: {
            Text(range.rawValue)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 0) {
            Text("\(viewModel.totalObservations)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(" observations · ")
                .foregroundStyle(.tertiary)
            Text("\(viewModel.studentsObserved)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text("/\(viewModel.totalEnrolled) students")
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Tag Frequency Chart

    private var tagFrequencyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tag Frequency")
                .font(.subheadline)
                .fontWeight(.semibold)

            Chart(viewModel.tagCounts, id: \.tagName) { item in
                BarMark(
                    x: .value("Count", item.count),
                    y: .value("Tag", item.tagName)
                )
                .foregroundStyle(item.color.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(position: .bottom)
            }
            .frame(height: CGFloat(viewModel.tagCounts.count) * 28 + 20)
        }
        .cardStyle()
    }

    // MARK: - CDStudent Breakdown

    private var studentBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By Student")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVStack(spacing: 8) {
                ForEach(viewModel.studentSummaries) { summary in
                    studentSummaryRow(summary)
                }
            }
        }
    }

    private func studentSummaryRow(_ summary: StudentObservationSummary) -> some View {
        HStack(spacing: 10) {
            Text(summary.initials)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(summary.levelColor.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                FlowLayout(spacing: 4) {
                    ForEach(summary.topTags, id: \.self) { tag in
                        let parsed = TagHelper.parseTag(tag)
                        Text(parsed.name)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(parsed.color.color.opacity(UIConstants.OpacityConstants.medium))
                            )
                    }
                }
            }

            Spacer()

            Text("\(summary.observationCount)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
        }
        .cardStyle()
    }

    // MARK: - Observation Coverage

    private var observationCoverageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Student Coverage", systemImage: "person.crop.rectangle.stack")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(viewModel.studentsObserved)/\(viewModel.totalEnrolled)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        viewModel.studentsObserved == viewModel.totalEnrolled
                            ? AppColors.success : AppColors.warning
                    )
            }

            let unobserved = viewModel.studentSummaries.filter { $0.observationCount == 0 }
            if unobserved.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                        .foregroundStyle(AppColors.success)
                    Text("All students observed this \(viewModel.timeRange.rawValue.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Not yet observed:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(unobserved) { student in
                        Text(student.name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(AppColors.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppColors.warning.opacity(UIConstants.OpacityConstants.light))
                            )
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Observations", systemImage: "eye")
        } description: {
            Text("Use the Observe tab to record Montessori observations. Patterns will appear here over time.")
        }
    }
}

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

        let descriptor = { let r = CDNote.fetchRequest() as! NSFetchRequest<CDNote>; r.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)]; return r }()
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
            context.safeFetch({ let r = CDStudent.fetchRequest() as! NSFetchRequest<CDStudent>; r.sortDescriptors = CDStudent.sortByName; return r }()).filterEnrolled()
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
