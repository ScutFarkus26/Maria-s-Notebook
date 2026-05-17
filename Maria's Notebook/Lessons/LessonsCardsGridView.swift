// LessonsCardsGridView.swift
// Browse mode lesson grid. Read-only: taps open detail, context menus surface
// quick actions. Reordering happens in Outline mode — see "Reorder in Outline"
// in the card context menu.

import OSLog
import SwiftUI
import CoreData
import Foundation

struct LessonsCardsGridView: View {
    private static let logger = Logger.lessons
    let lessons: [CDLesson]
    let onTapLesson: (CDLesson) -> Void
    let onGiveLesson: ((CDLesson) -> Void)?
    let onReorderInOutline: ((CDLesson) -> Void)?
    let onLocateInMap: ((CDLesson) -> Void)?
    let statusCounts: [UUID: Int]?
    let selectedArea: String?
    let selectedLessonID: UUID?
    let lastPresentedDates: [UUID: Date]?
    let showIntroductionCards: Bool

    init(
        lessons: [CDLesson],
        onTapLesson: @escaping (CDLesson) -> Void,
        onGiveLesson: ((CDLesson) -> Void)? = nil,
        onReorderInOutline: ((CDLesson) -> Void)? = nil,
        onLocateInMap: ((CDLesson) -> Void)? = nil,
        statusCounts: [UUID: Int]? = nil,
        selectedArea: String? = nil,
        selectedLessonID: UUID? = nil,
        lastPresentedDates: [UUID: Date]? = nil,
        showIntroductionCards: Bool = true
    ) {
        self.lessons = lessons
        self.onTapLesson = onTapLesson
        self.onGiveLesson = onGiveLesson
        self.onReorderInOutline = onReorderInOutline
        self.onLocateInMap = onLocateInMap
        self.statusCounts = statusCounts
        self.selectedArea = selectedArea
        self.selectedLessonID = selectedLessonID
        self.lastPresentedDates = lastPresentedDates
        self.showIntroductionCards = showIntroductionCards
    }

    @State var hasAppeared: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State var introductionToShow: CurriculumIntroduction?

    // Check size class to determine layout
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Curriculum introductions store
    @State private var introductionStore = CurriculumIntroductionStore.shared

    private var columns: [GridItem] {
        CardGridLayout.columns(for: sizeClass)
    }

    private var idList: [UUID] { lessons.compactMap(\.id) }

    /// Groups lessons by sequence and prepends introduction cards where available.
    private var groupedItems: [(key: String, value: [LessonsGridItem])] {
        let lessonSequences = groupedBySequence
        return lessonSequences.map { entry -> (key: String, value: [LessonsGridItem]) in
            var items: [LessonsGridItem] = []

            // Add introduction card at the top of each sequence if available and enabled
            if showIntroductionCards,
               let area = selectedArea,
               let intro = introductionStore.introduction(for: area, sequence: entry.key.isEmpty ? nil : entry.key) {
                items.append(.introduction(intro))
            }

            // Add lesson cards
            items.append(contentsOf: entry.value.map { .lesson($0) })

            return (key: entry.key, value: items)
        }
    }

