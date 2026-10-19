// ClassGridRecallView.swift
// The Class Grid's Recall view (once Lesson Recall): this year's retention as
// tiles, retention by child, and the lessons due for a recall check, grouped
// by child, each collapsed to the furthest lesson in its sequence with
// "covers N". A list, not lit grid cells: what's due crosses areas. On the Mac
// and iPad the check sits beside the list; on the iPhone it opens as a sheet.
//
// The area menu, the search and the children filter narrow the queue; the
// retention numbers are the whole class's this year.

import CoreData
import SwiftUI

struct ClassGridRecallView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(ClassGridScope.self) private var scope
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var model = RecallQueueViewModel()
    /// The entry the side pane checks (Mac and iPad).
    @State private var selectedID: String?
    /// The entry the sheet checks (iPhone).
    @State private var sheetEntry: RecallQueueEntry?
    @State private var showsByChild = false

    private var isRegular: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private var sections: [RecallStudentSection] {
        RecallQueueFilter.sections(
            model.sections, area: scope.area, query: scope.searchText, childIDs: scope.childFilterIDs
        )
    }

    private var byChild: [RecallStudentRetention] {
        model.retentionByStudent.filter { row in
            guard !scope.childFilterIDs.isEmpty else { return true }
            return UUID(uuidString: row.id).map(scope.childFilterIDs.contains) ?? false
        }
    }

    var body: some View {
        content
            .onAppear(perform: reload)
            .sheet(item: $sheetEntry) { entry in
                RecallCheckSheet(entry: entry, studentName: studentName(for: entry)) { reload() }
            }
            .sheet(isPresented: $showsByChild) {
                NavigationStack {
                    List(byChild) { row in ClassGridRecallChildRow(row: row) }
                        .navigationTitle("By child")
                        .inlineNavigationTitle()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsByChild = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.summary?.hasAnything != true && !model.hasContent {
            ContentUnavailableView {
                Label("All caught up", systemImage: "checkmark.circle")
            } description: {
                Text("No recall checks recorded yet, and nothing is due right now.")
            }
        } else if isRegular {
            regularLayout
        } else {
            compactLayout
        }
    }

    // MARK: - Mac and iPad

    private var regularLayout: some View {
        let sections = sections
        let selected = selectedEntry(in: sections)
        return VStack(spacing: 0) {
            ClassGridRecallTiles(
                summary: model.summary, fadePercent: model.fadeOverSummerPercent,
                dueCount: sections.reduce(0) { $0 + $1.entries.count }, columns: 5
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            Divider()
            HStack(spacing: 0) {
                byChildColumn
                    .frame(width: 230)
                Divider()
                queue(sections, selectedID: selected?.id)
                    .frame(maxWidth: .infinity)
                Divider()
                Group {
                    if let selected {
                        RecallCheckForm(
                            entry: selected, studentName: studentName(for: selected),
                            onRecorded: { afterCheck(of: selected, in: sections) },
                            onSkip: { selectedID = next(after: selected, in: sections)?.id }
                        )
                        .id(selected.id)
                    } else {
                        Text("Pick a lesson from the list to check it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 380)
            }
        }
        .background(ChecklistGridMetrics.surface)
    }

    private var byChildColumn: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("BY CHILD")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
                if byChild.isEmpty {
                    Text("No checks recorded this year.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }
                ForEach(byChild) { row in
                    ClassGridRecallChildRow(row: row)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                }
            }
        }
    }

    private func queue(_ sections: [RecallStudentSection], selectedID: String?) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if sections.isEmpty {
                    Text(model.hasContent
                         ? "Nothing due matches. Try another area or search."
                         : "No lessons are due for a recall check right now.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(20)
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            Button { self.selectedID = entry.id } label: {
                                ClassGridRecallRow(entry: entry, isSelected: entry.id == selectedID)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        ClassGridRecallSectionHeader(section: section)
                    }
                }
            }
        }
        .contentMargins(.bottom, ChecklistStatusBar.gridBottomMargin(isRegular: true), for: .scrollContent)
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        let sections = sections
        let due = sections.reduce(0) { $0 + $1.entries.count }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("RETENTION THIS YEAR")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                ClassGridRecallTiles(
                    summary: model.summary, fadePercent: model.fadeOverSummerPercent, dueCount: nil, columns: 2
                )
                HStack(alignment: .firstTextBaseline) {
                    Text("DUE FOR A CHECK · \(due)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("By child") { showsByChild = true }
                        .font(.subheadline)
                        .disabled(byChild.isEmpty)
                }
                .padding(.horizontal, 4)
                .padding(.top, 6)
                VStack(spacing: 0) {
                    if sections.isEmpty {
                        Text("No lessons are due for a recall check right now.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(sections) { section in
                        ClassGridRecallSectionHeader(section: section)
                        ForEach(section.entries) { entry in
                            Button { sheetEntry = entry } label: {
                                ClassGridRecallRow(entry: entry, isSelected: false, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(ChecklistGridMetrics.surface)
                .clipShape(.rect(cornerRadius: 12))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.controlBackgroundColor())
        .quickCaptureButtonClearance()
    }

    // MARK: - Actions

    private func reload() {
        model.loadData(context: viewContext, schoolYearStore: dependencies.schoolYearStore)
    }

    /// The pane's entry: the one picked, or the first due.
    private func selectedEntry(in sections: [RecallStudentSection]) -> RecallQueueEntry? {
        let entries = sections.flatMap(\.entries)
        return entries.first { $0.id == selectedID } ?? entries.first
    }

    private func next(after entry: RecallQueueEntry, in sections: [RecallStudentSection]) -> RecallQueueEntry? {
        let entries = sections.flatMap(\.entries)
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return entries.first }
        return entries.indices.contains(index + 1) ? entries[index + 1] : entries.first
    }

    /// After a check is recorded its row falls away; the pane moves to the next one.
    private func afterCheck(of entry: RecallQueueEntry, in sections: [RecallStudentSection]) {
        let following = next(after: entry, in: sections)
        reload()
        selectedID = following?.id == entry.id ? nil : following?.id
    }

    private func studentName(for entry: RecallQueueEntry) -> String {
        model.sections.first { $0.id == entry.studentID }?.studentName ?? ""
    }
}
