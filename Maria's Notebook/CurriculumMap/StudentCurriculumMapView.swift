// StudentCurriculumMapView.swift
// The Three-Year View for one child: the curriculum down the side, her years
// in the environment across the top, and a glyph wherever a record says
// something happened. The Great Lessons come first because they are the spine
// of the plane; every area follows, expandable to its sequences and key
// lessons. An area with no presentation in a while carries a soft flag —
// "she has not been in biology since spring" is the whole point.
//
// Nothing here judges. The grid reports presence and absence of records.

import CoreData
import SwiftUI

struct StudentCurriculumMapView: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext
    @State private var store = CurriculumMapStore()
    @State private var model = StudentCurriculumMapModel()
    @State private var settings = CurriculumMapSettings()
    @AppStorage(UserDefaultsKeys.curriculumMapZoom)
    private var zoomRaw = CurriculumZoom.years.rawValue
    @AppStorage(UserDefaultsKeys.curriculumMapGranularity)
    private var granularityRaw = CurriculumGranularity.keyLessons.rawValue
    @State var detailTarget: CurriculumCellDetailTarget?

    var zoom: CurriculumZoom { CurriculumZoom(rawValue: zoomRaw) ?? .years }
    var granularity: CurriculumGranularity {
        CurriculumGranularity(rawValue: granularityRaw) ?? .keyLessons
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .task(id: student.id) {
            await store.load(from: viewContext)
            rebuild()
        }
        .task { await watchForChanges() }
        .onChange(of: store.loadedAt) { _, _ in rebuild() }
        .onChange(of: zoomRaw) { _, _ in rebuild() }
        .onChange(of: granularityRaw) { _, _ in rebuild() }
        .onChange(of: settings.defaultUntouchedDays) { _, _ in rebuild() }
        .sheet(item: $detailTarget) { target in
            CurriculumCellDetailSheet(target: target, store: store) { detailTarget = nil }
                .studentDetailSheetSizing()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                yearBadge
                Spacer()
                Picker("Zoom", selection: $zoomRaw) {
                    ForEach(CurriculumZoom.allCases) { zoom in
                        Text(zoom.label).tag(zoom.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
                Menu {
                    Picker("Rows", selection: $granularityRaw) {
                        Text(CurriculumGranularity.keyLessons.label).tag(CurriculumGranularity.keyLessons.rawValue)
                        Text(CurriculumGranularity.allLessons.label).tag(CurriculumGranularity.allLessons.rawValue)
                    }
                    Divider()
                    Button("Expand All Areas") { model.expandAll() }
                    Button("Collapse All Areas") { model.collapseAll() }
                    Divider()
                    untouchedDefaultMenu
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
                }
                .help("Rows, expansion, and the untouched threshold")
            }
            HStack(spacing: 12) {
                CurriculumLegend()
                Spacer()
                if model.untouchedAreaCount > 0 {
                    Label(
                        "\(model.untouchedAreaCount) untouched area\(model.untouchedAreaCount == 1 ? "" : "s")",
                        systemImage: "moon.zzz.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var untouchedDefaultMenu: some View {
        Menu("Flag Areas Untouched After…") {
            ForEach(CurriculumMapSettings.untouchedChoices, id: \.self) { days in
                Button {
                    settings.defaultUntouchedDays = days
                } label: {
                    if days == settings.defaultUntouchedDays {
                        Label("\(days) days", systemImage: "checkmark")
                    } else {
                        Text("\(days) days")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var yearBadge: some View {
        if let timeline = model.timeline {
            HStack(spacing: 8) {
                Text(CurriculumTimeline.yearBadge(timeline.currentYear))
                    .font(.headline)
                if timeline.currentYear > CurriculumTimeline.cycleYears {
                    Text("stayed")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(UIConstants.OpacityConstants.medium), in: Capsule())
                }
                if timeline.anchorIsEstimated {
                    Label(
                        "No start date on file — years counted from her first record",
                        systemImage: "exclamationmark.triangle"
                    )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Set the start date on the Overview tab so the year bands are right")
                } else {
                    Text("started \(DateFormatters.mediumDate.string(from: timeline.anchor))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.isLoading, model.rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let timeline = model.timeline, !model.rows.isEmpty {
            StudentCurriculumGrid(
                rows: model.rows,
                timeline: timeline,
                settings: settings,
                onToggleArea: { area in model.toggle(area: area) },
                onOpen: { row, column in open(row: row, column: column) },
                onSetUntouched: { area, days in
                    settings.setUntouchedDays(days, for: area)
                    rebuild()
                }
            )
        } else {
            ContentUnavailableView(
                "No curriculum yet",
                systemImage: "square.grid.3x3",
                description: Text("Add lessons to the curriculum and this view fills in as they are given.")
            )
        }
    }

    // MARK: - Actions

    func rebuild() {
        guard let studentID = student.id else { return }
        model.rebuild(
            studentID: studentID, store: store, settings: settings, zoom: zoom, granularity: granularity
        )
    }

    private func open(row: CurriculumRow, column: CurriculumColumn?) {
        guard let studentID = student.id, !row.lessonIDs.isEmpty else { return }
        detailTarget = CurriculumCellDetailTarget(
            studentID: studentID,
            studentName: student.fullName,
            title: row.title,
            lessonIDs: row.lessonIDs,
            range: column.map { $0.start..<$0.end },
            rangeLabel: column?.detail
        )
    }

    /// Any save touching a watched entity, or a CloudKit remote change,
    /// reloads the snapshot — debounced in the store.
    private func watchForChanges() async {
        let saves = NotificationCenter.default
            .notifications(named: NSManagedObjectContext.didSaveObjectIDsNotification)
            .map { CurriculumMapStore.watchedEntities(in: $0) }
        for await names in saves where !names.isEmpty {
            store.scheduleReload(from: viewContext)
        }
    }
}
