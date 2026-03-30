// BirthdayStudentCard.swift
// Birthday celebration card for student grid view

import SwiftUI

// MARK: - Birthday Student Card

struct BirthdayStudentCard: View {
    let student: Student
    @Environment(\.calendar) private var calendar
    @State private var bob = false

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
                        .font(AppTheme.ScaledFont.titleSmall)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    balloon
                        .opacity(UIConstants.OpacityConstants.barelyTransparent)
                }

                VStack(spacing: 10) {
                    if daysUntil == 0 {
                        bigTodayBadge
                            .frame(maxWidth: .infinity)

                        Text("\(firstNameOnly) turns \(turningAge) today")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.white)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .accessibilityHidden(true)
                    } else {
                        bigDaysEmphasis
                            .frame(maxWidth: .infinity)

                        Text("until \(firstNameOnly) turns \(turningAge) on \(dateLabel)")
                            .font(AppTheme.ScaledFont.captionSemibold)
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
                    "\(daysUntil) \(daysUntil == 1 ? "day" : "days") until" +
                    " \(student.fullName) turns \(turningAge) on \(dateLabel)."
                )

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .studentCardRasterization()
    }

    // MARK: - Prominent headline badges
    private var bigDaysEmphasis: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(daysUntil)")
                .font(AppTheme.ScaledFont.titleXLarge)
                .foregroundStyle(.white)
                .bobbingAnimation(bob: $bob)
            Text(daysUntil == 1 ? "day" : "days")
                .font(AppTheme.ScaledFont.titleMedium)
                .foregroundStyle(.white.opacity(UIConstants.OpacityConstants.barelyTransparent))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(UIConstants.OpacityConstants.quarter), lineWidth: 1))
        .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.medium), radius: 8, x: 0, y: 4)
        .accessibilityHidden(true)
    }

    private var bigTodayBadge: some View {
        Text("Today")
            .font(AppTheme.ScaledFont.titleXLarge)
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(UIConstants.OpacityConstants.quarter), lineWidth: 1))
            .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.medium), radius: 8, x: 0, y: 4)
            .bobbingAnimation(bob: $bob)
            .accessibilityHidden(true)
    }

    // MARK: - Derived
    private var displayName: String {
        StudentFormatter.displayName(for: student)
    }

    private var firstNameOnly: String {
        StudentFormatter.firstName(for: student)
    }

    private var balloon: some View {
        Group {
            if SymbolSupportCache.hasBalloonFill {
                Image(systemName: "balloon.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            } else {
                Text("\u{1f388}")
            }
        }
        .font(.title3)
        .bobbingAnimation(bob: $bob, offset: 6)
        .accessibilityHidden(true)
    }

    private var dateLabel: String {
        DateFormatters.shortMonthDay.string(from: nextBirthdayDate)
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
                    .fill(
                        [Color.white.opacity(UIConstants.OpacityConstants.statusBg), .yellow.opacity(UIConstants.OpacityConstants.statusBg),
                         .mint.opacity(UIConstants.OpacityConstants.statusBg), .cyan.opacity(UIConstants.OpacityConstants.statusBg)].randomElement()!
                    )
                    .frame(width: CGFloat(Int.random(in: 4...8)), height: CGFloat(Int.random(in: 4...8)))
                    .offset(x: CGFloat(Int.random(in: -140...140)), y: CGFloat(Int.random(in: -60...60)))
            }
        }
        .allowsHitTesting(false)
    }
}
