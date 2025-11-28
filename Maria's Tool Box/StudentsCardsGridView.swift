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
    let isBirthdayMode: Bool
    let isAgeMode: Bool
    let isManualMode: Bool
    let onTapStudent: (Student) -> Void
    // Called when drag ends with final target index within the provided `students` subset
    let onReorder: (_ movingStudent: Student, _ fromIndex: Int, _ toIndex: Int, _ subset: [Student]) -> Void

    @State private var draggingStudentID: UUID?
    @State private var hoverTargetID: UUID?
    @State private var itemFrames: [UUID: CGRect] = [:]
    @Namespace private var gridNamespace

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 24)
    ]

    private var idList: [UUID] { students.map { $0.id } }

    private var gridAnimation: Animation? {
        draggingStudentID != nil ? nil : .spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(students, id: \.id) { student in
                    let isDragging = isManualMode && draggingStudentID == student.id
                    let isHover = hoverTargetID == student.id

                    Group {
                        if isBirthdayMode {
                            BirthdayStudentCard(student: student)
                        } else {
                            DefaultStudentCard(student: student, showAge: isAgeMode)
                        }
                    }
                    .matchedGeometryEffect(id: student.id, in: gridNamespace)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
            .animation(gridAnimation, value: idList)
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

// MARK: - Default Card
private struct DefaultStudentCard: View {
    let student: Student
    var showAge: Bool = false

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
            Circle().fill(levelColor).frame(width: 6, height: 6)
            Text(student.level.rawValue)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(levelColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(levelColor.opacity(0.12)))
    }

    // Age helpers
    private func roundedAgeComponents(birthday: Date, today: Date = Date()) -> (years: Int, months: Int) {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: birthday, to: today)
        var years = comps.year ?? 0
        var months = comps.month ?? 0
        let days = comps.day ?? 0
        guard let anchor = cal.date(byAdding: DateComponents(year: years, month: months), to: birthday),
              let daysInThisMonth = cal.range(of: .day, in: .month, for: anchor)?.count else {
            return (max(0, years), max(0, months))
        }
        if days * 2 >= daysInThisMonth { months += 1 }
        if months >= 12 { years += months / 12; months = months % 12 }
        return (max(0, years), max(0, months))
    }

    private func ageStrings(birthday: Date) -> (verbose: String, concise: String) {
        let age = roundedAgeComponents(birthday: birthday)
        let y = age.years, m = age.months
        let verbose: String = {
            if y == 0 { return m == 1 ? "1 month" : "\(m) months" }
            if m == 0 { return y == 1 ? "1 year" : "\(y) years" }
            return "\(y) years, \(m) months"
        }()
        let concise: String = {
            if y == 0 { return m == 1 ? "1 mo" : "\(m) mo" }
            if m == 0 { return y == 1 ? "1 yr" : "\(y) yr" }
            return "\(y)y \(m)m"
        }()
        return (verbose, concise)
    }

    @ViewBuilder
    private func ageBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .accessibilityLabel("Age: \(text)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayName)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if showAge {
                        ViewThatFits(in: .horizontal) {
                            ageBadge(text: ageStrings(birthday: student.birthday).verbose)
                            ageBadge(text: ageStrings(birthday: student.birthday).concise)
                        }
                        .transition(.opacity)
                    }
                    levelBadge
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - Birthday Card
private struct BirthdayStudentCard: View {
    let student: Student
    @Environment(\.calendar) private var calendar
    @State private var bob = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Fun birthday background
            LinearGradient(colors: [.pink, .orange, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(confettiOverlay.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayName)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    balloon
                }

                // Turning age text
                if daysUntil == 0 {
                    Text("Turning \(turningAge) Today!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("\(student.fullName) is turning \(turningAge) today.")
                } else {
                    let dayWord = daysUntil == 1 ? "Day" : "Days"
                    Text("Turning \(turningAge) in \(daysUntil) \(dayWord)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("\(student.fullName) is turning \(turningAge) in \(daysUntil) \(dayWord) on \(dateLabel).")
                }

                // Date chip
                Text(dateLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.18), in: Capsule())

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(minHeight: 100)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                bob.toggle()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived
    private var displayName: String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private var balloon: some View {
        Group {
            if NSImage(systemSymbolName: "balloon.fill", accessibilityDescription: nil) != nil {
                Image(systemName: "balloon.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            } else {
                Text("🎈")
            }
        }
        .font(.title2)
        .offset(y: bob ? -6 : 6)
        .accessibilityHidden(true)
    }

    private var dateLabel: String {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        return fmt.string(from: nextBirthdayDate)
    }

    private var daysUntil: Int {
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: nextBirthdayDate)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private var turningAge: Int {
        let birthYear = calendar.component(.year, from: student.birthday)
        let targetYear = calendar.component(.year, from: nextBirthdayDate)
        return max(0, targetYear - birthYear)
    }

    private var nextBirthdayDate: Date {
        let today = Date()
        let comps = calendar.dateComponents([.month, .day], from: student.birthday)
        let currentYear = calendar.component(.year, from: today)
        var thisYear = calendar.date(from: DateComponents(year: currentYear, month: comps.month, day: comps.day))
        // Handle Feb 29 on non-leap years by using Feb 28
        if thisYear == nil, comps.month == 2, comps.day == 29 {
            thisYear = calendar.date(from: DateComponents(year: currentYear, month: 2, day: 28))
        }
        guard let this = thisYear else { return today }
        let startOfToday = calendar.startOfDay(for: today)
        if this >= startOfToday { return this }
        let nextYear = currentYear + 1
        var next = calendar.date(from: DateComponents(year: nextYear, month: comps.month, day: comps.day))
        if next == nil, comps.month == 2, comps.day == 29 {
            next = calendar.date(from: DateComponents(year: nextYear, month: 2, day: 28))
        }
        return next ?? this
    }

    // Simple confetti overlay using circles
    private var confettiOverlay: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { _ in
                Circle()
                    .fill([Color.white.opacity(0.35), .yellow.opacity(0.35), .mint.opacity(0.35), .cyan.opacity(0.35)].randomElement()!)
                    .frame(width: CGFloat(Int.random(in: 4...8)), height: CGFloat(Int.random(in: 4...8)))
                    .offset(x: CGFloat(Int.random(in: -140...140)), y: CGFloat(Int.random(in: -60...60)))
            }
        }
        .allowsHitTesting(false)
    }
}
