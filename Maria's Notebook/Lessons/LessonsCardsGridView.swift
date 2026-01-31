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

    init(
        lessons: [Lesson],
        isManualMode: Bool,
        onTapLesson: @escaping (Lesson) -> Void,
        onReorder: ((_ movingLesson: Lesson, _ fromIndex: Int, _ toIndex: Int, _ subset: [Lesson]) -> Void)? = nil,
        onGiveLesson: ((Lesson) -> Void)? = nil,
        statusCounts: [UUID: Int]? = nil,
        selectedSubject: String? = nil
    ) {
        self.lessons = lessons
        self.isManualMode = isManualMode
        self.onTapLesson = onTapLesson
        self.onReorder = onReorder
        self.onGiveLesson = onGiveLesson
        self.statusCounts = statusCounts
        self.selectedSubject = selectedSubject
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
    @StateObject private var introductionStore = CurriculumIntroductionStore.shared

    private var columns: [GridItem] {
        CardGridLayout.columns(for: sizeClass)
    }

    private var idList: [UUID] { lessons.map { $0.id } }

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
        
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                if groupedByGroup.count > 1 {
                    ForEach(groupedByGroup, id: \.key) { entry in
                        Section {
                            ForEach(entry.value, id: \.id) { lesson in
                                card(lesson)
                            }
                        } header: {
                            groupHeader(for: entry.key, subject: selectedSubject)
                        }
                    }
                } else {
                    ForEach(lessons, id: \.id) { lesson in
                        card(lesson)
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
                    DispatchQueue.main.async {
                        itemFrames = frames
                    }
                }
        }
        .onAppear {
            // Defer enabling animations until after the first layout to avoid initial appear animations
            DispatchQueue.main.async {
                hasAppeared = true
            }
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

    // MARK: - Lesson Card

    @ViewBuilder
    private func card(_ lesson: Lesson) -> some View {
        let isDragging = isManualMode && draggingLessonID == lesson.id
        let isHover = hoverTargetID == lesson.id
        // Only measure frames when in manual reorder mode with a reorder handler
        let shouldMeasureFrames = isManualMode && onReorder != nil

        LessonCardContainer(
            lesson: lesson,
            isDragging: isDragging,
            isHover: isHover,
            hasAppeared: hasAppeared,
            gridNamespace: gridNamespace,
            disableAnimations: draggingLessonID != nil,
            shouldMeasureFrames: shouldMeasureFrames,
            shouldUseMatchedGeometry: shouldMeasureFrames,
            statusCount: statusCounts?[lesson.id]
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
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct LessonCardContainer: View {
    let lesson: Lesson
    let isDragging: Bool
    let isHover: Bool
    let hasAppeared: Bool
    let gridNamespace: Namespace.ID
    let disableAnimations: Bool
    let shouldMeasureFrames: Bool
    let shouldUseMatchedGeometry: Bool
    let statusCount: Int?

    var body: some View {
        let card = LessonCard(lesson: lesson, statusCount: statusCount)
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

// MARK: - Lesson Card
private struct LessonCard: View {
    let lesson: Lesson
    let statusCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if lesson.source == .personal {
                    Text(lesson.personalKind?.badgeLabel ?? "Personal")
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .foregroundStyle(.secondary)
                }
            }

            if !lesson.group.isEmpty || !lesson.subject.isEmpty {
                Text(groupSubjectLine)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !lesson.subheading.isEmpty {
                Text(lesson.subheading)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let firstLine = writeUpFirstLine {
                Text(firstLine)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .lineSpacing(2)
        .padding(14)
        .frame(minHeight: 100)
        .background(
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(subjectColor.opacity(0.3), lineWidth: 2)
                    )
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(subjectColor)
                            .frame(width: 4)
                            .padding(.vertical, 8)
                            .padding(.leading, 1)
                    }
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

                if let count = statusCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .overlay(Capsule().stroke(Color.orange.opacity(0.5)))
                        .padding(10)
                        .accessibilityLabel("\(count) students need this")
                }
            }
        )
    }

    private var groupSubjectLine: String {
        switch (lesson.subject.isEmpty, lesson.group.isEmpty) {
        case (false, false): return "\(lesson.subject) • \(lesson.group)"
        case (false, true): return lesson.subject
        case (true, false): return lesson.group
        default: return ""
        }
    }

    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var subjectColor: Color { AppColors.color(forSubject: lesson.subject) }

    private var writeUpFirstLine: String? {
        let trimmedWriteUp = lesson.writeUp.trimmed()
        guard !trimmedWriteUp.isEmpty else { return nil }
        return trimmedWriteUp.split(separator: "\n").first.map(String.init)
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
        isManualMode: true,
        onTapLesson: { _ in },
        onReorder: { _,_,_,_ in },
        onGiveLesson: nil,
        selectedSubject: nil
    )
}

