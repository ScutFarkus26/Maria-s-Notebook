// ClassGridChildRow.swift
// One child in the Children view: her name, level, year in class and how many
// lessons she has mastered, then each area she has started with a strip per
// sequence. A row on the Mac and iPad, a card that folds on the iPhone.

import SwiftUI

/// The Mac and iPad row: the child on the left, her areas' strips wrapping on the right.
struct ClassGridChildRow: View {
    let card: StudentProgressionCard
    let onOpen: (StudentProgressionCard, SequenceProgression) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ClassGridChildHeading(card: card, avatarSize: 30)
                .frame(width: 210, alignment: .leading)
                .padding(.leading, 20)
                .padding(.trailing, 12)
                .padding(.vertical, 14)
            // One flow of area blocks, each its caption over a row of at most three
            // strips (a longer area continues in the next block). A flow nested in a
            // flow is measured unconstrained and folds to one column, so the blocks
            // hold plain rows.
            FlowLayout(spacing: 18) {
                ForEach(Self.blocks(for: card)) { block in
                    VStack(alignment: .leading, spacing: 5) {
                        ClassGridAreaCaption(area: block.area)
                            .opacity(block.isContinuation ? 0 : 1)
                            .accessibilityHidden(block.isContinuation)
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(block.sequences) { sequence in
                                ClassGridSequenceChip(sequence: sequence) { onOpen(card, sequence) }
                            }
                        }
                    }
                    .fixedSize()
                }
            }
            .padding(.vertical, 12)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 92, alignment: .top)
    }

    /// An area's strips, three to a block.
    struct Block: Identifiable {
        let id: String
        let area: String
        let isContinuation: Bool
        let sequences: [SequenceProgression]
    }

    static func blocks(for card: StudentProgressionCard, perBlock: Int = 3) -> [Block] {
        card.subjects.flatMap { subject in
            stride(from: 0, to: subject.sequences.count, by: perBlock).map { start in
                Block(
                    id: "\(subject.id)|\(start)",
                    area: subject.area,
                    isContinuation: start > 0,
                    sequences: Array(subject.sequences[start..<min(start + perBlock, subject.sequences.count)])
                )
            }
        }
    }
}

/// The iPhone card: the child's heading, which folds and opens the card, then her
/// areas and a row per sequence.
struct ClassGridChildCard: View {
    let card: StudentProgressionCard
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: (StudentProgressionCard, SequenceProgression) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    ClassGridChildHeading(card: card, avatarSize: 34)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, isExpanded ? 8 : 0)
            .accessibilityValue(isExpanded ? "Open" : "Folded")
            .accessibilityHint(isExpanded ? "Folds the card" : "Shows her sequences")

            if isExpanded {
                ForEach(card.subjects) { subject in
                    ClassGridAreaCaption(area: subject.area)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    ForEach(subject.sequences) { sequence in
                        Button { onOpen(card, sequence) } label: {
                            HStack(spacing: 8) {
                                Text(sequence.sequence)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .frame(width: 118, alignment: .leading)
                                ClassGridSequenceStrip(pills: sequence.pills, markSize: 11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(sequence.presentedCount)/\(sequence.totalCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ClassGridSequenceChip.accessibilityText(sequence))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, isExpanded ? 6 : 12)
        .background(ChecklistGridMetrics.surface, in: .rect(cornerRadius: 12))
    }
}

/// Initials, name, "Upper · Year 2 · 3 areas" and "31 lessons mastered".
struct ClassGridChildHeading: View {
    let card: StudentProgressionCard
    let avatarSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(card.initials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.color(forLevel: card.level))
                .frame(width: avatarSize, height: avatarSize)
                .background(AppColors.color(forLevel: card.level).opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.fullName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(card.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(card.masteredText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "MATH" with its area's color: area color on headings only, never on a mark.
struct ClassGridAreaCaption: View {
    let area: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.color(forArea: area))
                .frame(width: 7, height: 7)
            Text(area.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A sequence as a button: its name and "4/8" over the strip of marks.
struct ClassGridSequenceChip: View {
    let sequence: SequenceProgression
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(sequence.sequence)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(sequence.presentedCount)/\(sequence.totalCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ClassGridSequenceStrip(pills: sequence.pills, markSize: 10)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .fixedSize()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(UIConstants.OpacityConstants.subtle), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("\(sequence.area) · \(sequence.sequence): \(sequence.presentedCount) of \(sequence.totalCount) presented")
        .accessibilityLabel(Self.accessibilityText(sequence))
        .accessibilityHint("Opens its work, presentations and notes")
    }

    static func accessibilityText(_ sequence: SequenceProgression) -> String {
        "\(sequence.sequence), \(sequence.presentedCount) of \(sequence.totalCount) presented"
    }
}

/// A sequence's lessons as the Checklist's marks, in lesson order.
struct ClassGridSequenceStrip: View {
    let pills: [LessonPillState]
    let markSize: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            ForEach(pills) { pill in
                ChecklistMark(status: pill.status, size: markSize)
                    .help("\(pill.name) — \(pill.status.label)")
            }
        }
        .accessibilityHidden(true)
    }
}
