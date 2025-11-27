import SwiftUI
import Foundation

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct StudentsCardsGridView: View {
    let students: [Student]
    let isManualMode: Bool
    let onTapStudent: (Student) -> Void
    // Called when drag ends with final target index within the provided `students` subset
    let onReorder: (_ movingStudent: Student, _ fromIndex: Int, _ toIndex: Int, _ subset: [Student]) -> Void

    @State private var draggingStudentID: UUID?
    @State private var dragStartIndex: Int?
    @State private var hoverTargetID: UUID?
    @State private var itemFrames: [UUID: CGRect] = [:]
    @Namespace private var gridNamespace

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 24)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(students.indices, id: \.self) { index in
                    let student = students[index]
                    let isDragging = isManualMode && draggingStudentID == student.id
                    let isHover = hoverTargetID == student.id

                    StudentCard(student: student)
                        .matchedGeometryEffect(id: student.id, in: gridNamespace)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .animation(
                            isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1).delay(Double(index) * 0.02),
                            value: student.id
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isDragging ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isHover ? Color.accentColor.opacity(0.35) : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                        )
                        .transaction { tx in
                            if draggingStudentID != nil { tx.animation = nil }
                        }
                        .contentShape(Rectangle())
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ItemFramePreference.self,
                                    value: [student.id: proxy.frame(in: .named("gridScroll"))]
                                )
                            }
                        )
                        .onTapGesture { onTapStudent(student) }
                        .if(isManualMode) { view in
                            view.highPriorityGesture(longPressThenDrag(for: student))
                        }
                }
            }
            .padding(24)
        }
        .coordinateSpace(name: "gridScroll")
        .onPreferenceChange(ItemFramePreference.self) { frames in
            itemFrames = frames
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
                    dragStartIndex = students.firstIndex(where: { $0.id == student.id })
                    hoverTargetID = student.id
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
                    dragStartIndex = nil
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

// MARK: - Card
private struct StudentCard: View {
    let student: Student

    private var levelColor: Color {
        switch student.level {
        case .upper: return .pink
        case .lower: return .blue
        }
    }

    private var displayName: String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private var levelBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(levelColor)
                .frame(width: 6, height: 6)
            Text(student.level.rawValue)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(levelColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(levelColor.opacity(0.12))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayName)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                levelBadge
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }
}
