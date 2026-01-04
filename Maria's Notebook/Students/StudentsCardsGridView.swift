import SwiftUI
import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func disableAnimation(when condition: Bool) -> some View {
        self.transaction { tx in
            if condition { tx.animation = nil }
        }
    }
}

struct StudentsCardsGridView: View {
    let students: [Student]
    let isBirthdayMode: Bool
    let isAgeMode: Bool
    let isLastLessonMode: Bool
    let lastLessonDays: [UUID: Int]
    let isManualMode: Bool
    let onTapStudent: (Student) -> Void
    // Called when drag ends with final target index within the provided `students` subset
    let onReorder: (_ movingStudent: Student, _ fromIndex: Int, _ toIndex: Int, _ subset: [Student]) -> Void

    @State private var draggingStudentID: UUID?
    @State private var hoverTargetID: UUID?
    @State private var itemFrames: [UUID: CGRect] = [:]
    @Namespace private var gridNamespace

    @State private var hasAppeared: Bool = false

    // Check size class to determine layout
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private var columns: [GridItem] {
        // iPhone/Compact: Allow smaller cards (approx 160pt wide) to fit 2 columns
        // iPad/Regular: Keep the original 260pt minimum for wider cards
        let minWidth: CGFloat = sizeClass == .compact ? 155 : 260
        let spacing: CGFloat = sizeClass == .compact ? 16 : 24
        
        return [
            GridItem(.adaptive(minimum: minWidth, maximum: 320), spacing: spacing)
        ]
    }

    private var idList: [UUID] { students.map { $0.id } }

    private var gridAnimation: Animation? {
        if draggingStudentID != nil || !hasAppeared {
            return nil
        } else {
            return Animation.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)
        }
    }

    @ViewBuilder
    private func cardContent(for student: Student) -> some View {
        if isBirthdayMode {
            BirthdayStudentCard(student: student)
        } else if isAgeMode {
            AgeStudentCard(student: student)
        } else if isLastLessonMode {
            LastLessonStudentCard(student: student, days: lastLessonDays[student.id] ?? 0)
        } else {
            DefaultStudentCard(student: student, showAge: false)
        }
    }

    private func combinedOverlay(isDragging: Bool, isHover: Bool) -> some View {
        ZStack {
            if isDragging {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
            }
            if isHover {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
            }
        }
    }

    private func itemFrameBackground(for id: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ItemFramePreference.self,
                value: [id: proxy.frame(in: .named("gridScroll"))]
            )
        }
    }
    
    // Inserted helper types/functions
    private struct CardMotion: ViewModifier {
        let id: UUID
        let ns: Namespace.ID
        func body(content: Content) -> some View {
            content
                .matchedGeometryEffect(id: id, in: ns)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func addCardGestures<Content: View>(_ view: Content, for student: Student) -> some View {
        view
            .onTapGesture { onTapStudent(student) }
            .if(isManualMode) { v in
                v.simultaneousGesture(longPressThenDrag(for: student))
            }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(students, id: \.id) { student in
                    let isDragging = isManualMode && draggingStudentID == student.id
                    let isHover = hoverTargetID == student.id

                    addCardGestures(
                        cardContent(for: student)
                            .modifier(CardMotion(id: student.id, ns: gridNamespace))
                            .overlay(combinedOverlay(isDragging: isDragging, isHover: isHover))
                            .disableAnimation(when: draggingStudentID != nil)
                            .contentShape(Rectangle())
                            .if(isManualMode) { view in
                                view.background(itemFrameBackground(for: student.id))
                            }
                        , for: student
                    )
                }
            }
            .animation(gridAnimation, value: idList)
            .transaction { tx in
                if !hasAppeared { tx.animation = nil }
            }
            .padding(24)
        }
        .coordinateSpace(name: "gridScroll")
        .onPreferenceChange(ItemFramePreference.self) { frames in
            itemFrames = frames
        }
        .onAppear {
            DispatchQueue.main.async {
                hasAppeared = true
            }
        }
    }

    // MARK: - Gesture
    private func longPressThenDrag(for student: Student) -> some Gesture {
        let press = LongPressGesture(minimumDuration: 0.25)
        let drag = DragGesture(minimumDistance: 1)
        return press.sequenced(before: drag)
            .onChanged { value in
                guard isManualMode else { return }
                switch value {
                case .first(true):
                    draggingStudentID = student.id
                case .second(true, let drag?):
                    if draggingStudentID == nil { draggingStudentID = student.id }
                    // Compute nearest target using measured frames and the current drag translation
                    let subsetIDs = students.map { $0.id }
                    let centers: [UUID: CGPoint] = subsetIDs.reduce(into: [:]) { dict, id in
                        if let rect = itemFrames[id] { dict[id] = CGPoint(x: rect.midX, y: rect.midY) }
                    }
                    guard let startCenter = centers[student.id] else { return }
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
                    draggingStudentID = nil
                }
                guard isManualMode else { return }
                guard let fromIndex = students.firstIndex(where: { $0.id == student.id }) else { return }

                // Prefer the live hover target if still valid; otherwise compute nearest
                let subsetIDs = students.map { $0.id }
                let centers: [UUID: CGPoint] = subsetIDs.reduce(into: [:]) { dict, id in
                    if let rect = itemFrames[id] { dict[id] = CGPoint(x: rect.midX, y: rect.midY) }
                }

                let toIndex: Int
                if let hID = hoverTargetID, let idx = subsetIDs.firstIndex(of: hID) {
                    toIndex = idx
                } else {
                    var translation = CGSize.zero
                    if case .second(true, let drag?) = value { translation = drag.translation }
                    guard let startCenter = centers[student.id] else { return }
                    let endCenter = CGPoint(x: startCenter.x + translation.width, y: startCenter.y + translation.height)
                    guard let targetID = centers.min(by: { lhs, rhs in
                        let dl = hypot(lhs.value.x - endCenter.x, lhs.value.y - endCenter.y)
                        let dr = hypot(rhs.value.x - endCenter.x, rhs.value.y - endCenter.y)
                        return dl < dr
                    })?.key, let idx = subsetIDs.firstIndex(of: targetID) else { return }
                    toIndex = idx
                }

                if toIndex == fromIndex { return }
                onReorder(student, fromIndex, toIndex, students)
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


