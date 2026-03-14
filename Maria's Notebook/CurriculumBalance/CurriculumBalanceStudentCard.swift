// CurriculumBalanceStudentCard.swift
// Expandable card showing one student's subject distribution and gap warnings.
// Design follows ProgressDashboardStudentCard: initials circle, level color, card style.

import SwiftUI

struct CurriculumBalanceStudentCard: View {
    let card: StudentBalanceCard

    @State private var isExpanded = false

    private var levelColor: Color {
        AppColors.color(forLevel: card.level)
    }

    private var initials: String {
        let first = card.firstName.prefix(1)
        let last = card.lastName.prefix(1)
        return "\(first)\(last)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isExpanded {
                expandedContent
            }
        }
        .background(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .fill(CardStyle.cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(CardStyle.strokeOpacity))
        )
        .shadow(color: CardStyle.shadowColor, radius: CardStyle.shadowRadius, y: 1)
    }

    // MARK: - Header

    private var headerRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                // Initial circle
                Text(initials)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(levelColor.gradient, in: Circle())

                // Name
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(card.firstName) \(card.lastName)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text(card.level.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)

                        Text("\(card.totalLessons) lessons")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if !card.gaps.isEmpty {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.quaternary)

                            Text("\(card.gaps.count) gaps")
                                .font(.caption2)
                                .foregroundStyle(AppColors.warning)
                        }
                    }
                }

                Spacer()

                Image(systemName: isExpanded ? SFSymbol.Navigation.chevronUp : SFSymbol.Navigation.chevronDown)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.horizontal, 14)

            // Subject distribution bars
            subjectBars
                .padding(.horizontal, 14)

            // Gap warnings
            if !card.gaps.isEmpty {
                gapWarnings
                    .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 12)
    }

    private var subjectBars: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(card.subjectCounts) { dist in
                HStack(spacing: 8) {
                    Text(dist.subject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                        .lineLimit(1)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(dist.color.gradient)
                            .frame(width: max(4, geo.size.width * dist.percentage))
                    }
                    .frame(height: 14)

                    Text("\(dist.count)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }

    private var gapWarnings: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(card.gaps) { gap in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)

                    Text("\(gap.subject) is underrepresented")
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                }
            }
        }
        .padding(8)
        .background(AppColors.warning.opacity(0.08))
        .cornerRadius(8)
    }
}
