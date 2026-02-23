// LessonsCardsGridView.swift
// Performance optimizations: Geometry measurement and matchedGeometryEffect are gated to only run
// when in manual reorder mode (isManualMode && onReorder != nil), avoiding expensive layout
// measurements during normal browsing. Grid mode is browse-only (no reordering).
// In browse mode (isManualMode=false), no GeometryReader, PreferenceKeys, or matchedGeometryEffect are used.

import SwiftUI
import Foundation

struct LessonsCardsGridView: View {
    let lessons: [Lesson]
    let isManualMode: Bool
    let onTapLesson: (Lesson) -> Void
    // Optional reorder callback; if provided and manual mode is enabled, supports drag reordering
    let onReorder: ((_ movingLesson: Lesson, _ fromIndex: Int, _ toIndex: Int, _ subset: [Lesson]) -> Void)?
    let onGiveLesson: ((Lesson) -> Void)?
    let statusCounts: [UUID: Int]?
    let selectedSubject: String?
    let selectedLessonID: UUID?
    let lastPresentedDates: [UUID: Date]?
    let showIntroductionCards: Bool

    init(
        lessons: [Lesson],
        isManualMode: Bool,
        onTapLesson: @escaping (Lesson) -> Void,
        onReorder: ((_ movingLesson: Lesson, _ fromIndex: Int, _ toIndex: Int, _ subset: [Lesson]) -> Void)? = nil,
        onGiveLesson: ((Lesson) -> Void)? = nil,
        statusCounts: [UUID: Int]? = nil,
        selectedSubject: String? = nil,
        selectedLessonID: UUID? = nil,
        lastPresentedDates: [UUID: Date]? = nil,
        showIntroductionCards: Bool = true
    ) {
        self.lessons = lessons
        self.isManualMode = isManualMode
        self.onTapLesson = onTapLesson
        self.onReorder = onReorder
        self.onGiveLesson = onGiveLesson
        self.statusCounts = statusCounts
        self.selectedSubject = selectedSubject
        self.selectedLessonID = selectedLessonID
        self.lastPresentedDates = lastPresentedDates
        self.showIntroductionCards = showIntroductionCards
    }

    @State private var draggingLessonID: UUID?
    @State private var hoverTargetID: UUID?
    @State private var itemFrames: [UUID: CGRect] = [:]
    @Namespace private var gridNamespace
    @State private var hasAppeared: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var introductionToShow: CurriculumIntroduction?

    // Check size class to determine layout
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Curriculum introductions store
    @State private var introductionStore = CurriculumIntroductionStore.shared

    private var columns: [GridItem] {
        CardGridLayout.columns(for: sizeClass)
    }

    private var idList: [UUID] { lessons.map { $0.id } }

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

