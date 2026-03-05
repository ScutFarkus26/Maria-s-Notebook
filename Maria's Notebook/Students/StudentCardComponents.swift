// StudentCardComponents.swift
// Student card components extracted from StudentsCardsGridView

import SwiftUI

// MARK: - Default Student Card

struct DefaultStudentCard: View {
    let student: Student
    var showAge: Bool = false

    private var levelColor: Color {
        AppColors.color(forLevel: student.level)
    }

    private var displayName: String {
        StudentNameFormatter.displayName(for: student)
    }

    private var levelBadge: some View {
        LevelBadge(level: student.level, backgroundColor: levelColor)
    }

    @ViewBuilder
    private func ageBadge(text: String) -> some View {
        Text(text)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .accessibilityLabel("Age: \(text)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(displayName)
                    .font(AppTheme.ScaledFont.titleSmall)
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
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .drawingGroup()
    }
}

// MARK: - Age Student Card

struct AgeStudentCard: View {
    let student: Student
    @State private var bob = false

    private var levelColor: Color {
        AppColors.color(forLevel: student.level)
    }

    private var displayName: String {
        StudentNameFormatter.displayName(for: student)
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
                        Text("\u{2b50}\u{fe0f}")
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
                .font(AppTheme.ScaledFont.titleXLarge)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .bobbingAnimation(bob: $bob)
        }
        .frame(width: 112, height: 112)
        .accessibilityLabel("Age: \(ageVerboseLabel)")
    }

    private var levelBadge: some View {
        LevelBadge(level: student.level, backgroundColor: levelColor, useWhiteBackground: true)
    }

    private var headerIcon: some View {
        Group {
            if SymbolSupportCache.hasSparkles {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .yellow)
            } else {
                Text("\u{2728}")
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
                        .font(AppTheme.ScaledFont.titleSmall)
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
        .accessibilityElement(children: .combine)
    }
}
