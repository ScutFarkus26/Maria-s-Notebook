// ClassGridChildrenView.swift
// The Class Grid's Children view (once the Progress Dashboard): one row per
// child, grouped by level, and every sequence she has started as a strip of
// the Checklist's marks in lesson order with "4/8". Clicking a strip opens the
// sequence sheet (Work, Presentations, Notes). The area menu narrows the
// strips to one area; the search finds children by name.

import CoreData
import SwiftUI

struct ClassGridChildrenView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(ClassGridScope.self) private var scope
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var model = ClassGridChildrenModel()
    @State private var detailTarget: StudentSequenceDetailTarget?
    /// The iPhone's open cards; the first opens on its own.
    @State private var expandedIDs: Set<UUID> = []
    @State private var reloadDebounceTask: Task<Void, Never>?

    /// What the view reloads on: presentations and work, the mastery marks
    /// "Mastered" is read from (`mark_mastered`, a checklist or synced mark),
    /// and lessons (a rename, a lesson moved to another sequence).
    static let reloadEntityNames: Set<String> = ["LessonAssignment", "WorkModel", "LessonPresentation", "Lesson"]

    private var isRegular: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private var groups: [ClassGridChildrenModel.LevelGroup] {
        model.groups(area: scope.area, query: scope.searchText, childIDs: scope.childFilterIDs)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            if isRegular {
                Divider()
                footer
            }
        }
        .onAppear { load() }
        .onPresentationDataChangeWhenVisible(of: Self.reloadEntityNames, in: viewContext, catchUpOnAppear: false) {
            // A CloudKit import or a bulk edit lands as several saves back to back;
            // one reload 250 ms after the last.
            reloadDebounceTask?.cancel()
            reloadDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                load()
            }
        }
        .sheet(item: $detailTarget) { target in
            StudentSequenceDetailSheet(target: target) { detailTarget = nil }
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizingFitted()
                #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }

    private func load() {
        model.loadData(context: viewContext)
        if expandedIDs.isEmpty, let first = groups.first?.cards.first?.id { expandedIDs = [first] }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.studentCards.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.studentCards.isEmpty {
            ContentUnavailableView {
                Label("Nothing started yet", systemImage: "person.text.rectangle")
            } description: {
                Text("Present a lesson or give a child work, and her sequences show here.")
            }
        } else if groups.isEmpty {
            if scope.searchText.trimmed().isEmpty {
                ContentUnavailableView {
                    Label("No one here", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No child shown has started a sequence in this area. Pick another area or more children.")
                }
            } else {
                ContentUnavailableView.search(text: scope.searchText)
            }
        } else if isRegular {
            regularList
        } else {
            compactList
        }
    }

    /// The Mac and iPad: a band per level, then one row per child, her strips
    /// wrapping beside her name.
    private var regularList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.cards) { card in
                            ClassGridChildRow(card: card, onOpen: open)
                            Divider()
                        }
                    } header: {
                        levelBand(group)
                    }
                }
            }
        }
        .background(ChecklistGridMetrics.surface)
        .contentMargins(.bottom, ChecklistStatusBar.gridBottomMargin(isRegular: true), for: .scrollContent)
    }

    private func levelBand(_ group: ClassGridChildrenModel.LevelGroup) -> some View {
        HStack(spacing: 8) {
            Text(group.level.title)
                .font(.subheadline.weight(.bold))
            Text("\(group.cards.count) child\(group.cards.count == 1 ? "" : "ren") · started sequences only")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 20)
        .frame(height: 30)
        .background(ChecklistGridMetrics.bandFill)
        .background(ChecklistGridMetrics.surface)
        .overlay(alignment: .bottom) { ChecklistGridMetrics.hairline.frame(height: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The iPhone: a card per child, her areas and strips inside, folded to its
    /// header until opened.
    private var compactList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(groups) { group in
                    ForEach(group.cards) { card in
                        ClassGridChildCard(
                            card: card,
                            isExpanded: expandedIDs.contains(card.id),
                            onToggle: { toggle(card.id) },
                            onOpen: open
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.controlBackgroundColor())
        .quickCaptureButtonClearance()
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("One strip per started sequence, in lesson order · same marks as the Checklist")
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("Click a strip for its work, presentations and notes")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(-1)
        }
        .font(.caption)
        .padding(.leading, 20)
        .padding(.trailing, 92)
        .frame(height: ChecklistStatusBar.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        withAnimation(.snappy(duration: 0.2)) {
            if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        }
    }

    private func open(_ card: StudentProgressionCard, _ sequence: SequenceProgression) {
        detailTarget = StudentSequenceDetailTarget(
            studentID: card.id,
            studentName: card.fullName,
            area: sequence.area,
            sequence: sequence.sequence,
            lessonIDs: sequence.pills.map(\.lessonID)
        )
    }
}
