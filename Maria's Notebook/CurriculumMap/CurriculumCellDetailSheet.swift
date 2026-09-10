// CurriculumCellDetailSheet.swift
// What a glyph stands for: the presentations, work, practice sessions,
// mastery marks and recall checks behind one cell (or one row, or one time
// bucket of a row). A presentation opens in PresentationDetailView, where its
// observation lives or can be written; work opens in WorkDetailView.
//
// A cell that is exactly one presentation and nothing else opens the
// presentation straight away — "tap a presented-never-chosen cell and I land
// on the presentation" — so the list only appears when there is a list.

import CoreData
import SwiftUI

/// Routing payload for the sheet; Identifiable so `.sheet(item:)` drives it.
struct CurriculumCellDetailTarget: Identifiable {
    let id = UUID()
    let studentID: UUID
    let studentName: String
    let title: String
    let lessonIDs: [UUID]
    /// Restrict to records dated inside this range (a tapped time bucket).
    let range: Range<Date>?
    let rangeLabel: String?
}

struct CurriculumCellDetailSheet: View {
    let target: CurriculumCellDetailTarget
    let store: CurriculumMapStore
    let onClose: () -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @State private var presentationToOpen: CDLessonAssignment?
    @State private var workToOpen: WorkTarget?

    private struct WorkTarget: Identifiable {
        let id: UUID
    }
    @State private var openedLonePresentation = false

    private var lessonSet: Set<UUID> { Set(target.lessonIDs) }
    private var lessonName: (UUID) -> String {
        { id in store.lesson(id)?.name ?? "Lesson" }
    }

