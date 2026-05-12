// ParshaCoverageView.swift
// At-a-glance view of every parsha and how many lessons / presentations
// are tagged to it. Sortable to surface coverage gaps quickly.

import SwiftUI
import CoreData

struct ParshaCoverageView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)],
        predicate: NSPredicate(format: "parshaKey != nil AND parshaKey != %@", "")
    )
    private var taggedLessons: FetchedResults<CDLesson>

    @State private var sortMode: SortMode = .cycleOrder
    @State private var presentationCounts: [String: Int] = [:]

    private enum SortMode: String, CaseIterable, Identifiable {
        case cycleOrder = "Cycle Order"
        case mostCovered = "Most Covered"
        case gapsFirst = "Gaps First"
        var id: String { rawValue }
    }

    private struct CoverageRow: Identifiable {
        let parshaKey: String
        let lessonCount: Int
        let presentationCount: Int
        var id: String { parshaKey }
        var hasContent: Bool { lessonCount > 0 || presentationCount > 0 }
    }

    private var lessonCountsByParsha: [String: Int] {
        var counts: [String: Int] = [:]
        for lesson in taggedLessons {
            guard let key = lesson.parshaKey, !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return counts
    }

    private var rows: [CoverageRow] {
        let lessonCounts = lessonCountsByParsha
        let base = HebrewParshaService.allParshaKeys.map { key in
            CoverageRow(
                parshaKey: key,
                lessonCount: lessonCounts[key] ?? 0,
                presentationCount: presentationCounts[key] ?? 0
            )
        }
        switch sortMode {
        case .cycleOrder:
            return base
        case .mostCovered:
            return base.sorted {
                ($0.lessonCount, $0.presentationCount) > ($1.lessonCount, $1.presentationCount)
            }
        case .gapsFirst:
            return base.sorted {
                ($0.lessonCount, $0.presentationCount) < ($1.lessonCount, $1.presentationCount)
            }
        }
    }

    private var totalLessons: Int { taggedLessons.count }
    private var totalPresentations: Int { presentationCounts.values.reduce(0, +) }
    private var coveredParshas: Int { rows.filter(\.hasContent).count }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                Section {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach(rows) { row in
                        coverageRowLink(row)
                    }
                }
            }
            .navigationTitle("Parsha Coverage")
            .navigationDestination(for: Date.self) { date in
                ThisWeeksParshaView(forShabbat: date)
            }
            .navigationDestination(for: CDLesson.self) { lesson in
                LessonDetailView(lesson: lesson, onSave: { _ in })
            }
            .onAppear { recomputePresentationCounts() }
            .onChange(of: taggedLessons.count) { _, _ in recomputePresentationCounts() }
        }
    }

    @ViewBuilder
    private func coverageRowLink(_ row: CoverageRow) -> some View {
        if let nextDate = HebrewParshaService.nextShabbat(forParshaKey: row.parshaKey) {
            NavigationLink(value: nextDate) {
                CoverageRowView(
                    parshaKey: row.parshaKey,
                    lessonCount: row.lessonCount,
                    presentationCount: row.presentationCount
                )
            }
        } else {
            CoverageRowView(
                parshaKey: row.parshaKey,
                lessonCount: row.lessonCount,
                presentationCount: row.presentationCount
            )
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: AppTheme.Spacing.large) {
                summaryCell(value: "\(coveredParshas)/54", label: "Parshas covered")
                summaryCell(value: "\(totalLessons)", label: "Lessons")
                summaryCell(value: "\(totalPresentations)", label: "Presentations")
            }
            .padding(.vertical, AppTheme.Spacing.xsmall)
        }
    }

    private func summaryCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
            Text(value)
                .font(AppTheme.ScaledFont.titleMedium)
                .foregroundStyle(.primary)
            Text(label)
                .font(AppTheme.ScaledFont.captionSmall)
                .foregroundStyle(.secondary)
        }
    }

    private func recomputePresentationCounts() {
        var lessonIDtoKey: [String: String] = [:]
        for lesson in taggedLessons {
            if let id = lesson.id?.uuidString, let key = lesson.parshaKey, !key.isEmpty {
                lessonIDtoKey[id] = key
            }
        }
        let lessonIDs = Array(lessonIDtoKey.keys)
        guard !lessonIDs.isEmpty else {
            presentationCounts = [:]
            return
        }
        let req = CDFetchRequest(CDLessonAssignment.self)
        req.predicate = NSPredicate(
            format: "lessonID IN %@ AND stateRaw == %@",
            lessonIDs, LessonAssignmentState.presented.rawValue
        )
        let assignments: [CDLessonAssignment] = viewContext.safeFetch(req)
        var counts: [String: Int] = [:]
        for assignment in assignments {
            if let key = lessonIDtoKey[assignment.lessonID] {
                counts[key, default: 0] += 1
            }
        }
        presentationCounts = counts
    }
}

private struct CoverageRowView: View {
    let parshaKey: String
    let lessonCount: Int
    let presentationCount: Int

    private var hasContent: Bool { lessonCount > 0 || presentationCount > 0 }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Circle()
                .fill(hasContent ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(HebrewParshaService.displayName(forKey: parshaKey))
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(hasContent ? .primary : .secondary)
                if let metadata = ParshaMetadataService.metadata(forKey: parshaKey) {
                    Text(metadata.passageRange)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: AppTheme.Spacing.small) {
                if lessonCount > 0 {
                    Label("\(lessonCount)", systemImage: "book")
                        .labelStyle(.titleAndIcon)
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                }
                if presentationCount > 0 {
                    Label("\(presentationCount)", systemImage: "person.fill.checkmark")
                        .labelStyle(.titleAndIcon)
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.xxsmall)
    }
}