    /// Organizes lessons within a sequence by section for hierarchical display.
    /// Returns ordered section keys (empty string = no section) and a lookup of lessons per section.
    private func sectionsForSequence(
        _ groupLessons: [CDLesson],
        sequenceName: String
    ) -> (order: [String], bySection: [String: [CDLesson]]) {
        let bySection = groupLessons.grouped { $0.section.trimmed() }
        let nonEmpty = Array(Set(bySection.keys.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let area = selectedArea ?? groupLessons.first?.area ?? ""
        let ordered = FilterOrderStore.loadSectionOrder(for: area, sequence: sequenceName, existing: nonEmpty)

        // Append the empty-section bucket at the end if present
        var result = ordered
        if bySection.keys.contains("") {
            result.append("")
        }
        return (order: result, bySection: bySection)
    }

    /// Whether a sequence has more than one distinct non-empty section (worth showing sub-sections).
    private func groupHasSections(_ groupLessons: [CDLesson]) -> Bool {
        let distinct = Set(groupLessons.map { $0.section.trimmed() }.filter { !$0.isEmpty })
        return !distinct.isEmpty
    }

    private var groupedBySequence: [(key: String, value: [CDLesson])] {
        let dict = lessons.grouped { $0.sequence.trimmed() }
        let mapped = dict
            .map { (key: $0.key, value: $0.value.sorted { lhs, rhs in
                if lhs.orderInSequence != rhs.orderInSequence { return lhs.orderInSequence < rhs.orderInSequence }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            })}

        let areaKey: String? = {
            if let selected = selectedArea, !selected.isEmpty {
                return selected
            }
            let areasSet = Set(lessons.map { $0.area.trimmed().lowercased() }.filter { !$0.isEmpty })
            if areasSet.count == 1 {
                return lessons.first?.area
            }
            return nil
        }()

        let keys = Array(dict.keys)

        if let areaKey {
            let existingNamed = keys.map { $0.trimmed() }.filter { !$0.isEmpty }
            let orderedNamed = FilterOrderStore.loadSequenceOrder(for: areaKey, existing: existingNamed)
            var index: [String: Int] = [:]
            for (i, g) in orderedNamed.enumerated() {
                index[g] = i
            }

            return mapped.sorted { lhs, rhs in
                let lk = lhs.key.trimmed()
                let rk = rhs.key.trimmed()

                if lk.isEmpty != rk.isEmpty {
                    return !lk.isEmpty
                }
                if !lk.isEmpty && !rk.isEmpty {
                    if let li = index[lk], let ri = index[rk] {
                        return li < ri
                    }
                    if index[lk] != nil && index[rk] == nil {
                        return true
                    }
                    if index[lk] == nil && index[rk] != nil {
                        return false
                    }
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
        } else {
            return mapped.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                    if groupedItems.count > 1 {
                        ForEach(groupedItems, id: \.key) { entry in
                            Section {
                                groupItemsWithSections(entry: entry)
                            } header: {
                                groupHeader(for: entry.key, area: selectedArea, lessonCount: entry.value.compactMap(\.asLesson).count)
                            }
                        }
                    } else {
                        // Single sequence or no grouping - show items with sections if applicable
                        let entry = groupedItems.first ?? (key: "", value: lessons.map { LessonsGridItem.lesson($0) })
                        groupItemsWithSections(entry: entry)
                    }
                }
                .transaction { tx in
                    if !hasAppeared { tx.animation = nil }
                }
                .adaptiveAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1), value: idList)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .padding(.trailing, 24)
                .padding(.leading, 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: selectedLessonID) { _, newValue in
                if let lessonID = newValue {
                    Task { @MainActor in
                        do {
                            try await Task.sleep(for: .milliseconds(100))
                            adaptiveWithAnimation {
                                scrollProxy.scrollTo(lessonID, anchor: .center)
                            }
                        } catch {
                            Self.logger.warning("Task sleep failed: \(error)")
                        }
                    }
                }
            }
        }
        .task {
            // Defer enabling animations until after the first layout to avoid initial appear animations
            hasAppeared = true
        }
        .task {
            if !introductionStore.isLoaded {
                await introductionStore.load()
            }
        }
        .sheet(item: $introductionToShow) { introduction in
            SequenceIntroductionSheet(introduction: introduction)
        }
    }

    // MARK: - Group Header

    @ViewBuilder
    private func groupHeader(for sequenceName: String, area: String?, lessonCount: Int) -> some View {
        let displayName = sequenceName.isEmpty ? "Ungrouped" : sequenceName
        let groupArg = sequenceName.isEmpty ? nil : sequenceName
        let hasIntro = area != nil && introductionStore.hasIntroduction(
            for: area!, sequence: groupArg
        )
        let accentColor = area.map { AppColors.color(forArea: $0) } ?? .accentColor

        HStack(spacing: 10) {
            Text(displayName)
                .font(AppTheme.ScaledFont.titleSmall)
                .foregroundStyle(.primary)

            if lessonCount > 0 {
                Text("\(lessonCount)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(accentColor.opacity(UIConstants.OpacityConstants.medium))
                    )
            }

            if hasIntro {
                Button {
                    if let subj = area {
                        introductionToShow = introductionStore.introduction(
                            for: subj, sequence: groupArg
                        )
                    }
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
                .help("View introduction")
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppTheme.Colors.paneBackground)
    }

    // MARK: - Section Sub-Sections

    /// Renders items within a sequence, inserting section divider rows when the sequence has sections.
    @ViewBuilder
    private func groupItemsWithSections(entry: (key: String, value: [LessonsGridItem])) -> some View {
        let groupLessons = entry.value.compactMap(\.asLesson)
        let introItems = entry.value.filter(\.isIntroduction)

        if groupHasSections(groupLessons) {
            let (order, bySection) = sectionsForSequence(groupLessons, sequenceName: entry.key)

            // Show introduction cards first
            ForEach(introItems, id: \.id) { item in
                gridItemView(item)
                    .id(item.id)
            }

            // Then section clusters. Lessons with no section render un-headered
            // at the bottom of the sequence rather than under a placeholder label.
            ForEach(order, id: \.self) { sh in
                if let shLessons = bySection[sh], !shLessons.isEmpty {
                    if sh.isEmpty {
                        ForEach(shLessons, id: \.id) { lesson in
                            gridItemView(.lesson(lesson))
                                .id("lesson-\(lesson.id?.uuidString ?? "")")
                        }
                    } else {
                        Section {
                            ForEach(shLessons, id: \.id) { lesson in
                                gridItemView(.lesson(lesson))
                                    .id("lesson-\(lesson.id?.uuidString ?? "")")
                            }
                        } header: {
                            sectionHeader(sh)
                        }
                    }
                }
            }
        } else {
            // No sections — render flat
            ForEach(entry.value, id: \.id) { item in
                gridItemView(item)
                    .id(item.id)
            }
        }
    }

    /// A section divider row that spans the grid, accented with the area color.
    @ViewBuilder
    private func sectionHeader(_ name: String) -> some View {
        let accentColor = selectedArea.map { AppColors.color(forArea: $0) } ?? .secondary

        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentColor.opacity(UIConstants.OpacityConstants.semi))
                .frame(width: 3, height: 16)

            Text(name)
                .font(AppTheme.ScaledFont.bodyMedium)
                .foregroundStyle(.primary.opacity(UIConstants.OpacityConstants.prominent))

            VStack {
                Rectangle()
                    .fill(Color.secondary.opacity(UIConstants.OpacityConstants.faint))
                    .frame(height: 1)
            }
        }
        .padding(.leading, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

}
