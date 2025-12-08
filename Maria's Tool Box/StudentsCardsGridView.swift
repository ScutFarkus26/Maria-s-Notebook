import SwiftUI
import Foundation

private enum SymbolSupportCache {
    static let hasStarFill = (NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) != nil)
    static let hasSparkles = (NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) != nil)
    static let hasBalloonFill = (NSImage(systemSymbolName: "balloon.fill", accessibilityDescription: nil) != nil)
}

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

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 24)
    ]

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

// MARK: - Default Card
private struct DefaultStudentCard: View {
    let student: Student
    var showAge: Bool = false

    private var levelColor: Color {
        AppColors.color(forLevel: student.level)
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
            HStack(alignment: .top) {
                Text(displayName)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if showAge {
                        ViewThatFits(in: .horizontal) {
                            ageBadge(text: AgeUtils.verboseQuarterAgeString(for: student.birthday))
                            ageBadge(text: AgeUtils.conciseQuarterAgeString(for: student.birthday))
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

// MARK: - Age Card
private struct AgeStudentCard: View {
    let student: Student
    @State private var bob = false

    private var levelColor: Color {
        AppColors.color(forLevel: student.level)
    }

    private var displayName: String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private var ageQuarter: (years: Int, months: Int) {
        AgeUtils.quarterRoundedAgeComponents(birthday: student.birthday)
    }

    private var ageVerboseLabel: String {
        AgeUtils.quarterFractionAgeString(for: student.birthday)
    }

    private var sparklesOverlay: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { _ in
                Group {
                    if SymbolSupportCache.hasStarFill {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.white.opacity(0.35))
                    } else {
                        Text("⭐️")
                    }
                }
                .font(.system(size: CGFloat(Int.random(in: 8...12))))
                .rotationEffect(.degrees(Double(Int.random(in: 0...360))))
                .offset(x: CGFloat(Int.random(in: -140...140)), y: CGFloat(Int.random(in: -60...60)))
            }
        }
        .allowsHitTesting(false)
    }

    private var ageBadge: some View {
        let y = ageQuarter.years
        let m = ageQuarter.months
        let text: String
        switch m {
        case 0: text = "\(y)"
        case 3: text = "\(y) 1/4"
        case 6: text = "\(y) 1/2"
        case 9: text = "\(y) 3/4"
        default: text = "\(y)" // should not happen
        }
        return ZStack {
            Circle()
                .fill(LinearGradient(colors: [.mint, .cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 2))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            Text(text)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .offset(y: bob ? -2 : 2)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bob)
        }
        .frame(width: 112, height: 112)
        .accessibilityLabel("Age: \(ageVerboseLabel)")
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
        .background(Capsule().fill(Color.white.opacity(0.18)))
        .accessibilityLabel("Level: \(student.level.rawValue)")
    }

    private var headerIcon: some View {
        Group {
            if SymbolSupportCache.hasSparkles {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .yellow)
            } else {
                Text("✨")
            }
        }
        .font(.title2)
        .accessibilityHidden(true)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [.mint, .teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(sparklesOverlay.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(displayName)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    headerIcon
                }

                ageBadge
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                HStack {
                    levelBadge
                }
            }
            .padding(14)
        }
        .frame(minHeight: 100)
        .onAppear {
            bob = true
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Last Lesson Card
private struct LastLessonStudentCard: View {
    let student: Student
    let days: Int

    private var displayName: String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(days < 0 ? "—" : "\(days)")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
            Text("since last lesson")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(days < 0 ? "No lessons yet" : "\(days) days since last lesson")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(displayName)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
            }
            headline
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

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        return fmt
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Keep celebratory background
            LinearGradient(colors: [.pink, .orange, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(confettiOverlay.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                // Top: name + balloon (subtle, not competing)
                HStack(alignment: .top) {
                    Text(displayName)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    balloon
                        .opacity(0.95)
                }

                VStack(spacing: 10) {
                    if daysUntil == 0 {
                        bigTodayBadge
                            .frame(maxWidth: .infinity)

                        Text("\(firstNameOnly) turns \(turningAge) today")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .accessibilityHidden(true)
                    } else {
                        bigDaysEmphasis
                            .frame(maxWidth: .infinity)

                        Text("until \(firstNameOnly) turns \(turningAge) on \(dateLabel)")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(daysUntil == 0 ?
                    "\(student.fullName) turns \(turningAge) today." :
                    "\(daysUntil) \(daysUntil == 1 ? "day" : "days") until \(student.fullName) turns \(turningAge) on \(dateLabel)."
                )

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .onAppear { bob = true }
    }

    // MARK: - Prominent headline badges
    private var bigDaysEmphasis: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(daysUntil)")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: bob ? -2 : 2)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bob)
            Text(daysUntil == 1 ? "day" : "days")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        .accessibilityHidden(true)
    }

    private var bigTodayBadge: some View {
        Text("Today")
            .font(.system(size: 36, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            .offset(y: bob ? -2 : 2)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bob)
            .accessibilityHidden(true)
    }

    // MARK: - Derived
    private var displayName: String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }
    
    private var firstNameOnly: String {
        let parts = student.fullName.split(separator: " ")
        return parts.first.map(String.init) ?? student.fullName
    }

    private var balloon: some View {
        Group {
            if SymbolSupportCache.hasBalloonFill {
                Image(systemName: "balloon.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            } else {
                Text("🎈")
            }
        }
        .font(.title3)
        .offset(y: bob ? -6 : 6)
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bob)
        .accessibilityHidden(true)
    }

    private var dateLabel: String {
        BirthdayStudentCard.dateFormatter.string(from: nextBirthdayDate)
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