    var body: some View {
        NavigationStack {
            List {
                if presentations.isEmpty && works.isEmpty && practice.isEmpty && recalls.isEmpty && masteries.isEmpty {
                    ContentUnavailableView(
                        "Nothing recorded",
                        systemImage: "circle.dotted",
                        description: Text(emptyDescription)
                    )
                } else {
                    presentationSection
                    masterySection
                    workSection
                    practiceSection
                    recallSection
                }
            }
            .navigationTitle(target.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onClose() }
                }
            }
            .safeAreaInset(edge: .top) { header }
        }
        .sheet(item: $presentationToOpen) { assignment in
            PresentationDetailView(lessonAssignment: assignment) { presentationToOpen = nil }
                .studentDetailSheetSizing()
        }
        .sheet(item: $workToOpen) { work in
            WorkDetailView(workID: work.id) { workToOpen = nil }
                .studentDetailSheetSizing()
        }
        .onAppear(perform: openLonePresentationIfAny)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(target.studentName)
                .font(.subheadline.weight(.semibold))
            if let rangeLabel = target.rangeLabel {
                Text("·").foregroundStyle(.tertiary)
                Text(rangeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var emptyDescription: String {
        target.rangeLabel.map { "No presentation, work, or practice for \(target.title) in \($0)." }
            ?? "No presentation, work, or practice for \(target.title) yet."
    }

    // MARK: - Evidence

    private func inRange(_ date: Date?) -> Bool {
        guard let range = target.range else { return true }
        guard let date else { return false }
        return range.contains(date)
    }

    private var presentations: [CurriculumPresentationRef] {
        (store.input?.presentations ?? [])
            .filter { lessonSet.contains($0.lessonID) && $0.studentIDs.contains(target.studentID) }
            .filter { target.range == nil || inRange($0.presentedAt) }
            .sorted { ($0.presentedAt ?? .distantPast) > ($1.presentedAt ?? .distantPast) }
    }

    private var masteries: [CurriculumMasteryRef] {
        (store.input?.masteries ?? [])
            .filter { lessonSet.contains($0.lessonID) && $0.studentID == target.studentID && $0.isMastered }
            .filter { target.range == nil || inRange($0.masteredAt ?? $0.lastObservedAt) }
    }

    private var works: [CurriculumWorkRef] {
        (store.input?.work ?? [])
            .filter { lessonSet.contains($0.lessonID) && $0.studentIDs.contains(target.studentID) }
            .filter { work in
                target.range == nil
                    || inRange(work.assignedAt) || inRange(work.completedAt) || inRange(work.lastTouchedAt)
            }
            .sorted { ($0.assignedAt ?? .distantPast) > ($1.assignedAt ?? .distantPast) }
    }

    private var practice: [CurriculumPracticeRef] {
        guard let input = store.input else { return [] }
        let lessonByWork: [UUID: UUID] = Dictionary(
            input.work.map { ($0.id, $0.lessonID) }, uniquingKeysWith: { first, _ in first }
        )
        return input.practice
            .filter { session in
                session.studentIDs.contains(target.studentID)
                    && session.workIDs.contains { lessonByWork[$0].map(lessonSet.contains) ?? false }
            }
            .filter { target.range == nil || inRange($0.date) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var recalls: [CurriculumRecallRef] {
        (store.input?.recalls ?? [])
            .filter { lessonSet.contains($0.lessonID) && $0.studentID == target.studentID }
            .filter { target.range == nil || inRange($0.checkedAt) }
            .sorted { ($0.checkedAt ?? .distantPast) > ($1.checkedAt ?? .distantPast) }
    }

    // MARK: - Sections

    @ViewBuilder
    private var presentationSection: some View {
        if !presentations.isEmpty {
            Section("Presentations") {
                ForEach(presentations) { presentation in
                    Button {
                        open(presentationID: presentation.id)
                    } label: {
                        row(
                            icon: "checkmark.circle",
                            title: lessonName(presentation.lessonID),
                            detail: presentation.presentedAt.map { DateFormatters.mediumDate.string(from: $0) }
                                ?? "previously presented, date not recorded",
                            trailing: observationSummary(for: presentation.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the presentation and its observation")
                }
            }
        }
    }

    @ViewBuilder
    private var masterySection: some View {
        if !masteries.isEmpty {
            Section("Mastery") {
                ForEach(masteries) { mastery in
                    row(
                        icon: "checkmark.seal.fill",
                        title: lessonName(mastery.lessonID),
                        detail: mastery.masteredAt.map { "mastered \(DateFormatters.mediumDate.string(from: $0))" }
                            ?? "marked mastered",
                        trailing: nil
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var workSection: some View {
        if !works.isEmpty {
            Section("Work") {
                ForEach(works) { work in
                    Button {
                        workToOpen = WorkTarget(id: work.id)
                    } label: {
                        row(
                            icon: "tray.full",
                            title: lessonName(work.lessonID),
                            detail: [
                                work.assignedAt.map { "assigned \(DateFormatters.mediumDate.string(from: $0))" },
                                WorkStatus(rawValue: work.statusRaw)?.displayName.lowercased()
                            ].compactMap { $0 }.joined(separator: " · "),
                            trailing: nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the work item")
                }
            }
        }
    }

    @ViewBuilder
    private var practiceSection: some View {
        if !practice.isEmpty {
            Section("Practice sessions") {
                ForEach(practice) { session in
                    row(
                        icon: "pencil.circle",
                        title: session.date.map { DateFormatters.mediumDate.string(from: $0) } ?? "undated",
                        detail: session.studentIDs.count > 1
                            ? "with \(session.studentIDs.count - 1) other\(session.studentIDs.count == 2 ? "" : "s")"
                            : "alone",
                        trailing: nil
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var recallSection: some View {
        if !recalls.isEmpty {
            Section("Recall checks") {
                ForEach(recalls) { recall in
                    row(
                        icon: "arrow.clockwise.circle",
                        title: lessonName(recall.lessonID),
                        detail: [
                            recall.checkedAt.map { DateFormatters.mediumDate.string(from: $0) },
                            recall.outcome.rawValue
                        ].compactMap { $0 }.joined(separator: " · "),
                        trailing: nil
                    )
                    .foregroundStyle(CurriculumCellGlyph.color(for: recall.outcome))
                }
            }
        }
    }

    private func row(icon: String, title: String, detail: String, trailing: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Opening Records

    private func observationSummary(for presentationID: UUID) -> String {
        guard let assignment = viewContext.object(CDLessonAssignment.self, id: presentationID) else { return "" }
        let notes = ((assignment.unifiedNotes?.allObjects as? [CDNote]) ?? [])
            .filter { $0.scope.applies(to: target.studentID) && !$0.body.trimmed().isEmpty }
        return notes.isEmpty ? "no observation yet" : "\(notes.count) observation\(notes.count == 1 ? "" : "s")"
    }

    private func open(presentationID: UUID) {
        presentationToOpen = viewContext.object(CDLessonAssignment.self, id: presentationID)
    }

    /// The acceptance case: one presentation, nothing else — land on it.
    private func openLonePresentationIfAny() {
        guard !openedLonePresentation else { return }
        openedLonePresentation = true
        guard presentations.count == 1, works.isEmpty, practice.isEmpty, masteries.isEmpty, recalls.isEmpty,
              let only = presentations.first else { return }
        open(presentationID: only.id)
    }
}
