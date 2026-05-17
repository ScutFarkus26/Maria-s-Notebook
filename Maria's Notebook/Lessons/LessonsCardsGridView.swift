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
    let selectedSubject: String?
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
        selectedSubject: String? = nil,
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
        self.selectedSubject = selectedSubject
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

    /// Groups lessons by group and prepends introduction cards where available.
    private var groupedItems: [(key: String, value: [LessonsGridItem])] {
        let lessonGroups = groupedByGroup
        return lessonGroups.map { entry -> (key: String, value: [LessonsGridItem]) in
            var items: [LessonsGridItem] = []

            // Add introduction card at the top of each group if available and enabled
            if showIntroductionCards,
               let subject = selectedSubject,
               let intro = introductionStore.introduction(for: subject, group: entry.key.isEmpty ? nil : entry.key) {
                items.append(.introduction(intro))
            }

            // Add lesson cards
            items.append(contentsOf: entry.value.map { .lesson($0) })

            return (key: entry.key, value: items)
        }
    }

    /// Organizes lessons within a group by subheading for hierarchical display.
    /// Returns ordered subheading keys (empty string = no subheading) and a lookup of lessons per subheading.
    private func subheadingsForGroup(
        _ groupLessons: [CDLesson],
        groupName: String
    ) -> (order: [String], bySubheading: [String: [CDLesson]]) {
        let bySubheading = groupLessons.grouped { $0.subheading.trimmed() }
        let nonEmpty = Array(Set(bySubheading.keys.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let subject = selectedSubject ?? groupLessons.first?.subject ?? ""
        let ordered = FilterOrderStore.loadSubheadingOrder(for: subject, group: groupName, existing: nonEmpty)

        // Append the empty-subheading bucket at the end if present
        var result = ordered
        if bySubheading.keys.contains("") {
            result.append("")
        }
        return (order: result, bySubheading: bySubheading)
    }

    /// Whether a group has more than one distinct non-empty subheading (worth showing sub-sections).
    private func groupHasSubheadings(_ groupLessons: [CDLesson]) -> Bool {
        let distinct = Set(groupLessons.map { $0.subheading.trimmed() }.filter { !$0.isEmpty })
        return !distinct.isEmpty
    }

    private var groupedByGroup: [(key: String, value: [CDLesson])] {
        let dict = lessons.grouped { $0.group.trimmed() }
        let mapped = dict
            .map { (key: $0.key, value: $0.value.sorted { lhs, rhs in
                if lhs.orderInGroup != rhs.orderInGroup { return lhs.orderInGroup < rhs.orderInGroup }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            })}

        let subjectKey: String? = {
            if let selected = selectedSubject, !selected.isEmpty {
                return selected
            }
            let subjectsSet = Set(lessons.map { $0.subject.trimmed().lowercased() }.filter { !$0.isEmpty })
            if subjectsSet.count == 1 {
                return lessons.first?.subject
            }
            return nil
        }()

        let keys = Array(dict.keys)

        if let subjectKey {
            let existingNamed = keys.map { $0.trimmed() }.filter { !$0.isEmpty }
            let orderedNamed = FilterOrderStore.loadGroupOrder(for: subjectKey, existing: existingNamed)
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
                                groupItemsWithSubheadings(entry: entry)
                            } header: {
                                groupHeader(for: entry.key, subject: selectedSubject, lessonCount: entry.value.compactMap(\.asLesson).count)
                            }
                        }
                    } else {
                        // Single group or no grouping - show items with subheadings if applicable
                        let entry = groupedItems.first ?? (key: "", value: lessons.map { LessonsGridItem.lesson($0) })
                        groupItemsWithSubheadings(entry: entry)
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
            GroupIntroductionSheet(introduction: introduction)
        }
    }

    // MARK: - Group Header

    @ViewBuilder
    private func groupHeader(for groupName: String, subject: String?, lessonCount: Int) -> some View {
        let displayName = groupName.isEmpty ? "Ungrouped" : groupName
        let groupArg = groupName.isEmpty ? nil : groupName
        let hasIntro = subject != nil && introductionStore.hasIntroduction(
            for: subject!, group: groupArg
        )
        let accentColor = subject.map { AppColors.color(forSubject: $0) } ?? .accentColor

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
                    if let subj = subject {
                        introductionToShow = introductionStore.introduction(
                            for: subj, group: groupArg
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

    // MARK: - Subheading Sub-Sections

    /// Renders items within a group, inserting subheading divider rows when the group has subheadings.
    @ViewBuilder
    private func groupItemsWithSubheadings(entry: (key: String, value: [LessonsGridItem])) -> some View {
        let groupLessons = entry.value.compactMap(\.asLesson)
        let introItems = entry.value.filter(\.isIntroduction)

        if groupHasSubheadings(groupLessons) {
            let (order, bySubheading) = subheadingsForGroup(groupLessons, groupName: entry.key)

            // Show introduction cards first
            ForEach(introItems, id: \.id) { item in
                gridItemView(item)
                    .id(item.id)
            }

            // Then subheading clusters. Lessons with no subheading render un-headered
            // at the bottom of the group rather than under a placeholder label.
            ForEach(order, id: \.self) { sh in
                if let shLessons = bySubheading[sh], !shLessons.isEmpty {
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
                            subheadingHeader(sh)
                        }
                    }
                }
            }
        } else {
            // No subheadings — render flat
            ForEach(entry.value, id: \.id) { item in
                gridItemView(item)
                    .id(item.id)
            }
        }
    }

    /// A subheading divider row that spans the grid, accented with the subject color.
    @ViewBuilder
    private func subheadingHeader(_ name: String) -> some View {
        let accentColor = selectedSubject.map { AppColors.color(forSubject: $0) } ?? .secondary

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
