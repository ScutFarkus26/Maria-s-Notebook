// ProgressDashboardStudentCard.swift
// One student's full progression map. Header is the student name + level + counts;
// body is a list of subject sections, each with a colored uppercase header and the
// student's sequence rows inside it. The whole card is collapsible from the header.

import SwiftUI

struct ProgressDashboardStudentCard: View {
    let card: StudentProgressionCard
    let onTapSequence: (SequenceProgression) -> Void

    @State private var isExpanded: Bool = true

    private var levelColor: Color {
        card.level == .lower ? Color.green : Color.blue
    }

    private var initials: String {
        let first = card.firstName.prefix(1)
        let last = card.lastName.prefix(1)
        return "\(first)\(last)"
    }

    private var countsSummary: String {
        let subjectCount = card.subjects.count
        let areaCount = card.sequenceCount  // reduce over subjects — read once
        let subjectSuffix = subjectCount == 1 ? "" : "s"
        let areaSuffix = areaCount == 1 ? "" : "s"
        return "\(subjectCount) subject\(subjectSuffix) · \(areaCount) area\(areaSuffix)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isExpanded {
                subjectSections
                    .padding(.top, 4)
                    .padding(.bottom, 10)
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
                Text(initials)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(levelColor.gradient, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(card.fullName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text(card.level.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        Text(countsSummary)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
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

    // MARK: - Subject sections

    private var subjectSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(card.subjects) { subject in
                subjectSection(subject)
            }
        }
        .padding(.horizontal, 14)
    }

    private func subjectSection(_ subject: SubjectProgression) -> some View {
        let areaColor = AppColors.color(forArea: subject.area)
        return VStack(alignment: .leading, spacing: 4) {
            Text(subject.area.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(areaColor)
                .padding(.leading, 2)
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(subject.sequences) { sequence in
                    ProgressDashboardCategoryRow(
                        sequence: sequence,
                        areaColor: areaColor,
                        onTap: { onTapSequence(sequence) }
                    )
                }
            }
        }
    }
}
