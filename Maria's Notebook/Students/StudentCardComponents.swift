// StudentCardComponents.swift
// Student card components extracted from StudentsCardsGridView

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Symbol Support Cache

private enum SymbolSupportCache {
    #if canImport(AppKit)
    static let hasStarFill: Bool = (NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) != nil)
    static let hasSparkles: Bool = (NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) != nil)
    static let hasBalloonFill: Bool = (NSImage(systemSymbolName: "balloon.fill", accessibilityDescription: nil) != nil)
    #elseif canImport(UIKit)
    static let hasStarFill: Bool = (UIImage(systemName: "star.fill") != nil)
    static let hasSparkles: Bool = (UIImage(systemName: "sparkles") != nil)
    static let hasBalloonFill: Bool = (UIImage(systemName: "balloon.fill") != nil)
    #else
    static let hasStarFill: Bool = true
    static let hasSparkles: Bool = true
    static let hasBalloonFill: Bool = true
    #endif
}

// MARK: - Color Extension

extension Color {
    static var cardBackground: Color {
        #if canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #elseif canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color.white
        #endif
    }
}

// MARK: - Default Student Card

struct DefaultStudentCard: View {
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
                .fill(Color.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .drawingGroup()
    }
}

// MARK: - Age Student Card

struct AgeStudentCard: View {
    let student: Student
    @State private var bob = false
    @Environment(\.scenePhase) private var scenePhase

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
    
    // Computed property to determine if animation should run (only when scene is active)
    private var isAnimating: Bool {
        scenePhase == .active
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
                .animation(
                    isAnimating ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : nil,
                    value: bob
                )
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
        .drawingGroup()
        .onAppear {
            bob = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            // ENERGY OPTIMIZATION: Only animate when scene is active to reduce GPU/CPU usage when backgrounded
            if newPhase == .active {
                // Resume animation when scene becomes active
                bob = true
            } else {
                // Stop animation immediately when scene becomes inactive
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    bob = false
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Last Lesson Student Card

struct LastLessonStudentCard: View {
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
            Text(displayName)
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
            headline
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - Birthday Student Card

struct BirthdayStudentCard: View {
    let student: Student
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @State private var bob = false

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        return fmt
    }()
    
    // Computed property to determine if animation should run (only when scene is active)
    private var isAnimating: Bool {
        scenePhase == .active
    }

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
        .drawingGroup()
        .onAppear { bob = true }
        .onChange(of: scenePhase) { _, newPhase in
            // ENERGY OPTIMIZATION: Only animate when scene is active to reduce GPU/CPU usage when backgrounded
            if newPhase == .active {
                // Resume animation when scene becomes active
                bob = true
            } else {
                // Stop animation immediately when scene becomes inactive
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    bob = false
                }
            }
        }
    }

    // MARK: - Prominent headline badges
    private var bigDaysEmphasis: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(daysUntil)")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: bob ? -2 : 2)
                .animation(
                    isAnimating ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : nil,
                    value: bob
                )
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
            .animation(
                isAnimating ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : nil,
                value: bob
            )
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
        .animation(
            isAnimating ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : nil,
            value: bob
        )
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

