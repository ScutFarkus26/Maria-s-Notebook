// LastLessonStudentCard.swift
// Card showing days since last lesson for student grid view

import SwiftUI

// MARK: - Last Lesson Student Card

struct LastLessonStudentCard: View {
    let student: Student
    let days: Int

    @State private var bob = false

    private var displayName: String {
        StudentNameFormatter.displayName(for: student)
    }

    private var firstNameOnly: String {
        StudentNameFormatter.firstName(for: student)
    }

    // Warm, inviting gradient - like a cozy classroom
    private var gradientColors: [Color] {
        if days < 0 {
            // New student - exciting purple/blue for discovery
            return [.purple, .indigo, .blue]
        } else {
            // Warm, encouraging tones - ready to learn!
            return [.orange, .pink, .purple]
        }
    }

    // Friendly decorative overlay with learning symbols
    private var decorativeOverlay: some View {
        ZStack {
            // Books, pencils, stars - symbols of learning and achievement
            ForEach(0..<12, id: \.self) { i in
                Group {
                    switch i % 4 {
                    case 0:
                        Image(systemName: "book.fill")
                    case 1:
                        Image(systemName: "pencil")
                    case 2:
                        Image(systemName: "star.fill")
                    default:
                        Image(systemName: "lightbulb.fill")
                    }
                }
                .font(.system(size: CGFloat(Int.random(in: 10...16))))
                .foregroundStyle(.white.opacity(0.3))
                .rotationEffect(.degrees(Double(Int.random(in: -20...20))))
                .offset(x: CGFloat(Int.random(in: -140...140)), y: CGFloat(Int.random(in: -60...60)))
            }
        }
        .allowsHitTesting(false)
    }

    private var headerIcon: some View {
        Image(systemName: days < 0 ? "sparkles" : "hand.wave.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .bobbingAnimation(bob: $bob, duration: 1.4, offset: 3)
            .accessibilityHidden(true)
    }

    private var daysBadge: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 2))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

            VStack(spacing: 2) {
                if days < 0 {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("New!")
                        .font(AppTheme.ScaledFont.calloutBold)
                        .foregroundStyle(.white)
                } else {
                    Text("\(days)")
                        .font(AppTheme.ScaledFont.titleXLarge)
                        .foregroundStyle(.white)
                        .bobbingAnimation(bob: $bob)
                    Text(days == 1 ? "day" : "days")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 100, height: 100)
        .accessibilityLabel(days < 0 ? "New student, no lessons yet" : "\(days) \(days == 1 ? "day" : "days") since last lesson")
    }

    private var statusMessage: String {
        if days < 0 {
            return "Ready for first lesson!"
        } else {
            return "Ready to learn!"
        }
    }

    private var levelColor: Color {
        AppColors.color(forLevel: student.level)
    }

    private var levelBadge: some View {
        LevelBadge(level: student.level, backgroundColor: levelColor, useWhiteBackground: true)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(decorativeOverlay.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(displayName)
                        .font(AppTheme.ScaledFont.titleSmall)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    headerIcon
                }

                daysBadge
                    .frame(maxWidth: .infinity)

                Text(statusMessage)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: Capsule())
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