    private var groupedByGroup: [(key: String, value: [Lesson])] {
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

        let keys = dict.keys.map { $0 }

        if let subjectKey = subjectKey {
            let existingNamed = keys.map { $0.trimmed() }.filter { !$0.isEmpty }
            let orderedNamed = FilterOrderStore.loadGroupOrder(for: subjectKey, existing: existingNamed)
            var index: [String: Int] = [:]
            for (i, g) in orderedNamed.enumerated() {
                index[g] = i
            }

            return mapped.sorted { lhs, rhs in
                let lk = lhs.key.trimmed()
                let rk = rhs.key.trimmed()

                if (lk.isEmpty != rk.isEmpty) {
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
        let needsGeometry = isManualMode && onReorder != nil

        return ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    if groupedItems.count > 1 {
                        ForEach(groupedItems, id: \.key) { entry in
                            Section {
                                ForEach(entry.value, id: \.id) { item in
                                    gridItemView(item)
                                        .id(item.id)
                                }
                            } header: {
                                groupHeader(for: entry.key, subject: selectedSubject)
                            }
                        }
                    } else {
                        // Single group or no grouping - show items directly
                        let items = groupedItems.first?.value ?? lessons.map { LessonsGridItem.lesson($0) }
                        ForEach(items, id: \.id) { item in
                            gridItemView(item)
                                .id(item.id)
                        }
                    }
                }
                .transaction { tx in
                    if !hasAppeared { tx.animation = nil }
                }
                .animation(gridAnimation, value: idList)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .padding(.trailing, 24)
                .padding(.leading, 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .when(needsGeometry) { view in
                view
                    .coordinateSpace(name: "lessonsGridScroll")
                    .onPreferenceChange(ItemFramePreference.self) { frames in
                        // Defer state update to next run loop to avoid layout recursion
                        // PreferenceKey updates happen during layout, so we must defer state changes
                        Task { @MainActor in
                            itemFrames = frames
                        }
                    }
            }
            .onChange(of: selectedLessonID) { _, newValue in
                if let lessonID = newValue {
                    Task { @MainActor in
                        do {
                            try await Task.sleep(for: .milliseconds(100))
                            withAnimation {
                                scrollProxy.scrollTo(lessonID, anchor: .center)
                            }
                        } catch {
                            print("⚠️ [onChange selectedLessonID] Task sleep failed: \(error)")
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
    private func groupHeader(for groupName: String, subject: String?) -> some View {
        let displayName = groupName.isEmpty ? "Ungrouped" : groupName
        let hasIntro = subject != nil && introductionStore.hasIntroduction(for: subject!, group: groupName.isEmpty ? nil : groupName)

        HStack(spacing: 8) {
            Text(displayName)
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            if hasIntro {
                Button {
                    if let subj = subject {
                        introductionToShow = introductionStore.introduction(for: subj, group: groupName.isEmpty ? nil : groupName)
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("View introduction")
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    // MARK: - Grid Item View

    @ViewBuilder
    private func gridItemView(_ item: LessonsGridItem) -> some View {
        switch item {
        case .introduction(let intro):
            IntroductionCard(
                introduction: intro,
                subjectColor: selectedSubject.map { AppColors.color(forSubject: $0) } ?? .accentColor,
                onTap: { introductionToShow = intro }
            )
        case .lesson(let lesson):
            card(lesson)
        }
    }

    // MARK: - Lesson Card

    @ViewBuilder
    private func card(_ lesson: Lesson) -> some View {
        let isDragging = isManualMode && draggingLessonID == lesson.id
        let isHover = hoverTargetID == lesson.id
        let isSelected = selectedLessonID == lesson.id
        // Only measure frames when in manual reorder mode with a reorder handler
        let shouldMeasureFrames = isManualMode && onReorder != nil

        LessonCardContainer(
            lesson: lesson,
            isDragging: isDragging,
            isHover: isHover,
            isSelected: isSelected,
            hasAppeared: hasAppeared,
            gridNamespace: gridNamespace,
            disableAnimations: draggingLessonID != nil,
            shouldMeasureFrames: shouldMeasureFrames,
            shouldUseMatchedGeometry: shouldMeasureFrames,
            statusCount: statusCounts?[lesson.id],
            lastPresentedDate: lastPresentedDates?[lesson.id]
        )
#if os(macOS)
        .highPriorityGesture(TapGesture(count: 1).onEnded { onTapLesson(lesson) })
#else
        .onTapGesture { onTapLesson(lesson) }
#endif
        .when(isManualMode && onReorder != nil) { view in
            view.simultaneousGesture(longPressThenDrag(for: lesson))
        }
#if os(macOS)
        .overlay(RightClickCatcher(onRightClick: { onGiveLesson?(lesson) }))
#endif
#if !os(macOS)
        .contextMenu {
            Button {
                onGiveLesson?(lesson)
            } label: {
                Label("Give Lesson", systemImage: "person.crop.circle.badge.checkmark")
            }
        }
#endif
    }

    // MARK: - Gesture

    private func nearestTargetID(from startCenter: CGPoint, translation: CGSize, centers: [UUID: CGPoint]) -> UUID? {
        let endCenter = CGPoint(x: startCenter.x + translation.width, y: startCenter.y + translation.height)
        return centers.min(by: { lhs, rhs in
            let dl = hypot(lhs.value.x - endCenter.x, lhs.value.y - endCenter.y)
            let dr = hypot(rhs.value.x - endCenter.x, rhs.value.y - endCenter.y)
            return dl < dr
        })?.key
    }

    private func longPressThenDrag(for lesson: Lesson) -> some Gesture {
        let press = LongPressGesture(minimumDuration: 0.25)
        let drag = DragGesture(minimumDistance: 1)
        return press.sequenced(before: drag)
            .onChanged { value in
                guard isManualMode else { return }
                switch value {
                case .first(true):
                    draggingLessonID = lesson.id
                case .second(true, let drag?):
                    if draggingLessonID == nil { draggingLessonID = lesson.id }
                    let subsetIDs = lessons.map { $0.id }
                    let centers: [UUID: CGPoint] = subsetIDs.reduce(into: [:]) { dict, id in
                        if let rect = itemFrames[id] { dict[id] = CGPoint(x: rect.midX, y: rect.midY) }
                    }
                    if let startCenter = centers[lesson.id] {
                        let translation = drag.translation
                        if let targetID = nearestTargetID(from: startCenter, translation: translation, centers: centers) {
                            hoverTargetID = targetID
                        }
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                defer {
                    hoverTargetID = nil
                    draggingLessonID = nil
                }
                guard isManualMode else { return }
                guard let fromIndex = lessons.firstIndex(where: { $0.id == lesson.id }) else { return }

                let subsetIDs = lessons.map { $0.id }
                let centers: [UUID: CGPoint] = subsetIDs.reduce(into: [:]) { dict, id in
                    if let rect = itemFrames[id] { dict[id] = CGPoint(x: rect.midX, y: rect.midY) }
                }

                let toIndex: Int
                if let hID = hoverTargetID, let idx = subsetIDs.firstIndex(of: hID) {
                    toIndex = idx
                } else {
                    var translation = CGSize.zero
                    if case .second(true, let drag?) = value { translation = drag.translation }
                    if let startCenter = centers[lesson.id], let targetID = nearestTargetID(from: startCenter, translation: translation, centers: centers), let idx = subsetIDs.firstIndex(of: targetID) {
                        toIndex = idx
                    } else {
                        return
                    }
                }

                if toIndex == fromIndex { return }
                onReorder?(lesson, fromIndex, toIndex, lessons)
            }
    }

    private var gridAnimation: Animation? {
        if draggingLessonID != nil || !hasAppeared {
            return nil
        } else {
            return .spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)
        }
    }
}

// MARK: - Preferences
private struct ItemFramePreference: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct LessonCardContainer: View {
    let lesson: Lesson
    let isDragging: Bool
    let isHover: Bool
    let isSelected: Bool
    let hasAppeared: Bool
    let gridNamespace: Namespace.ID
    let disableAnimations: Bool
    let shouldMeasureFrames: Bool
    let shouldUseMatchedGeometry: Bool
    let statusCount: Int?
    let lastPresentedDate: Date?

    var body: some View {
        let card = PaperLessonCard(
            lesson: lesson,
            statusCount: statusCount,
            lastPresentedDate: lastPresentedDate
        )
        let withMatchedGeometry = shouldUseMatchedGeometry
            ? AnyView(card.matchedGeometryEffect(id: lesson.id, in: gridNamespace))
            : AnyView(card)

        return withMatchedGeometry
            .when(hasAppeared) { view in
                view.transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isDragging ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isHover ? Color.accentColor.opacity(0.35) : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .transaction { tx in
                if disableAnimations { tx.animation = nil }
            }
            .contentShape(Rectangle())
            .background(
                Group {
                    if shouldMeasureFrames {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ItemFramePreference.self,
                                value: [lesson.id: proxy.frame(in: .named("lessonsGridScroll"))]
                            )
                        }
                    }
                }
            )
    }
}

#if os(macOS)
import AppKit

private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

private class RightClickView: NSView {
    var onRightClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only capture right mouse (or control-click) so left clicks pass through
        if let e = NSApp.currentEvent {
            if e.type == .rightMouseDown { return self }
            if e.type == .otherMouseDown && e.buttonNumber == 2 { return self }
            if e.type == .leftMouseDown && e.modifierFlags.contains(.control) { return self }
        }
        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onRightClick?() }
    }

    override func mouseDown(with event: NSEvent) {
        // Treat control-click as right-click
        if event.modifierFlags.contains(.control) {
            onRightClick?()
        } else {
            super.mouseDown(with: event)
        }
    }
}
#endif

#Preview {
    LessonsCardsGridView(
        lessons: [
            Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Introduction to base-10", writeUp: ""),
            Lesson(name: "Parts of Speech", subject: "Language", group: "Grammar", subheading: "Nouns and Verbs", writeUp: "")
        ],
        isManualMode: false,
        onTapLesson: { _ in },
        onReorder: nil,
        onGiveLesson: nil,
        selectedSubject: "Math",
        selectedLessonID: nil,
        lastPresentedDates: nil,
        showIntroductionCards: true
    )
}

