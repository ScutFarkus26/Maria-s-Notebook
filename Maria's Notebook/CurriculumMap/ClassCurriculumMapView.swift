// ClassCurriculumMapView.swift
// The class heat map of the Three-Year View. Pick an area to see its
// sequences and key lessons against every child; leave it on "All areas" for
// the Great Lessons and one row per area. Tap a lesson's name for the children
// in each state and a button that turns the not-yet-presented set into a
// draft presentation.

import CoreData
import SwiftUI

struct ClassCurriculumMapView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    @State private var store = CurriculumMapStore()
    @State private var model = ClassCurriculumMapModel()
    @AppStorage(UserDefaultsKeys.curriculumMapGranularity)
    private var granularityRaw = CurriculumGranularity.keyLessons.rawValue
    @State private var area: String?
    @State private var sequence: String?
    @State private var stateFilter: CurriculumCellState?
    @State private var rowTarget: ClassRow?
    @State private var cellTarget: CurriculumCellDetailTarget?
    @State private var draftToOpen: CDLessonAssignment?

    private var granularity: CurriculumGranularity {
        CurriculumGranularity(rawValue: granularityRaw) ?? .keyLessons
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .navigationTitle("Three-Year View")
        .task {
            await store.load(from: viewContext)
            rebuild()
        }
        .task { await watchForChanges() }
        .onChange(of: store.loadedAt) { _, _ in rebuild() }
        .onChange(of: area) { _, _ in
            sequence = nil
            rebuild()
        }
        .onChange(of: sequence) { _, _ in rebuild() }
        .onChange(of: granularityRaw) { _, _ in rebuild() }
        .onChange(of: stateFilter) { _, _ in rebuild() }
        .sheet(item: $rowTarget) { row in
            ClassCurriculumRowSheet(row: row, model: model, onPlan: plan(lessonID:students:)) { rowTarget = nil }
                .studentDetailSheetSizing()
        }
        .sheet(item: $cellTarget) { target in
            CurriculumCellDetailSheet(target: target, store: store) { cellTarget = nil }
                .studentDetailSheetSizing()
        }
        .sheet(item: $draftToOpen) { draft in
            PresentationDetailView(lessonAssignment: draft) { draftToOpen = nil }
                .studentDetailSheetSizing()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Menu {
                    Button("All areas") { area = nil }
                    Divider()
                    ForEach(model.areas, id: \.self) { name in
                        Button(name) { area = name }
                    }
                } label: {
                    Label(area ?? "All areas", systemImage: "square.grid.2x2")
                }
                if area != nil, !model.sequences.isEmpty {
                    Menu {
                        Button("All sequences") { sequence = nil }
                        Divider()
                        ForEach(model.sequences, id: \.self) { name in
                            Button(name.isEmpty ? "Other" : name) { sequence = name }
                        }
                    } label: {
                        Label(
                            sequence.map { $0.isEmpty ? "Other" : $0 } ?? "All sequences",
                            systemImage: "list.bullet.indent"
                        )
                    }
                }
                Spacer()
                if area != nil {
                    Picker("Rows", selection: $granularityRaw) {
                        Text(CurriculumGranularity.keyLessons.label).tag(CurriculumGranularity.keyLessons.rawValue)
                        Text(CurriculumGranularity.allLessons.label).tag(CurriculumGranularity.allLessons.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                Menu {
                    Button("Any state") { stateFilter = nil }
                    Divider()
                    ForEach(CurriculumCellState.allCases, id: \.rawValue) { state in
                        Button(state.label) { stateFilter = state }
                    }
                } label: {
                    Label(stateFilter.map { "Rows with a child \($0.label.lowercased())" } ?? "Any state",
                          systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            HStack {
                CurriculumLegend()
                Spacer()
                Text("\(model.columns.count) children, oldest cohort first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.isLoading, model.rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.columns.isEmpty {
            ContentUnavailableView("No enrolled students", systemImage: "person.3")
        } else if model.rows.isEmpty {
            ContentUnavailableView(
                "Nothing to show",
                systemImage: "square.grid.3x3",
                description: Text("No row has a child in that state.")
            )
        } else {
            ClassCurriculumGrid(
                rows: model.rows,
                columns: model.columns,
                onRow: { rowTarget = $0 },
                onCell: { row, column in
                    cellTarget = CurriculumCellDetailTarget(
                        studentID: column.student.id, studentName: column.student.fullName,
                        title: row.title, lessonIDs: row.lessonIDs, range: nil, rangeLabel: nil
                    )
                },
                onStudent: { AppRouter.shared.requestOpenStudentDetail($0.student.id) }
            )
        }
    }

    // MARK: - Actions

    private func rebuild() {
        model.rebuild(
            store: store, area: area, sequence: sequence, granularity: granularity, stateFilter: stateFilter
        )
    }

    /// The in-app twin of handing names to `schedule_presentation`: a draft
    /// presentation for the children who have not had the lesson, made the
    /// way the student detail makes one, opened for the guide to schedule.
    private func plan(lessonID: UUID, students: [CurriculumStudentRef]) {
        guard let lesson = viewContext.object(CDLesson.self, id: lessonID) else { return }
        let cdStudents = students.compactMap { viewContext.object(CDStudent.self, id: $0.id) }
        guard !cdStudents.isEmpty else { return }
        let draft = PresentationFactory.makeDraft(lesson: lesson, students: cdStudents, context: viewContext)
        draft.syncSnapshotsFromRelationships()
        saveCoordinator.save(viewContext, reason: "Draft presentation from the Three-Year View")
        rowTarget = nil
        draftToOpen = draft
    }

    private func watchForChanges() async {
        let saves = NotificationCenter.default
            .notifications(named: NSManagedObjectContext.didSaveObjectIDsNotification)
            .map { CurriculumMapStore.watchedEntities(in: $0) }
        for await names in saves where !names.isEmpty {
            store.scheduleReload(from: viewContext)
        }
    }
}

// MARK: - Grid

private struct ClassCurriculumGrid: View {
    let rows: [ClassRow]
    let columns: [ClassColumn]
    let onRow: (ClassRow) -> Void
    let onCell: (ClassRow, ClassColumn) -> Void
    let onStudent: (ClassColumn) -> Void

    private let labelWidth: CGFloat = 260
    private let columnWidth: CGFloat = 60
    private let headerHeight: CGFloat = 56

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rows) { row in
                        gridRow(row)
                    }
                } header: {
                    header
                }
            }
            .frame(minWidth: labelWidth + CGFloat(columns.count) * columnWidth, alignment: .leading)
        }
        .coordinateSpace(name: "gridSpace")
    }

    private var header: some View {
        HStack(spacing: 0) {
            StickyLeftItem(width: labelWidth, height: headerHeight) {
                ZStack {
                    Color.clear.backgroundPlatform()
                    Text("Lessons \\ Children")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: labelWidth, height: headerHeight)
                .borderSeparated()
            }
            .zIndex(100)
            ForEach(columns) { column in
                Button {
                    onStudent(column)
                } label: {
                    VStack(spacing: 2) {
                        Text(column.shortName)
                            .font(.caption.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                        Text(column.badge)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: columnWidth, height: headerHeight)
                    .background(cohortTint(column.year))
                    .backgroundPlatform()
                    .borderSeparated()
                }
                .buttonStyle(.plain)
                .help("\(column.student.fullName) — \(column.badge). Opens her record.")
            }
        }
        .zIndex(100)
    }

    private func cohortTint(_ year: Int) -> Color {
        Color.accentColor.opacity(Double(min(year, 4)) * UIConstants.OpacityConstants.hint)
    }

    private func rowHeight(_ row: ClassRow) -> CGFloat {
        switch row.kind {
        case .greatLessonsHeader, .area, .sequence: 34
        case .greatLesson, .lesson: 30
        }
    }

    @ViewBuilder
    private func rowBand(_ row: ClassRow) -> some View {
        switch row.kind {
        case .greatLessonsHeader, .area, .sequence:
            row.tint.opacity(UIConstants.OpacityConstants.veryFaint)
        case .greatLesson, .lesson:
            Color.clear
        }
    }

    private func gridRow(_ row: ClassRow) -> some View {
        let height = rowHeight(row)
        return HStack(spacing: 0) {
            StickyLeftItem(width: labelWidth, height: height) {
                labelCell(row, height: height)
            }
            ForEach(columns) { column in
                let glyph = row.cells[column.id]
                Button {
                    onCell(row, column)
                } label: {
                    ZStack {
                        rowBand(row)
                        cohortTint(column.year)
                        CurriculumCellGlyph(
                            state: glyph?.state ?? .notPresented, recall: glyph?.recall, tint: row.tint, size: 11
                        )
                    }
                    .frame(width: columnWidth, height: height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(row.lessonIDs.isEmpty)
                .borderSeparated()
                .accessibilityLabel("\(column.student.fullName), \(row.title)")
                .accessibilityValue(
                    CurriculumCellGlyph.label(state: glyph?.state ?? .notPresented, recall: glyph?.recall)
                )
            }
        }
    }

    private func labelCell(_ row: ClassRow, height: CGFloat) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(row.tint)
                .frame(width: 3, height: height - 12)
                .opacity(row.depth == 0 ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(row.depth == 0
                          ? .system(.subheadline, design: .rounded).weight(.bold)
                          : .system(.footnote, design: .rounded))
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if !row.lessonIDs.isEmpty {
                Text("\(row.counts[.notPresented] ?? 0) not yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Children with no presentation on this row")
            }
        }
        .padding(.leading, 8 + CGFloat(row.depth) * 14)
        .padding(.trailing, 8)
        .frame(width: labelWidth, height: height, alignment: .leading)
        .background(rowBand(row))
        .backgroundPlatform()
        .borderSeparated()
        .contentShape(Rectangle())
        .onTapGesture {
            if !row.lessonIDs.isEmpty { onRow(row) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the children in each state")
    }
}
