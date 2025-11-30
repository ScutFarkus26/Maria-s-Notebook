import SwiftUI
import Foundation

// Local conditional view modifier (mirrors the one used in StudentsCardsGridView)
extension View {
    @ViewBuilder
    func when<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct LessonsCardsGridView: View {
    let lessons: [Lesson]
    let isManualMode: Bool
    let onTapLesson: (Lesson) -> Void
    // Optional reorder callback; if provided and manual mode is enabled, supports drag reordering
    let onReorder: ((_ movingLesson: Lesson, _ fromIndex: Int, _ toIndex: Int, _ subset: [Lesson]) -> Void)?
    let onGiveLesson: ((Lesson) -> Void)?

    init(
        lessons: [Lesson],
        isManualMode: Bool,
        onTapLesson: @escaping (Lesson) -> Void,
        onReorder: ((_ movingLesson: Lesson, _ fromIndex: Int, _ toIndex: Int, _ subset: [Lesson]) -> Void)? = nil,
        onGiveLesson: ((Lesson) -> Void)? = nil
    ) {
        self.lessons = lessons
        self.isManualMode = isManualMode
        self.onTapLesson = onTapLesson
        self.onReorder = onReorder
        self.onGiveLesson = onGiveLesson
    }

    @State private var draggingLessonID: UUID?
    @State private var hoverTargetID: UUID?
    @State private var itemFrames: [UUID: CGRect] = [:]
    @Namespace private var gridNamespace
    @State private var hasAppeared: Bool = false

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 24)
    ]

    private var idList: [UUID] { lessons.map { $0.id } }

    private var gridAnimation: Animation? {
        if draggingLessonID != nil || !hasAppeared {
            return nil
        } else {
            return .spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(lessons, id: \.id) { lesson in
                    let isDragging = isManualMode && draggingLessonID == lesson.id
                    let isHover = hoverTargetID == lesson.id

                    LessonCard(lesson: lesson)
                        .matchedGeometryEffect(id: lesson.id, in: gridNamespace)
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
                            if draggingLessonID != nil { tx.animation = nil }
                        }
                        .contentShape(Rectangle())
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ItemFramePreference.self,
                                    value: [lesson.id: proxy.frame(in: .named("lessonsGridScroll"))]
                                )
                            }
                        )
                        .onTapGesture { onTapLesson(lesson) }
                        .when(isManualMode && onReorder != nil) { view in
                            view.simultaneousGesture(longPressThenDrag(for: lesson))
                        }
                        .contextMenu {
                            Button {
                                onGiveLesson?(lesson)
                            } label: {
                                Label("Give Lesson", systemImage: "person.crop.circle.badge.checkmark")
                            }
                        }
                }
            }
            .transaction { tx in
                if !hasAppeared { tx.animation = nil }
            }
            .animation(gridAnimation, value: idList)
            .padding(24)
        }
        .coordinateSpace(name: "lessonsGridScroll")
        .onPreferenceChange(ItemFramePreference.self) { frames in
            itemFrames = frames
        }
        .onAppear {
            // Defer enabling animations until after the first layout to avoid initial appear animations
            DispatchQueue.main.async {
                hasAppeared = true
            }
        }
    }

    // MARK: - Gesture
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
                    guard let startCenter = centers[lesson.id] else { return }
                    let endCenter = CGPoint(x: startCenter.x + drag.translation.width, y: startCenter.y + drag.translation.height)
                    if let targetID = centers.min(by: { lhs, rhs in
                        let dl = hypot(lhs.value.x - endCenter.x, lhs.value.y - endCenter.y)
                        let dr = hypot(rhs.value.x - endCenter.x, rhs.value.y - endCenter.y)
                        return dl < dr
                    })?.key {
                        hoverTargetID = targetID
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
                    guard let startCenter = centers[lesson.id] else { return }
                    let endCenter = CGPoint(x: startCenter.x + translation.width, y: startCenter.y + translation.height)
                    guard let targetID = centers.min(by: { lhs, rhs in
                        let dl = hypot(lhs.value.x - endCenter.x, lhs.value.y - endCenter.y)
                        let dr = hypot(rhs.value.x - endCenter.x, rhs.value.y - endCenter.y)
                        return dl < dr
                    })?.key, let idx = subsetIDs.firstIndex(of: targetID) else { return }
                    toIndex = idx
                }

                if toIndex == fromIndex { return }
                onReorder?(lesson, fromIndex, toIndex, lessons)
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

// MARK: - Lesson Card
private struct LessonCard: View {
    let lesson: Lesson

    private var subjectColor: Color {
        AppColors.color(forSubject: lesson.subject)
    }

    private var subjectBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(subjectColor).frame(width: 6, height: 6)
            Text(lesson.subject.isEmpty ? "Subject" : lesson.subject)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(subjectColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(subjectColor.opacity(0.12)))
        .accessibilityLabel("Subject: \(lesson.subject)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                subjectBadge
            }

            if !lesson.group.isEmpty || !lesson.subject.isEmpty {
                Text(groupSubjectLine)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if !lesson.subheading.isEmpty {
                Text(lesson.subheading)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
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
}

#Preview {
    LessonsCardsGridView(
        lessons: [
            Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Introduction to base-10", writeUp: ""),
            Lesson(name: "Parts of Speech", subject: "Language", group: "Grammar", subheading: "Nouns and Verbs", writeUp: "")
        ],
        isManualMode: true,
        onTapLesson: { _ in },
        onReorder: { _,_,_,_ in },
        onGiveLesson: nil
    )
}
